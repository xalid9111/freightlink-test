/// Maps 1:1 onto public.cargo (supabase/migrations/0001_schema.sql).
///
/// Field names were revised in Phase 2 to match the client's exact
/// spec (weight_kg not weight_tons, pickup_country/city/address/lat/lng
/// instead of a locations FK, etc.) — see docs/reports/PHASE2_REPORT.md item 2.
class CargoModel {
  final String id;
  final String ownerId;
  final String? companyId;

  final String pickupCountry;
  final String pickupCity;
  final String? pickupAddress;
  final double? pickupLatitude;
  final double? pickupLongitude;

  final String destinationCountry;
  final String destinationCity;
  final String? destinationAddress;
  final double? destinationLatitude;
  final double? destinationLongitude;

  final String? cargoType;
  final double weightKg;
  final double? volumeM3;
  final int? palletCount;

  final String? truckType;

  final DateTime pickupDate;
  final DateTime? deliveryDeadline;

  final double offeredPrice;
  final String currency;

  final String? description;
  final double? distanceKm;

  /// One of: new, carrier_found, agreed, loading, in_transit, delivered,
  /// completed, cancelled — kept in English in the database; the UI
  /// layer maps this to a localized label via assets/i18n/*.json.
  final String status;

  final bool isDemo;

  /// Hidden by an admin (migration 0012). Hidden loads never appear in
  /// the marketplace; the owner still sees them in "My loads".
  final bool isHidden;

  const CargoModel({
    required this.id,
    required this.ownerId,
    this.companyId,
    required this.pickupCountry,
    required this.pickupCity,
    this.pickupAddress,
    this.pickupLatitude,
    this.pickupLongitude,
    required this.destinationCountry,
    required this.destinationCity,
    this.destinationAddress,
    this.destinationLatitude,
    this.destinationLongitude,
    this.cargoType,
    required this.weightKg,
    this.volumeM3,
    this.palletCount,
    this.truckType,
    required this.pickupDate,
    this.deliveryDeadline,
    required this.offeredPrice,
    this.currency = 'USD',
    this.description,
    this.distanceKm,
    this.status = 'new',
    this.isDemo = false,
    this.isHidden = false,
  });

  factory CargoModel.fromJson(Map<String, dynamic> j) => CargoModel(
        id: j['id'] as String,
        ownerId: j['owner_id'] as String,
        companyId: j['company_id'] as String?,
        pickupCountry: j['pickup_country'] as String,
        pickupCity: j['pickup_city'] as String,
        pickupAddress: j['pickup_address'] as String?,
        pickupLatitude: (j['pickup_latitude'] as num?)?.toDouble(),
        pickupLongitude: (j['pickup_longitude'] as num?)?.toDouble(),
        destinationCountry: j['destination_country'] as String,
        destinationCity: j['destination_city'] as String,
        destinationAddress: j['destination_address'] as String?,
        destinationLatitude: (j['destination_latitude'] as num?)?.toDouble(),
        destinationLongitude: (j['destination_longitude'] as num?)?.toDouble(),
        cargoType: j['cargo_type'] as String?,
        weightKg: (j['weight_kg'] as num).toDouble(),
        volumeM3: (j['volume_m3'] as num?)?.toDouble(),
        palletCount: j['pallet_count'] as int?,
        truckType: j['truck_type'] as String?,
        pickupDate: DateTime.parse(j['pickup_date'] as String),
        deliveryDeadline: j['delivery_deadline'] != null
            ? DateTime.parse(j['delivery_deadline'] as String)
            : null,
        offeredPrice: (j['offered_price'] as num).toDouble(),
        currency: j['currency'] as String? ?? 'USD',
        description: j['description'] as String?,
        distanceKm: (j['distance_km'] as num?)?.toDouble(),
        status: j['status'] as String? ?? 'new',
        isDemo: j['is_demo'] as bool? ?? false,
        isHidden: j['is_hidden'] == true,
      );

  Map<String, dynamic> toInsertJson() => {
        'owner_id': ownerId,
        'company_id': companyId,
        'pickup_country': pickupCountry,
        'pickup_city': pickupCity,
        'pickup_address': pickupAddress,
        'pickup_latitude': pickupLatitude,
        'pickup_longitude': pickupLongitude,
        'destination_country': destinationCountry,
        'destination_city': destinationCity,
        'destination_address': destinationAddress,
        'destination_latitude': destinationLatitude,
        'destination_longitude': destinationLongitude,
        'cargo_type': cargoType,
        'weight_kg': weightKg,
        'volume_m3': volumeM3,
        'pallet_count': palletCount,
        'truck_type': truckType,
        'pickup_date': pickupDate.toIso8601String().split('T').first,
        'delivery_deadline': deliveryDeadline?.toIso8601String().split('T').first,
        'offered_price': offeredPrice,
        'currency': currency,
        'description': description,
        'distance_km': distanceKm,
        'status': status,
      };
}
