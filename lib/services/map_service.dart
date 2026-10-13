/// Provider-agnostic map contract. The UI and domain layers depend only
/// on this interface, never on Mapbox types directly — so swapping to
/// Google Maps later (per the brief) means writing one new
/// implementation class, with zero changes to feature code.
abstract class MapService {
  Future<double> distanceKm({
    required double fromLat,
    required double fromLng,
    required double toLat,
    required double toLng,
  });

  Future<Duration> estimatedTravelTime({
    required double fromLat,
    required double fromLng,
    required double toLat,
    required double toLng,
  });

  Future<List<({double lat, double lng})>> routePolyline({
    required double fromLat,
    required double fromLng,
    required double toLat,
    required double toLng,
  });
}

/// Implemented in Phase 10 using mapbox_maps_flutter + the Mapbox
/// Directions API. Kept as a stub here so the dependency direction
/// (features depend on this abstraction) is fixed from day one.
class MapboxMapService implements MapService {
  @override
  Future<double> distanceKm({
    required double fromLat,
    required double fromLng,
    required double toLat,
    required double toLng,
  }) {
    throw UnimplementedError('Implemented in Phase 10 — Map integration.');
  }

  @override
  Future<Duration> estimatedTravelTime({
    required double fromLat,
    required double fromLng,
    required double toLat,
    required double toLng,
  }) {
    throw UnimplementedError('Implemented in Phase 10 — Map integration.');
  }

  @override
  Future<List<({double lat, double lng})>> routePolyline({
    required double fromLat,
    required double fromLng,
    required double toLat,
    required double toLng,
  }) {
    throw UnimplementedError('Implemented in Phase 10 — Map integration.');
  }
}
