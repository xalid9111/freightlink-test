// Universal search of the Services page — pure logic (no Flutter, no
// Supabase), unit-tested in test/service_search_logic_test.dart.
import 'dart:math' as math;

/// Folds case and the letters people type in different ways (Azerbaijani,
/// Turkish, Russian, common Latin accents) so "seki", "Şəki" and "ŞƏKİ"
/// are the same, and "Baki" finds "Bakı".
String foldText(String s) {
  final lower = s.toLowerCase();
  final b = StringBuffer();
  for (final r in lower.runes) {
    final ch = String.fromCharCode(r);
    b.write(_fold[ch] ?? ch);
  }
  return b
      .toString()
      .replaceAll('̇', '') // "İ".toLowerCase() = "i" + combining dot
      .replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), ' ')
      .trim();
}

const _fold = <String, String>{
  'ə': 'e',
  'ı': 'i',
  'ö': 'o',
  'ü': 'u',
  'ş': 's',
  'ç': 'c',
  'ğ': 'g',
  'â': 'a',
  'á': 'a',
  'à': 'a',
  'ä': 'a',
  'ã': 'a',
  'å': 'a',
  'é': 'e',
  'è': 'e',
  'ê': 'e',
  'ë': 'e',
  'í': 'i',
  'ì': 'i',
  'î': 'i',
  'ï': 'i',
  'ó': 'o',
  'ò': 'o',
  'ô': 'o',
  'õ': 'o',
  'ú': 'u',
  'ù': 'u',
  'û': 'u',
  'ñ': 'n',
  'ý': 'y',
  'ž': 'z',
  'č': 'c',
  'š': 's',
  'ё': 'е',
  'й': 'и',
};

/// Words of a search text (folded), at least one character each.
List<String> searchTokens(String q) => foldText(q).split(' ').where((t) => t.isNotEmpty).toList();

/// Pattern for the database pre-filter (`ilike`): the longest word of the
/// query, with every letter that can be written in several ways ("e"/"ə",
/// "i"/"ı"/"İ", "s"/"ş", …) replaced by the one-character wildcard "_".
/// Characters that break a PostgREST filter are removed. Null = too short.
String? dbPattern(String q) {
  final clean = q.replaceAll(RegExp(r'[,()%*"\\:_.]'), ' ');
  final words = clean.split(RegExp(r'\s+')).where((w) => w.runes.length >= 2).toList();
  if (words.isEmpty) return null;
  words.sort((a, b) => b.runes.length.compareTo(a.runes.length));
  final w = words.first.toLowerCase();
  final b = StringBuffer();
  for (final r in w.runes) {
    final ch = String.fromCharCode(r);
    b.write(_ambiguous.contains(ch) ? '_' : ch);
  }
  return b.toString().replaceAll('̇', '');
}

const _ambiguous = {'e', 'ə', 'i', 'ı', 'o', 'ö', 'u', 'ü', 's', 'ş', 'c', 'ç', 'g', 'ğ'};

/// How well a service matches (lower = better); null = no match.
///  0 exact name · 1 name starts with the query · 2 a name word starts with
///  it · 3 name contains it · 4 found in category / speciality / city /
///  address / country. Every query word must be found somewhere.
int? serviceMatchRank({
  required String query,
  required String name,
  String? city,
  String? address,
  String? country,
  String? specialty,
  List<String> categoryNames = const [],
}) {
  final tokens = searchTokens(query);
  if (tokens.isEmpty) return null;
  final q = tokens.join(' ');
  final n = foldText(name);
  final other = foldText([specialty, city, address, country, ...categoryNames].whereType<String>().join(' '));
  final all = '$n $other';
  for (final t in tokens) {
    if (!all.contains(t)) return null;
  }
  if (n == q) return 0;
  if (n.startsWith(q)) return 1;
  if (n.split(' ').any((w) => w.startsWith(q))) return 2;
  if (n.contains(q)) return 3;
  return 4;
}

/// Straight-line distance in km (haversine).
double distanceKm(double lat1, double lng1, double lat2, double lng2) {
  const r = 6371.0;
  double rad(double d) => d * math.pi / 180;
  final dLat = rad(lat2 - lat1);
  final dLng = rad(lng2 - lng1);
  final h = math.pow(math.sin(dLat / 2), 2) + math.cos(rad(lat1)) * math.cos(rad(lat2)) * math.pow(math.sin(dLng / 2), 2);
  return 2 * r * math.asin(math.sqrt(h.toDouble()));
}

/// A real map position? 0,0 (and out-of-range values) mean "not set" —
/// such a service gets its info card but no pin on the map.
bool hasRealCoords(double? lat, double? lng) =>
    lat != null &&
    lng != null &&
    lat.isFinite &&
    lng.isFinite &&
    lat.abs() <= 90 &&
    lng.abs() <= 180 &&
    !(lat.abs() < 1e-6 && lng.abs() < 1e-6);

/// Distance from the user to a service, only when both positions are real.
double? userDistanceKm({double? userLat, double? userLng, required double lat, required double lng}) {
  if (!hasRealCoords(userLat, userLng) || !hasRealCoords(lat, lng)) return null;
  return distanceKm(userLat!, userLng!, lat, lng);
}

class RankedHit<T> {
  final T item;
  final int rank;
  final double? km;
  final String name;
  const RankedHit(this.item, this.rank, this.km, this.name);
}

/// Best match first; same match level → nearest first (unknown distance
/// last), then by name.
List<T> sortHits<T>(List<RankedHit<T>> hits) {
  final list = [...hits];
  list.sort((a, b) {
    final r = a.rank.compareTo(b.rank);
    if (r != 0) return r;
    if (a.km != null && b.km != null) {
      final d = a.km!.compareTo(b.km!);
      if (d != 0) return d;
    } else if (a.km != null) {
      return -1;
    } else if (b.km != null) {
      return 1;
    }
    return foldText(a.name).compareTo(foldText(b.name));
  });
  return [for (final h in list) h.item];
}

/// Map zoom for a place found by the address search.
double placeZoom(String? osmClass, String? osmType) {
  const street = {'house', 'building', 'residential', 'road', 'street', 'primary', 'secondary', 'tertiary', 'trunk', 'service'};
  const district = {'suburb', 'quarter', 'neighbourhood', 'village', 'hamlet', 'district', 'borough'};
  const region = {'state', 'region', 'province', 'county', 'administrative'};
  if (osmType == 'country') return 6;
  if (street.contains(osmType) || osmClass == 'highway' || osmClass == 'building') return 15;
  if (district.contains(osmType)) return 13;
  if (region.contains(osmType)) return 8;
  return 12;
}

/// A service category matches when every query word is in one of its
/// names (any language, so "tent", "тент" and "tente" all work).
bool categoryMatches(String query, Iterable<String?> names) {
  final tokens = searchTokens(query);
  if (tokens.isEmpty) return false;
  return names.whereType<String>().any((n) {
    final f = foldText(n);
    return tokens.every(f.contains);
  });
}
