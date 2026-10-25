/// A user makes his own load VIP (owner, 24.10.2026, migration 0062): the
/// same prices and card checkout as TIR Bazarı. The server sets the price
/// and makes the load VIP only after a verified payment.
class CargoVipPlan {
  final int days;
  final double price;
  final String currency;
  final bool isActive;
  const CargoVipPlan({required this.days, required this.price, this.currency = 'AZN', this.isActive = true});

  factory CargoVipPlan.fromJson(Map<String, dynamic> j) => CargoVipPlan(
        days: (j['days'] as num).toInt(),
        price: (j['price'] as num).toDouble(),
        currency: (j['currency'] as String?) ?? 'AZN',
        isActive: j['is_active'] != false,
      );
}

class CargoVipOrder {
  final String id, cargoId, currency, status;
  final int days;
  final double amount;
  const CargoVipOrder(
      {required this.id, required this.cargoId, required this.days, required this.amount, required this.currency, required this.status});

  factory CargoVipOrder.fromJson(Map<String, dynamic> j) => CargoVipOrder(
        id: '${j['id']}',
        cargoId: '${j['cargo_id']}',
        days: (j['days'] as num).toInt(),
        amount: (j['amount'] as num).toDouble(),
        currency: (j['currency'] as String?) ?? 'AZN',
        status: (j['status'] as String?) ?? 'pending_payment',
      );
}

/// An İrəli çək / Premium order for a load (0067); the price is the
/// server's.
class CargoPromoOrder {
  final String id, cargoId, kind, currency, status;
  final int qty;
  final double amount;
  const CargoPromoOrder(
      {required this.id,
      required this.cargoId,
      required this.kind,
      required this.qty,
      required this.amount,
      required this.currency,
      required this.status});

  factory CargoPromoOrder.fromJson(Map<String, dynamic> j) => CargoPromoOrder(
        id: '${j['id']}',
        cargoId: '${j['cargo_id']}',
        kind: (j['kind'] as String?) ?? 'bump',
        qty: (j['qty'] as num).toInt(),
        amount: (j['amount'] as num).toDouble(),
        currency: (j['currency'] as String?) ?? 'AZN',
        status: (j['status'] as String?) ?? 'pending_payment',
      );
}
