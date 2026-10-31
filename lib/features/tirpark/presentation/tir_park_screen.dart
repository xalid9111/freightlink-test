import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/localization/app_strings.dart';
import '../../../core/localization/locale_controller.dart';
import '../../../core/router/safe_navigation.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/map_tiles.dart';
import '../../../core/widgets/page_hero.dart';
import '../../../services/geo_service.dart';
import '../../services/presentation/services_providers.dart';
import '../data/tir_park_repository.dart';
import '../domain/tir_park.dart';
import 'tir_park_add_sheet.dart';
import 'tir_park_widgets.dart';

/// TIRPark (owner, 31.10.2026, picture): the banner, the map with the park
/// pins, the search, "TIR parkı əlavə et" and the nearby parks below.
/// "Servislər" (the former tab) opens from here. Approved parks for
/// everybody; one's own parks waiting for approval are shown grey.
class TirParkScreen extends ConsumerStatefulWidget {
  const TirParkScreen({super.key});

  @override
  ConsumerState<TirParkScreen> createState() => _TirParkScreenState();
}

/// Nearby list radius (owner's picture: "5 park · 100 km").
const kTirParkRadiusKm = 100.0;

class _TirParkScreenState extends ConsumerState<TirParkScreen> {
  final _map = MapController();
  final _search = TextEditingController();
  final _searchFocus = FocusNode();
  final _sheet = DraggableScrollableController();
  LatLng _center = kDefaultServiceCenter;
  bool _mapReady = false;
  bool _adding = false;
  String? _selectedId;
  String _query = '';
  Set<String> _needs = const {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _locate(initial: true));
  }

  @override
  void dispose() {
    _search.dispose();
    _searchFocus.dispose();
    _sheet.dispose();
    super.dispose();
  }

  void _move(LatLng p, double zoom) {
    if (!_mapReady) return;
    try {
      _map.move(p, zoom);
    } catch (_) {}
  }

  Future<void> _locate({bool initial = false}) async {
    final p = await ref.read(userLocationProvider.notifier).locate();
    if (!mounted || p == null) {
      if (!initial && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ref.read(stringsProvider).t('svc_gps_failed'))));
      }
      return;
    }
    setState(() => _center = p);
    _move(p, 11);
  }

  Future<void> _submitSearch(List<TirPark> parks) async {
    _searchFocus.unfocus();
    final q = _search.text.trim();
    if (q.length < 2) return;
    final hits = nearbyParks(parks, _center.latitude, _center.longitude, query: q);
    if (hits.isNotEmpty) {
      final p = hits.first.$1;
      setState(() => _selectedId = p.id);
      _move(LatLng(p.lat, p.lng), 13);
      return;
    }
    // Not a park: a place (city) — the map goes there.
    final place = await ref.read(geoServiceProvider).geocode(q);
    if (!mounted) return;
    if (place == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ref.read(stringsProvider).t('svc_place_not_found'))));
      return;
    }
    setState(() {
      _center = place;
      _search.clear();
      _query = '';
    });
    _move(place, 11);
  }

  Future<void> _openFilter(AppStrings s) async {
    final picked = await showModalBottomSheet<Set<String>>(
      context: context,
      useSafeArea: true,
      builder: (_) => _FilterSheet(initial: _needs, s: s),
    );
    if (picked != null) setState(() => _needs = picked);
  }

  Future<void> _confirmPlace(AppStrings s) async {
    final c = _mapReady ? _map.camera.center : _center;
    final added = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => TirParkAddSheet(lat: c.latitude, lng: c.longitude, s: s),
    );
    if (!mounted) return;
    if (added == true) {
      setState(() => _adding = false);
      ref.invalidate(tirParksProvider);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.t('tp_sent'))));
    }
  }

  void _select(TirPark p) {
    setState(() => _selectedId = p.id);
    _move(LatLng(p.lat, p.lng), 13);
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    ref.watch(currentLocaleProvider);
    final async = ref.watch(tirParksProvider);
    final parks = async.valueOrNull ?? const <TirPark>[];
    final me = ref.watch(userLocationProvider).point;
    final from = me ?? _center;
    final list = nearbyParks(parks, from.latitude, from.longitude, radiusKm: kTirParkRadiusKm, query: _query, needs: _needs);
    final shownOnMap = [for (final p in parks) if (_needs.isEmpty || _needs.every(p.amenities.contains)) p];

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(children: [
          _Banner(s: s),
          Expanded(
            child: Stack(children: [
              Positioned.fill(
                child: FlutterMap(
                  mapController: _map,
                  options: MapOptions(
                    initialCenter: _center,
                    initialZoom: 10,
                    minZoom: 3,
                    maxZoom: 18,
                    backgroundColor: AppColors.hero,
                    interactionOptions: const InteractionOptions(flags: InteractiveFlag.all & ~InteractiveFlag.rotate),
                    onMapReady: () {
                      _mapReady = true;
                      if (me != null) _move(me, 11);
                    },
                    onTap: (_, __) {
                      _searchFocus.unfocus();
                      if (_selectedId != null) setState(() => _selectedId = null);
                    },
                  ),
                  children: [
                    // Night: the map dimmed to the dark page (owner's picture).
                    const AppTileLayer(),
                    MarkerLayer(markers: [
                      for (final p in shownOnMap)
                        Marker(
                          key: ValueKey('tp-pin-${p.id}'),
                          point: LatLng(p.lat, p.lng),
                          width: 46,
                          height: 54,
                          alignment: Alignment.topCenter,
                          child: GestureDetector(onTap: () => _select(p), child: TirParkPin(approved: p.isApproved, selected: p.id == _selectedId)),
                        ),
                      if (me != null)
                        Marker(
                          point: me,
                          width: 22,
                          height: 22,
                          child: Container(
                            decoration: BoxDecoration(
                              color: AppColors.blue,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 3),
                            ),
                          ),
                        ),
                    ]),
                    const AppMapAttribution(),
                  ],
                ),
              ),
              // Choosing the place of a new park: a fixed pin in the middle.
              if (_adding)
                IgnorePointer(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 54),
                      child: Icon(Icons.location_on, size: 54, color: AppColors.accentFill),
                    ),
                  ),
                ),
              // Search · filter, and Parklar | Servislər.
              Positioned(
                left: 12,
                right: 12,
                top: 10,
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Row(children: [
                    Expanded(
                      child: Container(
                        height: 50,
                        decoration: BoxDecoration(
                          color: AppColors.card.withValues(alpha: 0.96),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: AppColors.line),
                        ),
                        child: TextField(
                          key: const ValueKey('tp-search'),
                          controller: _search,
                          focusNode: _searchFocus,
                          textInputAction: TextInputAction.search,
                          onChanged: (v) => setState(() => _query = v),
                          onSubmitted: (_) => _submitSearch(parks),
                          decoration: InputDecoration(
                            filled: false,
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            prefixIcon: Icon(Icons.search, color: AppColors.textSoft),
                            hintText: s.t('tp_search_hint'),
                            contentPadding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    _RoundButton(
                      buttonKey: 'tp-filter',
                      icon: Icons.tune,
                      badge: _needs.length,
                      tooltip: s.t('tp_filter'),
                      onTap: () => _openFilter(s),
                    ),
                  ]),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: ParksServicesSwitch(parks: true, s: s, onParks: () {}, onServices: () => context.go('/services')),
                  ),
                ]),
              ),
              // My position.
              Positioned(
                right: 12,
                top: 118,
                child: _RoundButton(buttonKey: 'tp-locate', icon: Icons.my_location, tooltip: s.t('svc_my_location'), onTap: () => _locate()),
              ),
              // "TIR parkı əlavə et +" / choosing the place.
              Positioned(
                right: 12,
                left: _adding ? 12 : null,
                // While choosing the place the panel sits low, so the pin in
                // the middle of the map stays in view.
                bottom: _adding ? 16 : MediaQuery.sizeOf(context).height * 0.26 + 10,
                child: _adding
                    ? Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.card,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: AppColors.line),
                        ),
                        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                          Text(s.t('tp_pick_place'), textAlign: TextAlign.center, style: TextStyle(color: AppColors.text)),
                          const SizedBox(height: 10),
                          Row(children: [
                            Expanded(
                              child: OutlinedButton(
                                key: const ValueKey('tp-add-cancel'),
                                onPressed: () => setState(() => _adding = false),
                                child: Text(s.t('common_cancel')),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: FilledButton(
                                key: const ValueKey('tp-add-here'),
                                onPressed: () => _confirmPlace(s),
                                child: Text(s.t('tp_pick_here')),
                              ),
                            ),
                          ]),
                        ]),
                      )
                    : MapAddButton(buttonKey: 'tp-add', label: s.t('tp_add'), onTap: () => setState(() => _adding = true)),
              ),
              // Nearby parks.
              if (!_adding)
                DraggableScrollableSheet(
                  controller: _sheet,
                  initialChildSize: 0.26,
                  minChildSize: 0.12,
                  maxChildSize: 0.92,
                  builder: (context, scroll) => Container(
                    decoration: BoxDecoration(
                      color: AppColors.background,
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                      border: Border(top: BorderSide(color: AppColors.line)),
                    ),
                    child: ListView.builder(
                      key: const ValueKey('tp-list'),
                      controller: scroll,
                      padding: const EdgeInsets.fromLTRB(14, 8, 14, 24),
                      itemCount: list.length + 1,
                      itemBuilder: (context, i) {
                        if (i == 0) return _ListHead(s: s, count: list.length, async: async);
                        final (p, km) = list[i - 1];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: TirParkCard(
                            park: p,
                            km: km,
                            s: s,
                            selected: p.id == _selectedId,
                            onTap: () => _select(p),
                            onReviews: () => context.pushOnce('/tirpark/p/${p.id}'),
                            onWrite: () => context.pushOnce('/tirpark/p/${p.id}?write=1'),
                          ),
                        );
                      },
                    ),
                  ),
                ),
            ]),
          ),
        ]),
      ),
    );
  }
}

/// "TIRPark — Yolda özünə uyğun park tap" with the owner's park photo.
/// An admin changes the picture (a GIF too), its place / zoom and the
/// texts with the pencil — the same banner editor as Servislər and TIR
/// Bazarı (page 'tirpark', 0078).
class _Banner extends ConsumerWidget {
  final AppStrings s;
  const _Banner({required this.s});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bg = AppColors.background;
    final hero = ref.watch(pageHeroProvider('tirpark')).valueOrNull;
    final img = hero?.imageFor(day: AppColors.isDay);
    final texts = img == null || (hero?.showText ?? true);
    final admin = isAdminUser(ref);
    return SizedBox(
      height: 168,
      child: Stack(fit: StackFit.expand, children: [
        if (img != null)
          PageHeroImage(
            url: img,
            align: hero!.alignmentFor(day: AppColors.isDay),
            zoom: hero.zoomFor(day: AppColors.isDay),
            fallback: (_) => const SizedBox.shrink(),
          )
        else
          Align(
            alignment: Alignment.centerRight,
            child: Image.asset('assets/images/tirpark/banner.jpg',
                fit: BoxFit.cover, alignment: const Alignment(0, -0.45), height: 168, width: 230),
          ),
        if (texts)
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [bg, bg, bg.withValues(alpha: 0.55), bg.withValues(alpha: 0.0)],
                stops: const [0, 0.42, 0.62, 0.85],
              ),
            ),
          ),
        if (texts)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 120, 12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
              Row(children: [
                Icon(Icons.local_shipping_outlined, color: AppColors.accent, size: 26),
                const SizedBox(width: 6),
                Text('TIR', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: AppColors.accent)),
                Text('Park', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: AppColors.text)),
              ]),
              const SizedBox(height: 8),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(hero?.title ?? s.t('tp_title_1'),
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: AppColors.text, height: 1.1)),
              ),
              Text(hero?.titleAccent ?? s.t('tp_title_2'),
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: AppColors.accent, height: 1.15)),
              const SizedBox(height: 4),
              Text(hero?.subtitle ?? s.t('tp_subtitle'),
                  maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: AppColors.textSoft)),
            ]),
          ),
        if (admin)
          Positioned(
            right: 10,
            top: 10,
            child: Material(
              color: Colors.black.withValues(alpha: 0.55),
              shape: const CircleBorder(),
              child: IconButton(
                key: const ValueKey('page-hero-edit-tirpark'),
                tooltip: s.t('mk_hero_edit'),
                icon: const Icon(Icons.edit_outlined, color: Colors.white, size: 20),
                onPressed: () => showPageHeroEditor(context, strings: s, page: 'tirpark', hero: hero, icon: Icons.local_parking),
              ),
            ),
          ),
      ]),
    );
  }
}

class _ListHead extends StatelessWidget {
  final AppStrings s;
  final int count;
  final AsyncValue<List<TirPark>> async;
  const _ListHead({required this.s, required this.count, required this.async});

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Center(
          child: Container(
            width: 42,
            height: 5,
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(color: AppColors.line, borderRadius: BorderRadius.circular(3)),
          ),
        ),
        Text(s.t('tp_nearby'), style: TextStyle(fontSize: 19, fontWeight: FontWeight.w600, color: AppColors.text)),
        const SizedBox(height: 2),
        Text(s.t('tp_nearby_count', {'n': '$count', 'km': kTirParkRadiusKm.round().toString()}),
            key: const ValueKey('tp-count'), style: TextStyle(fontSize: 14, color: AppColors.textSoft)),
        const SizedBox(height: 12),
        if (async.isLoading && !async.hasValue)
          const Padding(padding: EdgeInsets.all(20), child: Center(child: CircularProgressIndicator()))
        else if (async.error is TirParkNotReady)
          Text(s.t('tp_not_ready'), style: TextStyle(color: AppColors.textSoft))
        else if (async.hasError && !async.hasValue)
          Text(s.t('home_error_loading'), style: TextStyle(color: AppColors.textSoft))
        else if (count == 0)
          Text(s.t('tp_none'), key: const ValueKey('tp-none'), style: TextStyle(color: AppColors.textSoft)),
      ]);
}

class _RoundButton extends StatelessWidget {
  final String buttonKey, tooltip;
  final IconData icon;
  final int badge;
  final VoidCallback onTap;
  const _RoundButton({required this.buttonKey, required this.icon, required this.tooltip, required this.onTap, this.badge = 0});

  @override
  Widget build(BuildContext context) => Material(
        color: AppColors.card,
        shape: CircleBorder(side: BorderSide(color: AppColors.line)),
        child: InkWell(
          key: ValueKey(buttonKey),
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Tooltip(
            message: tooltip,
            child: SizedBox(
              width: 50,
              height: 50,
              child: Badge(isLabelVisible: badge > 0, label: Text('$badge'), child: Icon(icon, color: AppColors.text)),
            ),
          ),
        ),
      );
}



class _FilterSheet extends StatefulWidget {
  final Set<String> initial;
  final AppStrings s;
  const _FilterSheet({required this.initial, required this.s});

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  late final Set<String> _on = {...widget.initial};

  @override
  Widget build(BuildContext context) {
    final s = widget.s;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(s.t('tp_filter'), style: TextStyle(fontSize: 19, fontWeight: FontWeight.w600, color: AppColors.text)),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final a in kTirParkAmenities)
              FilterChip(
                key: ValueKey('tp-f-$a'),
                avatar: Icon(tirParkAmenityIcon(a), size: 16),
                label: Text(s.t('tp_am_$a')),
                selected: _on.contains(a),
                onSelected: (v) => setState(() => v ? _on.add(a) : _on.remove(a)),
              ),
          ]),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(
              child: OutlinedButton(onPressed: () => Navigator.pop(context, <String>{}), child: Text(s.t('job_filter_reset'))),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: FilledButton(
                key: const ValueKey('tp-f-apply'),
                onPressed: () => Navigator.pop(context, _on),
                child: Text(s.t('job_filter_apply')),
              ),
            ),
          ]),
        ]),
      ),
    );
  }
}
