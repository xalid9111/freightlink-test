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
import '../../../core/widgets/reorder_tile_grid.dart';
import '../../../models/service_models.dart';
import '../../../services/geo_service.dart';
import '../../auth/presentation/providers/auth_providers.dart';
import '../data/services_repository.dart';
import 'service_widgets.dart';
import 'services_providers.dart';
import '../../../core/widgets/map_tiles.dart';

/// Create / edit the signed-in user's own service profile. Moderation
/// fields (status, verified, rating) are never sent — the database
/// trigger ignores them for non-admins anyway.
class ServiceEditScreen extends ConsumerStatefulWidget {
  final String? id; // null = create
  final String? initialKind;
  const ServiceEditScreen({super.key, this.id, this.initialKind});

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
  static const _maxPhotos = 8;

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
      if (p != null) {
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
        if ((p.city ?? '').isNotEmpty) _place = PickedPlace.fromStored(p.city!, p.country ?? '');
        _point = LatLng(p.lat, p.lng);
        _mobile = p.isMobile;
        _is24h = p.is24h;
        _active = p.isActive;
        _photos = [for (final u in p.photos) _PhotoEntry.uploaded(u)];
      } else {
        _kind = widget.initialKind == 'center' ? 'center' : 'individual';
        _mobile = _kind == 'individual';
        final me = ref.read(currentUserProvider);
        _phone.text = me?.phone ?? '';
        if (_kind == 'individual' && (me?.fullName ?? '').isNotEmpty) _name.text = me!.fullName;
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
    if (_cats.isEmpty) {
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

    return Scaffold(
      appBar: AppBar(
        leading: context.canPop()
            ? null
            : IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.go('/services')),
        title: Text(s.t(_existing == null ? 'svc_create_title' : 'svc_edit_title')),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: Form(
                key: _form,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
                  children: [
                    if (_existing == null)
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(color: AppColors.cardAlt, borderRadius: BorderRadius.circular(12)),
                        child: Text(s.t('svc_create_intro'), style: TextStyle(fontSize: 13, color: AppColors.textSoft, height: 1.35)),
                      ),
                    const SizedBox(height: 14),
                    _Label(s.t('svc_kind')),
                    SegmentedButton<String>(
                      segments: [
                        ButtonSegment(value: 'individual', icon: const Icon(Icons.handyman_outlined, size: 18), label: Text(s.t('svc_kind_individual'))),
                        ButtonSegment(value: 'center', icon: const Icon(Icons.car_repair, size: 18), label: Text(s.t('svc_kind_center'))),
                      ],
                      selected: {_kind},
                      onSelectionChanged: (v) => setState(() => _kind = v.first),
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _name,
                      maxLength: 120,
                      textCapitalization: TextCapitalization.words,
                      decoration: InputDecoration(labelText: s.t(_kind == 'center' ? 'svc_name_center' : 'svc_name_individual')),
                      validator: (v) => (v == null || v.trim().length < 2) ? s.t('field_required') : null,
                    ),
                    TextFormField(
                      controller: _specialty,
                      maxLength: 200,
                      decoration: InputDecoration(labelText: s.t('svc_specialty'), hintText: s.t('svc_specialty_hint')),
                    ),
                    _Label(s.t('svc_categories')),
                    cats.when(
                      loading: () => const LinearProgressIndicator(),
                      error: (_, __) => Text(s.t('svc_load_failed')),
                      data: (list) => Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final c in list)
                            FilterChip(
                              avatar: Icon(serviceCategoryIcon(c.icon), size: 16),
                              label: Text(c.name(lang), style: const TextStyle(fontSize: 12.5)),
                              selected: _cats.contains(c.id),
                              onSelected: (v) => setState(() => v ? _cats.add(c.id) : _cats.remove(c.id)),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _description,
                      maxLength: 2000,
                      minLines: 2,
                      maxLines: 6,
                      decoration: InputDecoration(labelText: s.t('svc_description'), hintText: s.t('svc_description_hint')),
                    ),
                    _Label(s.t('svc_location')),
                    OutlinedButton.icon(
                      onPressed: _pickCity,
                      icon: Text(_place?.flag ?? '📍'),
                      label: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          _place == null ? s.t('svc_city_pick') : '${_place!.cityLabel(lang)}, ${_place!.countryLabel(lang)}',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _address,
                      maxLength: 300,
                      decoration: InputDecoration(labelText: s.t('svc_address')),
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            _point == null ? s.t('svc_map_hint_empty') : s.t('svc_map_hint'),
                            style: TextStyle(fontSize: 12, color: AppColors.textSoft),
                          ),
                        ),
                        TextButton.icon(
                          onPressed: _locating ? null : _useGps,
                          icon: _locating
                              ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.my_location, size: 18),
                          label: Text(s.t('svc_use_gps')),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: SizedBox(
                        height: 220,
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
                    const SizedBox(height: 10),
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
                    _Label(s.t('svc_contacts')),
                    TextFormField(
                      controller: _phone,
                      keyboardType: TextInputType.phone,
                      decoration: InputDecoration(labelText: s.t('svc_phone'), hintText: '+994 50 123 45 67'),
                      validator: (v) => (v ?? '').replaceAll(RegExp(r'[^0-9]'), '').length < 7 ? s.t('profile_phone_invalid') : null,
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _whatsapp,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(labelText: 'WhatsApp'),
                    ),
                    _Label(s.t('svc_hours')),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(s.t('svc_24h')),
                      value: _is24h,
                      onChanged: (v) => setState(() => _is24h = v),
                    ),
                    if (!_is24h)
                      TextFormField(
                        controller: _hours,
                        maxLength: 300,
                        decoration: InputDecoration(labelText: s.t('svc_hours'), hintText: s.t('svc_hours_hint')),
                      ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(s.t('svc_available_now')),
                      subtitle: Text(s.t('svc_available_now_sub'), style: const TextStyle(fontSize: 12)),
                      value: _active,
                      onChanged: (v) => setState(() => _active = v),
                    ),
                    _Label('${s.t('svc_photos')} (${_photos.length}/$_maxPhotos)'),
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
                              onTap: _addPhoto,
                              borderRadius: BorderRadius.circular(10),
                              child: Container(
                                width: 84,
                                height: 84,
                                decoration: BoxDecoration(
                                  color: AppColors.card,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: AppColors.line),
                                ),
                                child: Icon(Icons.add_a_photo_outlined, color: AppColors.textSoft),
                              ),
                            )
                          : null,
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 14),
                      Text(_error!, style: TextStyle(color: AppColors.danger)),
                    ],
                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed: _saving ? null : _save,
                      style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                      child: _saving
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : Text(s.t(_existing == null ? 'svc_create_button' : 'svc_save_button')),
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

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 14, bottom: 8),
        child: Text(text.toUpperCase(),
            style: TextStyle(color: AppColors.textSoft, fontSize: 11.5, letterSpacing: 1.0, fontWeight: FontWeight.w500)),
      );
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
