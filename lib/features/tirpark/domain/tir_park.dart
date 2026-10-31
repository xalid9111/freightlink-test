import 'dart:math' as math;

/// TIRPark (owner, 31.10.2026, migration 0077): a TIR park on the map.
/// Added by drivers, approved by an admin; until then only its author
/// (and admins) see it.
class TirPark {
  final String id;
  final String name;
  final double lat, lng;
  final String? city;
  final List<String> amenities;
  final String? note;
  final String status; // pending | approved | rejected | hidden
  final List<String> photoUrls;
  final double ratingAvg;
  final int ratingCount;
  final String? createdBy;
  final DateTime? createdAt;

  const TirPark({
    required this.id,
    required this.name,
    required this.lat,
    required this.lng,
    this.city,
    this.amenities = const [],
    this.note,
    this.status = 'pending',
    this.photoUrls = const [],
    this.ratingAvg = 0,
    this.ratingCount = 0,
    this.createdBy,
    this.createdAt,
  });

  bool get isApproved => status == 'approved';
  bool get isPending => status == 'pending';

  factory TirPark.fromJson(Map<String, dynamic> j) {
    double d(Object? v) => v is num ? v.toDouble() : double.tryParse('${v ?? ''}') ?? 0;
    List<String> l(Object? v) => [for (final x in (v as List? ?? const [])) '$x'];
    return TirPark(
      id: '${j['id']}',
      name: (j['name'] as String?) ?? '',
      lat: d(j['lat']),
      lng: d(j['lng']),
      city: j['city'] as String?,
      amenities: l(j['amenities']),
      note: j['note'] as String?,
      status: (j['status'] as String?) ?? 'pending',
      photoUrls: l(j['photo_urls']),
      ratingAvg: d(j['rating_avg']),
      ratingCount: (j['rating_count'] as num?)?.toInt() ?? 0,
      createdBy: j['created_by'] as String?,
      createdAt: DateTime.tryParse('${j['created_at']}'),
    );
  }
}

/// What a park offers (the server accepts only these, 0077), in the order
/// shown on the card and in the form.
const kTirParkAmenities = ['secure', '24_7', 'food', 'shower', 'wc', 'fuel', 'wifi', 'repair', 'lighting', 'camera', 'free', 'paid'];

/// Straight-line distance in kilometres.
double distanceKm(double lat1, double lng1, double lat2, double lng2) {
  const r = 6371.0;
  double rad(double x) => x * math.pi / 180;
  final dLat = rad(lat2 - lat1), dLng = rad(lng2 - lng1);
  final a = math.pow(math.sin(dLat / 2), 2) + math.cos(rad(lat1)) * math.cos(rad(lat2)) * math.pow(math.sin(dLng / 2), 2);
  return 2 * r * math.asin(math.sqrt(a));
}

/// "2.5 km" / "850 m".
String distanceLabel(double km) => km < 1 ? '${(km * 1000).round()} m' : (km < 10 ? '${km.toStringAsFixed(1)} km' : '${km.round()} km');

/// Parks within [radiusKm] of (lat, lng), nearest first; [query] matches
/// the name or the city (any letter case); [needs] = amenities a park must
/// all have.
List<(TirPark, double)> nearbyParks(List<TirPark> all, double lat, double lng,
    {double radiusKm = 100, String query = '', Set<String> needs = const {}}) {
  final q = query.trim().toLowerCase();
  final out = <(TirPark, double)>[];
  for (final p in all) {
    if (q.isNotEmpty && !p.name.toLowerCase().contains(q) && !(p.city ?? '').toLowerCase().contains(q)) continue;
    if (needs.isNotEmpty && !needs.every(p.amenities.contains)) continue;
    final d = distanceKm(lat, lng, p.lat, p.lng);
    if (q.isEmpty && d > radiusKm) continue;
    out.add((p, d));
  }
  out.sort((a, b) => a.$2.compareTo(b.$2));
  return out;
}

/// A park found near the place chosen for a new one (tir_parks_near).
class NearbyPark {
  final String id, name, status;
  final int distanceM;
  const NearbyPark({required this.id, required this.name, required this.status, required this.distanceM});
  factory NearbyPark.fromJson(Map<String, dynamic> j) => NearbyPark(
        id: '${j['id']}',
        name: '${j['name']}',
        status: '${j['status']}',
        distanceM: (j['distance_m'] as num?)?.toInt() ?? 0,
      );
}

/// Closer than this to an existing park = the same park (the server
/// refuses it too, 'duplicate_nearby').
const kTirParkDuplicateM = 60;

/// A comment on a park (0078): 1…5 stars and an optional text; one per
/// user and park.
class TirParkReview {
  final String id, userId;
  final int rating;
  final String? comment;
  final String? name, avatarUrl;
  final DateTime? createdAt;
  const TirParkReview({required this.id, required this.userId, required this.rating, this.comment, this.name, this.avatarUrl, this.createdAt});

  factory TirParkReview.fromJson(Map<String, dynamic> j) => TirParkReview(
        id: '${j['id']}',
        userId: '${j['user_id']}',
        rating: (j['rating'] as num?)?.toInt() ?? 0,
        comment: j['comment'] as String?,
        name: j['name'] as String?,
        avatarUrl: j['avatar_url'] as String?,
        createdAt: DateTime.tryParse('${j['created_at']}'),
      );
}

/// At most this many pictures per park (the server checks the same).
const kTirParkMaxPhotos = 10;
