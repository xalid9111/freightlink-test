import '../../../models/cargo_model.dart';

/// Load categories on the Loads page and the load form (owner, 21.10.2026).
///
/// * Four truck types with their own picture: Tent, Ref, Konteyner,
///   Samosval (public.cargo.truck_type, codes from truck_types.dart).
/// * QRUPAJ is a load category, NOT a truck type: public.cargo.groupage
///   (0055). A groupage load is always a small load (set on the server).
/// * Big / small load: public.cargo.load_size 'big' | 'small'; null = not
///   known (older loads) — never guessed.
const kCategoryTruckTypes = ['tent', 'ref', 'container', 'dump'];

/// Truck types without a picture, shown under "Digər növlər".
const kOtherTruckTypes = ['open', 'tanker'];

/// Six more truck types (owner, 25.10.2026, 0063): Qazel, Manipulyator,
/// Evakuator, Furqon, Lowbed, Avtodaşıyıcı — after Sistern on the Loads
/// page, chips on the load form.
const kNewTruckTypes = ['gazelle', 'manipulator', 'tow_truck', 'van', 'lowbed', 'car_carrier'];

/// The choices on the Loads page, in order (owner, 21.10.2026): 'groupage'
/// is QRUPAJ, the others are truck types (Açıq and Sistern have their own
/// picture now too). The first seven never move; the new six follow.
const kCategoryChoices = [
  'tent', 'ref', 'container', 'dump', 'groupage', 'open', 'tanker', //
  ...kNewTruckTypes,
];

/// Other ways a truck type was typed under "Digər" (owner, 25.10.2026):
/// such loads show under the tile too. Nothing stored is changed.
/// [exact]: the whole text (any letter case); [part]: a piece of it.
const kTruckTypeAliases = <String, ({List<String> exact, List<String> part})>{
  'tent': (exact: ['тент'], part: []),
  'ref': (exact: ['reff', 'refrijerator', 'refrigerator', 'рефрижератор', 'реф'], part: ['soyuducu', 'reff', 'refrij', 'рефриж', 'reefer']),
  'gazelle': (exact: [], part: ['qazel', 'gazel', 'газел']),
  'manipulator': (exact: [], part: ['manipul', 'манипул']),
  'tow_truck': (exact: [], part: ['evakuator', 'evacuator', 'эвакуатор', 'tow truck']),
  'van': (exact: [], part: ['furqon', 'furgon', 'фургон']),
  'lowbed': (exact: ['трал'], part: ['lowbed', 'low bed', 'low-bed']),
  'car_carrier': (exact: [], part: ['avtovoz', 'автовоз', 'avtodaşıyıcı', 'avtodasiyici', 'car carrier']),
};

String _fold(String s) => s.trim().replaceAll('İ', 'i').replaceAll('I', 'i').toLowerCase();

/// The Loads-page truck type of a stored truck type: the code itself in
/// any letter case ("Tent" → tent), a known other spelling ("soyuducu
/// reff" → ref, "Qazel" → gazelle), or null (shown under no tile).
String? truckCategoryOf(String? stored) {
  final t = _fold(stored ?? '');
  if (t.isEmpty) return null;
  if (kCategoryChoices.contains(t) && t != 'groupage') return t;
  for (final e in kTruckTypeAliases.entries) {
    if (e.value.exact.contains(t)) return e.key;
  }
  for (final e in kTruckTypeAliases.entries) {
    if (e.value.part.any(t.contains)) return e.key;
  }
  return null;
}

/// The same rule for the server query (PostgREST `or`): the code in any
/// letter case, the exact spellings and the pieces. Written in lower case
/// and with a capital first letter, so it holds also where the database
/// does not fold non-Latin letters.
String truckTypeOrFilter(String code) {
  String cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
  final a = kTruckTypeAliases[code];
  final out = <String>{};
  for (final v in {code, ...?a?.exact}) {
    for (final w in {v, cap(v), v.toUpperCase()}) {
      out.add('truck_type.ilike."$w"');
    }
  }
  for (final v in a?.part ?? const <String>[]) {
    for (final w in {v, cap(v)}) {
      out.add('truck_type.ilike."*$w*"');
    }
  }
  return out.join(',');
}

const kLoadSizeBig = 'big';
const kLoadSizeSmall = 'small';

/// Picture of a category tile ([code] = a truck type or 'groupage'):
/// dark on the white day tile, white on the dark night tile.
String categoryIconAsset(String code, {bool night = false}) =>
    'assets/images/cargo/type_$code${night ? '_night' : ''}.png';

/// What the user picked on the Loads page: one truck type OR groupage,
/// and / or big / small. Route (from / to country) is kept separately
/// (route_filter.dart) and works together with this.
class CargoCategoryFilter {
  final String? truckType;
  final bool groupage;
  final String? size;
  const CargoCategoryFilter({this.truckType, this.groupage = false, this.size});

  bool get isActive => truckType != null || groupage || size != null;

  /// Tap a tile: select it. A second tap keeps it (owner, 25.10.2026);
  /// another tile or "Sıfırla" changes it. Truck type and groupage
  /// exclude each other (one tile at a time).
  CargoCategoryFilter tapTruck(String code) => CargoCategoryFilter(truckType: code, size: size);
  CargoCategoryFilter tapGroupage() => CargoCategoryFilter(groupage: true, size: size);
  CargoCategoryFilter tapSize(String s) =>
      CargoCategoryFilter(truckType: truckType, groupage: groupage, size: size == s ? null : s);

  /// Same rule as the server query (used when 0055 is not run yet and
  /// for the tests). A load whose size is not known matches no size.
  bool matches(CargoModel c) =>
      (truckType == null || truckCategoryOf(c.truckType) == truckType) &&
      (!groupage || c.groupage) &&
      (size == null || c.loadSize == size);

  /// What is kept on the device: the tile only (big / small is not kept).
  String get savedKey => groupage ? 'groupage' : (truckType ?? '');
  static CargoCategoryFilter fromSaved(String? key) => key == 'groupage'
      ? const CargoCategoryFilter(groupage: true)
      : (key != null && kCategoryChoices.contains(key) ? CargoCategoryFilter(truckType: key) : const CargoCategoryFilter());

  @override
  bool operator ==(Object other) =>
      other is CargoCategoryFilter && other.truckType == truckType && other.groupage == groupage && other.size == size;
  @override
  int get hashCode => Object.hash(truckType, groupage, size);
}

/// Size saved with a load: groupage is always small; otherwise what the
/// owner picked (null = not said).
String? effectiveLoadSize({required bool groupage, required String? picked}) =>
    groupage ? kLoadSizeSmall : picked;
