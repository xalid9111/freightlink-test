import 'dart:math' as math;

/// Truck parking from OpenStreetMap on the TIRPark map ("Xəritə məlumatı",
/// owner 11.11.2026, SQL 0117). Map data only: never a platform park, never
/// bookable or managed, never in "Yaxınlıqdakı parklar". Only what the source
/// says is shown — nothing is made up. Azerbaijan never has any (the server
/// refuses AZ; there only the platform's own parks show).
class OsmTruckPark {
  /// OSM object id: 'node/123' | 'way/123' | 'relation/123'.
  final String id;
  final double lat;
  final double lng;
  final String? name;
  final Map<String, String> tags;
  const OsmTruckPark({required this.id, required this.lat, required this.lng, this.name, this.tags = const {}});

  factory OsmTruckPark.fromJson(Map<String, dynamic> j) {
    final raw = j['tags'];
    final name = (j['name'] as String?)?.trim();
    return OsmTruckPark(
      id: j['id'] as String,
      lat: (j['lat'] as num).toDouble(),
      lng: (j['lng'] as num).toDouble(),
      name: name == null || name.isEmpty ? null : name,
      tags: raw is Map ? {for (final e in raw.entries) '${e.key}': '${e.value}'} : const {},
    );
  }

  /// 'parking' | 'rest_area' | 'services'.
  String get kind => tags['kind'] ?? 'parking';

  /// true = paid, false = free, null = the source does not say.
  bool? get paid => switch (tags['fee']?.toLowerCase()) {
        'yes' => true,
        'no' => false,
        _ => null,
      };

  /// Truck spaces, only when the source gives a plain number.
  int? get capacity => int.tryParse((tags['capacity:hgv'] ?? '').trim());

  String? get openingHours => _text('opening_hours');
  String? get operator => _text('operator');

  /// Facilities the source marks with "yes" (toilets, shower, supervised, lit).
  List<String> get facilities => [
        for (final k in const ['toilets', 'shower', 'supervised', 'lit'])
          if ((tags[k] ?? '').toLowerCase() == 'yes') k,
      ];

  String? _text(String k) {
    final v = tags[k]?.trim();
    return v == null || v.isEmpty ? null : v;
  }

  /// Link to the object on openstreetmap.org (the source page).
  String get sourceUrl => 'https://www.openstreetmap.org/$id';
}

/// The map area asked for OSM objects: the visible screen snapped outwards
/// to a 0.5° grid, so small moves reuse the same answer (cached) and the
/// server is asked once per area, not on every frame.
class OsmBounds {
  final double south, west, north, east;
  const OsmBounds(this.south, this.west, this.north, this.east);

  /// Below this zoom no OSM objects are shown (too many for a phone).
  static const minZoom = 7.0;
  static const _step = 0.5;
  // The server answers only areas up to 12° × 24°.
  static const _maxLat = 12.0, _maxLng = 24.0;

  /// null = nothing to ask (zoomed out too far or a too big screen).
  static OsmBounds? of({required double south, required double west, required double north, required double east, required double zoom}) {
    if (zoom < minZoom || !south.isFinite || !north.isFinite || !west.isFinite || !east.isFinite) return null;
    double down(double v) => (v / _step).floorToDouble() * _step;
    double up(double v) => (v / _step).ceilToDouble() * _step;
    final b = OsmBounds(
      math.max(-90, down(south)),
      math.max(-180, down(west)),
      math.min(90, up(north)),
      math.min(180, up(east)),
    );
    if (b.south >= b.north || b.west >= b.east) return null;
    if (b.north - b.south > _maxLat || b.east - b.west > _maxLng) return null;
    return b;
  }

  @override
  bool operator ==(Object other) =>
      other is OsmBounds && other.south == south && other.west == west && other.north == north && other.east == east;
  @override
  int get hashCode => Object.hash(south, west, north, east);
  @override
  String toString() => 'OsmBounds($south, $west, $north, $east)';
}
