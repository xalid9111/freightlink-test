/// Services module (migration 0017): mechanics, service centres, tow trucks.

class ServiceCategory {
  final String id;
  final Map<String, String?> names; // az / tr / en / ru / ka
  final String icon;
  final int sortOrder;
  final bool isActive;

  const ServiceCategory({required this.id, required this.names, required this.icon, required this.sortOrder, required this.isActive});

  factory ServiceCategory.fromJson(Map<String, dynamic> j) => ServiceCategory(
        id: j['id'] as String,
        names: {
          'az': j['name_az'] as String?,
          'tr': j['name_tr'] as String?,
          'en': j['name_en'] as String?,
          'ru': j['name_ru'] as String?,
          'ka': j['name_ka'] as String?,
        },
        icon: (j['icon'] as String?) ?? 'build',
        sortOrder: (j['sort_order'] as num?)?.toInt() ?? 100,
        isActive: j['is_active'] != false,
      );

  /// Name in [lang]; falls back to English, then Azerbaijani, then the id.
  String name(String lang) {
    String? ok(String? v) => (v == null || v.trim().isEmpty) ? null : v;
    return ok(names[lang]) ?? ok(names['en']) ?? ok(names['az']) ?? id;
  }
}

/// How a provider is drawn on the map.
enum ServiceMarkerType { mobile, center, tow }

class ServiceProvider {
  final String id;
  final String? ownerId;
  final String kind; // individual | center
  final String name;
  final String? specialty;
  final String? description;
  final List<String> categories;
  final String? country;
  final String? city;
  final String? address;
  final double lat;
  final double lng;
  final bool isMobile;
  final int? serviceRadiusKm;
  final String? phone;
  final String? whatsapp;
  final String? workingHours;
  final bool is24h;
  final bool isActive;
  final String status; // pending | approved | rejected | suspended
  final bool isVerified;
  /// PRO service (admin-set, 0028): gold badge, listed first. A label,
  /// not a rating — stars come only from real reviews.
  final bool isPro;
  final bool addedByAdmin;
  final String? adminNote;
  final List<String> photos;
  final double ratingAvg;
  final int ratingCount;
  final DateTime? createdAt;
  /// Straight-line distance from the search point (nearby_services only).
  final double? distanceKm;

  const ServiceProvider({
    required this.id,
    required this.ownerId,
    required this.kind,
    required this.name,
    this.specialty,
    this.description,
    required this.categories,
    this.country,
    this.city,
    this.address,
    required this.lat,
    required this.lng,
    required this.isMobile,
    this.serviceRadiusKm,
    this.phone,
    this.whatsapp,
    this.workingHours,
    required this.is24h,
    required this.isActive,
    required this.status,
    required this.isVerified,
    this.isPro = false,
    required this.addedByAdmin,
    this.adminNote,
    required this.photos,
    required this.ratingAvg,
    required this.ratingCount,
    this.createdAt,
    this.distanceKm,
  });

  static List<String> _list(dynamic v) => v is List ? v.map((e) => e.toString()).toList() : const [];

  factory ServiceProvider.fromJson(Map<String, dynamic> j) => ServiceProvider(
        id: j['id'] as String,
        ownerId: j['owner_id'] as String?,
        kind: (j['kind'] as String?) ?? 'individual',
        name: (j['name'] as String?) ?? '',
        specialty: j['specialty'] as String?,
        description: j['description'] as String?,
        categories: _list(j['categories']),
        country: j['country'] as String?,
        city: j['city'] as String?,
        address: j['address'] as String?,
        lat: (j['lat'] as num).toDouble(),
        lng: (j['lng'] as num).toDouble(),
        isMobile: j['is_mobile'] == true,
        serviceRadiusKm: (j['service_radius_km'] as num?)?.toInt(),
        phone: j['phone'] as String?,
        whatsapp: j['whatsapp'] as String?,
        workingHours: j['working_hours'] as String?,
        is24h: j['is_24h'] == true,
        isActive: j['is_active'] != false,
        status: (j['status'] as String?) ?? 'pending',
        isVerified: j['is_verified'] == true,
        isPro: j['is_pro'] == true,
        addedByAdmin: j['added_by_admin'] == true,
        adminNote: j['admin_note'] as String?,
        photos: _list(j['photos']),
        ratingAvg: (j['rating_avg'] as num?)?.toDouble() ?? 0,
        ratingCount: (j['rating_count'] as num?)?.toInt() ?? 0,
        createdAt: DateTime.tryParse('${j['created_at'] ?? ''}'),
        distanceKm: (j['distance_km'] as num?)?.toDouble(),
      );

  bool get isCenter => kind == 'center';
  bool get isTow => categories.contains('tow');
  bool get isVisible => status == 'pending' || status == 'approved';
  bool get isUnclaimed => ownerId == null;

  ServiceMarkerType get markerType {
    if (isTow) return ServiceMarkerType.tow;
    return isCenter ? ServiceMarkerType.center : ServiceMarkerType.mobile;
  }

  /// Fields the owner may write (the database ignores moderation fields).
  Map<String, dynamic> toWriteJson() => {
        'kind': kind,
        'name': name.trim(),
        'specialty': _n(specialty),
        'description': _n(description),
        'categories': categories,
        'country': _n(country),
        'city': _n(city),
        'address': _n(address),
        'lat': double.parse(lat.toStringAsFixed(6)),
        'lng': double.parse(lng.toStringAsFixed(6)),
        'is_mobile': isMobile,
        'service_radius_km': serviceRadiusKm,
        'phone': _n(phone),
        'whatsapp': _n(whatsapp),
        'working_hours': _n(workingHours),
        'is_24h': is24h,
        'is_active': isActive,
        'photos': photos,
      };

  static String? _n(String? v) => (v == null || v.trim().isEmpty) ? null : v.trim();

  /// [distanceKm]: pass `() => km` to replace the distance (null = unknown).
  ServiceProvider copyWith({List<String>? photos, bool? isActive, double? Function()? distanceKm}) => ServiceProvider(
        id: id,
        ownerId: ownerId,
        kind: kind,
        name: name,
        specialty: specialty,
        description: description,
        categories: categories,
        country: country,
        city: city,
        address: address,
        lat: lat,
        lng: lng,
        isMobile: isMobile,
        serviceRadiusKm: serviceRadiusKm,
        phone: phone,
        whatsapp: whatsapp,
        workingHours: workingHours,
        is24h: is24h,
        isActive: isActive ?? this.isActive,
        status: status,
        isVerified: isVerified,
        isPro: isPro,
        addedByAdmin: addedByAdmin,
        adminNote: adminNote,
        photos: photos ?? this.photos,
        ratingAvg: ratingAvg,
        ratingCount: ratingCount,
        createdAt: createdAt,
        distanceKm: distanceKm != null ? distanceKm() : this.distanceKm,
      );
}

class ServiceReview {
  final String id;
  final String providerId;
  final String userId;
  final int rating;
  final String? comment;
  final DateTime createdAt;

  const ServiceReview({required this.id, required this.providerId, required this.userId, required this.rating, this.comment, required this.createdAt});

  factory ServiceReview.fromJson(Map<String, dynamic> j) => ServiceReview(
        id: j['id'] as String,
        providerId: j['provider_id'] as String,
        userId: j['user_id'] as String,
        rating: (j['rating'] as num).toInt(),
        comment: j['comment'] as String?,
        createdAt: DateTime.tryParse('${j['created_at']}') ?? DateTime.now(),
      );
}

class ServiceClaim {
  final String id;
  final String providerId;
  final String userId;
  final String? message;
  final String? phone;
  final String status; // pending | approved | rejected
  final String? adminNote;
  final DateTime createdAt;

  const ServiceClaim({
    required this.id,
    required this.providerId,
    required this.userId,
    this.message,
    this.phone,
    required this.status,
    this.adminNote,
    required this.createdAt,
  });

  factory ServiceClaim.fromJson(Map<String, dynamic> j) => ServiceClaim(
        id: j['id'] as String,
        providerId: j['provider_id'] as String,
        userId: j['user_id'] as String,
        message: j['message'] as String?,
        phone: j['phone'] as String?,
        status: (j['status'] as String?) ?? 'pending',
        adminNote: j['admin_note'] as String?,
        createdAt: DateTime.tryParse('${j['created_at']}') ?? DateTime.now(),
      );
}
