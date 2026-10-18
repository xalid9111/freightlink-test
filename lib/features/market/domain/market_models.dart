// TIR Bazarı (migration 0040) — models and pure logic, no Flutter and no
// Supabase, unit-tested in test/market_logic_test.dart.

enum MarketCategory { truck, trailer, semitrailer, construction, other }

extension MarketCategoryX on MarketCategory {
  String get wire => name;
  String get labelKey => 'mk_cat_$name';
  static MarketCategory parse(String? s) =>
      MarketCategory.values.firstWhere((c) => c.name == s, orElse: () => MarketCategory.truck);
}

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
  final int? year, mileageKm, powerHp;
  final double? engineL, price;
  final String? gearbox, fuel;
  final String currency;
  final String? country, city, phone, description;
  final double? lat, lng;
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
  int? year, mileageKm, powerHp;
  double? engineL, price, lat, lng;
  String currency;
  List<String> photos;

  MarketDraft({
    this.category = MarketCategory.truck,
    this.brand,
    this.model,
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
    this.currency = 'USD',
    List<String>? photos,
  }) : photos = photos ?? [];

  factory MarketDraft.from(MarketListing l) => MarketDraft(
        category: l.category,
        brand: l.brand,
        model: l.model,
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
        currency: l.currency,
        photos: [...l.photos],
      );

  static String? _n(String? v) => (v == null || v.trim().isEmpty) ? null : v.trim();

  Map<String, dynamic> toJson() => {
        'category': category.wire,
        'brand': _n(brand),
        'model': _n(model),
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
  final double? minPrice, maxPrice;
  final int? yearFrom, yearTo, maxMileage;

  const MarketFilter({
    this.category,
    this.q,
    this.brand,
    this.model,
    this.city,
    this.minPrice,
    this.maxPrice,
    this.yearFrom,
    this.yearTo,
    this.maxMileage,
  });

  bool get hasDetails => brand != null || model != null || city != null || minPrice != null || maxPrice != null ||
      yearFrom != null || yearTo != null || maxMileage != null;

  MarketFilter copyWith({
    MarketCategory? Function()? category,
    String? Function()? q,
    String? Function()? brand,
    String? Function()? model,
    String? Function()? city,
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
        minPrice: minPrice != null ? minPrice() : this.minPrice,
        maxPrice: maxPrice != null ? maxPrice() : this.maxPrice,
        yearFrom: yearFrom != null ? yearFrom() : this.yearFrom,
        yearTo: yearTo != null ? yearTo() : this.yearTo,
        maxMileage: maxMileage != null ? maxMileage() : this.maxMileage,
      );

  /// Parameters of market_search().
  Map<String, dynamic> toParams({int limit = 20, int offset = 0}) {
    String? n(String? v) => (v == null || v.trim().isEmpty) ? null : v.trim();
    return {
      'p_category': category?.wire,
      'p_q': n(q),
      'p_brand': n(brand),
      'p_model': n(model),
      'p_city': n(city),
      'p_min_price': minPrice,
      'p_max_price': maxPrice,
      'p_year_from': yearFrom,
      'p_year_to': yearTo,
      'p_max_mileage': maxMileage,
      'p_limit': limit,
      'p_offset': offset,
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
      other.minPrice == minPrice &&
      other.maxPrice == maxPrice &&
      other.yearFrom == yearFrom &&
      other.yearTo == yearTo &&
      other.maxMileage == maxMileage;

  @override
  int get hashCode => Object.hash(category, q, brand, model, city, minPrice, maxPrice, yearFrom, yearTo, maxMileage);
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
