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
import '../../../services/geo_service.dart';
import '../../chat/presentation/widgets/location_message.dart' show ChatLocation, showNavigationPicker;
import '../../services/presentation/services_providers.dart';
import '../data/tir_park_repository.dart';
import '../domain/tir_park.dart';
import 'map_page_banner.dart';
import 'tir_park_booking.dart';
import 'tir_park_widgets.dart';
import '../../promo/place_promo.dart';
import '../../promo/premium_pin.dart';

/// TIRPark (owner, 31.10.2026, picture): the banner, the map with the park
/// pins, the search, "TIR parkı əlavə et" and the nearby parks below.
/// "Servislər" (the former tab) opens from here. Approved parks for
/// everybody; one's own parks waiting for approval are shown grey.
class TirParkScreen extends ConsumerStatefulWidget {
  // Users no longer add parking spots on the map (owner, 07.11.2026): no
  // "TIR parkı əlavə et" / "Dayanacaq əlavə et" — parks come only through
  // "Park işlədirəm" (admin approval) and the admins.
  const TirParkScreen({super.key});

  @override
  ConsumerState<TirParkScreen> createState() => _TirParkScreenState();
}

/// Nearby list radius (owner's picture: "5 park · 100 km").
const kTirParkRadiusKm = 100.0;

class _TirParkScreenState extends ConsumerState<TirParkScreen> with SingleTickerProviderStateMixin, PremiumDropHost<TirParkScreen> {
  final _map = MapController();
  final _search = TextEditingController();
  final _searchFocus = FocusNode();
  final _sheet = DraggableScrollableController();
  LatLng _center = kDefaultServiceCenter;
  bool _mapReady = false;
  Map<String, PlacePromo> _lastPromos = const {};
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
    disposePremium();
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
      // Over the bottom bar, so "Sıfırla" / "Göstər" are never hidden
      // (owner, 01.11.2026).
      useRootNavigator: true,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => _FilterSheet(initial: _needs, s: s),
    );
    if (picked != null) setState(() => _needs = picked);
  }

  /// A pin or a card: the park opens first (its card on top of the list,
  /// the list raised), then the way there is drawn and "Marşrut" offers
  /// the navigation apps (owner, 01.11.2026 — like Servislər).
  void _select(TirPark p) {
    setState(() => _selectedId = p.id);
    _move(LatLng(p.lat, p.lng), 13);
    if (_sheet.isAttached && _sheet.size < 0.4) {
      _sheet.animateTo(0.42, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
    }
  }

  void _navigate(TirPark p, AppStrings s) => showNavigationPicker(
        context,
        s,
        ChatLocation(url: 'https://maps.google.com/?q=${p.lat},${p.lng}', lat: p.lat, lng: p.lng),
      );

  /// A promoted, approved park: the premium marker (0093 / 05.11.2026).
  bool _premium(TirPark p, Map<String, PlacePromo> promos) => p.isApproved && (promos[p.id]?.isPromoted ?? false);

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    ref.watch(currentLocaleProvider);
    final async = ref.watch(tirParksProvider);
    final parks = async.valueOrNull ?? const <TirPark>[];
    final me = ref.watch(userLocationProvider).point;
    final from = me ?? _center;
    final found = nearbyParks(parks, from.latitude, from.longitude, radiusKm: kTirParkRadiusKm, query: _query, needs: _needs);
    TirPark? selected;
    for (final p in parks) {
      if (p.id == _selectedId) selected = p;
    }
    final shownOnMap = [for (final p in parks) if (_needs.isEmpty || _needs.every(p.amenities.contains)) p];
    // "Önə çıxar" (owner, 04.11.2026, 0093): promoted parks around their own
    // place first (Premium on top), then the rest nearest first.
    final promoAsync = ref.watch(placePromoStateProvider(placePromoKey(PlaceTarget.tirpark, shownOnMap.map((p) => p.id))));
    final promos = promoAsync.valueOrNull ?? _lastPromos;
    if (promoAsync.hasValue) _lastPromos = promoAsync.value!;
    final ordered = promotedFirst(found, (e) => e.$1.id, promos);
    premiumMaybeStart(promoAsync.hasValue ? [for (final p in ordered) if (_premium(p.$1, promos)) p.$1.id, for (final p in shownOnMap) if (_premium(p, promos)) p.id] : null);
    // The selected park stands first in the list.
    final list = [
      ...ordered.where((e) => e.$1.id == _selectedId),
      ...ordered.where((e) => e.$1.id != _selectedId),
    ];
    RouteInfo? route;
    if (selected != null && me != null) {
      route = ref.watch(routeInfoProvider((aLat: me.latitude, aLng: me.longitude, bLat: selected.lat, bLng: selected.lng))).valueOrNull;
    }

    return PopScope(
      child: Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(children: [
          MapPageBanner(
            s: s,
            page: 'tirpark',
            brandIcon: Icons.local_shipping_outlined,
            editIcon: Icons.local_parking,
            brandAccent: 'TIR',
            brandRest: 'Park',
            defaultTitle: s.t('tp_title_1'),
            defaultAccent: s.t('tp_title_2'),
            defaultSubtitle: s.t('tp_subtitle'),
            asset: 'assets/images/tirpark/banner.jpg',
          ),
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
                      premiumMapReady();
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
                    if (selected != null && me != null)
                      PolylineLayer(polylines: [
                        Polyline(
                          points: route?.points ?? [me, LatLng(selected.lat, selected.lng)],
                          color: AppColors.accent,
                          strokeWidth: 4,
                        ),
                      ]),
                    MarkerLayer(markers: [
                      for (final p in shownOnMap)
                        if (!_premium(p, promos))
                          Marker(
                            key: ValueKey('tp-pin-${p.id}'),
                            point: LatLng(p.lat, p.lng),
                            width: 46,
                            height: 54,
                            alignment: Alignment.topCenter,
                            child: GestureDetector(
                                onTap: () => _select(p), child: TirParkPin(approved: p.isApproved, selected: p.id == _selectedId)),
                          ),
                      // Promoted parks (owner, 05.11.2026): the premium icon,
                      // 20 % bigger, on top, dropped in once after the map.
                      for (final p in shownOnMap)
                        if (_premium(p, promos))
                          Marker(
                            key: ValueKey('tp-premium-${p.id}'),
                            point: LatLng(p.lat, p.lng),
                            width: p.id == _selectedId ? kPremiumPinSelectedSize : kPremiumPinSize,
                            height: p.id == _selectedId ? kPremiumPinSelectedSize : kPremiumPinSize,
                            alignment: Alignment.topCenter,
                            child: GestureDetector(
                              onTap: () => _select(p),
                              child: PremiumDropIn(
                                clock: premiumClock,
                                started: premiumStarted,
                                index: premiumIndex(p.id),
                                child: PremiumMarker(
                                  kind: PremiumPinKind.park,
                                  size: p.id == _selectedId ? kPremiumPinSelectedSize : kPremiumPinSize,
                                  label: promos[p.id]!.isPremium ? s.t('mk_promo_premium') : null,
                                ),
                              ),
                            ),
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
                    child: ParksServicesSwitch(
                        parks: true,
                        s: s,
                        onParks: () {},
                        onServices: () => context.go('/services'),
                        onShops: () => context.go('/services?shops=1')),
                  ),
                ]),
              ),
              // My position.
              AboveSheet(
                sheet: 0.26,
                gap: 10,
                child: _RoundButton(buttonKey: 'tp-locate', icon: Icons.my_location, tooltip: s.t('svc_my_location'), onTap: () => _locate()),
              ),
              // Nearby parks.
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
                            onOpen: () => context.pushOnce('/tirpark/p/${p.id}'),
                            onReviews: () => context.pushOnce('/tirpark/p/${p.id}'),
                            onWrite: () => context.pushOnce('/tirpark/p/${p.id}?write=1'),
                            booking: p.isManaged ? TirParkCardBooking(park: p, s: s) : null,
                            badge: (promos[p.id]?.isPromoted ?? false) ? PlacePromoTag(s: s, promo: promos[p.id]!) : null,
                            footer: TirParkRouteRow(s: s, route: route, hasGps: me != null, onNavigate: () => _navigate(p, s)),
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
    ),
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
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SheetTitle(title: s.t('tp_filter'), s: s, closeKey: 'tp-filter-close'),
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
