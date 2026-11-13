import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:latlong2/latlong.dart';

import '../../../core/constants/cities.dart';
import '../../../core/constants/countries.dart';
import '../../../core/localization/app_strings.dart';
import '../../../core/localization/locale_controller.dart';
import '../../../core/router/after_save.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/city_picker.dart';
import '../../../core/widgets/published_notice.dart';
import '../../../services/geo_service.dart';
import '../../auth/presentation/providers/auth_providers.dart';
import '../../cargo/domain/truck_types.dart';
import '../../services/presentation/service_edit_screen.dart' show MapPlacePicker;
import '../../services/presentation/services_providers.dart';
import '../data/empty_truck_repository.dart';
import '../domain/empty_truck.dart';

/// "Boş maşın əlavə et" (owner, 13.11.2026): one scrolled page —
/// 1) where the truck is now (pick a town, or the map; the GPS place is only
///    OFFERED, used after the user taps it), 2) where it goes or "İstiqamət
///    fərq etmir", 3) the truck (type, free tonnes, load kinds), 4) free now
///    or from a date / time, 5) contact (from the profile / the last ad,
///    changeable), 6) "Boş maşın elanını paylaş". [editId] = edit an ad.
class EmptyTruckFormScreen extends ConsumerStatefulWidget {
  final String? editId;
  const EmptyTruckFormScreen({super.key, this.editId});

  @override
  ConsumerState<EmptyTruckFormScreen> createState() => _EmptyTruckFormScreenState();
}

class _EmptyTruckFormScreenState extends ConsumerState<EmptyTruckFormScreen> {
  PickedPlace? _from;
  LatLng? _fromPoint;
  PickedPlace? _to;
  bool _anyDirection = false;
  String? _truck;
  final _tons = TextEditingController();
  final Set<String> _bodies = {};
  DateTime? _availableFrom; // null = İndi
  final _phone = TextEditingController();
  final _whatsapp = TextEditingController();
  final _note = TextEditingController();
  bool _busy = false;
  bool _loaded = false;
  String? _error;

  // The GPS place, only offered until the user taps it.
  PickedPlace? _suggest;
  LatLng? _suggestPoint;
  bool _locating = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _prefill());
  }

  @override
  void dispose() {
    for (final c in [_tons, _phone, _whatsapp, _note]) {
      c.dispose();
    }
    super.dispose();
  }

  static PickedPlace _place(String city, String country, String? code) {
    final p = PickedPlace.fromStored(city, country);
    return p.countryCode.isEmpty && code != null ? PickedPlace(city: p.city, country: p.country, countryCode: code) : p;
  }

  /// Edit: the ad as saved. New: contact from the profile, or from the
  /// user's last empty truck ad (never typed twice).
  Future<void> _prefill() async {
    final repo = ref.read(emptyTruckRepositoryProvider);
    final me = ref.read(currentUserProvider);
    EmptyTruck? base;
    try {
      if (widget.editId != null) {
        base = await repo.byId(widget.editId!);
      } else if (me != null) {
        final mine = await ref.read(myEmptyTrucksProvider.future);
        if (mine.isNotEmpty) {
          final last = mine.first;
          _phone.text = last.phone ?? '';
          _whatsapp.text = last.whatsapp ?? '';
        }
      }
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      final t = base;
      if (t != null) {
        _from = _place(t.fromCity, t.fromCountry, t.fromIso);
        _fromPoint = t.fromLat != null && t.fromLng != null ? LatLng(t.fromLat!, t.fromLng!) : null;
        _anyDirection = t.anyDirection;
        _to = t.anyDirection || t.toCity == null ? null : _place(t.toCity!, t.toCountry ?? '', t.toIso);
        _truck = t.truckType;
        _tons.text = t.freeTons == t.freeTons.roundToDouble() ? t.freeTons.toStringAsFixed(0) : '${t.freeTons}';
        _bodies
          ..clear()
          ..addAll(t.bodyTypes);
        _availableFrom = t.availableFrom != null && t.availableFrom!.isAfter(DateTime.now()) ? t.availableFrom : null;
        _phone.text = t.phone ?? '';
        _whatsapp.text = t.whatsapp ?? '';
        _note.text = t.note ?? '';
      }
      if (_phone.text.isEmpty) _phone.text = me?.phone ?? '';
      if (_whatsapp.text.isEmpty) _whatsapp.text = _phone.text;
      _loaded = true;
    });
  }

  AppStrings get s => ref.read(stringsProvider);

  Future<PickedPlace?> _pickCity(String title) {
    final lang = ref.read(currentLocaleProvider).languageCode;
    return showModalBottomSheet<PickedPlace>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => CityPickerSheet(languageCode: lang, strings: s, title: title),
    );
  }

  /// The town of a map point: the catalogue name when known (one name in
  /// every language), otherwise as the map names it.
  Future<PickedPlace?> _placeOf(LatLng p) async {
    final r = await ref.read(geoServiceProvider).reverse(p);
    if (r == null) return null;
    final known = Cities.find(r.city);
    final country = Countries.find(r.countryCode);
    return PickedPlace(
      city: known?.en ?? r.city,
      country: country?.en ?? r.countryCode,
      countryCode: country?.code ?? r.countryCode,
    );
  }

  /// "Hazırkı yerimi təklif et": the GPS place is shown as a suggestion; it
  /// becomes the ad's place only when the user taps "Bu yeri istifadə et".
  Future<void> _suggestHere() async {
    setState(() => _locating = true);
    final p = await ref.read(userLocationProvider.notifier).locate(allowApprox: false);
    PickedPlace? place;
    if (p != null) place = await _placeOf(p);
    if (!mounted) return;
    setState(() {
      _locating = false;
      _suggest = place;
      _suggestPoint = place == null ? null : p;
    });
    if (place == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.t('et_gps_failed'))));
    }
  }

  Future<void> _pickOnMap() async {
    final start = _fromPoint ?? ref.read(userLocationProvider).point ?? kDefaultServiceCenter;
    final p = await Navigator.of(context).push<LatLng>(
        MaterialPageRoute(fullscreenDialog: true, builder: (_) => MapPlacePicker(start: start, s: s)));
    if (p == null || !mounted) return;
    final place = await _placeOf(p);
    if (!mounted) return;
    if (place == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.t('et_map_failed'))));
      return;
    }
    setState(() {
      _from = place;
      _fromPoint = p;
    });
  }

  Future<void> _pickTime() async {
    final now = DateTime.now();
    final d = await showDatePicker(
        context: context, firstDate: DateTime(now.year, now.month, now.day), lastDate: now.add(const Duration(days: 90)), initialDate: _availableFrom ?? now);
    if (d == null || !mounted) return;
    final t = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(_availableFrom ?? now.add(const Duration(hours: 1))));
    if (!mounted) return;
    setState(() => _availableFrom = DateTime(d.year, d.month, d.day, t?.hour ?? 9, t?.minute ?? 0));
  }

  Future<void> _save() async {
    if (_busy) return;
    final tons = double.tryParse(_tons.text.trim().replaceAll(',', '.'));
    final err = emptyTruckFormError(
      fromCity: _from?.city ?? '',
      fromCountry: _from?.country ?? '',
      anyDirection: _anyDirection,
      toCity: _to?.city,
      toCountry: _to?.country,
      truckType: _truck,
      freeTons: tons,
      availableFrom: _availableFrom,
      now: DateTime.now(),
    );
    if (err != null) {
      setState(() => _error = s.t(err));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final id = await ref.read(emptyTruckRepositoryProvider).save(
            id: widget.editId,
            fromCity: _from!.city,
            fromCountry: _from!.country,
            fromCode: _from!.countryCode.isEmpty ? null : _from!.countryCode,
            fromLat: _fromPoint?.latitude,
            fromLng: _fromPoint?.longitude,
            anyDirection: _anyDirection,
            toCity: _to?.city,
            toCountry: _to?.country,
            toCode: (_to?.countryCode.isEmpty ?? true) ? null : _to!.countryCode,
            truckType: _truck!,
            freeTons: tons!,
            bodyTypes: _bodies.toList(),
            availableFrom: _availableFrom,
            phone: _phone.text.trim().isEmpty ? null : _phone.text.trim(),
            whatsapp: _whatsapp.text.trim().isEmpty ? null : _whatsapp.text.trim(),
            note: _note.text.trim().isEmpty ? null : _note.text.trim(),
          );
      ref.invalidate(emptyTrucksProvider);
      ref.invalidate(myEmptyTrucksProvider);
      ref.invalidate(emptyTruckProvider(id));
      if (!mounted) return;
      if (widget.editId != null) {
        leaveAfterSave(context, fallback: '/trucks/$id', notice: s.t('et_saved'));
      } else {
        // A new ad goes straight to Daşıyıcılar (as a new load to Yüklər).
        ref.read(loadsSectionProvider.notifier).state = LoadsSection.carriers;
        showPublishedNotice(context, s.t('et_published'));
        context.go('/cargo');
      }
    } on EmptyTruckRefused catch (e) {
      if (mounted) setState(() => _error = s.t('et_err_${e.reason}'));
    } on EmptyTruckNotReady {
      if (mounted) setState(() => _error = s.t('et_not_ready'));
    } catch (_) {
      if (mounted) setState(() => _error = s.t('et_err_save'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    final lang = ref.watch(currentLocaleProvider).languageCode;
    final edit = widget.editId != null;
    Widget label(String text) => Padding(
          padding: const EdgeInsets.fromLTRB(2, 18, 2, 8),
          child: Text(text, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.text)),
        );
    Widget placeTile({required Key key, required String title, required PickedPlace? place, required VoidCallback? onTap}) =>
        Material(
          color: AppColors.card,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: AppColors.line)),
          child: ListTile(
            key: key,
            onTap: onTap,
            leading: Icon(Icons.place_outlined, color: AppColors.accent),
            title: Text(title, style: TextStyle(fontSize: 12.5, color: AppColors.textSoft)),
            subtitle: Text(
              place == null ? s.t('city_pick') : '${place.flag.isEmpty ? '' : '${place.flag} '}${place.cityLabel(lang)}, ${place.countryLabel(lang)}',
              style: TextStyle(fontSize: 16, color: place == null ? AppColors.accent : AppColors.text),
            ),
            trailing: const Icon(Icons.chevron_right),
          ),
        );

    return Scaffold(
      appBar: AppBar(title: Text(s.t(edit ? 'et_edit_title' : 'et_new_title'))),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
              children: [
                // 1) Where the truck is now.
                label(s.t('et_step_from')),
                placeTile(
                  key: const ValueKey('et-from'),
                  title: s.t('et_from_label'),
                  place: _from,
                  onTap: () async {
                    final p = await _pickCity(s.t('et_from_label'));
                    if (p != null && mounted) {
                      setState(() {
                        _from = p;
                        _fromPoint = null;
                      });
                    }
                  },
                ),
                const SizedBox(height: 8),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  OutlinedButton.icon(
                    key: const ValueKey('et-gps'),
                    onPressed: _locating ? null : _suggestHere,
                    icon: _locating
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.my_location, size: 18),
                    label: Text(s.t('et_gps_offer')),
                  ),
                  OutlinedButton.icon(
                    key: const ValueKey('et-map'),
                    onPressed: _pickOnMap,
                    icon: const Icon(Icons.map_outlined, size: 18),
                    label: Text(s.t('et_pick_on_map')),
                  ),
                ]),
                if (_suggest != null)
                  Container(
                    key: const ValueKey('et-suggest'),
                    margin: const EdgeInsets.only(top: 10),
                    padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
                    decoration: BoxDecoration(color: AppColors.cardAlt, borderRadius: BorderRadius.circular(12)),
                    child: Row(children: [
                      Icon(Icons.my_location, size: 18, color: AppColors.accent),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(s.t('et_gps_here', {'place': '${_suggest!.cityLabel(lang)}, ${_suggest!.countryLabel(lang)}'}),
                            style: TextStyle(fontSize: 14, color: AppColors.text)),
                      ),
                      TextButton(
                        key: const ValueKey('et-suggest-use'),
                        onPressed: () => setState(() {
                          _from = _suggest;
                          _fromPoint = _suggestPoint;
                          _suggest = null;
                        }),
                        child: Text(s.t('et_gps_use')),
                      ),
                    ]),
                  ),
                // 2) Where it goes.
                label(s.t('et_step_to')),
                placeTile(
                  key: const ValueKey('et-to'),
                  title: s.t('et_to_label'),
                  place: _anyDirection ? null : _to,
                  onTap: _anyDirection
                      ? null
                      : () async {
                          final p = await _pickCity(s.t('et_to_label'));
                          if (p != null && mounted) setState(() => _to = p);
                        },
                ),
                CheckboxListTile(
                  key: const ValueKey('et-any-direction'),
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: _anyDirection,
                  onChanged: (v) => setState(() => _anyDirection = v ?? false),
                  title: Text(s.t('et_any_direction')),
                ),
                if (_from != null)
                  Text(
                    key: const ValueKey('et-route-preview'),
                    '${s.t('et_route')}: ${_routePreview(lang, s)}',
                    style: TextStyle(fontSize: 14, color: AppColors.textSoft),
                  ),
                // 3) The truck.
                label(s.t('et_step_truck')),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final t in kTruckTypes)
                    ChoiceChip(
                      key: ValueKey('et-truck-$t'),
                      label: Text(s.t('truck_$t')),
                      selected: _truck == t,
                      onSelected: (on) => setState(() => _truck = on ? t : null),
                    ),
                ]),
                const SizedBox(height: 12),
                TextField(
                  key: const ValueKey('et-tons'),
                  controller: _tons,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(labelText: s.t('et_tons_label'), suffixText: 't'),
                ),
                const SizedBox(height: 12),
                Text(s.t('et_bodies_label'), style: TextStyle(fontSize: 13, color: AppColors.textSoft)),
                const SizedBox(height: 6),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final b in kEmptyTruckBodyTypes)
                    FilterChip(
                      key: ValueKey('et-body-$b'),
                      label: Text(s.t('et_body_$b')),
                      selected: _bodies.contains(b),
                      onSelected: (on) => setState(() => on ? _bodies.add(b) : _bodies.remove(b)),
                    ),
                ]),
                // 4) When it is free.
                label(s.t('et_step_time')),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  ChoiceChip(
                    key: const ValueKey('et-time-now'),
                    label: Text(s.t('et_free_now')),
                    selected: _availableFrom == null,
                    onSelected: (_) => setState(() => _availableFrom = null),
                  ),
                  ChoiceChip(
                    key: const ValueKey('et-time-pick'),
                    label: Text(_availableFrom == null
                        ? s.t('et_time_pick')
                        : DateFormat('d MMM, HH:mm', lang).format(_availableFrom!)),
                    selected: _availableFrom != null,
                    onSelected: (_) => _pickTime(),
                  ),
                ]),
                // 5) Contact.
                label(s.t('et_step_contact')),
                TextField(
                  key: const ValueKey('et-phone'),
                  controller: _phone,
                  keyboardType: TextInputType.phone,
                  decoration: InputDecoration(labelText: s.t('et_phone'), prefixIcon: const Icon(Icons.phone_outlined)),
                ),
                const SizedBox(height: 10),
                TextField(
                  key: const ValueKey('et-whatsapp'),
                  controller: _whatsapp,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(labelText: 'WhatsApp', prefixIcon: Icon(Icons.chat_outlined)),
                ),
                const SizedBox(height: 10),
                TextField(
                  key: const ValueKey('et-note'),
                  controller: _note,
                  maxLength: 300,
                  maxLines: 3,
                  minLines: 1,
                  decoration: InputDecoration(labelText: s.t('et_note')),
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(_error!, key: const ValueKey('et-error'), style: TextStyle(color: AppColors.danger)),
                  ),
                const SizedBox(height: 16),
                // 6) Share.
                FilledButton(
                  key: const ValueKey('et-save'),
                  onPressed: _busy ? null : _save,
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52), backgroundColor: AppColors.accentFill),
                  child: _busy
                      ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : Text(s.t(edit ? 'et_save' : 'et_share'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
                ),
              ],
            ),
    );
  }

  String _routePreview(String lang, AppStrings s) {
    final f = _from!;
    final from = '${f.flag.isEmpty ? '' : '${f.flag} '}${f.cityLabel(lang)}';
    if (_anyDirection || _to == null) return '$from → ${s.t('et_any_direction_short')}';
    final t = _to!;
    return '$from → ${t.flag.isEmpty ? '' : '${t.flag} '}${t.cityLabel(lang)}';
  }
}
