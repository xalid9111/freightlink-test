/// Maps 1:1 onto public.shipments.
class ShipmentModel {
  final String id;
  final String cargoId;
  final String carrierId;
  final String? driverId;
  final String? truckId;
  final String? acceptedOfferId;
  final double agreedPrice;
  final String currency;
  final DateTime? pickupTime;
  final DateTime? deliveryDeadline;
  final DateTime? deliveredAt;
  final String status; // new..completed|cancelled, see migration 0001

  const ShipmentModel({
    required this.id,
    required this.cargoId,
    required this.carrierId,
    this.driverId,
    this.truckId,
    this.acceptedOfferId,
    required this.agreedPrice,
    this.currency = 'USD',
    this.pickupTime,
    this.deliveryDeadline,
    this.deliveredAt,
    this.status = 'new',
  });

  factory ShipmentModel.fromJson(Map<String, dynamic> j) => ShipmentModel(
        id: j['id'] as String,
        cargoId: j['cargo_id'] as String,
        carrierId: j['carrier_id'] as String,
        driverId: j['driver_id'] as String?,
        truckId: j['truck_id'] as String?,
        acceptedOfferId: j['accepted_offer_id'] as String?,
        agreedPrice: (j['agreed_price'] as num).toDouble(),
        currency: j['currency'] as String? ?? 'USD',
        pickupTime: j['pickup_time'] != null ? DateTime.parse(j['pickup_time']) : null,
        deliveryDeadline:
            j['delivery_deadline'] != null ? DateTime.parse(j['delivery_deadline']) : null,
        deliveredAt: j['delivered_at'] != null ? DateTime.parse(j['delivered_at']) : null,
        status: j['status'] as String? ?? 'new',
      );
}
