// TIR Bazarı (migration 0040) — models and pure logic, no Flutter and no
// Supabase, unit-tested in test/market_logic_test.dart.
import 'market_catalog.dart';

/// Vehicle class. Medium (3.5–16 t) and light (Qazel, vans, up to 3.5 t)
/// trucks were added after TIR (owner, 25.10.2026, 0064); the first five
/// keep their stored names.
enum MarketCategory { truck, mediumTruck, lightTruck, trailer, semitrailer, construction, other }

extension MarketCategoryX on MarketCategory {
  String get wire => switch (this) {
        MarketCategory.mediumTruck => 'medium_truck',
        MarketCategory.lightTruck => 'light_truck',
        _ => name,
      };
  String get labelKey => 'mk_cat_$wire';
  static MarketCategory parse(String? s) =>
      MarketCategory.values.firstWhere((c) => c.wire == s, orElse: () => MarketCategory.truck);
}

/// Body / superstructure (owner, 25.10.2026, 0064) — apart from brand,
/// model and category; not required. Codes as on the Loads page.
const kMarketBodyTypes = [
  'tractor_unit', 'tent', 'ref', 'van', 'dump', 'tow_truck', 'manipulator', 'car_carrier', //
  'tanker', 'open', 'lowbed', 'container', 'chassis', 'concrete_mixer', 'special',
];

String? marketBodyType(String? s) => kMarketBodyTypes.contains(s) ? s : null;

const kMarketGearboxes = ['manual', 'automatic', 'semi'];
const kMarketFuels = ['diesel', 'petrol', 'gas', 'electric', 'hybrid'];
const kMarketMaxPhotos = 20;
const kMarketMaxDescription = 1000;

/// Ad states: draft (only the owner) → pending (waits for the admin) →
/// active (everybody) → sold; rejected / inactive are set by the admin.
enum MarketStatus { draft, pending, active, rejected, inactive, sold }

MarketStatus marketStatus(String? s) => MarketStatus.values.firstWhere((x) => x.name == s, orElse: () => MarketStatus.draft);

class MarketListing {
  final String id;
  final int listingNo;
  final String ownerId;
  final MarketStatus status;
  final MarketCategory category;
  final String? brand, model;
  /// [kMarketBodyTypes] code or null (not said / before 0064).
  final String? bodyType;
  final int? year, mileageKm, powerHp;
  final double? engineL, price;
  final String? gearbox, fuel;
  final String currency;
  final String? country, city, phone, description;
  final double? lat, lng;

  /// true: [lat]/[lng] is the place the seller marked; false: city centre
  /// (0053).
  final bool locationExact;
  final List<String> photos;
  final int views;
  final bool isVip;
  final DateTime? vipUntil;
  final String? adminNote;
  final DateTime createdAt;
  final DateTime? publishedAt, soldAt;

  const MarketListing({
    required this.id,
    required this.listingNo,
    required this.ownerId,
    required this.status,
    required this.category,
    this.brand,
    this.model,
    this.bodyType,
    this.year,
    this.mileageKm,
    this.powerHp,
    this.engineL,
    this.price,
    this.gearbox,
    this.fuel,
    this.currency = 'USD',
    this.country,
    this.city,
    this.phone,
    this.description,
    this.lat,
    this.lng,
    this.locationExact = false,
    this.photos = const [],
    this.views = 0,
    this.isVip = false,
    this.vipUntil,
    this.adminNote,
    required this.createdAt,
    this.publishedAt,
    this.soldAt,
  });

  /// VIP badge only while it is on and not expired.
  bool vipActive([DateTime? now]) => isVip && (vipUntil == null || vipUntil!.isAfter(now ?? DateTime.now()));

  /// "DAF XF 106 — 2017"
  String get title {
    final name = [brand, model].where((e) => (e ?? '').trim().isNotEmpty).map((e) => e!.trim()).join(' ');
    return year == null ? name : '$name — $year';
  }

  String? get cover => photos.isEmpty ? null : photos.first;

  static double? _d(Object? v) => v is num ? v.toDouble() : double.tryParse('${v ?? ''}');
  static int? _i(Object? v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}');
  static DateTime? _t(Object? v) => v == null ? null : DateTime.tryParse('$v')?.toLocal();

  factory MarketListing.fromJson(Map<String, dynamic> j) => MarketListing(
        id: '${j['id']}',
        listingNo: _i(j['listing_no']) ?? 0,
        ownerId: '${j['owner_id']}',
        status: marketStatus(j['status'] as String?),
        category: MarketCategoryX.parse(j['category'] as String?),
        brand: j['brand'] as String?,
        model: j['model'] as String?,
        bodyType: marketBodyType(j['body_type'] as String?),
        year: _i(j['year']),
        mileageKm: _i(j['mileage_km']),
        powerHp: _i(j['power_hp']),
        engineL: _d(j['engine_l']),
        price: _d(j['price']),
        gearbox: j['gearbox'] as String?,
        fuel: j['fuel'] as String?,
        currency: (j['currency'] as String?) ?? 'USD',
        country: j['country'] as String?,
        city: j['city'] as String?,
        phone: j['phone'] as String?,
        description: j['description'] as String?,
        lat: _d(j['lat']),
        lng: _d(j['lng']),
        locationExact: j['location_exact'] == true,
        photos: (j['photos'] is List ? j['photos'] as List : const []).map((e) => '$e').toList(),
        views: _i(j['views']) ?? 0,
        isVip: j['is_vip'] == true,
        vipUntil: _t(j['vip_until']),
        adminNote: j['admin_note'] as String?,
        createdAt: _t(j['created_at']) ?? DateTime.now(),
        publishedAt: _t(j['published_at']),
        soldAt: _t(j['sold_at']),
      );
}

/// What the owner writes (moderation / VIP / counters are server-side).
class MarketDraft {
  MarketCategory category;
  String? brand, model, gearbox, fuel, country, city, phone, description;
  String? bodyType;
  int? year, mileageKm, powerHp;
  double? engineL, price, lat, lng;
  /// The seller marked the place on the map (0053).
  bool locationExact;
  String currency;
  List<String> photos;

  MarketDraft({
    this.category = MarketCategory.truck,
    this.brand,
    this.model,
    this.bodyType,
    this.gearbox,
    this.fuel,
    this.country,
    this.city,
    this.phone,
    this.description,
    this.year,
    this.mileageKm,
    this.powerHp,
    this.engineL,
    this.price,
    this.lat,
    this.lng,
    this.locationExact = false,
    this.currency = 'USD',
    List<String>? photos,
  }) : photos = photos ?? [];

  factory MarketDraft.from(MarketListing l) => MarketDraft(
        category: l.category,
        brand: l.brand,
        model: l.model,
        bodyType: l.bodyType,
        gearbox: l.gearbox,
        fuel: l.fuel,
        country: l.country,
        city: l.city,
        phone: l.phone,
        description: l.description,
        year: l.year,
        mileageKm: l.mileageKm,
        powerHp: l.powerHp,
        engineL: l.engineL,
        price: l.price,
        lat: l.lat,
        lng: l.lng,
        locationExact: l.locationExact,
        currency: l.currency,
        photos: [...l.photos],
      );

  static String? _n(String? v) => (v == null || v.trim().isEmpty) ? null : v.trim();

  Map<String, dynamic> toJson() => {
        'category': category.wire,
        'brand': _n(brand),
        'model': _n(model),
        // Left out by the repository while 0064 is not run.
        'body_type': marketBodyType(bodyType),
        'year': year,
        'mileage_km': mileageKm,
        'engine_l': engineL,
        'power_hp': powerHp,
        'gearbox': gearbox,
        'fuel': fuel,
        'price': price,
        'currency': currency,
        'country': _n(country),
        'city': _n(city),
        'lat': lat,
        'lng': lng,
        'location_exact': locationExact && lat != null && lng != null,
        'phone': _n(phone),
        'description': _n(description),
        'photos': photos,
      };

  /// Keys of what is still missing before "Elanı dərc et" (a draft can be
  /// saved with anything).
  List<String> missingForPublish() => [
        if (_n(brand) == null) 'mk_err_brand',
        if (_n(model) == null) 'mk_err_model',
        if (year == null) 'mk_err_year',
        if (price == null || price! <= 0) 'mk_err_price',
        if (_n(city) == null) 'mk_err_city',
        if (photos.isEmpty) 'mk_err_photos',
      ];
}

/// Filters of the feed (null = any).
class MarketFilter {
  final MarketCategory? category;
  final String? q, brand, model, city;
  /// [kMarketBodyTypes] code (0064).
  final String? bodyType;
  final double? minPrice, maxPrice;
  final int? yearFrom, yearTo, maxMileage;

  const MarketFilter({
    this.category,
    this.q,
    this.brand,
    this.model,
    this.city,
    this.bodyType,
    this.minPrice,
    this.maxPrice,
    this.yearFrom,
    this.yearTo,
    this.maxMileage,
  });

  bool get hasDetails => brand != null || model != null || city != null || bodyType != null || minPrice != null ||
      maxPrice != null || yearFrom != null || yearTo != null || maxMileage != null;

  MarketFilter copyWith({
    MarketCategory? Function()? category,
    String? Function()? q,
    String? Function()? brand,
    String? Function()? model,
    String? Function()? city,
    String? Function()? bodyType,
    double? Function()? minPrice,
    double? Function()? maxPrice,
    int? Function()? yearFrom,
    int? Function()? yearTo,
    int? Function()? maxMileage,
  }) =>
      MarketFilter(
        category: category != null ? category() : this.category,
        q: q != null ? q() : this.q,
        brand: brand != null ? brand() : this.brand,
        model: model != null ? model() : this.model,
        city: city != null ? city() : this.city,
        bodyType: bodyType != null ? bodyType() : this.bodyType,
        minPrice: minPrice != null ? minPrice() : this.minPrice,
        maxPrice: maxPrice != null ? maxPrice() : this.maxPrice,
        yearFrom: yearFrom != null ? yearFrom() : this.yearFrom,
        yearTo: yearTo != null ? yearTo() : this.yearTo,
        maxMileage: maxMileage != null ? maxMileage() : this.maxMileage,
      );

  /// Parameters of market_search(). The 0064 ones (body type, every
  /// spelling of the brand / model) are added only when used, so the
  /// search keeps working before 0064 is run.
  Map<String, dynamic> toParams({int limit = 20, int offset = 0}) {
    String? n(String? v) => (v == null || v.trim().isEmpty) ? null : v.trim();
    final b = n(brand), m = n(model);
    final brands = b == null ? const <String>[] : marketBrandSpellings(b);
    final models = b == null || m == null ? const <String>[] : marketModelSpellings(b, m);
    return {
      'p_category': category?.wire,
      'p_q': n(q),
      'p_brand': b,
      'p_model': m,
      'p_city': n(city),
      'p_min_price': minPrice,
      'p_max_price': maxPrice,
      'p_year_from': yearFrom,
      'p_year_to': yearTo,
      'p_max_mileage': maxMileage,
      'p_limit': limit,
      'p_offset': offset,
      if (marketBodyType(bodyType) != null) 'p_body_type': bodyType,
      if (brands.length > 1) 'p_brands': brands,
      if (models.length > 1) 'p_models': models,
    };
  }

  @override
  bool operator ==(Object other) =>
      other is MarketFilter &&
      other.category == category &&
      other.q == q &&
      other.brand == brand &&
      other.model == model &&
      other.city == city &&
      other.bodyType == bodyType &&
      other.minPrice == minPrice &&
      other.maxPrice == maxPrice &&
      other.yearFrom == yearFrom &&
      other.yearTo == yearTo &&
      other.maxMileage == maxMileage;

  @override
  int get hashCode =>
      Object.hash(category, q, brand, model, city, bodyType, minPrice, maxPrice, yearFrom, yearTo, maxMileage);
}

/// "32 500 €" / "67 000 USD"
String marketPrice(double? v, String currency) {
  if (v == null) return '—';
  final s = v.round().toString().replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]} ');
  final sym = const {'EUR': '€', 'USD': r'$', 'AZN': '₼', 'TRY': '₺', 'RUB': '₽', 'GEL': '₾'}[currency];
  return sym == null ? '$s $currency' : (currency == 'USD' ? '$sym$s' : '$s $sym');
}

/// "420 000 km"
String marketKm(int? v) => v == null ? '—' : '${v.toString().replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]} ')} km';

/// Years offered in the form: next model year down to 1980.
List<int> marketYears([DateTime? now]) => [for (var y = (now ?? DateTime.now()).year + 1; y >= 1980; y--) y];

/// Status after "Elanı dərc et" (null = keep it): visible at once, no
/// admin approval (owner decision); an ad the admin deactivated only goes
/// back to the admin.
MarketStatus? marketPublishStatus(MarketStatus? current) => switch (current) {
      null || MarketStatus.draft || MarketStatus.pending || MarketStatus.rejected => MarketStatus.active,
      MarketStatus.inactive => MarketStatus.pending,
      MarketStatus.active || MarketStatus.sold => null,
    };

/// Moves photo [from] to position [to] (form: change the order).
List<String> movePhoto(List<String> photos, int from, int to) {
  if (from < 0 || from >= photos.length || to < 0 || to >= photos.length || from == to) return [...photos];
  final out = [...photos];
  final p = out.removeAt(from);
  out.insert(to, p);
  return out;
}

/// "3 gün əvvəl": translation key + number for the time since [t].
(String, int) marketAgo(DateTime t, [DateTime? now]) {
  final d = (now ?? DateTime.now()).difference(t);
  if (d.inMinutes < 60) return ('mk_ago_min', d.inMinutes < 1 ? 1 : d.inMinutes);
  if (d.inHours < 24) return ('mk_ago_hours', d.inHours);
  if (d.inDays < 30) return ('mk_ago_days', d.inDays);
  if (d.inDays < 365) return ('mk_ago_months', d.inDays ~/ 30);
  return ('mk_ago_years', d.inDays ~/ 365);
}

/// Price offer sent to the seller through the normal chat.
String marketOfferMessage({
  required String title,
  required int listingNo,
  required String amount,
  String? note,
  required String label,
}) {
  final n = (note ?? '').trim();
  return '$label: $title (#$listingNo) — $amount${n.isEmpty ? '' : '\n$n'}';
}

// ---- 0044: banner + paid VIP ------------------------------------------------

/// The banner at the top of TIR Bazarı, set by the admin. Empty texts /
/// no picture → the app's own default texts and background.
class MarketHero {
  final String? imageUrl, title, titleAccent, subtitle;
  const MarketHero({this.imageUrl, this.title, this.titleAccent, this.subtitle});

  static String? _s(Object? v) {
    final t = (v as String?)?.trim();
    return (t == null || t.isEmpty) ? null : t;
  }

  factory MarketHero.fromJson(Map<String, dynamic> j) => MarketHero(
        imageUrl: _s(j['image_url']),
        title: _s(j['title']),
        titleAccent: _s(j['title_accent']),
        subtitle: _s(j['subtitle']),
      );
}

/// A VIP price: [days] for [price] (admin can change it).
class MarketVipPlan {
  final int days;
  final double price;
  final String currency;
  final bool isActive;
  const MarketVipPlan({required this.days, required this.price, this.currency = 'AZN', this.isActive = true});

  factory MarketVipPlan.fromJson(Map<String, dynamic> j) => MarketVipPlan(
        days: (j['days'] as num).toInt(),
        price: (j['price'] as num).toDouble(),
        currency: (j['currency'] as String?) ?? 'AZN',
        isActive: j['is_active'] != false,
      );
}

/// "VIP et" order for one of my ads; the price is the server's.
class MarketVipOrder {
  final String id, listingId, currency, status;
  final int days;
  final double amount;
  const MarketVipOrder({
    required this.id,
    required this.listingId,
    required this.days,
    required this.amount,
    required this.currency,
    required this.status,
  });

  factory MarketVipOrder.fromJson(Map<String, dynamic> j) => MarketVipOrder(
        id: '${j['id']}',
        listingId: '${j['listing_id']}',
        days: (j['days'] as num).toInt(),
        amount: (j['amount'] as num).toDouble(),
        currency: (j['currency'] as String?) ?? 'AZN',
        status: (j['status'] as String?) ?? 'pending_payment',
      );
}

/// The two VIP columns beside the ads on a computer: 3 places left, 3
/// right, filled with the newest VIP ads in order; null = a free place.
(List<T?>, List<T?>) marketVipColumns<T>(List<T> newest, {int perSide = 3}) {
  T? at(int i) => i < newest.length ? newest[i] : null;
  return (
    [for (var i = 0; i < perSide; i++) at(i * 2)],
    [for (var i = 0; i < perSide; i++) at(i * 2 + 1)],
  );
}

/// Phone TIR Bazarı (owner, 21.10.2026): the [top] newest VIP ads stand
/// under the banner; in "Bütün elanlar" [per] more VIP ads follow every
/// [every] ads, the next ones in VIP order (newest first), starting again
/// from the newest once all were shown. VIP ads are not repeated inside
/// the plain list. Returns (top, list of (item, isVip)).
(List<T>, List<(T, bool)>) marketPhoneVipLayout<T>(List<T> vip, List<T> plain,
    {int top = 2, int every = 4, int per = 2}) {
  final head = vip.take(top).toList();
  final out = <(T, bool)>[];
  var next = top;
  final perSlot = per < vip.length ? per : vip.length;
  for (var i = 0; i < plain.length; i++) {
    out.add((plain[i], false));
    if (vip.isEmpty || (i + 1) % every != 0) continue;
    for (var k = 0; k < perSlot; k++) {
      out.add((vip[next % vip.length], true));
      next++;
    }
  }
  return (head, out);
}
