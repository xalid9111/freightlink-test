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

  /// Tap a tile: select it, or clear it when it is already selected.
  /// Truck type and groupage exclude each other (one tile at a time).
  CargoCategoryFilter tapTruck(String code) =>
      CargoCategoryFilter(truckType: truckType == code ? null : code, size: size);
  CargoCategoryFilter tapGroupage() => CargoCategoryFilter(groupage: !groupage, size: size);
  CargoCategoryFilter tapSize(String s) =>
      CargoCategoryFilter(truckType: truckType, groupage: groupage, size: size == s ? null : s);

  /// Same rule as the server query (used when 0055 is not run yet and
  /// for the tests). A load whose size is not known matches no size.
  bool matches(CargoModel c) =>
      (truckType == null || (c.truckType ?? '').trim().toLowerCase() == truckType) &&
      (!groupage || c.groupage) &&
      (size == null || c.loadSize == size);

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
