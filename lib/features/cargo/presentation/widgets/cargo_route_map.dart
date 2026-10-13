import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../../../core/config/supabase_config.dart';
import '../../../../core/constants/countries.dart';
import '../../../../core/localization/app_strings.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../models/cargo_model.dart';
import '../../../../services/geo_service.dart';
import '../providers/cargo_providers.dart';

const _tileUrl = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
const _userAgent = 'az.freightlink.app';

EndpointsKey _keyFor(CargoModel c) => (
      pickupQuery: '${c.pickupCity}, ${Countries.canonical(c.pickupCountry)}',
      destQuery: '${c.destinationCity}, ${Countries.canonical(c.destinationCountry)}',
      pLat: c.pickupLatitude,
      pLng: c.pickupLongitude,
      dLat: c.destinationLatitude,
      dLng: c.destinationLongitude,
    );

String _fmtKm(double km) => km >= 100 ? km.toStringAsFixed(0) : km.toStringAsFixed(1);

String _fmtDuration(double minutes, AppStrings s) {
  final h = minutes ~/ 60;
  final m = (minutes % 60).round();
  return h > 0 ? s.t('map_duration_hm', {'h': '$h', 'm': '$m'}) : s.t('map_duration_m', {'m': '$m'});
}

Widget _pin(Color color, String letter) => Container(
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2.5),
        boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 6)],
      ),
      alignment: Alignment.center,
      child: Text(letter, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
    );

/// Route card on cargo detail (replaces the stage stepper): a small map
/// with the loading point (A, teal) and unloading point (B, orange), the
/// road route between them and the distance — so carriers can price the
/// job at a glance. Tap to open it full screen; the cargo owner can move
/// the points there.
class CargoRouteMap extends ConsumerWidget {
  final CargoModel cargo;
  final AppStrings strings;
  final bool isOwner;
  const CargoRouteMap({super.key, required this.cargo, required this.strings, required this.isOwner});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final endpointsAsync = ref.watch(cargoEndpointsProvider(_keyFor(cargo)));
    final ends = endpointsAsync.valueOrNull;
    final a = ends?.pickup;
    final b = ends?.destination;
    final routeAsync = (a != null && b != null)
        ? ref.watch(routeInfoProvider((aLat: a.latitude, aLng: a.longitude, bLat: b.latitude, bLng: b.longitude)))
        : null;
    final route = routeAsync?.valueOrNull;
    final approx = ends != null && (!ends.pickupExact || !ends.destinationExact);

    void open() {
      if (a == null || b == null) return;
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => RouteMapScreen(cargo: cargo, strings: strings, canEdit: isOwner, start: a, end: b),
      ));
    }

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
            child: Row(
              children: [
                Text(strings.t('map_title'), style: AppFonts.mono(color: AppColors.textSoft, letterSpacing: 1)),
                const Spacer(),
                if (route != null)
                  Text('≈ ${_fmtKm(route.distanceKm)} km', style: AppFonts.display(size: 20, color: AppColors.accent)),
              ],
            ),
          ),
          SizedBox(
            height: 210,
            child: (a == null || b == null)
                ? Center(
                    child: endpointsAsync.isLoading
                        ? const CircularProgressIndicator(strokeWidth: 2)
                        : Text(strings.t('map_unavailable'), style: const TextStyle(color: AppColors.textSoft)),
                  )
                : GestureDetector(
                    onTap: open,
                    child: AbsorbPointer(
                      child: _RouteMapView(start: a, end: b, route: route, interactive: false),
                    ),
                  ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (route != null)
                  Text(
                    route.isRoad
                        ? '${strings.t('map_road_distance')}: ${_fmtKm(route.distanceKm)} km'
                            '${route.durationMin != null ? ' · ${_fmtDuration(route.durationMin!, strings)}' : ''}'
                        : '${strings.t('map_straight_distance')}: ${_fmtKm(route.distanceKm)} km',
                    style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.text),
                  ),
                if (approx)
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Text(strings.t('map_approx_note'), style: const TextStyle(fontSize: 12, color: AppColors.textSoft)),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: (a == null || b == null) ? null : open,
                icon: Icon(isOwner ? Icons.edit_location_alt_outlined : Icons.fullscreen),
                label: Text(strings.t(isOwner ? 'map_edit_points' : 'map_open_full')),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RouteMapView extends StatelessWidget {
  final LatLng start;
  final LatLng end;
  final RouteInfo? route;
  final bool interactive;
  final void Function(LatLng)? onTap;
  final MapController? controller;
  const _RouteMapView({required this.start, required this.end, this.route, required this.interactive, this.onTap, this.controller});

  @override
  Widget build(BuildContext context) {
    final same = (start.latitude - end.latitude).abs() < 1e-6 && (start.longitude - end.longitude).abs() < 1e-6;
    return FlutterMap(
      mapController: controller,
      options: MapOptions(
        initialCenter: start,
        initialZoom: 6,
        initialCameraFit: same
            ? null
            : CameraFit.bounds(bounds: LatLngBounds(start, end), padding: const EdgeInsets.all(48)),
        backgroundColor: AppColors.hero,
        interactionOptions: InteractionOptions(
          flags: interactive ? (InteractiveFlag.all & ~InteractiveFlag.rotate) : InteractiveFlag.none,
        ),
        onTap: onTap == null ? null : (_, point) => onTap!(point),
      ),
      children: [
        TileLayer(urlTemplate: _tileUrl, userAgentPackageName: _userAgent),
        PolylineLayer(
          polylines: [
            Polyline(
              points: route?.points ?? [start, end],
              color: AppColors.accent,
              strokeWidth: 4,
            ),
          ],
        ),
        MarkerLayer(
          markers: [
            Marker(point: start, width: 34, height: 34, child: _pin(AppColors.route, 'A')),
            Marker(point: end, width: 34, height: 34, child: _pin(AppColors.accentFill, 'B')),
          ],
        ),
        RichAttributionWidget(
          attributions: [TextSourceAttribution('OpenStreetMap contributors')],
        ),
      ],
    );
  }
}

/// Full-screen route map. Carriers can pan/zoom; the cargo owner can
/// also move A (loading) and B (unloading) by choosing which point to
/// place and tapping the map, then save — exact coordinates and the
/// distance are stored on the cargo (owner-only RLS cargo_owner_write).
class RouteMapScreen extends ConsumerStatefulWidget {
  final CargoModel cargo;
  final AppStrings strings;
  final bool canEdit;
  final LatLng start;
  final LatLng end;
  const RouteMapScreen({super.key, required this.cargo, required this.strings, required this.canEdit, required this.start, required this.end});

  @override
  ConsumerState<RouteMapScreen> createState() => _RouteMapScreenState();
}

class _RouteMapScreenState extends ConsumerState<RouteMapScreen> {
  late LatLng _a = widget.start;
  late LatLng _b = widget.end;
  bool _editingA = true;
  bool _saving = false;
  bool _dirty = false;

  Future<void> _save() async {
    final s = widget.strings;
    setState(() => _saving = true);
    try {
      final route = await ref.read(geoServiceProvider).route(_a, _b);
      await SupabaseConfig.client.from('cargo').update({
        'pickup_latitude': double.parse(_a.latitude.toStringAsFixed(6)),
        'pickup_longitude': double.parse(_a.longitude.toStringAsFixed(6)),
        'destination_latitude': double.parse(_b.latitude.toStringAsFixed(6)),
        'destination_longitude': double.parse(_b.longitude.toStringAsFixed(6)),
        'distance_km': double.parse(route.distanceKm.toStringAsFixed(1)),
      }).eq('id', widget.cargo.id);
      ref.invalidate(cargoDetailProvider(widget.cargo.id));
      ref.invalidate(marketplaceProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.t('map_saved'))));
        Navigator.of(context).pop();
      }
    } catch (_) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.t('error_generic'))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.strings;
    final routeAsync = ref.watch(routeInfoProvider((aLat: _a.latitude, aLng: _a.longitude, bLat: _b.latitude, bLng: _b.longitude)));
    final route = routeAsync.valueOrNull;

    return Scaffold(
      appBar: AppBar(title: Text(s.t(widget.canEdit ? 'map_edit_points' : 'map_title_plain'))),
      body: Column(
        children: [
          if (widget.canEdit)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SegmentedButton<bool>(
                    segments: [
                      ButtonSegment(value: true, label: Text(s.t('map_point_a')), icon: const Icon(Icons.upload_outlined)),
                      ButtonSegment(value: false, label: Text(s.t('map_point_b')), icon: const Icon(Icons.download_outlined)),
                    ],
                    selected: {_editingA},
                    onSelectionChanged: (v) => setState(() => _editingA = v.first),
                  ),
                  const SizedBox(height: 6),
                  Text(s.t('map_edit_hint'), style: const TextStyle(fontSize: 12.5, color: AppColors.textSoft)),
                ],
              ),
            ),
          Expanded(
            child: _RouteMapView(
              start: _a,
              end: _b,
              route: route,
              interactive: true,
              onTap: widget.canEdit
                  ? (p) => setState(() {
                        if (_editingA) {
                          _a = p;
                        } else {
                          _b = p;
                        }
                        _dirty = true;
                      })
                  : null,
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          route == null ? '…' : '≈ ${_fmtKm(route.distanceKm)} km',
                          style: AppFonts.display(size: 26, color: AppColors.accent),
                        ),
                        if (route != null)
                          Text(
                            route.isRoad
                                ? '${s.t('map_road_distance')}${route.durationMin != null ? ' · ${_fmtDuration(route.durationMin!, s)}' : ''}'
                                : s.t('map_straight_distance'),
                            style: const TextStyle(fontSize: 12, color: AppColors.textSoft),
                          ),
                      ],
                    ),
                  ),
                  if (widget.canEdit)
                    FilledButton(
                      onPressed: (_dirty && !_saving) ? _save : null,
                      child: _saving
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                          : Text(s.t('map_save')),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
