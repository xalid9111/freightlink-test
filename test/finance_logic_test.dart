// Finance & payments (0037): pure logic + the checkout sheet (double tap →
// one payment, server decides). The server rules themselves are tested in
// supabase/tests/local/75_finance.sql and the Edge Functions in
// supabase/functions/_shared/payments_test.ts.
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freightlink/core/localization/app_strings.dart';
import 'package:freightlink/features/finance/data/finance_repository.dart';
import 'package:freightlink/features/finance/domain/finance_models.dart';
import 'package:freightlink/features/finance/presentation/card_checkout.dart';
import 'package:freightlink/models/ad_models.dart';

class _FakeRepo extends FinanceRepository {
  final List<String> keys = [];
  int completes = 0;
  bool slow = true;

  @override
  Future<CheckoutPayment> startCheckout({required String orderId, required PayMethod method, required String idempotencyKey}) async {
    keys.add(idempotencyKey);
    if (slow) await Future<void>.delayed(const Duration(milliseconds: 300));
    return CheckoutPayment(id: 'p1', orderId: orderId, amount: 20, currency: 'AZN', status: 'pending', mode: 'test');
  }

  @override
  Future<CheckoutPayment> completeTestPayment(String paymentId, {required bool success}) async {
    completes++;
    return CheckoutPayment(id: paymentId, orderId: 'o1', amount: 20, currency: 'AZN', status: success ? 'succeeded' : 'failed', mode: 'test');
  }

  @override
  Future<void> cancelPayment(String paymentId) async {}
}

AdOrder _order() => AdOrder(
      id: 'o1',
      advertiserId: 'u1',
      packageId: 'd5',
      packageName: '5 gün',
      days: 5,
      price: 20,
      currency: 'AZN',
      paymentStatus: 'unpaid',
      status: 'pending_payment',
      createdAt: DateTime(2026, 10, 14),
    );

void main() {
  group('payment methods by device', () {
    const all = [PayMethod.card, PayMethod.applePay, PayMethod.googlePay];
    test('iPhone / Mac → Apple Pay + card', () => expect(methodsForDevice(DeviceKind.apple, all), [PayMethod.applePay, PayMethod.card]));
    test('Android → Google Pay + card', () => expect(methodsForDevice(DeviceKind.android, all), [PayMethod.googlePay, PayMethod.card]));
    test('computer → Google Pay (Chrome) + card', () => expect(methodsForDevice(DeviceKind.desktop, all), [PayMethod.googlePay, PayMethod.card]));
    test('only what the admin enabled', () {
      expect(methodsForDevice(DeviceKind.apple, const [PayMethod.card]), [PayMethod.card]);
      expect(methodsForDevice(DeviceKind.android, const [PayMethod.applePay]), isEmpty);
    });
  });

  test('idempotency key: format the server accepts, random', () {
    final a = newIdempotencyKey(), b = newIdempotencyKey(Random(1));
    expect(RegExp(r'^[A-Za-z0-9_-]{8,80}$').hasMatch(a), isTrue);
    expect(a, isNot(b));
  });

  test('money', () {
    expect(money(1234567.5), '1 234 567.50 AZN');
    expect(money(20, 'USD'), '20.00 USD');
  });

  group('payout account validation (same as the database)', () {
    test('VÖEN 10 digits', () {
      expect(isValidVoen('1234567890'), isTrue);
      expect(isValidVoen('12345'), isFalse);
      expect(isValidVoen('12345678901'), isFalse);
    });
    test('AZ IBAN incl. checksum, spaces allowed', () {
      expect(isValidAzIban('AZ21NABZ00000000137010001944'), isTrue);
      expect(isValidAzIban('az21 nabz 0000 0000 1370 1000 1944'), isTrue);
      expect(isValidAzIban('AZ22NABZ00000000137010001944'), isFalse, reason: 'wrong check digits');
      expect(isValidAzIban('DE89370400440532013000'), isFalse);
    });
    test('card: only the last 4 digits, never a full number', () {
      expect(isValidLast4('1234'), isTrue);
      expect(isValidLast4('4111111111111111'), isFalse);
      expect(isValidLast4('12a4'), isFalse);
    });
  });

  test('parsing server replies', () {
    final s = FinanceSummary.fromJson({'mode': 'test', 'gross': 20, 'commission': '0.50', 'confirmed_balance': 19.5, 'pending_count': 2});
    expect(s.gross, 20);
    expect(s.commission, 0.5);
    expect(s.pendingCount, 2);
    final a = CheckoutAvailability.fromJson({'available': true, 'mode': 'test', 'methods': ['card', 'bitcoin', 'apple_pay']});
    expect(a.methods, [PayMethod.card, PayMethod.applePay]);
    expect(CheckoutAvailability.fromJson(null).available, isFalse);
    final acc = PayoutAccount.fromJson({'id': 'x', 'kind': 'card', 'holder_name': 'A', 'card_last4': '1234', 'card_brand': 'visa', 'status': 'pending_verification', 'is_primary': true});
    expect(acc.title, 'Visa •••• 1234');
    expect(acc.isVerified, isFalse);
  });

  test('error texts', () {
    expect(financeErrorText(Exception('PostgrestException(message: reauth_required, code: 42501)')), contains('parolu'));
    expect(financeErrorText(Exception('weird_thing_happened')), contains('weird_thing_happened'));
    expect(checkoutErrorKey(Exception('already_paid')), 'pay_err_already_paid');
    expect(checkoutErrorKey(Exception('boom')), 'pay_err_generic');
  });

  testWidgets('checkout: double tap sends ONE request with one key; result only from the server', (tester) async {
    final repo = _FakeRepo();
    const s = AppStrings({'pay_now': 'Pay', 'pay_test_approve': 'Approve (test)', 'pay_success_test': 'TEST OK'});
    await tester.pumpWidget(ProviderScope(
      overrides: [financeRepositoryProvider.overrideWithValue(repo)],
      child: MaterialApp(
        home: Scaffold(
          body: CheckoutSheet(
            order: _order(),
            s: s,
            availability: const CheckoutAvailability(available: true, mode: 'test', methods: [PayMethod.card]),
            methods: const [PayMethod.card],
          ),
        ),
      ),
    ));
    final pay = find.textContaining('Pay ·');
    await tester.tap(pay);
    await tester.pump();
    await tester.tap(find.byType(FilledButton), warnIfMissed: false); // second tap while the first runs (button busy)
    await tester.pump(const Duration(milliseconds: 400));
    expect(repo.keys.length, 1);
    expect(find.text('Approve (test)'), findsOneWidget);
    // A fast second tap lands where the next step's buttons appear: locked.
    await tester.tap(find.text('Approve (test)'), warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 50));
    expect(repo.completes, 0);
    await tester.pump(const Duration(milliseconds: 800));
    await tester.tap(find.text('Approve (test)'));
    await tester.pumpAndSettle();
    expect(repo.completes, 1);
    expect(find.text('TEST OK'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1)); // let the step lock end
  });

  group('guards', () {
    String read(String p) => File(p).readAsStringSync();
    test('finance route + profile entry only for the finance owner', () {
      expect(read('lib/core/router/app_router.dart').contains("path: '/finance'"), isTrue);
      final profile = read('lib/features/auth/presentation/profile_screen.dart');
      expect(profile.contains('ref.watch(isFinanceAdminProvider).valueOrNull != true'), isTrue);
    });
    test('checkout button only when the server opens it', () {
      expect(read('lib/features/finance/presentation/card_checkout.dart').contains('if (av == null || !av.available) return const SizedBox.shrink();'), isTrue);
      expect(read('lib/features/ads/presentation/ad_order_screen.dart').contains('CardCheckoutButton(order: o, s: s)'), isTrue);
    });
    test('the app never sends an amount and never stores card numbers', () {
      final repo = read('lib/features/finance/data/finance_repository.dart');
      expect(repo.contains("'amount'"), isFalse);
      expect(repo.contains('cvv'), isFalse);
      final sql = read('supabase/migrations/0037_finance_payments.sql');
      expect(sql.contains("card_last4 ~ '^[0-9]{4}\$'"), isTrue);
      expect(sql.contains("raise exception 'live_not_enabled'"), isTrue);
      expect(sql.toLowerCase().contains('cvv text'), isFalse);
    });
  });
}
