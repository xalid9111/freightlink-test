import 'dart:typed_data';
import 'dart:ui' as ui;

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
import '../../../core/widgets/published_notice.dart';
import '../../../core/router/after_save.dart';

/// Create / edit the signed-in user's own service profile. Moderation
/// fields (status, verified, rating) are never sent — the database
/// trigger ignores them for non-admins anyway.
class ServiceEditScreen extends ConsumerStatefulWidget {
  final String? id; // null = create
  final String? initialKind;
  /// "Mağaza əlavə et" (owner, 06.11.2026): the "+" on Mağazalar opens this
  /// same form with the shop category (spare_parts) already ticked.
  final bool shop;
  /// A shop kind ticked when the form opens (shop_used from "Mağaza əlavə
  /// et" → "İşlənmiş ehtiyat hissələri", owner 09.11.2026); only shop_* kinds.
  final String? initialShopKind;
  const ServiceEditScreen({super.key, this.id, this.initialKind, this.shop = false, this.initialShopKind});

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

  /// Saved and on the way back: a second tap creates nothing (owner, 09.11.2026).
  bool _left = false;
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
        if (widget.shop && kShopKindOrder.contains(widget.initialShopKind)) _cats.add(widget.initialShopKind!);
        if ((p.city ?? '').isNotEmpty) _place = PickedPlace.fromStored(p.city!, p.country ?? '');
        _point = LatLng(p.lat, p.lng);
        _mobile = p.isMobile;
        _is24h = p.is24h;
        _active = p.isActive;
        _photos = [for (final u in p.photos) _PhotoEntry.uploaded(u)];
      } else {
        _kind = _shopForm || widget.initialKind == 'center' ? 'center' : 'individual';
        if (_shopForm) _cats.add(kShopCategory);
        if (_shopForm && kShopKindOrder.contains(widget.initialShopKind)) _cats.add(widget.initialShopKind!);
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
    if (_saving || _left) return; // a double tap never saves twice
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
      if (_existing == null) {
        // A new service / shop: straight back to its map with a clear
        // green notice (owner, 07.11.2026).
        _left = true;
        showPublishedNotice(context, s.t(_shopForm ? 'pub_shop_done' : 'pub_service_done'));
        context.go(_shopForm ? '/services?shops=1' : '/services');
        return;
      }
      // Edited: back to the page it was opened from (the service / shop
      // page reads the refreshed profile) — no second copy of that page in
      // the history any more; opened from a link: the saved page.
      _left = true;
      leaveAfterSave(context, fallback: '/service/${saved.id}', notice: s.t('svc_saved'));
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
      builder: (_) => MapPlacePicker(start: _point ?? ref.read(userLocationProvider).point ?? kDefaultServiceCenter, s: s),
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
    final all = cats.valueOrNull ?? const <ServiceCategory>[];
    // The kinds of this form only. The shop's kinds in their fixed order
    // (shown even before SQL 0097, which stores them); the service kinds
    // (spare_parts included, as before) from the server.
    final kinds = shop
        ? [
            for (final id in kShopKindOrder)
              all.firstWhere((c) => c.id == id,
                  orElse: () => ServiceCategory(id: id, names: const {}, icon: 'parts', sortOrder: 0, isActive: true)),
          ]
        : [for (final c in all) if (!c.isShopKind) c];

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
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
                  children: [
                    // One service per owner: the shop is added to it.
                    if (widget.shop && _existing != null && !_existing!.categories.contains(kShopCategory))
                      _Note(key: const ValueKey('svc-shop-note'), text: s.t('svc_shop_note')),
                    // Logo + background (no ready names, logos or texts on them).
                    _MediaRow(
                      logoUrl: _logoUrl,
                      coverUrl: _coverUrl,
                      name: _name,
                      nameHint: s.t(shop ? 'shop_name_hint' : 'svc_name_hint'),
                      hint: s.t('media_hint'),
                      shop: shop,
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
                      _FieldLabel(s.t('svc_kind')),
                      SegmentedButton<String>(
                        segments: [
                          ButtonSegment(value: 'individual', icon: const Icon(Icons.handyman_outlined, size: 18), label: Text(s.t('svc_kind_individual'))),
                          ButtonSegment(value: 'center', icon: const Icon(Icons.car_repair, size: 18), label: Text(s.t('svc_kind_center'))),
                        ],
                        selected: {_kind},
                        onSelectionChanged: (v) => setState(() => _kind = v.first),
                      ),
                    ],
                    _FieldLabel(s.t(shop ? 'shop_name' : (_kind == 'center' ? 'svc_name_center' : 'svc_name_individual')), required: true),
                    TextFormField(
                      key: const ValueKey('svc-name'),
                      controller: _name,
                      maxLength: 120,
                      textCapitalization: TextCapitalization.words,
                      decoration: InputDecoration(
                        hintText: s.t(shop ? 'shop_name_hint' : 'svc_name_hint'),
                        counterText: '',
                        prefixIcon: Icon(shop ? Icons.storefront_outlined : Icons.home_repair_service_outlined),
                      ),
                      validator: (v) => (v == null || v.trim().length < 2) ? s.t('field_required') : null,
                    ),
                    if (!shop) ...[
                      _FieldLabel(s.t('svc_specialty')),
                      TextFormField(
                        controller: _specialty,
                        maxLength: 200,
                        decoration: InputDecoration(hintText: s.t('svc_specialty_hint'), counterText: ''),
                      ),
                    ],
                    _FieldLabel(s.t(shop ? 'shop_kinds' : 'svc_categories'), required: true),
                    if (!shop && cats.isLoading && !cats.hasValue)
                      const LinearProgressIndicator()
                    else if (!shop && cats.hasError && !cats.hasValue)
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
                              avatar: Icon(shop ? shopKindIcon(c.id) : serviceCategoryIcon(c.icon), size: 18, color: AppColors.accent),
                              label: Text(shop ? s.t('shop_kind_${c.id.substring(5)}') : c.name(lang), style: const TextStyle(fontSize: 14)),
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                              selected: _cats.contains(c.id),
                              selectedColor: AppColors.accent.withValues(alpha: 0.22),
                              onSelected: (v) => setState(() => v ? _cats.add(c.id) : _cats.remove(c.id)),
                            ),
                        ],
                      ),
                    _FieldLabel(s.t('svc_description')),
                    TextFormField(
                      controller: _description,
                      maxLength: 2000,
                      minLines: 3,
                      maxLines: 6,
                      decoration: InputDecoration(hintText: s.t(shop ? 'shop_about_hint' : 'svc_description_hint')),
                    ),
                    _FieldLabel(s.t('svc_city')),
                    InkWell(
                      key: const ValueKey('svc-city'),
                      onTap: _pickCity,
                      borderRadius: BorderRadius.circular(12),
                      child: InputDecorator(
                        decoration: InputDecoration(
                          prefixIcon: Padding(
                            padding: const EdgeInsets.only(left: 14, right: 8),
                            child: Text(_place?.flag ?? '📍', style: const TextStyle(fontSize: 22)),
                          ),
                          prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
                          suffixIcon: const Icon(Icons.keyboard_arrow_down),
                        ),
                        child: Text(
                          _place == null ? s.t('svc_city_pick') : '${_place!.cityLabel(lang)}, ${_place!.countryLabel(lang)}',
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 16, color: _place == null ? AppColors.textSoft : AppColors.text),
                        ),
                      ),
                    ),
                    _FieldLabel(s.t('svc_full_address')),
                    TextFormField(
                      controller: _address,
                      maxLength: 300,
                      decoration: InputDecoration(
                        hintText: s.t('svc_address_hint'),
                        counterText: '',
                        prefixIcon: const Icon(Icons.location_on_outlined),
                      ),
                    ),
                    const SizedBox(height: 12),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: SizedBox(
                        height: 210,
                        child: Stack(children: [
                          FlutterMap(
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
                          // "Xəritədə yeri seç" on the map (owner's picture).
                          Positioned(
                            left: 12,
                            bottom: 12,
                            child: Material(
                              color: AppColors.card.withValues(alpha: 0.92),
                              borderRadius: BorderRadius.circular(14),
                              child: InkWell(
                                key: const ValueKey('svc-map-pick'),
                                onTap: _pickOnMap,
                                borderRadius: BorderRadius.circular(14),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                                    Icon(Icons.my_location, size: 20, color: AppColors.accent),
                                    const SizedBox(width: 8),
                                    Text(s.t('map_pick_place'), style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: AppColors.text)),
                                  ]),
                                ),
                              ),
                            ),
                          ),
                          Positioned(
                            right: 10,
                            top: 10,
                            child: Material(
                              color: AppColors.card.withValues(alpha: 0.92),
                              shape: const CircleBorder(),
                              child: IconButton(
                                key: const ValueKey('svc-gps'),
                                tooltip: s.t('svc_use_gps'),
                                onPressed: _locating ? null : _useGps,
                                icon: _locating
                                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                                    : Icon(Icons.gps_fixed, color: AppColors.accent),
                              ),
                            ),
                          ),
                        ]),
                      ),
                    ),
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
                    // Telefon | WhatsApp side by side.
                    Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                          _FieldLabel(s.t('svc_phone'), required: true),
                          TextFormField(
                            key: const ValueKey('svc-phone'),
                            controller: _phone,
                            keyboardType: TextInputType.phone,
                            decoration: InputDecoration(
                              hintText: '+994 50 123 45 67',
                              prefixIcon: Icon(Icons.phone, color: AppColors.accent),
                            ),
                            validator: (v) => (v ?? '').replaceAll(RegExp(r'[^0-9]'), '').length < 7 ? s.t('profile_phone_invalid') : null,
                          ),
                        ]),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                          const _FieldLabel('WhatsApp'),
                          TextFormField(
                            controller: _whatsapp,
                            keyboardType: TextInputType.phone,
                            decoration: InputDecoration(
                              hintText: '+994 …',
                              prefixIcon: Icon(Icons.chat_outlined, color: AppColors.online),
                            ),
                          ),
                        ]),
                      ),
                    ]),
                    // İş saatları | 24/7 side by side.
                    _FieldLabel(s.t('svc_hours')),
                    Row(children: [
                      Expanded(
                        child: TextFormField(
                          controller: _hours,
                          enabled: !_is24h,
                          maxLength: 300,
                          decoration: InputDecoration(
                            hintText: s.t('svc_hours_hint'),
                            counterText: '',
                            prefixIcon: const Icon(Icons.schedule),
                          ),
                        ),
                      ),
                      Container(width: 1, height: 40, margin: const EdgeInsets.symmetric(horizontal: 12), color: AppColors.line),
                      Text(s.t('svc_24h_two_lines'), style: TextStyle(fontSize: 13, color: AppColors.text, height: 1.2)),
                      Switch(key: const ValueKey('svc-24h'), value: _is24h, onChanged: (v) => setState(() => _is24h = v)),
                    ]),
                    _FieldLabel('${s.t(shop ? 'shop_photos' : 'svc_photos_title')} (${_photos.length}/$_maxPhotos)'),
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
                              borderRadius: BorderRadius.circular(12),
                              child: CustomPaint(
                                painter: _DashedBox(color: AppColors.online.withValues(alpha: 0.7), radius: 12),
                                child: SizedBox(
                                  width: 84,
                                  height: 84,
                                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                                    Icon(Icons.add_photo_alternate_outlined, color: AppColors.accent),
                                    const SizedBox(height: 4),
                                    Text(s.t('photo_add'), textAlign: TextAlign.center, style: TextStyle(fontSize: 11.5, color: AppColors.text)),
                                  ]),
                                ),
                              ),
                            )
                          : null,
                    ),
                    const SizedBox(height: 16),
                    // Open now (shown "qeyri-aktiv" on the map when off).
                    Container(
                      decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.line)),
                      child: SwitchListTile(
                        key: const ValueKey('svc-active'),
                        secondary: Icon(Icons.location_on_outlined, color: AppColors.text),
                        title: Text(s.t(shop ? 'shop_open_now' : 'svc_available_now')),
                        subtitle: Text(s.t(shop ? 'shop_open_now_sub' : 'svc_available_now_sub'), style: const TextStyle(fontSize: 12)),
                        value: _active,
                        onChanged: (v) => setState(() => _active = v),
                      ),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 14),
                      Text(_error!, key: const ValueKey('svc-error'), style: TextStyle(color: AppColors.danger)),
                    ],
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      key: const ValueKey('svc-save'),
                      onPressed: _saving ? null : _save,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(56),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      icon: _saving
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : Icon(shop ? Icons.storefront_outlined : Icons.home_repair_service_outlined),
                      label: Text(s.t(shop ? 'shop_save' : 'svc_profile_save'), style: const TextStyle(fontSize: 17)),
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

/// The shop's product kinds in the owner's order (0097).
const kShopKindOrder = ['shop_new', 'shop_used', 'shop_engine', 'shop_electric', 'shop_tyres', 'shop_oils', 'shop_accessories', 'shop_other'];

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

/// A small label over a field (owner's picture): "Mağazanın adı *".
class _FieldLabel extends StatelessWidget {
  final String text;
  final bool required;
  const _FieldLabel(this.text, {this.required = false});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 18, bottom: 8, left: 2),
        child: Text.rich(TextSpan(children: [
          TextSpan(text: text, style: TextStyle(fontSize: 15, color: AppColors.text)),
          if (required) TextSpan(text: ' *', style: TextStyle(fontSize: 15, color: AppColors.accent)),
        ])),
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

/// A dashed rounded frame (the "add" boxes of the owner's picture).
class _DashedBox extends CustomPainter {
  final Color color;
  final double radius;
  const _DashedBox({required this.color, required this.radius});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    final path = ui.Path()..addRRect(RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius)));
    for (final m in path.computeMetrics()) {
      for (double d = 0; d < m.length; d += 9) {
        canvas.drawPath(m.extractPath(d, d + 5), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBox old) => old.color != color || old.radius != radius;
}

/// Background on top with the camera, the round logo half over its lower
/// edge with its own camera, and the name beside it — the same look as the
/// Profil card (owner, 06.11.2026).
class _MediaRow extends StatelessWidget {
  final String? logoUrl, coverUrl;
  final TextEditingController name;
  final String nameHint, hint, logoLabel, coverLabel;
  final bool shop;
  final VoidCallback? onLogo, onCover;
  final VoidCallback onLogoClear, onCoverClear;
  const _MediaRow({
    required this.logoUrl,
    required this.coverUrl,
    required this.name,
    required this.nameHint,
    required this.hint,
    required this.logoLabel,
    required this.coverLabel,
    required this.shop,
    required this.onLogo,
    required this.onCover,
    required this.onLogoClear,
    required this.onCoverClear,
  });

  static const double _r = 44;

  Widget _round(VoidCallback onTap, String key, IconData icon, String tooltip) => Material(
        color: AppColors.cardAlt.withValues(alpha: 0.9),
        shape: const CircleBorder(),
        child: IconButton(key: ValueKey(key), tooltip: tooltip, onPressed: onTap, icon: Icon(icon, color: AppColors.text)),
      );

  @override
  Widget build(BuildContext context) {
    const left = 14.0;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: LayoutBuilder(builder: (context, box) {
        final coverH = box.maxWidth / kPlaceCoverAspect;
        return Stack(children: [
          Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SizedBox(
              height: coverH,
              child: Stack(fit: StackFit.expand, children: [
                InkWell(
                  key: const ValueKey('svc-cover'),
                  onTap: onCover,
                  // Never empty: the default picture until the owner puts his own.
                  child: (coverUrl ?? '').isEmpty
                      ? Image.asset(defaultServiceCover(shop: shop), key: const ValueKey('svc-default-cover'), fit: BoxFit.cover)
                      : FramedImage(
                          image: NetworkImage(coverUrl!),
                          framing: ImageFraming.of(coverUrl),
                          errorBuilder: (_, __, ___) => Image.asset(defaultServiceCover(shop: shop), fit: BoxFit.cover),
                        ),
                ),
                if (onCover != null)
                  Positioned(right: 8, top: 8, child: _round(onCover!, 'svc-cover-edit', Icons.photo_camera_outlined, coverLabel)),
                if (coverUrl != null) Positioned(left: 8, top: 8, child: _round(onCoverClear, 'svc-cover-clear', Icons.close, '')),
              ]),
            ),
            Container(height: 1, color: AppColors.line),
            Padding(
              padding: const EdgeInsets.fromLTRB(left + _r * 2 + 14, 10, 14, 14),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: _r + 4),
                child: ValueListenableBuilder<TextEditingValue>(
                  valueListenable: name,
                  builder: (context, v, _) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(
                      v.text.trim().isEmpty ? nameHint : v.text.trim(),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                          color: v.text.trim().isEmpty ? AppColors.textSoft : AppColors.text),
                    ),
                    const SizedBox(height: 4),
                    Text(hint, style: TextStyle(fontSize: 13, color: AppColors.textSoft)),
                  ]),
                ),
              ),
            ),
          ]),
          // The logo, half over the background's edge, with its camera.
          Positioned(
            left: left,
            top: coverH - _r,
            child: InkWell(
              key: const ValueKey('svc-logo'),
              customBorder: const CircleBorder(),
              onTap: onLogo,
              child: Stack(clipBehavior: Clip.none, children: [
                Container(
                  width: _r * 2 + 6,
                  height: _r * 2 + 6,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: AppColors.cardAlt, border: Border.all(color: AppColors.card, width: 3)),
                  child: ClipOval(
                    child: roundPicture(logoUrl, Image.asset(defaultServiceLogo(shop: shop), key: const ValueKey('svc-default-logo'), fit: BoxFit.cover)),
                  ),
                ),
                Positioned(
                  right: -2,
                  bottom: -2,
                  child: Tooltip(
                    message: logoLabel,
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: AppColors.cardAlt,
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.card, width: 2),
                      ),
                      child: Icon(Icons.photo_camera, size: 16, color: AppColors.text),
                    ),
                  ),
                ),
                if (logoUrl != null)
                  Positioned(
                    right: -2,
                    top: -2,
                    child: InkWell(
                      key: const ValueKey('svc-logo-clear'),
                      onTap: onLogoClear,
                      child: Container(
                        decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                        padding: const EdgeInsets.all(4),
                        child: const Icon(Icons.close, size: 14, color: Colors.white),
                      ),
                    ),
                  ),
              ]),
            ),
          ),
        ]);
      }),
    );
  }
}

/// "Xəritədə yeri seç": move the map under the pin, then "Bu yeri seç".
class MapPlacePicker extends StatefulWidget {
  final LatLng start;
  final AppStrings s;
  const MapPlacePicker({super.key, required this.start, required this.s});

  @override
  State<MapPlacePicker> createState() => _MapPlacePickerState();
}

class _MapPlacePickerState extends State<MapPlacePicker> {
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

/// "Mağaza əlavə et" (owner, 09.11.2026): pick the shop's kind in the same
/// look as "Usta / Servis kimi qoşul", then the existing shop form opens —
/// "Mağaza" as before, "İşlənmiş ehtiyat hissələri" with that kind ticked.
/// An existing service gets the shop added by the form, as before.
class ShopJoinScreen extends ConsumerWidget {
  const ShopJoinScreen({super.key});

  /// The existing shop form.
  static const shopRoute = '/service-edit?kind=center&shop=1';
  static const usedRoute = '/service-edit?kind=center&shop=1&shopKind=shop_used';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    return Scaffold(
      appBar: AppBar(title: Text(s.t('svc_add_shop'))),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(s.t('shop_join_intro'), style: TextStyle(color: AppColors.textSoft, height: 1.4)),
          const SizedBox(height: 16),
          _JoinCard(
            key: const ValueKey('shop-join-shop'),
            icon: Icons.storefront_outlined,
            title: s.t('shop_profile_title'),
            sub: s.t('shop_join_shop_sub'),
            onTap: () => context.pushReplacement(shopRoute),
          ),
          const SizedBox(height: 10),
          _JoinCard(
            key: const ValueKey('shop-join-used'),
            icon: Icons.autorenew,
            title: s.t('shop_kind_used'),
            sub: s.t('shop_join_used_sub'),
            onTap: () => context.pushReplacement(usedRoute),
          ),
        ],
      ),
    );
  }
}

class _JoinCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String sub;
  final VoidCallback onTap;
  const _JoinCard({super.key, required this.icon, required this.title, required this.sub, required this.onTap});

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
