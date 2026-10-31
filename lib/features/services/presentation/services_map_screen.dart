import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/layout/desktop_layout.dart';
import '../../../core/localization/app_strings.dart';
import '../../../core/localization/locale_controller.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/service_models.dart';
import '../../../services/geo_service.dart';
import '../data/services_repository.dart';
import 'service_search_logic.dart';
import 'service_widgets.dart';
import 'services_providers.dart';
import '../../../core/router/safe_navigation.dart';
import '../../../core/widgets/map_tiles.dart';
import '../../../core/widgets/mouse_drag_scroll.dart';
import '../../../core/widgets/page_hero.dart';
import '../../tirpark/presentation/tir_park_widgets.dart';


/// "Servislər" tab: a GPS map of nearby mechanics, service centres and
/// tow trucks, with category chips, filters, a results sheet and
/// Call / Message / Route on every card.
class ServicesMapScreen extends ConsumerStatefulWidget {
  const ServicesMapScreen({super.key});

  @override
  ConsumerState<ServicesMapScreen> createState() => _ServicesMapScreenState();
}

class _ServicesMapScreenState extends ConsumerState<ServicesMapScreen> {
  final _map = MapController();
  final _sheet = DraggableScrollableController();
  final _searchCtrl = TextEditingController();
  final _searchFocus = FocusNode();

  ServiceQuery _query = ServiceQuery(lat: kDefaultServiceCenter.latitude, lng: kDefaultServiceCenter.longitude, radiusKm: 100);
  String? _selectedId;
  /// Service chosen in the universal search; shown (card first) even when
  /// it is outside the current map area or has no map position.
  ServiceProvider? _picked;
  bool _moved = false;
  bool _geocoding = false;
  int _zoomBucket = 11;
  bool _mapReady = false;
  List<ServiceProvider> _lastItems = const [];

  @override
  void initState() {
    super.initState();
    _searchFocus.addListener(_onFocus);
    WidgetsBinding.instance.addPostFrameCallback((_) => _locate(initial: true));
  }

  void _onFocus() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _searchFocus.removeListener(_onFocus);
    _searchCtrl.dispose();
    _searchFocus.dispose();
    _sheet.dispose();
    super.dispose();
  }

  void _moveMap(LatLng p, double zoom) {
    if (!_mapReady) return;
    try {
      _map.move(p, zoom);
    } catch (_) {}
  }

  Future<void> _locate({bool initial = false}) async {
    final p = await ref.read(userLocationProvider.notifier).locate();
    if (!mounted) return;
    if (p == null) {
      if (!initial) {
        // Say why (location off on the device / blocked / not found), not just "failed".
        final why = gpsMessageKey(ref.read(userLocationProvider).state) ?? 'svc_gps_failed';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ref.read(stringsProvider).t(why))));
      }
      return;
    }
    setState(() {
      _query = _query.copyWith(lat: p.latitude, lng: p.longitude);
      _moved = false;
    });
    _moveMap(p, 12);
  }

  Future<void> _searchPlace() async {
    final q = _searchCtrl.text.trim();
    if (q.length < 2) return;
    _searchFocus.unfocus();
    setState(() => _geocoding = true);
    final p = await ref.read(geoServiceProvider).geocode(q);
    if (!mounted) return;
    setState(() => _geocoding = false);
    if (p == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ref.read(stringsProvider).t('svc_place_not_found'))));
      return;
    }
    setState(() {
      _query = _query.copyWith(lat: p.latitude, lng: p.longitude);
      _selectedId = null;
      _picked = null;
      _moved = false;
    });
    _moveMap(p, 12);
  }

  /// Enter in the search box: an exact service name opens that service,
  /// otherwise the first place found, otherwise the old place lookup.
  Future<void> _submitSearch() async {
    final key = (q: _searchCtrl.text.trim(), lang: ref.read(currentLocaleProvider).languageCode);
    if (key.q.length < 2) return;
    final services = ref.read(serviceTextSearchProvider(key)).valueOrNull ?? const <ServiceProvider>[];
    if (services.isNotEmpty && foldText(services.first.name) == foldText(key.q)) {
      _pickService(services.first);
      return;
    }
    final places = ref.read(placeSuggestionsProvider(key)).valueOrNull ?? const <PlaceSuggestion>[];
    if (places.isNotEmpty) {
      _pickPlace(places.first);
      return;
    }
    await _searchPlace();
  }

  /// A city / district / street / address from the search: the map goes
  /// there and the nearby services of that area are loaded.
  void _pickPlace(PlaceSuggestion pl) {
    _searchFocus.unfocus();
    final p = LatLng(pl.lat, pl.lng);
    setState(() {
      _searchCtrl.text = pl.title;
      _query = _query.copyWith(lat: p.latitude, lng: p.longitude);
      _selectedId = null;
      _picked = null;
      _moved = false;
    });
    _moveMap(p, placeZoom(pl.osmClass, pl.osmType));
  }

  /// A service from the search (anywhere): its card opens; with a real map
  /// position the map goes there and nearby services load around it.
  /// Without a position no pin is drawn (no fake point).
  void _pickService(ServiceProvider p) {
    _searchFocus.unfocus();
    final hasPin = hasRealCoords(p.lat, p.lng);
    setState(() {
      _searchCtrl.text = p.name;
      _picked = p;
      _selectedId = p.id;
      if (hasPin) {
        _query = _query.copyWith(lat: p.lat, lng: p.lng);
        _moved = false;
      }
    });
    if (hasPin) _moveMap(LatLng(p.lat, p.lng), 14);
    if (_sheet.isAttached && _sheet.size < 0.4) {
      _sheet.animateTo(0.42, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
    }
  }

  void _pickCategory(ServiceCategory c) {
    _searchFocus.unfocus();
    setState(() {
      _searchCtrl.clear();
      _query = _query.copyWith(category: () => c.id);
      _selectedId = null;
      _picked = null;
    });
  }

  void _searchHere() {
    if (!_mapReady) return;
    final c = _map.camera.center;
    setState(() {
      _query = _query.copyWith(lat: c.latitude, lng: c.longitude);
      _moved = false;
      _selectedId = null;
    });
  }

  void _select(ServiceProvider p) {
    setState(() => _selectedId = p.id);
    if (hasRealCoords(p.lat, p.lng)) _moveMap(LatLng(p.lat, p.lng), math.max(_mapReady ? _map.camera.zoom : 12, 13));
    if (_sheet.isAttached && _sheet.size < 0.4) {
      _sheet.animateTo(0.42, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
    }
  }

  Future<void> _openFilters(AppStrings s) async {
    final res = await showModalBottomSheet<ServiceQuery>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _FilterSheet(query: _query, s: s),
    );
    if (res != null && mounted) setState(() => _query = res);
  }

  /// Simple grid clustering so weak phones never draw hundreds of pins.
  List<Marker> _markers(List<ServiceProvider> all, LatLng? me) {
    final out = <Marker>[];
    final items = [for (final p in all) if (hasRealCoords(p.lat, p.lng)) p];
    final zoom = _zoomBucket;
    if (zoom >= 14 || items.length <= 25) {
      for (final p in items) {
        final sel = p.id == _selectedId;
        out.add(Marker(
          point: LatLng(p.lat, p.lng),
          width: sel ? 46 : 38,
          height: sel ? 46 : 38,
          child: GestureDetector(
            onTap: () => _select(p),
            child: ServicePin(type: p.markerType, active: p.isActive, selected: sel, pro: p.isPro),
          ),
        ));
      }
    } else {
      final cellDeg = 360 / (256 * math.pow(2, zoom)) * 60;
      final cells = <String, List<ServiceProvider>>{};
      for (final p in items) {
        final key = '${(p.lat / cellDeg).floor()}:${(p.lng / cellDeg).floor()}';
        (cells[key] ??= []).add(p);
      }
      for (final group in cells.values) {
        if (group.length == 1 || group.any((p) => p.id == _selectedId)) {
          for (final p in group) {
            final sel = p.id == _selectedId;
            out.add(Marker(
              point: LatLng(p.lat, p.lng),
              width: sel ? 46 : 38,
              height: sel ? 46 : 38,
              child: GestureDetector(onTap: () => _select(p), child: ServicePin(type: p.markerType, active: p.isActive, selected: sel, pro: p.isPro)),
            ));
          }
          continue;
        }
        final lat = group.map((p) => p.lat).reduce((a, b) => a + b) / group.length;
        final lng = group.map((p) => p.lng).reduce((a, b) => a + b) / group.length;
        out.add(Marker(
          point: LatLng(lat, lng),
          width: 44,
          height: 44,
          child: GestureDetector(
            onTap: () => _moveMap(LatLng(lat, lng), math.min(zoom + 2.0, 16)),
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.accentFill,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
                boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 5)],
              ),
              alignment: Alignment.center,
              child: Text('${group.length}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500, fontSize: 13)),
            ),
          ),
        ));
      }
    }
    if (me != null) {
      out.add(Marker(
        point: me,
        width: 26,
        height: 26,
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.blue.withValues(alpha: 0.25),
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(color: AppColors.blue, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2.5)),
          ),
        ),
      ));
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    final lang = ref.watch(currentLocaleProvider).languageCode;
    final loc = ref.watch(userLocationProvider);
    final results = ref.watch(serviceNearbyProvider(_query));
    final cats = ref.watch(serviceCategoriesProvider).valueOrNull ?? const <ServiceCategory>[];
    // Keep showing the previous pins while a new search loads.
    // PRO services first, then by distance (server order).
    final items = [...(results.valueOrNull ?? _lastItems)];
    if (results.hasValue) _lastItems = results.value!;
    if (items.any((p) => p.isPro)) {
      final pro = items.where((p) => p.isPro).toList();
      final rest = items.where((p) => !p.isPro).toList();
      items
        ..clear()
        ..addAll(pro)
        ..addAll(rest);
    }
    // The service picked in the search keeps its real (user) distance and
    // stays visible while it is selected, even outside the loaded area.
    final picked = _picked != null && _picked!.id == _selectedId ? _picked : null;
    if (picked != null) {
      final i = items.indexWhere((p) => p.id == picked.id);
      if (i >= 0) {
        items[i] = picked;
      } else {
        items.insert(0, picked);
      }
    }
    ServiceProvider? selected;
    for (final p in items) {
      if (p.id == _selectedId) selected = p;
    }
    final me = loc.point;
    final selectedHasPin = selected != null && hasRealCoords(selected.lat, selected.lng);

    RouteInfo? route;
    if (selected != null && selectedHasPin && me != null) {
      route = ref
          .watch(routeInfoProvider((aLat: me.latitude, aLng: me.longitude, bLat: selected.lat, bLng: selected.lng)))
          .valueOrNull;
    }

    return Scaffold(
      body: Column(children: [
        // Banner (owner, 21.10.2026): night / day picture, the admin
        // changes it here (pencil).
        SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: LayoutBuilder(
              builder: (context, c) => PageHeroBanner(
                page: 'services',
                strings: s,
                kicker: s.t('nav_services'),
                defaultTitle: s.t('svc_hero_title'),
                defaultAccent: s.t('svc_hero_accent'),
                defaultSubtitle: s.t('svc_hero_subtitle'),
                icon: Icons.handyman,
                compact: !isDesktopLayout(context),
                height: isDesktopLayout(context) ? (c.maxWidth * 0.16).clamp(180.0, 260.0) : 150,
              ),
            ),
          ),
        ),
        // The map and its controls under the banner (no second top inset).
        Expanded(
          child: MediaQuery.removePadding(
            context: context,
            removeTop: true,
            child: Stack(
        children: [
          Positioned.fill(
            child: FlutterMap(
              mapController: _map,
              options: MapOptions(
                initialCenter: LatLng(_query.lat, _query.lng),
                initialZoom: 11,
                minZoom: 3,
                maxZoom: 18,
                backgroundColor: AppColors.hero,
                interactionOptions: const InteractionOptions(flags: InteractiveFlag.all & ~InteractiveFlag.rotate),
                onMapReady: () {
                  _mapReady = true;
                  final p = ref.read(userLocationProvider).point;
                  if (p != null) _moveMap(p, 12);
                },
                onTap: (_, __) {
                  _searchFocus.unfocus();
                  if (_selectedId != null) {
                    setState(() {
                      _selectedId = null;
                      _picked = null;
                    });
                  }
                },
                onPositionChanged: (camera, hasGesture) {
                  final b = camera.zoom.floor();
                  final movedNow = hasGesture && !_moved;
                  if (b != _zoomBucket || movedNow) {
                    // Called while the map lays out — update after the frame.
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (!mounted) return;
                      setState(() {
                        _zoomBucket = b;
                        if (movedNow) _moved = true;
                      });
                    });
                  }
                },
              ),
              children: [
                const AppTileLayer(),
                if (selected != null && selectedHasPin && me != null)
                  PolylineLayer(polylines: [
                    Polyline(
                      points: route?.points ?? [me, LatLng(selected.lat, selected.lng)],
                      color: AppColors.accent,
                      strokeWidth: 4,
                    ),
                  ]),
                MarkerLayer(markers: _markers(items, me)),
                const AppMapAttribution(),
              ],
            ),
          ),
          // Search + category chips.
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Material(
                          color: AppColors.hero.withValues(alpha: 0.96),
                          elevation: 3,
                          borderRadius: BorderRadius.circular(14),
                          child: TextField(
                            controller: _searchCtrl,
                            focusNode: _searchFocus,
                            textInputAction: TextInputAction.search,
                            onSubmitted: (_) => _submitSearch(),
                            style: const TextStyle(fontSize: 14),
                            decoration: InputDecoration(
                              isDense: true,
                              hintText: s.t('svc_search_place_hint'),
                              prefixIcon: const Icon(Icons.search, size: 20),
                              suffixIcon: _geocoding
                                  ? const Padding(
                                      padding: EdgeInsets.all(12),
                                      child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                                    )
                                  : (_searchCtrl.text.isEmpty
                                      ? null
                                      : IconButton(
                                          icon: const Icon(Icons.close, size: 18),
                                          onPressed: () => setState(() {
                                            _searchCtrl.clear();
                                            _picked = null;
                                          }),
                                        )),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                              filled: false,
                              contentPadding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                            onChanged: (_) => setState(() {}),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      _RoundButton(
                        icon: Icons.tune,
                        tooltip: s.t('svc_filters'),
                        highlighted: _query.minRating > 0 || _query.onlyActive || _query.kind != null || (_query.text ?? '').isNotEmpty || _query.radiusKm != 100,
                        onTap: () => _openFilters(s),
                      ),
                    ],
                  ),
                  // "Parklar | Servislər" (owner, 31.10.2026): back to TIRPark.
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: ParksServicesSwitch(parks: false, s: s, onParks: () => context.go('/tirpark'), onServices: () {}),
                  ),
                  if (_searchFocus.hasFocus && _searchCtrl.text.trim().length >= 2)
                    TextFieldTapRegion(
                      child: _SearchSuggestions(
                        s: s,
                        lang: lang,
                        query: _searchCtrl.text.trim(),
                        categories: cats,
                        onPlace: _pickPlace,
                        onService: _pickService,
                        onCategory: _pickCategory,
                      ),
                    ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 34,
                    child: MouseDragScroll(child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: [
                        _CatChip(
                          label: s.t('svc_all'),
                          icon: Icons.apps,
                          selected: _query.category == null,
                          onTap: () => setState(() => _query = _query.copyWith(category: () => null)),
                        ),
                        for (final c in cats)
                          _CatChip(
                            label: c.name(lang),
                            icon: serviceCategoryIcon(c.icon),
                            selected: _query.category == c.id,
                            onTap: () => setState(() {
                              _query = _query.copyWith(category: () => _query.category == c.id ? null : c.id);
                              _selectedId = null;
                            }),
                          ),
                      ],
                    )),
                  ),
                  if (gpsMessageKey(loc.state) != null) ...[
                    const SizedBox(height: 8),
                    _GpsBanner(s: s, messageKey: gpsMessageKey(loc.state)!, onRetry: () => _locate()),
                  ],
                  if (_moved) ...[
                    const SizedBox(height: 8),
                    Center(
                      child: FilledButton.icon(
                        onPressed: _searchHere,
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          minimumSize: Size.zero,
                          visualDensity: VisualDensity.compact,
                        ),
                        icon: const Icon(Icons.refresh, size: 16),
                        label: Text(s.t('svc_search_here'), style: const TextStyle(fontSize: 13)),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          // My location button.
          Positioned(
            right: 12,
            bottom: MediaQuery.sizeOf(context).height * 0.30 + 12,
            child: _RoundButton(
              icon: loc.state == GpsState.locating ? Icons.gps_not_fixed : Icons.my_location,
              tooltip: s.t('svc_my_location'),
              highlighted: loc.state == GpsState.ok,
              onTap: () => _locate(),
            ),
          ),
          // "Servis əlavə et" (owner, 31.10.2026): one's own service, or
          // joining as a master / service centre (the existing flows).
          Positioned(
            right: 12,
            bottom: MediaQuery.sizeOf(context).height * 0.30 + 72,
            child: MapAddButton(
              buttonKey: 'svc-add',
              label: s.t('svc_add'),
              onTap: () {
                final id = ref.read(myServiceProvider).valueOrNull?.id;
                context.pushOnce(id != null ? '/service/$id' : '/service-join');
              },
            ),
          ),
          // Results sheet.
          DraggableScrollableSheet(
            controller: _sheet,
            initialChildSize: 0.28,
            minChildSize: 0.12,
            maxChildSize: 0.88,
            snap: true,
            snapSizes: const [0.28, 0.5],
            builder: (context, scroll) => _ResultsSheet(
              scroll: scroll,
              s: s,
              lang: lang,
              results: results,
              items: items,
              selected: selected,
              route: route,
              hasGps: me != null,
              query: _query,
              categories: cats,
              onSelect: _select,
              onRetry: () => ref.invalidate(serviceNearbyProvider(_query)),
              onWiden: () => setState(() => _query = _query.copyWith(radiusKm: math.min(_query.radiusKm * 2.5, 1000))),
            ),
          ),
        ],
      ),
          ),
        ),
      ]),
    );
  }
}

class _RoundButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final bool highlighted;
  final VoidCallback onTap;
  const _RoundButton({required this.icon, required this.tooltip, required this.onTap, this.highlighted = false});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.hero.withValues(alpha: 0.96),
      elevation: 3,
      shape: const CircleBorder(),
      child: IconButton(
        tooltip: tooltip,
        onPressed: onTap,
        icon: Icon(icon, color: highlighted ? AppColors.accent : AppColors.text, size: 22),
      ),
    );
  }
}

class _CatChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  const _CatChip({required this.label, required this.icon, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: Material(
        color: selected ? AppColors.accentFill : AppColors.hero.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(17),
        elevation: 2,
        child: InkWell(
          borderRadius: BorderRadius.circular(17),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 11),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 15, color: selected ? Colors.white : AppColors.textSoft),
                const SizedBox(width: 5),
                Text(label, style: TextStyle(fontSize: 12.5, color: selected ? Colors.white : AppColors.text, fontWeight: FontWeight.w500)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _GpsBanner extends StatelessWidget {
  final AppStrings s;
  final String messageKey;
  final VoidCallback onRetry;
  const _GpsBanner({required this.s, required this.messageKey, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    // Approximate position (computers): an information, not an error.
    final info = messageKey == 'svc_gps_approx';
    final fg = info ? AppColors.text : AppColors.urgentFg;
    return Material(
      color: info ? AppColors.cardAlt : AppColors.urgentBg,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
        child: Row(
          children: [
            Icon(info ? Icons.location_searching : Icons.location_off, size: 18, color: fg),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                s.t(messageKey),
                style: TextStyle(fontSize: 12, color: fg, height: 1.3),
              ),
            ),
            TextButton(onPressed: onRetry, child: Text(s.t('svc_gps_retry'), style: const TextStyle(fontSize: 12))),
          ],
        ),
      ),
    );
  }
}

class _ResultsSheet extends ConsumerWidget {
  final ScrollController scroll;
  final AppStrings s;
  final String lang;
  final AsyncValue<List<ServiceProvider>> results;
  final List<ServiceProvider> items;
  final ServiceProvider? selected;
  final RouteInfo? route;
  final bool hasGps;
  final ServiceQuery query;
  final List<ServiceCategory> categories;
  final ValueChanged<ServiceProvider> onSelect;
  final VoidCallback onRetry;
  final VoidCallback onWiden;

  const _ResultsSheet({
    required this.scroll,
    required this.s,
    required this.lang,
    required this.results,
    required this.items,
    required this.selected,
    required this.route,
    required this.hasGps,
    required this.query,
    required this.categories,
    required this.onSelect,
    required this.onRetry,
    required this.onWiden,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mine = ref.watch(myServiceProvider);
    final pendingKind = pendingServiceKind();
    final hasMine = mine.valueOrNull != null;
    final ordered = <ServiceProvider>[
      if (selected != null) selected!,
      ...items.where((p) => p.id != selected?.id),
    ];

    return Material(
      color: AppColors.background,
      elevation: 8,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
      clipBehavior: Clip.antiAlias,
      child: CustomScrollView(
        controller: scroll,
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 38,
                      height: 4,
                      decoration: BoxDecoration(color: AppColors.line, borderRadius: BorderRadius.circular(2)),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          results.isLoading && items.isEmpty
                              ? s.t('svc_searching')
                              : s.t('svc_found', {'n': '${items.length}', 'km': query.radiusKm.round().toString()}),
                          style: const TextStyle(fontWeight: FontWeight.w400, fontSize: 14.5),
                        ),
                      ),
                      TextButton.icon(
                        onPressed: () => context.pushOnce(hasMine ? '/service/${mine.valueOrNull!.id}' : '/service-join'),
                        style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8), visualDensity: VisualDensity.compact),
                        icon: Icon(hasMine ? Icons.storefront : Icons.add_business, size: 18),
                        label: Text(s.t(hasMine ? 'svc_my_service' : 'svc_join_short'), style: const TextStyle(fontSize: 12.5)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  ServiceLegend(s: s),
                  if (!hasMine && pendingKind != null && mine.hasValue) ...[
                    const SizedBox(height: 10),
                    Material(
                      color: AppColors.routeSoft,
                      borderRadius: BorderRadius.circular(12),
                      child: ListTile(
                        dense: true,
                        leading: Icon(Icons.storefront, color: AppColors.route),
                        title: Text(s.t('svc_finish_profile_title'), style: const TextStyle(fontWeight: FontWeight.w400)),
                        subtitle: Text(s.t('svc_finish_profile_body')),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => context.pushOnce('/service-edit?kind=$pendingKind'),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (results.hasError && items.isEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    Text(s.t('svc_load_failed'), textAlign: TextAlign.center, style: TextStyle(color: AppColors.textSoft)),
                    const SizedBox(height: 8),
                    OutlinedButton(onPressed: onRetry, child: Text(s.t('common_try_again'))),
                  ],
                ),
              ),
            )
          else if (results.isLoading && items.isEmpty)
            const SliverToBoxAdapter(
              child: Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
            )
          else if (items.isEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                child: Column(
                  children: [
                    Icon(Icons.search_off, size: 36, color: AppColors.textSoft),
                    const SizedBox(height: 8),
                    Text(s.t('svc_none_here'), textAlign: TextAlign.center, style: TextStyle(color: AppColors.textSoft)),
                    const SizedBox(height: 10),
                    if (query.radiusKm < 1000) OutlinedButton(onPressed: onWiden, child: Text(s.t('svc_widen'))),
                  ],
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
              sliver: SliverList.separated(
                itemCount: ordered.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, i) {
                  final p = ordered[i];
                  final isSel = p.id == selected?.id;
                  return ServiceListCard(
                    p: p,
                    s: s,
                    lang: lang,
                    categories: categories,
                    selected: isSel,
                    route: isSel ? route : null,
                    hasGps: hasGps,
                    onTap: () => onSelect(p),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

/// One provider in the results list.
class ServiceListCard extends StatelessWidget {
  final ServiceProvider p;
  final AppStrings s;
  final String lang;
  final List<ServiceCategory> categories;
  final bool selected;
  final RouteInfo? route;
  final bool hasGps;
  final VoidCallback onTap;

  const ServiceListCard({
    super.key,
    required this.p,
    required this.s,
    required this.lang,
    required this.categories,
    required this.selected,
    required this.route,
    required this.hasGps,
    required this.onTap,
  });

  String _catNames() {
    final names = <String>[];
    for (final id in p.categories) {
      for (final c in categories) {
        if (c.id == id) names.add(c.name(lang));
      }
    }
    return names.take(2).join(' · ') + (names.length > 2 ? ' +${names.length - 2}' : '');
  }

  String _duration(double minutes) {
    final h = minutes ~/ 60;
    final m = (minutes % 60).round();
    return h > 0 ? s.t('map_duration_hm', {'h': '$h', 'm': '$m'}) : s.t('map_duration_m', {'m': '$m'});
  }

  @override
  Widget build(BuildContext context) {
    final type = p.markerType;
    final cats = _catNames();
    return Material(
      color: selected ? AppColors.cardAlt : AppColors.card,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? AppColors.accent : (p.isPro ? kProGold.withValues(alpha: 0.75) : AppColors.line),
              width: p.isPro ? 1.5 : 1,
            ),
            gradient: p.isPro
                ? const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0x26FFC83D), Color(0x00FFC83D)],
                  )
                : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(width: 34, height: 34, child: ServicePin(type: type, active: p.isActive, pro: p.isPro)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(p.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontWeight: FontWeight.w400, fontSize: 15)),
                            ),
                            const SizedBox(width: 5),
                            ServiceTrustBadge(p: p, s: s, compact: true),
                            if (p.isPro) ...[
                              const SizedBox(width: 5),
                              const ServiceProBadge(compact: true),
                            ],
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          [s.t(serviceMarkerLabelKey(type)), if (cats.isNotEmpty) cats].join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12, color: AppColors.textSoft),
                        ),
                        const SizedBox(height: 4),
                        Wrap(
                          spacing: 10,
                          runSpacing: 2,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            if (p.distanceKm != null)
                              _Meta(icon: Icons.near_me, text: fmtKm(p.distanceKm!)),
                            if (p.ratingCount > 0)
                              _Meta(icon: Icons.star_rounded, text: '${p.ratingAvg.toStringAsFixed(1)} (${p.ratingCount})', color: const Color(0xFFFACC15))
                            else
                              _Meta(icon: Icons.star_outline_rounded, text: s.t('svc_no_reviews')),
                            _Meta(
                              icon: Icons.circle,
                              text: s.t(p.isActive ? 'svc_active' : 'svc_inactive'),
                              color: p.isActive ? AppColors.online : AppColors.textSoft,
                              iconSize: 8,
                            ),
                            if (p.is24h) const _Meta(icon: Icons.schedule, text: '24/7'),
                          ],
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: s.t('svc_details'),
                    visualDensity: VisualDensity.compact,
                    onPressed: () => context.pushOnce('/service/${p.id}'),
                    icon: Icon(Icons.chevron_right, color: AppColors.textSoft),
                  ),
                ],
              ),
              if (selected) ...[
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(color: AppColors.routeSoft, borderRadius: BorderRadius.circular(10)),
                  child: Row(
                    children: [
                      Icon(Icons.route, size: 18, color: AppColors.route),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          !hasRealCoords(p.lat, p.lng)
                              ? s.t('svc_no_pin')
                              : !hasGps
                              ? s.t('svc_route_need_gps')
                              : route == null
                                  ? s.t('svc_route_loading')
                                  : route!.isRoad
                                      ? s.t('svc_route_info', {
                                          'km': fmtKm(route!.distanceKm),
                                          'time': route!.durationMin == null ? '—' : _duration(route!.durationMin!),
                                        })
                                      : s.t('svc_route_straight', {'km': fmtKm(route!.distanceKm)}),
                          style: TextStyle(fontSize: 12.5, color: AppColors.newFg),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                ServiceContactBar(p: p, s: s, dense: true),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Suggestions under the search box while typing: matching categories,
/// services (all active + approved ones, best match first, then nearest)
/// and places (city, district, street, address — any country).
class _SearchSuggestions extends ConsumerWidget {
  final AppStrings s;
  final String lang;
  final String query;
  final List<ServiceCategory> categories;
  final ValueChanged<PlaceSuggestion> onPlace;
  final ValueChanged<ServiceProvider> onService;
  final ValueChanged<ServiceCategory> onCategory;

  const _SearchSuggestions({
    required this.s,
    required this.lang,
    required this.query,
    required this.categories,
    required this.onPlace,
    required this.onService,
    required this.onCategory,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = (q: query, lang: lang);
    final services = ref.watch(serviceTextSearchProvider(key));
    final places = ref.watch(placeSuggestionsProvider(key));
    final cats = [for (final c in categories) if (categoryMatches(query, c.names.values)) c].take(3).toList();
    final serviceList = (services.valueOrNull ?? const <ServiceProvider>[]).take(6).toList();
    final placeList = (places.valueOrNull ?? const <PlaceSuggestion>[]).take(4).toList();
    final loading = services.isLoading || places.isLoading;

    String catNames(ServiceProvider p) =>
        [for (final c in categories) if (p.categories.contains(c.id)) c.name(lang)].take(2).join(', ');

    Widget header(String key) => Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
          child: Text(s.t(key).toUpperCase(),
              style: TextStyle(fontSize: 11, color: AppColors.textSoft, letterSpacing: 1.0, fontWeight: FontWeight.w500)),
        );

    final children = <Widget>[
      if (cats.isNotEmpty) ...[
        header('svc_sugg_categories'),
        for (final c in cats)
          ListTile(
            dense: true,
            leading: Icon(serviceCategoryIcon(c.icon), color: AppColors.accent),
            title: Text(c.name(lang), maxLines: 1, overflow: TextOverflow.ellipsis),
            onTap: () => onCategory(c),
          ),
      ],
      if (serviceList.isNotEmpty) ...[
        header('svc_sugg_services'),
        for (final p in serviceList)
          ListTile(
            dense: true,
            leading: Icon(serviceMarkerIcon(p.markerType), color: serviceMarkerColor(p.markerType)),
            title: Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w400)),
            // City and kind of service tell services with the same name apart.
            subtitle: Text(
              [
                if ((p.city ?? '').trim().isNotEmpty) p.city!.trim(),
                if (catNames(p).isNotEmpty) catNames(p) else s.t(serviceMarkerLabelKey(p.markerType)),
              ].join(' · '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: AppColors.textSoft),
            ),
            // Real distance from the user only; nothing when it is unknown.
            trailing: p.distanceKm == null
                ? null
                : Text(fmtKm(p.distanceKm!), style: TextStyle(fontSize: 12, color: AppColors.textSoft)),
            onTap: () => onService(p),
          ),
      ],
      if (placeList.isNotEmpty) ...[
        header('svc_sugg_places'),
        for (final pl in placeList)
          ListTile(
            dense: true,
            leading: Icon(Icons.place_outlined, color: AppColors.blue),
            title: Text(pl.title, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: pl.subtitle.isEmpty
                ? null
                : Text(pl.subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: AppColors.textSoft)),
            onTap: () => onPlace(pl),
          ),
      ],
      if (loading)
        const Padding(
          padding: EdgeInsets.all(12),
          child: Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))),
        )
      else if (cats.isEmpty && serviceList.isEmpty && placeList.isEmpty)
        Padding(
          padding: const EdgeInsets.all(14),
          child: Text(s.t('svc_sugg_none'), style: TextStyle(color: AppColors.textSoft)),
        ),
    ];

    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Material(
        color: AppColors.hero.withValues(alpha: 0.98),
        elevation: 4,
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: math.min(380, MediaQuery.sizeOf(context).height * 0.45)),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.only(bottom: 6),
            children: children,
          ),
        ),
      ),
    );
  }
}

class _Meta extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color? _color;
  final double iconSize;
  const _Meta({required this.icon, required this.text, Color? color, this.iconSize = 13}) : _color = color;
  Color get color => _color ?? AppColors.textSoft;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: iconSize, color: color),
        const SizedBox(width: 3),
        Text(text, style: TextStyle(fontSize: 11.5, color: AppColors.textSoft)),
      ],
    );
  }
}

/// Filters: distance, minimum rating, only active, provider kind, name.
class _FilterSheet extends StatefulWidget {
  final ServiceQuery query;
  final AppStrings s;
  const _FilterSheet({required this.query, required this.s});

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  late ServiceQuery q = widget.query;
  late final _text = TextEditingController(text: widget.query.text ?? '');

  static const _radii = [10.0, 25.0, 50.0, 100.0, 250.0, 500.0];
  static const _ratings = [0.0, 3.0, 4.0, 4.5];

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.s;
    Widget title(String k) => Padding(
          padding: const EdgeInsets.only(top: 14, bottom: 6),
          child: Text(s.t(k), style: TextStyle(fontWeight: FontWeight.w400, color: AppColors.textSoft, fontSize: 12.5)),
        );
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(s.t('svc_filters'), style: Theme.of(context).textTheme.titleMedium),
            title('svc_filter_name'),
            TextField(
              controller: _text,
              decoration: InputDecoration(isDense: true, hintText: s.t('svc_filter_name_hint'), prefixIcon: const Icon(Icons.search, size: 18)),
            ),
            title('svc_filter_distance'),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final r in _radii)
                  ChoiceChip(
                    label: Text('${r.round()} km'),
                    selected: q.radiusKm == r,
                    onSelected: (_) => setState(() => q = q.copyWith(radiusKm: r)),
                  ),
              ],
            ),
            title('svc_filter_rating'),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final r in _ratings)
                  ChoiceChip(
                    label: Text(r == 0 ? s.t('svc_all') : '${r.toString().replaceAll('.0', '')}+ ★'),
                    selected: q.minRating == r,
                    onSelected: (_) => setState(() => q = q.copyWith(minRating: r)),
                  ),
              ],
            ),
            title('svc_filter_kind'),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                ChoiceChip(label: Text(s.t('svc_all')), selected: q.kind == null, onSelected: (_) => setState(() => q = q.copyWith(kind: () => null))),
                ChoiceChip(
                  label: Text(s.t('svc_kind_individual')),
                  selected: q.kind == 'individual',
                  onSelected: (_) => setState(() => q = q.copyWith(kind: () => 'individual')),
                ),
                ChoiceChip(
                  label: Text(s.t('svc_kind_center')),
                  selected: q.kind == 'center',
                  onSelected: (_) => setState(() => q = q.copyWith(kind: () => 'center')),
                ),
              ],
            ),
            const SizedBox(height: 6),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(s.t('svc_filter_only_active')),
              value: q.onlyActive,
              onChanged: (v) => setState(() => q = q.copyWith(onlyActive: v)),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(
                      context,
                      ServiceQuery(lat: q.lat, lng: q.lng, category: q.category),
                    ),
                    child: Text(s.t('svc_filter_reset')),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.pop(context, q.copyWith(text: () => _text.text.trim().isEmpty ? null : _text.text.trim())),
                    child: Text(s.t('svc_filter_apply')),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
