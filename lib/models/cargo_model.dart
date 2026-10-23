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

  /// "Ödəniş və gözləmə şərtləri" (migration 0046): amounts in [currency]
  /// for advance / cash / bank transfer; null = not offered (not shown).
  final double? payAdvance;
  final double? payCash;
  final double? payBank;

  /// Ticked payment ways without an amount (migration 0047, owner
  /// 21.10.2026): cash, payment after delivery, bank transfer.
  final bool payCashOn;
  final bool payOnDelivery;
  final bool payBankOn;

  /// "Prostoy": free waiting time in hours (24 / 36 / 48); null on loads
  /// posted before 0046.
  final int? freeWaitHours;

  /// Big / small load (migration 0055): 'big' | 'small'; null = not known
  /// (loads posted before 0055 — never guessed).
  final String? loadSize;

  /// QRUPAJ (groupage) load category (0055) — not a truck type; always
  /// a small load.
  final bool groupage;

  /// Picture on the load's card (0058): an admin template or the owner's
  /// own photo; null = none (the load type icon is shown).
  final String? imageUrl;

  /// VIP (0006 columns, given by an admin — 0059): shown in the VIP rows
  /// of the Loads page while [featuredUntil] has not passed (null = no end).
  /// Read only: never sent when a load is saved.
  final bool isFeatured;
  final DateTime? featuredUntil;

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
    this.payAdvance,
    this.payCash,
    this.payBank,
    this.payCashOn = false,
    this.payOnDelivery = false,
    this.payBankOn = false,
    this.freeWaitHours,
    this.loadSize,
    this.groupage = false,
    this.imageUrl,
    this.isFeatured = false,
    this.featuredUntil,
  });

  bool isVipAt(DateTime now) => isFeatured && (featuredUntil == null || featuredUntil!.isAfter(now));

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
        payAdvance: (j['pay_advance'] as num?)?.toDouble(),
        payCash: (j['pay_cash'] as num?)?.toDouble(),
        payBank: (j['pay_bank'] as num?)?.toDouble(),
        payCashOn: j['pay_cash_on'] == true,
        payOnDelivery: j['pay_on_delivery'] == true,
        payBankOn: j['pay_bank_on'] == true,
        freeWaitHours: (j['free_wait_hours'] as num?)?.toInt(),
        loadSize: j['load_size'] as String?,
        groupage: j['groupage'] == true,
        imageUrl: j['image_url'] as String?,
        isFeatured: j['is_featured'] == true,
        featuredUntil: j['featured_until'] == null ? null : DateTime.tryParse('${j['featured_until']}'),
      );

  /// Columns added by migration 0046 (left out if the database does not
  /// have them yet, see CargoRepositoryImpl).
  static const termsColumns = ['pay_advance', 'pay_cash', 'pay_bank', 'free_wait_hours'];

  /// Columns added by migration 0047 (left out if not run yet).
  static const choiceColumns = ['pay_cash_on', 'pay_on_delivery', 'pay_bank_on'];

  /// Columns added by migration 0055 (left out if not run yet).
  static const sizeColumns = ['load_size', 'groupage'];

  /// Column added by migration 0058 (left out if not run yet).
  static const imageColumns = ['image_url'];

  /// Cash / bank ticked; a load saved with an amount there (0046) counts
  /// as ticked.
  bool get cashTicked => payCashOn || (payCash != null && payCash! > 0);
  bool get bankTicked => payBankOn || (payBank != null && payBank! > 0);

  /// Payment ways in display order: (i18n key, amount). Only the advance
  /// has an amount; the others are just ticked (amount null).
  List<(String, double?)> get paymentTerms => [
        if (payAdvance != null && payAdvance! > 0) ('cargo_pay_advance', payAdvance!),
        if (cashTicked) ('cargo_pay_cash', null),
        if (payOnDelivery) ('cargo_pay_on_delivery', null),
        if (bankTicked) ('cargo_pay_bank', null),
      ];

  bool get hasTerms => paymentTerms.isNotEmpty || freeWaitHours != null;

  Map<String, dynamic> toInsertJson({bool withTerms = true, bool withChoices = true, bool withSize = true, bool withImage = true}) => {
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
        if (withTerms) ...{
          'pay_advance': payAdvance,
          'pay_cash': payCash,
          'pay_bank': payBank,
          'free_wait_hours': freeWaitHours,
          if (withChoices) ...{
            'pay_cash_on': payCashOn,
            'pay_on_delivery': payOnDelivery,
            'pay_bank_on': payBankOn,
          },
        },
        if (withSize) ...{
          'load_size': loadSize,
          'groupage': groupage,
        },
        if (withImage) 'image_url': imageUrl,
      };
}

/// Free waiting time choices (hours); 48 is preselected on a new load.
const kFreeWaitChoices = [24, 36, 48];
const kDefaultFreeWaitHours = 48;

/// Payment amount typed by the load owner: empty → null (not offered);
/// otherwise a positive number (comma or dot), else [FormatException].
double? parsePaymentAmount(String? text) {
  final t = (text ?? '').trim().replaceAll(' ', '').replaceAll(',', '.');
  if (t.isEmpty) return null;
  final v = double.tryParse(t);
  if (v == null || !v.isFinite || v <= 0 || v >= 1e10) throw const FormatException('amount');
  return v;
}
