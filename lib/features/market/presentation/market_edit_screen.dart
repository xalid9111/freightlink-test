import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/constants/currencies.dart';
import '../../../core/localization/app_strings.dart';
import '../../../core/localization/locale_controller.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/city_picker.dart';
import '../../../core/widgets/reorder_tile_grid.dart';
import '../../../services/geo_service.dart';
import '../../auth/presentation/providers/auth_providers.dart';
import '../data/market_repository.dart';
import '../domain/market_catalog.dart';
import '../domain/market_models.dart';
import 'market_card.dart';
import 'market_home_screen.dart' show marketCategoryIcon;
import 'market_providers.dart';

const _other = '__other__';

/// "Satış elanı yerləşdir" (Şəkil 3): 1 category · 2 brand / model / year ·
/// 3 technical data · 4 price + currency · 5 location (+ phone) · 6 up to 20
/// photos (add / delete / reorder) · 7 description. "Saxla" keeps a draft,
/// "Elanı dərc et" sends it to the admin. Also used to edit an own ad.
class MarketEditScreen extends ConsumerStatefulWidget {
  final String? listingId;
  const MarketEditScreen({super.key, this.listingId});

  @override
  ConsumerState<MarketEditScreen> createState() => _MarketEditScreenState();
}

class _MarketEditScreenState extends ConsumerState<MarketEditScreen> {
  MarketDraft _d = MarketDraft();
  MarketListing? _orig;
  bool _loaded = false;
  bool _busy = false;
  bool _uploading = false;
  String? _error;
  bool _brandOther = false;
  bool _modelOther = false;

  final _brand = TextEditingController();
  final _model = TextEditingController();
  final _km = TextEditingController();
  final _engine = TextEditingController();
  final _power = TextEditingController();
  final _price = TextEditingController();
  final _phone = TextEditingController();
  final _desc = TextEditingController();

  /// Photos uploaded in this session (deleted again if removed / cancelled).
  final Set<String> _fresh = {};

  bool get _editing => widget.listingId != null;

  @override
  void initState() {
    super.initState();
    _desc.addListener(() => setState(() {}));
    _load();
  }

  Future<void> _load() async {
    if (!_editing) {
      _phone.text = ref.read(currentUserProvider)?.phone ?? '';
      setState(() => _loaded = true);
      return;
    }
    final l = await ref.read(marketRepositoryProvider).byId(widget.listingId!);
    if (!mounted) return;
    if (l == null) {
      setState(() {
        _loaded = true;
        _error = 'mk_not_found';
      });
      return;
    }
    _orig = l;
    _d = MarketDraft.from(l);
    _brandOther = l.brand != null && !marketBrands(l.category).contains(l.brand);
    _modelOther = l.model != null && !marketModels(l.category, l.brand).contains(l.model);
    _brand.text = l.brand ?? '';
    _model.text = l.model ?? '';
    _km.text = l.mileageKm?.toString() ?? '';
    _engine.text = l.engineL?.toString() ?? '';
    _power.text = l.powerHp?.toString() ?? '';
    _price.text = l.price?.round().toString() ?? '';
    _phone.text = l.phone ?? '';
    _desc.text = l.description ?? '';
    setState(() => _loaded = true);
  }

  @override
  void dispose() {
    for (final c in [_brand, _model, _km, _engine, _power, _price, _phone, _desc]) {
      c.dispose();
    }
    super.dispose();
  }

  int? _int(TextEditingController c) => int.tryParse(c.text.replaceAll(RegExp(r'[\s,]'), ''));
  double? _dbl(TextEditingController c) => double.tryParse(c.text.replaceAll(' ', '').replaceAll(',', '.'));

  void _collect() {
    _d
      ..brand = _brandOther ? _brand.text : _d.brand
      ..model = _modelOther ? _model.text : _d.model
      ..mileageKm = _int(_km)
      ..engineL = _dbl(_engine)
      ..powerHp = _int(_power)
      ..price = _dbl(_price)
      ..phone = _phone.text
      ..description = _desc.text;
  }

  Future<void> _addPhotos(AppStrings s) async {
    final left = kMarketMaxPhotos - _d.photos.length;
    if (left <= 0) return;
    // Resized on the phone before upload (fast, small files).
    final files = await ImagePicker().pickMultiImage(maxWidth: 1600, maxHeight: 1600, imageQuality: 80, limit: left);
    if (files.isEmpty || !mounted) return;
    setState(() => _uploading = true);
    final repo = ref.read(marketRepositoryProvider);
    try {
      for (final f in files.take(left)) {
        final bytes = await f.readAsBytes();
        final ext = f.name.contains('.') ? f.name.split('.').last : 'jpg';
        final url = await repo.uploadPhoto(bytes, ext);
        _fresh.add(url);
        if (mounted) setState(() => _d.photos = [..._d.photos, url]);
      }
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.t('mk_photo_failed'))));
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  void _removePhoto(String url) {
    setState(() => _d.photos = [..._d.photos]..remove(url));
    if (_fresh.remove(url)) ref.read(marketRepositoryProvider).removePhoto(url);
  }

  Future<void> _pickCity(AppStrings s, String lang) async {
    final p = await showModalBottomSheet<PickedPlace>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => CityPickerSheet(languageCode: lang, strings: s, title: s.t('mk_city')),
    );
    if (p == null || !mounted) return;
    setState(() {
      _d
        ..city = p.city
        ..country = p.country
        ..lat = null
        ..lng = null;
    });
  }

  Future<void> _save(AppStrings s, {required bool publish}) async {
    _collect();
    if (publish) {
      final missing = _d.missingForPublish();
      if (missing.isNotEmpty) {
        setState(() => _error = missing.first);
        return;
      }
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      // City → approximate map point (city centre), once.
      if (_d.lat == null && (_d.city ?? '').isNotEmpty) {
        final p = await ref.read(geoServiceProvider).geocode([_d.city, _d.country].whereType<String>().join(', '));
        _d
          ..lat = p?.latitude
          ..lng = p?.longitude;
      }
      final saved = await ref.read(marketRepositoryProvider).save(_d, id: _orig?.id, publish: publish, current: _orig?.status);
      // Photos taken out of a saved ad: delete the files now.
      for (final url in _orig?.photos ?? const <String>[]) {
        if (!_d.photos.contains(url)) ref.read(marketRepositoryProvider).removePhoto(url);
      }
      _fresh.clear();
      ref.invalidate(myMarketListingsProvider);
      ref.invalidate(marketListingProvider(saved.id));
      ref.invalidate(marketFeedProvider);
      if (!mounted) return;
      final msg = !publish ? 'mk_saved_draft' : (saved.status == MarketStatus.pending ? 'mk_sent_review' : 'mk_published');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.t(msg))));
      context.pop();
    } catch (_) {
      if (mounted) setState(() => _error = 'mk_save_failed');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    final lang = ref.watch(currentLocaleProvider).languageCode;
    final brands = marketBrands(_d.category);
    final models = marketModels(_d.category, _d.brand);
    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        // Leaving without saving: drop the photos uploaded just now.
        if (didPop) {
          for (final url in _fresh) {
            ref.read(marketRepositoryProvider).removePhoto(url);
          }
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(s.t(_editing ? 'mk_edit_title' : 'mk_new_title')),
          actions: [
            TextButton.icon(
              key: const ValueKey('mk-save-draft'),
              onPressed: _busy || _uploading || !_loaded ? null : () => _save(s, publish: false),
              icon: const Icon(Icons.save_outlined, color: AppColors.accent),
              label: Text(s.t('mk_save'), style: const TextStyle(color: AppColors.accent, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
        body: !_loaded
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.fromLTRB(14, 8, 14, 32),
                children: [
                  if (_orig?.status == MarketStatus.rejected && (_orig?.adminNote ?? '').isNotEmpty)
                    _Note(text: '${s.t('mk_rejected_note')}: ${_orig!.adminNote}'),
                  _Section(n: 1, title: s.t('mk_s_category'), child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final c in MarketCategory.values)
                        _CatTile(
                          icon: marketCategoryIcon(c),
                          label: s.t(c.labelKey),
                          selected: _d.category == c,
                          onTap: () => setState(() {
                            if (_d.category != c) {
                              _d
                                ..category = c
                                ..brand = null
                                ..model = null;
                              _brandOther = marketBrands(c).isEmpty;
                              _modelOther = _brandOther;
                            }
                          }),
                        ),
                    ],
                  )),
                  _Section(n: 2, title: s.t('mk_s_brand'), child: Column(children: [
                    Row(children: [
                      Expanded(
                        child: _brandOther || brands.isEmpty
                            ? TextField(controller: _brand, decoration: InputDecoration(labelText: s.t('mk_brand')))
                            : _Drop<String>(
                                label: s.t('mk_brand'),
                                value: brands.contains(_d.brand) ? _d.brand : null,
                                items: {for (final b in brands) b: b, _other: s.t('mk_other')},
                                onChanged: (v) => setState(() {
                                  if (v == _other) {
                                    _brandOther = true;
                                    _modelOther = true;
                                    _d.brand = null;
                                  } else {
                                    _d
                                      ..brand = v
                                      ..model = null;
                                    _modelOther = marketModels(_d.category, v).isEmpty;
                                  }
                                }),
                              ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _modelOther || models.isEmpty
                            ? TextField(controller: _model, decoration: InputDecoration(labelText: s.t('mk_model')))
                            : _Drop<String>(
                                label: s.t('mk_model'),
                                value: models.contains(_d.model) ? _d.model : null,
                                items: {for (final m in models) m: m, _other: s.t('mk_other')},
                                onChanged: (v) => setState(() {
                                  if (v == _other) {
                                    _modelOther = true;
                                    _d.model = null;
                                  } else {
                                    _d.model = v;
                                  }
                                }),
                              ),
                      ),
                    ]),
                    const SizedBox(height: 8),
                    _Drop<int>(
                      label: s.t('mk_year'),
                      value: _d.year,
                      items: {for (final y in marketYears()) y: '$y'},
                      onChanged: (v) => setState(() => _d.year = v),
                    ),
                  ])),
                  _Section(n: 3, title: s.t('mk_s_tech'), child: Column(children: [
                    Row(children: [
                      Expanded(child: _num(_km, s.t('mk_mileage'))),
                      const SizedBox(width: 8),
                      Expanded(child: _num(_engine, s.t('mk_engine'), decimal: true)),
                    ]),
                    const SizedBox(height: 8),
                    Row(children: [
                      Expanded(child: _num(_power, s.t('mk_power'))),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _Drop<String>(
                          label: s.t('mk_fuel_short'),
                          value: _d.fuel,
                          items: {for (final f in kMarketFuels) f: s.t('mk_fuel_$f')},
                          onChanged: (v) => setState(() => _d.fuel = v),
                        ),
                      ),
                    ]),
                    const SizedBox(height: 8),
                    _Drop<String>(
                      label: s.t('mk_gearbox'),
                      value: _d.gearbox,
                      items: {for (final g in kMarketGearboxes) g: s.t('mk_gear_$g')},
                      onChanged: (v) => setState(() => _d.gearbox = v),
                    ),
                  ])),
                  _Section(n: 4, title: s.t('mk_s_price'), child: Row(children: [
                    Expanded(flex: 3, child: _num(_price, s.t('mk_price'))),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 2,
                      child: _Drop<String>(
                        label: s.t('mk_currency'),
                        value: _d.currency,
                        items: {for (final c in cargoCurrencyChoices(_d.currency)) c: c},
                        onChanged: (v) => setState(() => _d.currency = v ?? kDefaultCargoCurrency),
                      ),
                    ),
                  ])),
                  _Section(n: 5, title: s.t('mk_s_location'), child: Column(children: [
                    InkWell(
                      onTap: () => _pickCity(s, lang),
                      borderRadius: BorderRadius.circular(12),
                      child: InputDecorator(
                        decoration: InputDecoration(labelText: s.t('mk_city'), suffixIcon: const Icon(Icons.expand_more)),
                        child: Text(
                          (_d.city ?? '').isEmpty
                              ? s.t('mk_pick_city')
                              : [PickedPlace.fromStored(_d.city!, _d.country ?? '').flag,
                                 PickedPlace.fromStored(_d.city!, _d.country ?? '').cityLabel(lang),
                                 if ((_d.country ?? '').isNotEmpty) '· ${PickedPlace.fromStored(_d.city!, _d.country!).countryLabel(lang)}'].join(' ').trim(),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _phone,
                      keyboardType: TextInputType.phone,
                      inputFormatters: [LengthLimitingTextInputFormatter(30)],
                      decoration: InputDecoration(labelText: s.t('mk_phone'), prefixIcon: const Icon(Icons.phone_outlined)),
                    ),
                  ])),
                  _Section(
                    n: 6,
                    title: s.t('mk_s_photos'),
                    trailing: Text('${_d.photos.length} / $kMarketMaxPhotos', style: const TextStyle(color: AppColors.textSoft)),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      ReorderTileGrid(
                        ids: _d.photos,
                        tileSize: 92,
                        onReorder: (ids) => setState(() => _d.photos = ids),
                        tileBuilder: (url) => Stack(fit: StackFit.expand, children: [
                          ClipRRect(borderRadius: BorderRadius.circular(10), child: MarketPhoto(url: url)),
                          if (_d.photos.first == url)
                            Positioned(
                              left: 4,
                              bottom: 4,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(color: AppColors.accentFill, borderRadius: BorderRadius.circular(8)),
                                child: Text(s.t('mk_cover'), style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800)),
                              ),
                            ),
                          Positioned(
                            right: 2,
                            top: 2,
                            child: GestureDetector(
                              onTap: () => _removePhoto(url),
                              child: const CircleAvatar(radius: 12, backgroundColor: Colors.black87, child: Icon(Icons.close, size: 15, color: Colors.white)),
                            ),
                          ),
                        ]),
                        trailing: _d.photos.length >= kMarketMaxPhotos
                            ? null
                            : InkWell(
                                key: const ValueKey('mk-add-photo'),
                                onTap: _uploading ? null : () => _addPhotos(s),
                                borderRadius: BorderRadius.circular(10),
                                child: Container(
                                  width: 92,
                                  height: 92,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(color: AppColors.line, width: 1.5),
                                  ),
                                  alignment: Alignment.center,
                                  child: _uploading
                                      ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                                      : Column(mainAxisSize: MainAxisSize.min, children: [
                                          const Icon(Icons.add, color: AppColors.accent, size: 30),
                                          Text(s.t('mk_add_photo'), textAlign: TextAlign.center, style: const TextStyle(fontSize: 11)),
                                        ]),
                                ),
                              ),
                      ),
                      const SizedBox(height: 6),
                      Text(s.t('mk_photos_hint'), style: const TextStyle(color: AppColors.textSoft, fontSize: 11.5)),
                    ]),
                  ),
                  _Section(n: 7, title: s.t('mk_s_description'), child: TextField(
                    controller: _desc,
                    maxLines: 5,
                    minLines: 3,
                    inputFormatters: [LengthLimitingTextInputFormatter(kMarketMaxDescription)],
                    decoration: InputDecoration(
                      hintText: s.t('mk_description_hint'),
                      counterText: '${_desc.text.length}/$kMarketMaxDescription',
                    ),
                  )),
                  if (_error != null) ...[
                    const SizedBox(height: 4),
                    Text(s.t(_error!), style: const TextStyle(color: AppColors.danger)),
                  ],
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    key: const ValueKey('mk-publish'),
                    onPressed: _busy || _uploading ? null : () => _save(s, publish: true),
                    style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                    icon: _busy
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.send),
                    label: Text(s.t('mk_publish'), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                  ),
                  const SizedBox(height: 8),
                  Text(s.t(_orig?.status == MarketStatus.inactive ? 'mk_review_note' : 'mk_publish_note'), textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textSoft, fontSize: 12)),
                ],
              ),
      ),
    );
  }

  Widget _num(TextEditingController c, String label, {bool decimal = false}) => TextField(
        controller: c,
        keyboardType: TextInputType.numberWithOptions(decimal: decimal),
        decoration: InputDecoration(labelText: label),
      );
}

/// Numbered card (orange circle) like Şəkil 3.
class _Section extends StatelessWidget {
  final int n;
  final String title;
  final Widget child;
  final Widget? trailing;
  const _Section({required this.n, required this.title, required this.child, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          CircleAvatar(
            radius: 13,
            backgroundColor: AppColors.accentFill,
            child: Text('$n', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13)),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
          if (trailing != null) trailing!,
        ]),
        const SizedBox(height: 12),
        child,
      ]),
    );
  }
}

class _CatTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _CatTile({required this.icon, required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final fg = selected ? AppColors.accent : AppColors.text;
    return SizedBox(
      width: 104,
      height: 78,
      child: Material(
        color: selected ? AppColors.accent.withValues(alpha: 0.10) : AppColors.background,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: selected ? AppColors.accent : AppColors.line, width: selected ? 2 : 1),
            ),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(icon, color: fg, size: 26),
              const SizedBox(height: 4),
              Text(label, textAlign: TextAlign.center, maxLines: 2, style: TextStyle(color: fg, fontWeight: FontWeight.w700, fontSize: 12.5)),
            ]),
          ),
        ),
      ),
    );
  }
}

class _Drop<T> extends StatelessWidget {
  final String label;
  final T? value;
  final Map<T, String> items;
  final ValueChanged<T?> onChanged;
  const _Drop({required this.label, required this.value, required this.items, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<T>(
      key: ValueKey('$label-$value'),
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(labelText: label),
      items: [for (final e in items.entries) DropdownMenuItem(value: e.key, child: Text(e.value, overflow: TextOverflow.ellipsis))],
      onChanged: onChanged,
    );
  }
}

class _Note extends StatelessWidget {
  final String text;
  const _Note({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: AppColors.urgentBg, borderRadius: BorderRadius.circular(12)),
      child: Text(text, style: const TextStyle(color: AppColors.urgentFg)),
    );
  }
}
