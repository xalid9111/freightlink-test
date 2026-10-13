/// Maps 1:1 onto public.offers.
class OfferModel {
  final String id;
  final String cargoId;
  final String carrierId;
  final String? truckId;
  final double offeredPrice;
  final String currency;
  final String? message;
  final String status; // pending | accepted | rejected | countered | cancelled | expired

  const OfferModel({
    required this.id,
    required this.cargoId,
    required this.carrierId,
    this.truckId,
    required this.offeredPrice,
    this.currency = 'USD',
    this.message,
    this.status = 'pending',
  });

  factory OfferModel.fromJson(Map<String, dynamic> j) => OfferModel(
        id: j['id'] as String,
        cargoId: j['cargo_id'] as String,
        carrierId: j['carrier_id'] as String,
        truckId: j['truck_id'] as String?,
        offeredPrice: (j['offered_price'] as num).toDouble(),
        currency: j['currency'] as String? ?? 'USD',
        message: j['message'] as String?,
        status: j['status'] as String? ?? 'pending',
      );

  Map<String, dynamic> toInsertJson() => {
        'cargo_id': cargoId,
        'carrier_id': carrierId,
        'truck_id': truckId,
        'offered_price': offeredPrice,
        'currency': currency,
        'message': message,
      };
}
