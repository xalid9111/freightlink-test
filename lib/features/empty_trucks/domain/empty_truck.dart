import '../../../core/constants/cities.dart';
import '../../../core/constants/countries.dart';
import '../../cargo/domain/cargo_categories.dart';
import '../../cargo/presentation/providers/route_filter.dart';

/// "Daşıyıcılar" — an empty truck ad (owner, 13.11.2026, SQL 0118): where
/// the truck stands now, where it is going (or any direction), the truck,
/// free tonnes, from when, and the contact. Its own kind (empty_truck_ads),
/// never mixed with loads.
class EmptyTruck {
  final String id;
  final String ownerId;
  final String fromCity, fromCountry;
  final String? fromCode;
  final double? fromLat, fromLng;
  final bool anyDirection;
  final String? toCity, toCountry, toCode;
  final String truckType;
  final double freeTons;
  final List<String> bodyTypes;

  /// null = free now.
  final DateTime? availableFrom;
  final String? phone, whatsapp, note;

  /// 'active' | 'paused' | 'filled' (Maşın doldu).
  final String status;
  final DateTime createdAt;

  const EmptyTruck({
    required this.id,
    required this.ownerId,
    required this.fromCity,
    required this.fromCountry,
    this.fromCode,
    this.fromLat,
    this.fromLng,
    this.anyDirection = false,
    this.toCity,
    this.toCountry,
    this.toCode,
    required this.truckType,
    required this.freeTons,
    this.bodyTypes = const [],
    this.availableFrom,
    this.phone,
    this.whatsapp,
    this.note,
    this.status = 'active',
    required this.createdAt,
  });

  factory EmptyTruck.fromJson(Map<String, dynamic> j) => EmptyTruck(
        id: j['id'] as String,
        ownerId: j['owner_id'] as String,
        fromCity: (j['from_city'] as String?) ?? '',
        fromCountry: (j['from_country'] as String?) ?? '',
        fromCode: j['from_code'] as String?,
        fromLat: (j['from_lat'] as num?)?.toDouble(),
        fromLng: (j['from_lng'] as num?)?.toDouble(),
        anyDirection: j['any_direction'] == true,
        toCity: j['to_city'] as String?,
        toCountry: j['to_country'] as String?,
        toCode: j['to_code'] as String?,
        truckType: (j['truck_type'] as String?) ?? '',
        freeTons: (j['free_tons'] as num?)?.toDouble() ?? 0,
        bodyTypes: [for (final b in (j['body_types'] as List? ?? const [])) '$b'],
        availableFrom: DateTime.tryParse('${j['available_from'] ?? ''}')?.toLocal(),
        phone: j['phone'] as String?,
        whatsapp: j['whatsapp'] as String?,
        note: j['note'] as String?,
        status: (j['status'] as String?) ?? 'active',
        createdAt: DateTime.tryParse('${j['created_at'] ?? ''}')?.toLocal() ?? DateTime.now(),
      );

  bool get isActive => status == 'active';
  bool get isFilled => status == 'filled';

  /// Free now: no time given, or the time has come.
  bool freeNow(DateTime now) => availableFrom == null || !availableFrom!.isAfter(now);

  String? get fromIso => fromCode ?? Countries.find(fromCountry)?.code;
  String? get toIso => toCode ?? (toCountry == null ? null : Countries.find(toCountry)?.code);

  /// "Bakı, Azərbaycan" — the truck's place now.
  String placeLabel(String lang) {
    final country = Countries.find(fromIso ?? fromCountry)?.name(lang) ?? fromCountry;
    return '${Cities.label(fromCity, lang)}, $country';
  }

  /// "🇦🇿 Bakı → 🇹🇷 İstanbul", or "🇦🇿 Bakı → [anyLabel]".
  String routeLabel(String lang, {required String anyLabel}) {
    String flag(String? code) => code == null ? '' : '${Countries.find(code)?.flag ?? ''} ';
    final from = '${flag(fromIso)}${Cities.label(fromCity, lang)}';
    if (anyDirection || toCity == null) return '$from → $anyLabel';
    return '$from → ${flag(toIso)}${Cities.label(toCity!, lang)}';
  }

  /// The Loads page's filters, in the Daşıyıcılar section: the route
  /// search (from = where the truck is, to = where it goes; a truck going
  /// "any direction" fits every destination) and the load-type tile (the
  /// truck's type; QRUPAJ = trucks that take groupage).
  bool matchesRoute(RouteFilter f) {
    bool side(String? code, String? city, String? iso, String? cityHere) =>
        (code == null || iso == code) && (city == null || (cityHere != null && RouteFilter.cityKey(cityHere) == RouteFilter.cityKey(city)));
    if (!side(f.from, f.fromCity, fromIso, fromCity)) return false;
    if (f.to == null) return true;
    if (anyDirection) return true;
    return side(f.to, f.toCity, toIso, toCity);
  }

  bool matchesCategory(CargoCategoryFilter c) {
    if (c.groupage) return bodyTypes.contains('groupage');
    if (c.truckType != null) return truckCategoryOf(truckType) == c.truckType;
    return true;
  }
}

/// Kinds of load a truck takes (the form's chips; "groupage" = QRUPAJ).
const kEmptyTruckBodyTypes = ['groupage', 'pallets', 'bulk', 'liquid', 'cooled', 'oversize', 'containers', 'cars'];

/// The form's checks, also used by the tests (null = fine, else an i18n key).
String? emptyTruckFormError({
  required String fromCity,
  required String fromCountry,
  required bool anyDirection,
  String? toCity,
  String? toCountry,
  required String? truckType,
  required double? freeTons,
  DateTime? availableFrom,
  required DateTime now,
}) {
  if (fromCity.trim().isEmpty || fromCountry.trim().isEmpty) return 'et_err_from';
  if (!anyDirection && ((toCity ?? '').trim().isEmpty || (toCountry ?? '').trim().isEmpty)) return 'et_err_to';
  if ((truckType ?? '').trim().isEmpty) return 'et_err_truck';
  if (freeTons == null || freeTons <= 0 || freeTons > 100) return 'et_err_tons';
  if (availableFrom != null && availableFrom.isBefore(now.subtract(const Duration(days: 1)))) return 'et_err_time';
  return null;
}
