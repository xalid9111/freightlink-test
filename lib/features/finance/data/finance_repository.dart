import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/supabase_config.dart';
import '../domain/finance_models.dart';

/// Finance & payments (migration 0037, Edge Functions payments-checkout /
/// payments-webhook). Every rule is enforced on the server; this class only
/// calls it.
class FinanceRepository {
  SupabaseClient get _c => SupabaseConfig.client;
  static const _timeout = Duration(seconds: 25);

  Future<bool> isFinanceAdmin() async {
    try {
      return await _c.rpc('is_finance_admin').timeout(_timeout) == true;
    } catch (_) {
      return false; // 0037 not installed yet / signed out → no finance section
    }
  }

  Future<CheckoutAvailability> checkoutAvailability() async {
    try {
      return CheckoutAvailability.fromJson(await _c.rpc('payment_checkout_available').timeout(_timeout));
    } catch (_) {
      return const CheckoutAvailability(available: false, mode: 'off');
    }
  }

  // ---- customer checkout (Edge Function) --------------------------------
  Future<Map<String, dynamic>> _checkout(Map<String, dynamic> body) async {
    try {
      final res = await _c.functions.invoke('payments-checkout', body: body).timeout(_timeout);
      return Map<String, dynamic>.from(res.data as Map);
    } on FunctionException catch (e) {
      final d = e.details;
      throw Exception(d is Map && d['error'] != null ? '${d['error']}' : 'checkout_failed_${e.status}');
    }
  }

  Future<CheckoutPayment> startCheckout({required String orderId, required PayMethod method, required String idempotencyKey}) async {
    final j = await _checkout({'action': 'create', 'order_id': orderId, 'method': method.wire, 'idempotency_key': idempotencyKey});
    return CheckoutPayment.fromJson(j['payment'] as Map);
  }

  /// Checkout for a TIR Bazarı VIP order (0044): same rules, the amount
  /// comes from the VIP order on the server.
  Future<CheckoutPayment> startVipCheckout({required String vipOrderId, required PayMethod method, required String idempotencyKey}) async {
    final j = await _checkout({'action': 'create', 'vip_order_id': vipOrderId, 'method': method.wire, 'idempotency_key': idempotencyKey});
    return CheckoutPayment.fromJson(j['payment'] as Map);
  }

  /// Checkout for a load VIP order (0062): same rules, the amount comes
  /// from the order on the server.
  Future<CheckoutPayment> startCargoVipCheckout(
      {required String vipOrderId, required PayMethod method, required String idempotencyKey}) async {
    final j = await _checkout(
        {'action': 'create', 'cargo_vip_order_id': vipOrderId, 'method': method.wire, 'idempotency_key': idempotencyKey});
    return CheckoutPayment.fromJson(j['payment'] as Map);
  }

  /// Checkout for a TIR Bazarı İrəli çək / Premium order (0066): same rules,
  /// the amount comes from the order on the server.
  Future<CheckoutPayment> startPromoCheckout(
      {required String promoOrderId, required PayMethod method, required String idempotencyKey}) async {
    final j = await _checkout(
        {'action': 'create', 'promo_order_id': promoOrderId, 'method': method.wire, 'idempotency_key': idempotencyKey});
    return CheckoutPayment.fromJson(j['payment'] as Map);
  }

  /// TEST mode only: the built-in test provider sends a signed result to
  /// the webhook; the server decides.
  Future<CheckoutPayment> completeTestPayment(String paymentId, {required bool success}) async {
    final j = await _checkout({'action': 'test_complete', 'payment_id': paymentId, 'outcome': success ? 'success' : 'fail'});
    return CheckoutPayment.fromJson(j['payment'] as Map);
  }

  Future<CheckoutPayment> paymentStatus(String paymentId) async {
    final j = await _checkout({'action': 'status', 'payment_id': paymentId});
    return CheckoutPayment.fromJson(j['payment'] as Map);
  }

  Future<void> cancelPayment(String paymentId) async {
    await _c.rpc('payment_cancel', params: {'p_payment': paymentId}).timeout(_timeout);
  }

  // ---- finance admin -------------------------------------------------------
  Future<FinanceSummary> summary(String mode) async =>
      FinanceSummary.fromJson(await _c.rpc('finance_summary', params: {'p_mode': mode}).timeout(_timeout) as Map);

  Future<List<FinancePayment>> payments({required String mode, String? status, DateTime? from, DateTime? to, String? search}) async {
    String? d(DateTime? x) => x == null ? null : '${x.year}-${x.month.toString().padLeft(2, '0')}-${x.day.toString().padLeft(2, '0')}';
    final rows = await _c.rpc('finance_payments', params: {
      'p_mode': mode,
      'p_status': status,
      'p_from': d(from),
      'p_to': d(to),
      'p_search': (search ?? '').trim().isEmpty ? null : search!.trim(),
      'p_limit': 200,
    }).timeout(_timeout);
    return [for (final r in (rows as List)) FinancePayment.fromJson(r as Map)];
  }

  Future<PaymentSettingsData> settings() async =>
      PaymentSettingsData.fromJson(await _c.rpc('finance_get_settings').timeout(_timeout) as Map);

  Future<PaymentSettingsData> saveSettings({required String mode, required double commissionPct, required List<PayMethod> methods}) async =>
      PaymentSettingsData.fromJson(await _c.rpc('finance_set_settings', params: {
        'p_mode': mode,
        'p_provider': 'test',
        'p_commission_pct': commissionPct,
        'p_methods': [for (final m in methods) m.wire],
      }).timeout(_timeout) as Map);

  Future<List<PayoutAccount>> accounts() async {
    final rows = await _c.rpc('finance_list_payout_accounts').timeout(_timeout);
    return [for (final r in (rows as List)) PayoutAccount.fromJson(r as Map)];
  }

  Future<void> addCardAccount({required String holder, String? bank, required String last4, required String brand}) async {
    await _c.rpc('finance_add_payout_account', params: {
      'p_kind': 'card',
      'p_holder': holder,
      'p_bank': bank,
      'p_card_last4': last4,
      'p_card_brand': brand,
    }).timeout(_timeout);
  }

  Future<void> addBusinessAccount({required String holder, String? bank, required String company, required String voen, required String iban}) async {
    await _c.rpc('finance_add_payout_account', params: {
      'p_kind': 'business',
      'p_holder': holder,
      'p_bank': bank,
      'p_company': company,
      'p_voen': voen,
      'p_iban': normalizeIban(iban),
    }).timeout(_timeout);
  }

  Future<void> setPrimary(String id) async => _c.rpc('finance_set_primary_payout_account', params: {'p_id': id}).timeout(_timeout);
  Future<void> disable(String id) async => _c.rpc('finance_disable_payout_account', params: {'p_id': id}).timeout(_timeout);
  Future<void> requestPayout(double amount) async => _c.rpc('finance_request_payout', params: {'p_amount': amount}).timeout(_timeout);

  Future<List<Map>> auditRecent() async {
    final rows = await _c.rpc('finance_audit_recent', params: {'p_limit': 100}).timeout(_timeout);
    return [for (final r in (rows as List)) r as Map];
  }

  /// Extra authentication: sign in again with the password. The new
  /// session carries a fresh sign-in time that the server checks.
  Future<void> reauthenticate(String email, String password) async {
    await _c.auth.signInWithPassword(email: email, password: password).timeout(_timeout);
  }
}

final financeRepositoryProvider = Provider<FinanceRepository>((ref) => FinanceRepository());
