// TIR Bazarı banner + paid VIP (0044): pure logic, the VIP checkout (one
// request, amount from the server) and guards. The server rules are tested
// in supabase/tests/local/82_market_hero_vip.sql.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freightlink/core/localization/app_strings.dart';
import 'package:freightlink/features/finance/data/finance_repository.dart';
import 'package:freightlink/features/finance/domain/finance_models.dart';
import 'package:freightlink/features/finance/presentation/card_checkout.dart';
import 'package:freightlink/features/market/domain/market_models.dart';

class _FakeRepo extends FinanceRepository {
  final List<String> vipOrders = [];
  int adCheckouts = 0;

  @override
  Future<CheckoutPayment> startCheckout({required String orderId, required PayMethod method, required String idempotencyKey}) async {
    adCheckouts++;
    throw StateError('an ad checkout must not start for a VIP order');
  }

  @override
  Future<CheckoutPayment> startVipCheckout({required String vipOrderId, required PayMethod method, required String idempotencyKey}) async {
    vipOrders.add(vipOrderId);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    return const CheckoutPayment(id: 'p1', orderId: 'v1', amount: 9, currency: 'AZN', status: 'pending', mode: 'test');
  }

  @override
  Future<void> cancelPayment(String paymentId) async {}
}

void main() {
  group('VIP places beside the ads (3 left, 3 right)', () {
    test('newest first, alternating left / right, free places stay empty', () {
      final (l, r) = marketVipColumns(['a', 'b', 'c', 'd']);
      expect(l, ['a', 'c', null]);
      expect(r, ['b', 'd', null]);
    });
    test('no VIP ads → six free places', () {
      final (l, r) = marketVipColumns(const <String>[]);
      expect([...l, ...r].every((x) => x == null), isTrue);
      expect(l.length + r.length, 6);
    });
    test('more than six → only the six newest', () {
      final (l, r) = marketVipColumns(List.generate(9, (i) => i));
      expect([...l, ...r]..sort(), [0, 1, 2, 3, 4, 5]);
    });
  });

  group('models', () {
    test('banner: empty texts fall back to the app defaults', () {
      final h = MarketHero.fromJson({'image_url': ' ', 'title': ' Etibarlı TIR-lar ', 'title_accent': null, 'subtitle': ''});
      expect(h.imageUrl, isNull);
      expect(h.title, 'Etibarlı TIR-lar');
      expect(h.titleAccent, isNull);
      expect(h.subtitle, isNull);
    });
    test('VIP plan and order', () {
      final p = MarketVipPlan.fromJson({'days': 14, 'price': 9, 'currency': 'AZN', 'is_active': true});
      expect([p.days, p.price, p.currency, p.isActive], [14, 9.0, 'AZN', true]);
      final o = MarketVipOrder.fromJson({'id': 'v1', 'listing_id': 'l1', 'days': 7, 'amount': 5, 'currency': 'AZN', 'status': 'pending_payment'});
      expect([o.id, o.listingId, o.days, o.amount, o.status], ['v1', 'l1', 7, 5.0, 'pending_payment']);
    });
  });

  testWidgets('VIP checkout: one request for the VIP order, the server\'s price, never an ad checkout', (tester) async {
    final repo = _FakeRepo();
    const s = AppStrings({'pay_now': 'Pay', 'pay_test_approve': 'Approve (test)'});
    await tester.pumpWidget(ProviderScope(
      overrides: [financeRepositoryProvider.overrideWithValue(repo)],
      child: const MaterialApp(
        home: Scaffold(
          body: CheckoutSheet(
            vip: VipCheckoutTarget(vipOrderId: 'v1', amount: 9, currency: 'AZN'),
            s: s,
            availability: CheckoutAvailability(available: true, mode: 'test', methods: [PayMethod.card]),
            methods: [PayMethod.card],
          ),
        ),
      ),
    ));
    expect(find.textContaining(money(9, 'AZN')), findsWidgets);
    await tester.tap(find.textContaining('Pay ·'));
    await tester.pump();
    await tester.tap(find.byType(FilledButton), warnIfMissed: false); // double tap while busy
    await tester.pump(const Duration(milliseconds: 400));
    expect(repo.vipOrders, ['v1']);
    expect(repo.adCheckouts, 0);
    expect(find.text('Approve (test)'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
  });

  group('guards', () {
    String read(String p) => File(p).readAsStringSync();
    test('default prices 7 / 14 / 30 days = 5 / 9 / 15 AZN, changed only by an admin', () {
      final sql = read('supabase/migrations/0044_market_hero_vip.sql');
      expect(sql.contains('values (7, 5), (14, 9), (30, 15)'), isTrue);
      expect(sql.contains('function public.admin_market_set_vip_plan'), isTrue);
      expect(RegExp(r'admin_market_set_vip_plan[\s\S]*?perform public\._require_admin\(\);').hasMatch(sql), isTrue);
      expect(RegExp(r'admin_market_set_hero[\s\S]*?perform public\._require_admin\(\);').hasMatch(sql), isTrue);
    });
    test('an ad becomes VIP only after a verified LIVE payment', () {
      final sql = read('supabase/migrations/0044_market_hero_vip.sql');
      expect(
          RegExp(r"if v_new = 'succeeded' and v_pay\.mode = 'live' then[\s\S]*?perform public\._market_vip_apply").hasMatch(sql),
          isTrue);
      expect(sql.contains('revoke all on function public._market_vip_apply(uuid) from public, anon, authenticated;'), isTrue);
    });
    test('the app never sends a VIP price', () {
      final repo = read('lib/features/market/data/market_repository.dart');
      final start = repo.indexOf('Future<MarketVipOrder> createVipOrder');
      expect(repo.substring(start, repo.indexOf('}', start)).contains('price'), isFalse);
      expect(read('lib/features/finance/data/finance_repository.dart').contains("'amount'"), isFalse);
    });
    test('computer page only on a wide window; the phone page stays', () {
      final home = read('lib/features/market/presentation/market_home_screen.dart');
      expect(home.contains('if (isDesktopLayout(context)) return const MarketHomeDesktop();'), isTrue);
      expect(home.contains('_VipGrid(items: vip.take(4).toList())'), isTrue);
    });
    test('banner edit button only for an admin', () {
      final d = read('lib/features/market/presentation/market_home_desktop.dart');
      expect(d.contains('final isAdmin = ref.watch(currentUserProvider)?.role == AppConstants.roleAdmin;'), isTrue);
      expect(d.contains('if (isAdmin)'), isTrue);
    });
  });
}
