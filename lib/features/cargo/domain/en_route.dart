import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

/// "Yolüstü yük" (owner, 21.10.2026): small loads that lie ON the
/// carrier's own road route — not "same country". A load matches when
///  * its pickup point and its delivery point are both within [maxOffKm]
///    of the carrier's road route (start → end), and
///  * the pickup comes before the delivery along that route (same
///    direction as the carrier drives).
/// Only a real road route (OSRM) is used; without one nothing is shown.

/// Where a point falls next to a route line.
class RoutePosition {
  /// Distance from the route line, km.
  final double offKm;

  /// Distance driven from the start to the nearest place on the route, km.
  final double alongKm;
  const RoutePosition(this.offKm, this.alongKm);
}

/// Nearest place on the route line [route] (≥ 2 points) to [p].
RoutePosition positionOnRoute(List<LatLng> route, LatLng p) {
  const kmPerDeg = 111.32;
  var best = const RoutePosition(double.infinity, 0);
  var driven = 0.0;
  for (var i = 0; i + 1 < route.length; i++) {
    final a = route[i], b = route[i + 1];
    // Flat projection around p — accurate enough for a few hundred km.
    final cosLat = math.cos(p.latitude * math.pi / 180);
    double x(LatLng q) => (q.longitude - p.longitude) * kmPerDeg * cosLat;
    double y(LatLng q) => (q.latitude - p.latitude) * kmPerDeg;
    final ax = x(a), ay = y(a), bx = x(b), by = y(b);
    final dx = bx - ax, dy = by - ay;
    final len2 = dx * dx + dy * dy;
    final t = len2 == 0 ? 0.0 : (-(ax * dx + ay * dy) / len2).clamp(0.0, 1.0);
    final cx = ax + t * dx, cy = ay + t * dy;
    final off = math.sqrt(cx * cx + cy * cy);
    final segKm = math.sqrt(len2);
    if (off < best.offKm) best = RoutePosition(off, driven + t * segKm);
    driven += segKm;
  }
  return best;
}

/// One load on the carrier's way.
class EnRouteMatch<T> {
  final T load;
  final double pickupOffKm, dropOffKm;

  /// Where the carrier picks it up, km from the start of the route.
  final double pickupAlongKm;
  const EnRouteMatch(this.load, this.pickupOffKm, this.dropOffKm, this.pickupAlongKm);
}

/// Loads (with their pickup and delivery points) that lie on [route], in
/// the order the carrier reaches them.
List<EnRouteMatch<T>> findEnRoute<T>({
  required List<LatLng> route,
  required List<({T load, LatLng pickup, LatLng drop})> loads,
  double maxOffKm = 50,
}) {
  if (route.length < 2) return const [];
  final out = <EnRouteMatch<T>>[];
  for (final l in loads) {
    final p = positionOnRoute(route, l.pickup);
    final d = positionOnRoute(route, l.drop);
    if (p.offKm > maxOffKm || d.offKm > maxOffKm) continue;
    if (d.alongKm <= p.alongKm) continue; // other direction
    out.add(EnRouteMatch(l.load, p.offKm, d.offKm, p.alongKm));
  }
  out.sort((a, b) => a.pickupAlongKm.compareTo(b.pickupAlongKm));
  return out;
}

/// Corridor widths the carrier can choose, km.
const kEnRouteRadii = [25, 50, 100];
const kEnRouteDefaultRadius = 50;
