import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

/// Free, key-less geo helpers for the cargo route map:
///  * geocoding a city ("Baku, Azerbaijan") with OpenStreetMap Nominatim,
///  * road distance / duration / shape with the public OSRM router,
///  * straight-line (great-circle) distance as an offline fallback.
/// The public servers are meant for light use — fine for testing and an
/// early launch; switch to a paid/self-hosted provider when traffic grows.
class RouteInfo {
  final double distanceKm;
  final double? durationMin;
  final List<LatLng> points;
  /// true = real road route (OSRM); false = straight-line estimate.
  final bool isRoad;
  const RouteInfo({required this.distanceKm, this.durationMin, required this.points, required this.isRoad});
}

class GeoService {
  static double straightKm(LatLng a, LatLng b) {
    const r = 6371.0;
    double rad(double d) => d * math.pi / 180;
    final dLat = rad(b.latitude - a.latitude);
    final dLng = rad(b.longitude - a.longitude);
    final h = math.pow(math.sin(dLat / 2), 2) +
        math.cos(rad(a.latitude)) * math.cos(rad(b.latitude)) * math.pow(math.sin(dLng / 2), 2);
    return 2 * r * math.asin(math.sqrt(h.toDouble()));
  }

  Future<LatLng?> geocode(String query) async {
    try {
      final uri = Uri.https('nominatim.openstreetmap.org', '/search', {
        'format': 'json',
        'limit': '1',
        'accept-language': 'en',
        'q': query,
      });
      final res = await http.get(uri).timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return null;
      final list = jsonDecode(res.body) as List<dynamic>;
      if (list.isEmpty) return null;
      final first = list.first as Map<String, dynamic>;
      final lat = double.tryParse('${first['lat']}');
      final lon = double.tryParse('${first['lon']}');
      return (lat == null || lon == null) ? null : LatLng(lat, lon);
    } catch (_) {
      return null;
    }
  }

  Future<RouteInfo> route(LatLng a, LatLng b) async {
    try {
      final uri = Uri.parse(
        'https://router.project-osrm.org/route/v1/driving/'
        '${a.longitude},${a.latitude};${b.longitude},${b.latitude}'
        '?overview=simplified&geometries=geojson',
      );
      final res = await http.get(uri).timeout(const Duration(seconds: 12));
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body) as Map<String, dynamic>;
        final routes = body['routes'] as List<dynamic>?;
        if (routes != null && routes.isNotEmpty) {
          final r = routes.first as Map<String, dynamic>;
          final coords = ((r['geometry'] as Map<String, dynamic>)['coordinates'] as List<dynamic>)
              .map((c) => LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble()))
              .toList();
          return RouteInfo(
            distanceKm: (r['distance'] as num).toDouble() / 1000,
            durationMin: (r['duration'] as num).toDouble() / 60,
            points: coords,
            isRoad: true,
          );
        }
      }
    } catch (_) {}
    return RouteInfo(distanceKm: straightKm(a, b), points: [a, b], isRoad: false);
  }
}

/// A city found by the online search (OpenStreetMap Nominatim).
class PlaceHit {
  final String city; // English name — what gets stored
  final String countryCode; // ISO, upper-case ('' if unknown)
  final String countryName; // English country name
  const PlaceHit({required this.city, required this.countryCode, required this.countryName});
}

extension GeoCitySearch on GeoService {
  /// Cities / towns matching [query] anywhere in the world (online).
  Future<List<PlaceHit>> searchCities(String query) async {
    final q = query.trim();
    if (q.length < 3) return const [];
    try {
      final uri = Uri.https('nominatim.openstreetmap.org', '/search', {
        'format': 'json',
        'limit': '8',
        'addressdetails': '1',
        'featureType': 'settlement',
        'accept-language': 'en',
        'q': q,
      });
      final res = await http.get(uri).timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return const [];
      final list = jsonDecode(res.body) as List<dynamic>;
      final out = <PlaceHit>[];
      final seen = <String>{};
      for (final item in list) {
        final m = item as Map<String, dynamic>;
        final a = (m['address'] as Map<String, dynamic>?) ?? const {};
        final city = (a['city'] ?? a['town'] ?? a['village'] ?? a['municipality'] ?? m['name'] ?? '').toString().trim();
        if (city.isEmpty) continue;
        final cc = (a['country_code'] ?? '').toString().toUpperCase();
        final key = '$city|$cc';
        if (!seen.add(key)) continue;
        out.add(PlaceHit(city: city, countryCode: cc, countryName: (a['country'] ?? '').toString()));
      }
      return out;
    } catch (_) {
      return const [];
    }
  }
}

/// A city, district, street or address found by the Services search.
class PlaceSuggestion {
  final String title; // "Nərimanov" / "Atatürk Caddesi 12"
  final String subtitle; // "Bakı, Azərbaycan"
  final double lat;
  final double lng;
  final String? osmClass;
  final String? osmType;
  const PlaceSuggestion({required this.title, required this.subtitle, required this.lat, required this.lng, this.osmClass, this.osmType});
}

extension GeoPlaceSearch on GeoService {
  /// Places matching [query] in any country (OpenStreetMap Nominatim), in
  /// the app language. Empty on error / offline.
  Future<List<PlaceSuggestion>> searchPlaces(String query, {String lang = 'az', int limit = 5}) async {
    final q = query.trim();
    if (q.length < 3) return const [];
    try {
      final uri = Uri.https('nominatim.openstreetmap.org', '/search', {
        'format': 'jsonv2',
        'limit': '$limit',
        'addressdetails': '1',
        'accept-language': '$lang,en',
        'q': q,
      });
      final res = await http.get(uri).timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return const [];
      final out = <PlaceSuggestion>[];
      for (final item in jsonDecode(res.body) as List<dynamic>) {
        final m = item as Map<String, dynamic>;
        final lat = double.tryParse('${m['lat']}');
        final lng = double.tryParse('${m['lon']}');
        if (lat == null || lng == null) continue;
        final display = '${m['display_name'] ?? ''}'.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
        final name = '${m['name'] ?? ''}'.trim();
        final title = name.isNotEmpty ? name : (display.isEmpty ? q : display.first);
        final a = (m['address'] as Map<String, dynamic>?) ?? const {};
        final area = [
          a['city'] ?? a['town'] ?? a['village'] ?? a['county'] ?? a['state'],
          a['country'],
        ].whereType<Object>().map((e) => '$e').where((e) => e.isNotEmpty && e != title).toList();
        out.add(PlaceSuggestion(
          title: title,
          subtitle: area.isNotEmpty ? area.join(', ') : display.skip(1).take(2).join(', '),
          lat: lat,
          lng: lng,
          osmClass: m['category'] as String? ?? m['class'] as String?,
          osmType: (m['addresstype'] ?? m['type']) as String?,
        ));
      }
      return out;
    } catch (_) {
      return const [];
    }
  }
}

final geoServiceProvider = Provider<GeoService>((ref) => GeoService());

typedef EndpointsKey = ({String pickupQuery, String destQuery, double? pLat, double? pLng, double? dLat, double? dLng});

/// Pickup / destination points of a cargo: the exact saved coordinates
/// when the owner set them, otherwise the geocoded city centre.
class CargoEndpoints {
  final LatLng? pickup;
  final LatLng? destination;
  final bool pickupExact;
  final bool destinationExact;
  const CargoEndpoints(this.pickup, this.destination, this.pickupExact, this.destinationExact);
}

final cargoEndpointsProvider = FutureProvider.family<CargoEndpoints, EndpointsKey>((ref, k) async {
  final geo = ref.watch(geoServiceProvider);
  final pExact = k.pLat != null && k.pLng != null;
  final dExact = k.dLat != null && k.dLng != null;
  final p = pExact ? LatLng(k.pLat!, k.pLng!) : await geo.geocode(k.pickupQuery);
  final d = dExact ? LatLng(k.dLat!, k.dLng!) : await geo.geocode(k.destQuery);
  return CargoEndpoints(p, d, pExact, dExact);
});

typedef RouteKey = ({double aLat, double aLng, double bLat, double bLng});

final routeInfoProvider = FutureProvider.family<RouteInfo, RouteKey>((ref, k) {
  return ref.watch(geoServiceProvider).route(LatLng(k.aLat, k.aLng), LatLng(k.bLat, k.bLng));
});
