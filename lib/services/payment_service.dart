/// Provider-agnostic payment contract (per brief: mock first,
/// Stripe / local AZ providers / bank gateway later, without
/// touching call sites in the shipment feature).
abstract class PaymentService {
  Future<String> deposit({required String shipmentId, required double amount});
  Future<void> release({required String paymentId});
  Future<void> refund({required String paymentId});
}

/// Phase 15 implementation: simulates escrow-like state transitions
/// in the `payments` table without calling any real payment provider.
class MockPaymentService implements PaymentService {
  @override
  Future<String> deposit({required String shipmentId, required double amount}) {
    throw UnimplementedError('Implemented in Phase 15 — Payment architecture.');
  }

  @override
  Future<void> release({required String paymentId}) {
    throw UnimplementedError('Implemented in Phase 15 — Payment architecture.');
  }

  @override
  Future<void> refund({required String paymentId}) {
    throw UnimplementedError('Implemented in Phase 15 — Payment architecture.');
  }
}
