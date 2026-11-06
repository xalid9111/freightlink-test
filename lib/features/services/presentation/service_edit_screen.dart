import 'dart:typed_data';

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/localization/app_strings.dart';
import '../../../core/localization/locale_controller.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/city_picker.dart';
import '../../../core/widgets/framed_image.dart';
import '../../../core/widgets/reorder_tile_grid.dart';
import '../../../models/service_models.dart';
import '../../../services/geo_service.dart';
import '../../auth/presentation/providers/auth_providers.dart';
import '../../covers/profile_covers.dart';
import '../data/services_repository.dart';
import 'service_widgets.dart';
import 'services_map_screen.dart' show kShopCategory;
import 'services_providers.dart';
import '../../../core/widgets/map_tiles.dart';

/// Create / edit the signed-in user's own service profile. Moderation
/// fields (status, verified, rating) are never sent — the database
/// trigger ignores them for non-admins anyway.
class ServiceEditScreen extends ConsumerStatefulWidget {
  final String? id; // null = create
  final String? initialKind;
  /// "Mağaza əlavə et" (owner, 06.11.2026): the "+" on Mağazalar opens this
  /// same form with the shop category (spare_parts) already ticked.
  final bool shop;
  const ServiceEditScreen({super.key, this.id, this.initialKind, this.shop = false});

  @override
  ConsumerState<ServiceEditScreen> createState() => _ServiceEditScreenState();
}

class _NewPhoto {
  final Uint8List bytes;
  final String ext;
  _NewPhoto(this.bytes, this.ext);
}

/// One photo in the form, in display order: an uploaded one ([url]) or a
/// new one waiting for "Yadda saxla" ([fresh]). [id] is stable for drag &
/// drop.
class _PhotoEntry {
  final String id;
  final String? url;
  final _NewPhoto? fresh;
  _PhotoEntry.uploaded(String this.url)
      : id = 'u:$url',
        fresh = null;
  _PhotoEntry.added(_NewPhoto this.fresh, int n)
      : id = 'n:$n',
        url = null;
}

class _ServiceEditScreenState extends ConsumerState<ServiceEditScreen> {
  static const _maxPhotos = 10; // the server allows 10 (0017)

  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _specialty = TextEditingController();
  final _description = TextEditingController();
  final _address = TextEditingController();
  final _phone = TextEditingController();
  final _whatsapp = TextEditingController();
  final _hours = TextEditingController();
  final _radius = TextEditingController();
  final _mapCtrl = MapController();

  ServiceProvider? _existing;
  bool _loading = true;
  bool _saving = false;
  bool _locating = false;
  String? _error;

  String _kind = 'individual';
  final Set<String> _cats = {};
  PickedPlace? _place;
  LatLng? _point;
  bool _mobile = false;
  bool _is24h = false;
  bool _active = true;
  /// All photos in the order the owner arranged them (first = main photo).
  List<_PhotoEntry> _photos = [];
  int _newCount = 0;
  final List<String> _removedPhotos = [];
  /// Mağaza form (owner, 06.11.2026): shop fields only, never mixed with
  /// the service ones.
  bool _shopForm = false;
  /// Logo and background (0096 / 0097): picked here, saved with the profile.
  String? _coverUrl, _logoUrl;
  bool _coverDirty = false, _logoDirty = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final uid = ref.read(currentUserIdProvider);
    try {
      ServiceProvider? p;
      if (widget.id != null) {
        p = await ref.read(servicesRepositoryProvider).byId(widget.id!);
      } else if (uid != null) {
        // Already has a profile → edit it instead of creating a second.
        p = await ref.read(servicesRepositoryProvider).mine(uid);
      }
      if (!mounted) return;
      _shopForm = widget.shop ||
          (p != null && p.categories.contains(kShopCategory) && p.categories.every((c) => c == kShopCategory || c.startsWith('shop_')));
      if (p != null) {
        final media = await ref.read(coverRepositoryProvider).serviceMedia(p.id);
        if (!mounted) return;
        _coverUrl = media.cover;
        _logoUrl = media.logo;
        _existing = p;
        _kind = p.kind;
        _name.text = p.name;
        _specialty.text = p.specialty ?? '';
        _description.text = p.description ?? '';
        _address.text = p.address ?? '';
        _phone.text = p.phone ?? '';
        _whatsapp.text = p.whatsapp ?? '';
        _hours.text = p.workingHours ?? '';
        _radius.text = p.serviceRadiusKm?.toString() ?? '';
        _cats.addAll(p.categories);
        if (widget.shop) _cats.add(kShopCategory);
        if ((p.city ?? '').isNotEmpty) _place = PickedPlace.fromStored(p.city!, p.country ?? '');
        _point = LatLng(p.lat, p.lng);
        _mobile = p.isMobile;
        _is24h = p.is24h;
        _active = p.isActive;
        _photos = [for (final u in p.photos) _PhotoEntry.uploaded(u)];
      } else {
        _kind = _shopForm || widget.initialKind == 'center' ? 'center' : 'individual';
        if (_shopForm) _cats.add(kShopCategory);
        _mobile = !_shopForm && _kind == 'individual';
        final me = ref.read(currentUserProvider);
        _phone.text = me?.phone ?? '';
        // The name starts empty: only the faint "Servis adı" / "Mağaza adı"
        // placeholder (owner, 06.11.2026).
        // Start from the phone's position when it is already known.
        _point = ref.read(userLocationProvider).point;
      }
    } catch (_) {
      _error = ref.read(stringsProvider).t('svc_load_failed');
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  void dispose() {
    for (final c in [_name, _specialty, _description, _address, _phone, _whatsapp, _hours, _radius]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _useGps() async {
    setState(() => _locating = true);
    // The pin is saved as the service's address: a real position only.
    final p = await ref.read(userLocationProvider.notifier).locate(allowApprox: false);
    if (!mounted) return;
    setState(() {
      _locating = false;
      if (p != null) _point = p;
    });
    if (p == null) {
      // Say why (location off on the device / blocked / not found), not just "failed".
      final why = gpsMessageKey(ref.read(userLocationProvider).state) ?? 'svc_gps_failed';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ref.read(stringsProvider).t(why))));
    } else {
      try {
        _mapCtrl.move(p, 15);
      } catch (_) {}
    }
  }

  Future<void> _pickCity() async {
    final s = ref.read(stringsProvider);
    final lang = ref.read(currentLocaleProvider).languageCode;
    final picked = await showModalBottomSheet<PickedPlace>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => CityPickerSheet(languageCode: lang, strings: s, title: s.t('svc_city')),
    );
    if (picked == null || !mounted) return;
    setState(() => _place = picked);
    if (_point == null) {
      final p = await ref.read(geoServiceProvider).geocode('${picked.city}, ${picked.country}');
      if (p != null && mounted) {
        setState(() => _point = p);
        try {
          _mapCtrl.move(p, 13);
        } catch (_) {}
      }
    }
  }

  Future<void> _addPhoto() async {
    if (_photos.length >= _maxPhotos) return;
    final f = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1600, maxHeight: 1600, imageQuality: 80);
    if (f == null) return;
    final bytes = await f.readAsBytes();
    if (bytes.length > 5 * 1024 * 1024) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ref.read(stringsProvider).t('chat_file_too_big'))));
      return;
    }
    final name = f.name.toLowerCase();
    final ext = name.endsWith('.png') ? 'png' : (name.endsWith('.webp') ? 'webp' : 'jpg');
    setState(() => _photos.add(_PhotoEntry.added(_NewPhoto(bytes, ext), _newCount++)));
  }

  Future<void> _save() async {
    final s = ref.read(stringsProvider);
    if (!_form.currentState!.validate()) return;
    if (_shopForm && !_cats.any((c) => c.startsWith('shop_'))) {
      setState(() => _error = s.t('shop_pick_kind'));
      return;
    }
    if (!_shopForm && !_cats.any((c) => !c.startsWith('shop_'))) {
      setState(() => _error = s.t('svc_pick_category'));
      return;
    }
    if (_point == null) {
      setState(() => _error = s.t('svc_pick_location'));
      return;
    }
    final uid = ref.read(currentUserIdProvider);
    if (uid == null) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final repo = ref.read(servicesRepositoryProvider);
    try {
      final draft = ServiceProvider(
        id: _existing?.id ?? '',
        ownerId: uid,
        kind: _kind,
        name: _name.text,
        specialty: _specialty.text,
        description: _description.text,
        categories: _cats.toList(),
        country: _place?.country,
        city: _place?.city,
        address: _address.text,
        lat: _point!.latitude,
        lng: _point!.longitude,
        isMobile: _mobile,
        serviceRadiusKm: _mobile ? int.tryParse(_radius.text.trim()) : null,
        phone: _phone.text,
        whatsapp: _whatsapp.text,
        workingHours: _is24h ? null : _hours.text,
        is24h: _is24h,
        isActive: _active,
        status: _existing?.status ?? 'pending',
        isVerified: _existing?.isVerified ?? false,
        addedByAdmin: _existing?.addedByAdmin ?? false,
        photos: [for (final e in _photos) if (e.url != null) e.url!],
        ratingAvg: 0,
        ratingCount: 0,
      );
      ServiceProvider saved;
      if (_existing == null) {
        saved = await repo.create(draft, uid);
      } else {
        final patch = draft.toWriteJson()..remove('photos');
        saved = await repo.update(_existing!.id, patch);
      }
      // Photos need the profile id (folder) — upload after the row exists.
      // New photos are uploaded in place, so the saved order is exactly the
      // order on screen (drag & drop included).
      final urls = <String>[];
      for (final e in _photos) {
        urls.add(e.url ?? await repo.uploadPhoto(saved.id, e.fresh!.bytes, e.fresh!.ext));
      }
      if (_existing == null || _removedPhotos.isNotEmpty || !listEquals(urls, _existing!.photos)) {
        saved = await repo.update(saved.id, {'photos': urls});
      }
      for (final u in _removedPhotos) {
        await repo.removePhotoFile(u);
      }
      await _saveMedia(saved.id);
      ref.invalidate(myServiceProvider);
      ref.invalidate(serviceByIdProvider(saved.id));
      ref.invalidate(serviceNearbyProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.t(_existing == null ? 'svc_created' : 'svc_saved'))));
      context.pushReplacement('/service/${saved.id}');
    } catch (e) {
      final raw = e.toString();
      if (mounted) {
        setState(() => _error = raw.contains('uq_service_providers_owner') || raw.contains('23505')
          ? s.t('svc_already_have')
          : s.t('svc_save_failed'));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Logo / background after the row exists; a failure here never loses
  /// the saved profile (it is said, and can be done again on its page).
  Future<void> _saveMedia(String id) async {
    if (!_coverDirty && !_logoDirty) return;
    final media = ref.read(coverRepositoryProvider);
    try {
      if (_coverDirty) await media.setServiceCover(id, _coverUrl);
      if (_logoDirty) await media.setServiceLogo(id, _logoUrl);
      _coverDirty = _logoDirty = false;
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ref.read(stringsProvider).t('cover_error'))));
    }
    ref.invalidate(placeMediaProvider((CoverSection.service, id)));
  }

  Future<void> _pickCover() async {
    final s = ref.read(stringsProvider);
    final repo = ref.read(coverRepositoryProvider);
    await changeCover(
      context: context,
      ref: ref,
      s: s,
      section: CoverSection.service,
      current: _coverUrl,
      aspect: kPlaceCoverAspect,
      upload: (b, t) => repo.upload('service-${_existing?.id ?? 'new'}', b, contentType: t),
      save: (url) async => setState(() {
        _coverUrl = url;
        _coverDirty = true;
      }),
    );
  }

  Future<void> _pickLogo() async {
    final s = ref.read(stringsProvider);
    final repo = ref.read(coverRepositoryProvider);
    await changeRoundPicture(
      context: context,
      s: s,
      upload: (b, t) => repo.upload('service-logo-${_existing?.id ?? 'new'}', b, contentType: t),
      save: (url) async => setState(() {
        _logoUrl = url;
        _logoDirty = true;
      }),
    );
  }

  /// "Xəritədə yeri seç": the whole screen, the pin in the middle.
  Future<void> _pickOnMap() async {
    final s = ref.read(stringsProvider);
    final p = await Navigator.of(context).push<LatLng>(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => _MapPlacePicker(start: _point ?? ref.read(userLocationProvider).point ?? kDefaultServiceCenter, s: s),
    ));
    if (p == null || !mounted) return;
    setState(() => _point = p);
    try {
      _mapCtrl.move(p, 15);
    } catch (_) {}
  }

  Future<void> _delete() async {
    final s = ref.read(stringsProvider);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.t('svc_delete_title')),
        content: Text(s.t('svc_delete_body')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(s.t('common_cancel'))),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(s.t('svc_delete')),
          ),
        ],
      ),
    );
    if (ok != true || _existing == null || !mounted) return;
    setState(() => _saving = true);
    try {
      final repo = ref.read(servicesRepositoryProvider);
      await repo.delete(_existing!.id);
      for (final u in _existing!.photos) {
        await repo.removePhotoFile(u);
      }
      ref.invalidate(myServiceProvider);
      ref.invalidate(serviceNearbyProvider);
      if (mounted) context.go('/services');
    } catch (_) {
      if (mounted) setState(() => _error = s.t('svc_save_failed'));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    final lang = ref.watch(currentLocaleProvider).languageCode;
    final cats = ref.watch(serviceCategoriesProvider);

    final shop = _shopForm;
    final title = shop
        ? (_existing == null ? 'shop_create_title' : 'shop_edit_title')
        : (_existing == null ? 'svc_profile_create_title' : 'svc_edit_title');
    // The kinds of this form only: shop products on the Mağaza form, the
    // service kinds (spare_parts included, as before) on the Servis form.
    final kinds = [
      for (final c in cats.valueOrNull ?? const <ServiceCategory>[])
        if (shop ? c.isShopKind : !c.isShopKind) c,
    ];

    return Scaffold(
      appBar: AppBar(
        leading: context.canPop()
            ? null
            : IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.go('/services')),
        title: Text(s.t(title)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: Form(
                key: _form,
                child: ListView(
                  key: const ValueKey('svc-form'),
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
                  children: [
                    // One service per owner: the shop is added to it.
                    if (widget.shop && _existing != null && !_existing!.categories.contains(kShopCategory))
                      _Note(key: const ValueKey('svc-shop-note'), text: s.t('svc_shop_note')),
                    // Logo + background (no ready names, logos or texts on them).
                    _MediaRow(
                      logoUrl: _logoUrl,
                      coverUrl: _coverUrl,
                      logoLabel: s.t('media_logo_add'),
                      coverLabel: s.t(_coverUrl == null ? 'media_cover_add' : 'cover_change'),
                      onLogo: _saving ? null : _pickLogo,
                      onCover: _saving ? null : _pickCover,
                      onLogoClear: () => setState(() {
                        _logoUrl = null;
                        _logoDirty = true;
                      }),
                      onCoverClear: () => setState(() {
                        _coverUrl = null;
                        _coverDirty = true;
                      }),
                    ),
                    if (!shop) ...[
                      _Section(icon: Icons.handyman_outlined, title: s.t('svc_kind')),
                      SegmentedButton<String>(
                        segments: [
                          ButtonSegment(value: 'individual', icon: const Icon(Icons.handyman_outlined, size: 18), label: Text(s.t('svc_kind_individual'))),
                          ButtonSegment(value: 'center', icon: const Icon(Icons.car_repair, size: 18), label: Text(s.t('svc_kind_center'))),
                        ],
                        selected: {_kind},
                        onSelectionChanged: (v) => setState(() => _kind = v.first),
                      ),
                    ],
                    _Section(
                      icon: shop ? Icons.storefront_outlined : Icons.home_repair_service_outlined,
                      title: s.t(shop ? 'shop_name' : (_kind == 'center' ? 'svc_name_center' : 'svc_name_individual')),
                      required: true,
                    ),
                    TextFormField(
                      key: const ValueKey('svc-name'),
                      controller: _name,
                      maxLength: 120,
                      textCapitalization: TextCapitalization.words,
                      decoration: InputDecoration(hintText: s.t(shop ? 'shop_name_hint' : 'svc_name_hint'), counterText: ''),
                      validator: (v) => (v == null || v.trim().length < 2) ? s.t('field_required') : null,
                    ),
                    if (!shop) ...[
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _specialty,
                        maxLength: 200,
                        decoration: InputDecoration(labelText: s.t('svc_specialty'), hintText: s.t('svc_specialty_hint'), counterText: ''),
                      ),
                    ],
                    _Section(
                      icon: shop ? Icons.inventory_2_outlined : Icons.build_outlined,
                      title: s.t(shop ? 'shop_kinds' : 'svc_categories'),
                      sub: s.t(shop ? 'shop_kinds_sub' : 'svc_categories_sub'),
                      required: true,
                    ),
                    if (cats.isLoading && !cats.hasValue)
                      const LinearProgressIndicator()
                    else if (cats.hasError && !cats.hasValue)
                      Text(s.t('svc_load_failed'))
                    else
                      Wrap(
                        key: const ValueKey('svc-kinds'),
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final c in kinds)
                            FilterChip(
                              key: ValueKey('svc-kind-${c.id}'),
                              avatar: Icon(shop ? shopKindIcon(c.id) : serviceCategoryIcon(c.icon), size: 18),
                              label: Text(shop ? s.t('shop_kind_${c.id.substring(5)}') : c.name(lang), style: const TextStyle(fontSize: 14)),
                              selected: _cats.contains(c.id),
                              onSelected: (v) => setState(() => v ? _cats.add(c.id) : _cats.remove(c.id)),
                            ),
                        ],
                      ),
                    _Section(icon: Icons.description_outlined, title: s.t(shop ? 'shop_about' : 'svc_about')),
                    TextFormField(
                      controller: _description,
                      maxLength: 2000,
                      minLines: 3,
                      maxLines: 6,
                      decoration: InputDecoration(hintText: s.t(shop ? 'shop_about_hint' : 'svc_description_hint')),
                    ),
                    _Section(icon: Icons.place_outlined, title: s.t('svc_address_title')),
                    OutlinedButton.icon(
                      key: const ValueKey('svc-city'),
                      onPressed: _pickCity,
                      style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                      icon: Text(_place?.flag ?? '📍'),
                      label: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          _place == null ? s.t('svc_city_pick') : '${_place!.cityLabel(lang)}, ${_place!.countryLabel(lang)}',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _address,
                      maxLength: 300,
                      decoration: InputDecoration(labelText: s.t('svc_address'), hintText: s.t('svc_address_hint'), counterText: ''),
                    ),
                    const SizedBox(height: 12),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: SizedBox(
                        height: 200,
                        child: FlutterMap(
                          mapController: _mapCtrl,
                          options: MapOptions(
                            initialCenter: _point ?? kDefaultServiceCenter,
                            initialZoom: _point == null ? 10 : 15,
                            backgroundColor: AppColors.hero,
                            interactionOptions: const InteractionOptions(flags: InteractiveFlag.all & ~InteractiveFlag.rotate),
                            onTap: (_, p) => setState(() => _point = p),
                          ),
                          children: [
                            const AppTileLayer(),
                            if (_point != null)
                              MarkerLayer(markers: [
                                Marker(
                                  point: _point!,
                                  width: 44,
                                  height: 44,
                                  child: ServicePin(
                                    type: _cats.contains('tow')
                                        ? ServiceMarkerType.tow
                                        : (_kind == 'center' ? ServiceMarkerType.center : ServiceMarkerType.mobile),
                                    selected: true,
                                  ),
                                ),
                              ]),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(children: [
                      Expanded(
                        child: FilledButton.tonalIcon(
                          key: const ValueKey('svc-map-pick'),
                          onPressed: _pickOnMap,
                          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                          icon: const Icon(Icons.my_location),
                          label: Text(s.t('map_pick_place')),
                        ),
                      ),
                      const SizedBox(width: 8),
                      TextButton.icon(
                        onPressed: _locating ? null : _useGps,
                        icon: _locating
                            ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.gps_fixed, size: 18),
                        label: Text(s.t('svc_use_gps')),
                      ),
                    ]),
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        _point == null ? s.t('svc_map_hint_empty') : s.t('svc_map_hint'),
                        style: TextStyle(fontSize: 12.5, color: AppColors.textSoft),
                      ),
                    ),
                    if (!shop) ...[
                      const SizedBox(height: 6),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(s.t('svc_mobile_switch')),
                        subtitle: Text(s.t('svc_mobile_switch_sub'), style: const TextStyle(fontSize: 12)),
                        value: _mobile,
                        onChanged: (v) => setState(() => _mobile = v),
                      ),
                      if (_mobile)
                        TextFormField(
                          controller: _radius,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(labelText: s.t('svc_radius'), suffixText: 'km'),
                          validator: (v) {
                            final t = (v ?? '').trim();
                            if (t.isEmpty) return null;
                            final n = int.tryParse(t);
                            return (n == null || n < 1 || n > 2000) ? s.t('svc_radius_invalid') : null;
                          },
                        ),
                    ],
                    _Section(icon: Icons.call_outlined, title: s.t('svc_contacts')),
                    TextFormField(
                      key: const ValueKey('svc-phone'),
                      controller: _phone,
                      keyboardType: TextInputType.phone,
                      decoration: InputDecoration(
                        labelText: '${s.t('svc_phone')} *',
                        hintText: '+994 50 123 45 67',
                        prefixIcon: const Icon(Icons.phone_outlined),
                      ),
                      validator: (v) => (v ?? '').replaceAll(RegExp(r'[^0-9]'), '').length < 7 ? s.t('profile_phone_invalid') : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _whatsapp,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(labelText: 'WhatsApp', prefixIcon: Icon(Icons.chat_outlined)),
                    ),
                    _Section(icon: Icons.schedule_outlined, title: s.t('svc_hours')),
                    if (!_is24h)
                      TextFormField(
                        controller: _hours,
                        maxLength: 300,
                        decoration: InputDecoration(hintText: s.t('svc_hours_hint'), counterText: ''),
                      ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(s.t('svc_24h')),
                      value: _is24h,
                      onChanged: (v) => setState(() => _is24h = v),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(s.t(shop ? 'shop_open_now' : 'svc_available_now')),
                      subtitle: Text(s.t(shop ? 'shop_open_now_sub' : 'svc_available_now_sub'), style: const TextStyle(fontSize: 12)),
                      value: _active,
                      onChanged: (v) => setState(() => _active = v),
                    ),
                    _Section(
                      icon: Icons.photo_library_outlined,
                      title: '${s.t(shop ? 'shop_photos' : 'svc_photos_title')} (${_photos.length}/$_maxPhotos)',
                    ),
                    if (_photos.length > 1)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(s.t('svc_photos_reorder_hint'), style: TextStyle(fontSize: 12, color: AppColors.textSoft)),
                      ),
                    ReorderTileGrid(
                      ids: [for (final e in _photos) e.id],
                      onReorder: (ids) => setState(() {
                        final byId = {for (final e in _photos) e.id: e};
                        _photos = [for (final id in ids) byId[id]!];
                      }),
                      tileBuilder: (id) {
                        final e = _photos.firstWhere((x) => x.id == id);
                        return _Thumb(
                          image: e.url != null ? Image.network(e.url!, fit: BoxFit.cover) : Image.memory(e.fresh!.bytes, fit: BoxFit.cover),
                          onRemove: () => setState(() {
                            _photos.remove(e);
                            if (e.url != null) _removedPhotos.add(e.url!);
                          }),
                        );
                      },
                      trailing: _photos.length < _maxPhotos
                          ? InkWell(
                              key: const ValueKey('svc-photo-add'),
                              onTap: _addPhoto,
                              borderRadius: BorderRadius.circular(10),
                              child: Container(
                                width: 84,
                                height: 84,
                                decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(10)),
                                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                                  Icon(Icons.add_photo_alternate_outlined, color: AppColors.accent),
                                  const SizedBox(height: 4),
                                  Text(s.t('photo_add'), textAlign: TextAlign.center, style: TextStyle(fontSize: 11.5, color: AppColors.textSoft)),
                                ]),
                              ),
                            )
                          : null,
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 14),
                      Text(_error!, key: const ValueKey('svc-error'), style: TextStyle(color: AppColors.danger)),
                    ],
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      key: const ValueKey('svc-save'),
                      onPressed: _saving ? null : _save,
                      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(54)),
                      icon: _saving
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : Icon(shop ? Icons.storefront_outlined : Icons.home_repair_service_outlined),
                      label: Text(s.t(shop ? 'shop_save' : 'svc_profile_save'), style: const TextStyle(fontSize: 16)),
                    ),
                    if (_existing != null) ...[
                      const SizedBox(height: 10),
                      TextButton.icon(
                        onPressed: _saving ? null : _delete,
                        style: TextButton.styleFrom(foregroundColor: AppColors.danger),
                        icon: const Icon(Icons.delete_outline),
                        label: Text(s.t('svc_delete')),
                      ),
                    ],
                  ],
                ),
              ),
            ),
    );
  }
}

/// The icon of a shop's product kind (0097).
IconData shopKindIcon(String id) => switch (id) {
      'shop_new' => Icons.settings_outlined,
      'shop_used' => Icons.autorenew,
      'shop_engine' => Icons.precision_manufacturing_outlined,
      'shop_electric' => Icons.bolt_outlined,
      'shop_tyres' => Icons.tire_repair_outlined,
      'shop_oils' => Icons.water_drop_outlined,
      'shop_accessories' => Icons.category_outlined,
      _ => Icons.more_horiz,
    };

/// A section heading: icon, title (w600), "*" when required, a hint under it.
class _Section extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? sub;
  final bool required;
  const _Section({required this.icon, required this.title, this.sub, this.required = false});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 26, bottom: 10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(icon, size: 22, color: AppColors.accent),
            const SizedBox(width: 10),
            Flexible(child: Text(title, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: AppColors.text))),
            if (required) Text(' *', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: AppColors.accent)),
          ]),
          if (sub != null)
            Padding(
              padding: const EdgeInsets.only(top: 4, left: 32),
              child: Text(sub!, style: TextStyle(fontSize: 13, color: AppColors.textSoft)),
            ),
        ]),
      );
}

class _Note extends StatelessWidget {
  final String text;
  const _Note({super.key, required this.text});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(color: AppColors.cardAlt, borderRadius: BorderRadius.circular(12)),
        child: Text(text, style: TextStyle(fontSize: 13, color: AppColors.textSoft, height: 1.35)),
      );
}

/// Logo (square, left) and background (right), as in the owner's picture.
class _MediaRow extends StatelessWidget {
  final String? logoUrl, coverUrl;
  final String logoLabel, coverLabel;
  final VoidCallback? onLogo, onCover;
  final VoidCallback onLogoClear, onCoverClear;
  const _MediaRow({
    required this.logoUrl,
    required this.coverUrl,
    required this.logoLabel,
    required this.coverLabel,
    required this.onLogo,
    required this.onCover,
    required this.onLogoClear,
    required this.onCoverClear,
  });

  Widget _empty(IconData icon, String label) => Container(
        color: AppColors.card,
        alignment: Alignment.center,
        padding: const EdgeInsets.all(8),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, color: AppColors.accent, size: 28),
          const SizedBox(height: 6),
          Text(label, textAlign: TextAlign.center, maxLines: 2, style: TextStyle(fontSize: 12.5, color: AppColors.text)),
        ]),
      );

  Widget _clear(VoidCallback onTap, String key) => Positioned(
        top: 6,
        right: 6,
        child: InkWell(
          key: ValueKey(key),
          onTap: onTap,
          child: Container(
            decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
            padding: const EdgeInsets.all(4),
            child: const Icon(Icons.close, size: 16, color: Colors.white),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    const h = 112.0;
    return SizedBox(
      height: h,
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(
          width: h,
          child: Stack(fit: StackFit.expand, children: [
            InkWell(
              key: const ValueKey('svc-logo'),
              onTap: onLogo,
              borderRadius: BorderRadius.circular(16),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: roundPicture(logoUrl, _empty(Icons.add_a_photo_outlined, logoLabel)),
              ),
            ),
            if (logoUrl != null) _clear(onLogoClear, 'svc-logo-clear'),
          ]),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Stack(fit: StackFit.expand, children: [
            InkWell(
              key: const ValueKey('svc-cover'),
              onTap: onCover,
              borderRadius: BorderRadius.circular(16),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: (coverUrl ?? '').isEmpty
                    ? _empty(Icons.add_photo_alternate_outlined, coverLabel)
                    : FramedImage(
                        image: NetworkImage(coverUrl!),
                        framing: ImageFraming.of(coverUrl),
                        errorBuilder: (_, __, ___) => _empty(Icons.add_photo_alternate_outlined, coverLabel),
                      ),
              ),
            ),
            if (coverUrl != null) _clear(onCoverClear, 'svc-cover-clear'),
          ]),
        ),
      ]),
    );
  }
}

/// "Xəritədə yeri seç": move the map under the pin, then "Bu yeri seç".
class _MapPlacePicker extends StatefulWidget {
  final LatLng start;
  final AppStrings s;
  const _MapPlacePicker({required this.start, required this.s});

  @override
  State<_MapPlacePicker> createState() => _MapPlacePickerState();
}

class _MapPlacePickerState extends State<_MapPlacePicker> {
  final _map = MapController();
  late LatLng _centre = widget.start;

  @override
  Widget build(BuildContext context) {
    final s = widget.s;
    return Scaffold(
      appBar: AppBar(title: Text(s.t('map_pick_place'))),
      body: Stack(children: [
        FlutterMap(
          mapController: _map,
          options: MapOptions(
            initialCenter: widget.start,
            initialZoom: 15,
            backgroundColor: AppColors.hero,
            interactionOptions: const InteractionOptions(flags: InteractiveFlag.all & ~InteractiveFlag.rotate),
            onPositionChanged: (camera, _) => _centre = camera.center,
          ),
          children: const [AppTileLayer()],
        ),
        IgnorePointer(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 44),
              child: Icon(Icons.location_on, size: 48, color: AppColors.accent),
            ),
          ),
        ),
        Positioned(
          left: 16,
          right: 16,
          bottom: 24,
          child: SafeArea(
            child: FilledButton.icon(
              key: const ValueKey('map-pick-confirm'),
              onPressed: () => Navigator.of(context).pop(_centre),
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
              icon: const Icon(Icons.check),
              label: Text(s.t('map_pick_confirm')),
            ),
          ),
        ),
      ]),
    );
  }
}

class _Thumb extends StatelessWidget {
  final Widget image;
  final VoidCallback onRemove;
  const _Thumb({required this.image, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 84,
      height: 84,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ClipRRect(borderRadius: BorderRadius.circular(10), child: image),
          Positioned(
            top: 2,
            right: 2,
            child: InkWell(
              onTap: onRemove,
              child: Container(
                decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                padding: const EdgeInsets.all(3),
                child: const Icon(Icons.close, size: 14, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// "Join as a mechanic / service": pick individual or centre. Existing
/// users keep their account and role — this only adds a service profile.
class ServiceJoinScreen extends ConsumerWidget {
  const ServiceJoinScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final mine = ref.watch(myServiceProvider);
    return Scaffold(
      appBar: AppBar(title: Text(s.t('svc_join_title'))),
      body: mine.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => Center(child: Text(s.t('svc_load_failed'))),
        data: (p) => ListView(
          padding: const EdgeInsets.all(20),
          children: [
            if (p != null) ...[
              Text(s.t('svc_join_have'), style: TextStyle(color: AppColors.textSoft)),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: () => context.pushReplacement('/service/${p.id}'),
                icon: const Icon(Icons.storefront),
                label: Text(s.t('svc_my_service')),
              ),
            ] else ...[
              Text(s.t('svc_join_intro'), style: TextStyle(color: AppColors.textSoft, height: 1.4)),
              const SizedBox(height: 16),
              _JoinCard(
                icon: Icons.handyman_outlined,
                title: s.t('svc_kind_individual'),
                sub: s.t('svc_kind_individual_sub'),
                onTap: () => context.pushReplacement('/service-edit?kind=individual'),
              ),
              const SizedBox(height: 10),
              _JoinCard(
                icon: Icons.car_repair,
                title: s.t('svc_kind_center'),
                sub: s.t('svc_kind_center_sub'),
                onTap: () => context.pushReplacement('/service-edit?kind=center'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _JoinCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String sub;
  final VoidCallback onTap;
  const _JoinCard({required this.icon, required this.title, required this.sub, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        leading: Icon(icon, color: AppColors.accent, size: 30),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w400)),
        subtitle: Text(sub),
        trailing: const Icon(Icons.arrow_forward_ios, size: 16),
        onTap: onTap,
      ),
    );
  }
}

/// Used by the admin form too.
String serviceKindLabel(AppStrings s, String kind) => s.t(kind == 'center' ? 'svc_kind_center' : 'svc_kind_individual');
