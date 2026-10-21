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

String read(String p) => File(p).readAsStringSync();

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

  group('phone: 2 VIP under the banner, then 2 VIP after every 4 ads', () {
    final plain = List.generate(10, (i) => 'a$i');
    test('newest VIP on top, the next ones further down, then again from the newest', () {
      final (top, feed) = marketPhoneVipLayout(['v1', 'v2', 'v3', 'v4', 'v5'], plain);
      expect(top, ['v1', 'v2']);
      expect([for (final e in feed) e.$1], ['a0', 'a1', 'a2', 'a3', 'v3', 'v4', 'a4', 'a5', 'a6', 'a7', 'v5', 'v1', 'a8', 'a9']);
      expect([for (final e in feed) if (e.$2) e.$1], ['v3', 'v4', 'v5', 'v1']);
    });
    test('a new VIP comes first and pushes the others down', () {
      final (top, feed) = marketPhoneVipLayout(['new', 'v1', 'v2'], plain.take(4).toList());
      expect(top, ['new', 'v1']);
      expect([for (final e in feed) if (e.$2) e.$1], ['v2', 'new']);
    });
    test('no VIP → plain list; one VIP → not twice in one place', () {
      expect(marketPhoneVipLayout(<String>[], plain).$2.every((e) => !e.$2), isTrue);
      final (_, feed) = marketPhoneVipLayout(['v1'], plain.take(4).toList());
      expect([for (final e in feed) e.$1], ['a0', 'a1', 'a2', 'a3', 'v1']);
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

  group('exact place of the truck (0053)', () {
    test('marked place is saved; a city-only point is not called exact; old ads read as city centre', () {
      final d = MarketDraft(lat: 40.4, lng: 49.8, locationExact: true);
      expect(d.toJson()['location_exact'], isTrue);
      expect(MarketDraft(lat: null, lng: null, locationExact: true).toJson()['location_exact'], isFalse);
      final l = MarketListing.fromJson({'id': 'x', 'listing_no': 1, 'owner_id': 'o', 'status': 'active', 'category': 'truck', 'created_at': '2026-10-21T10:00:00Z'});
      expect(l.locationExact, isFalse);
      expect(MarketDraft.from(MarketListing.fromJson({'id': 'x', 'listing_no': 1, 'owner_id': 'o', 'status': 'active', 'category': 'truck', 'created_at': '2026-10-21T10:00:00Z', 'lat': 1, 'lng': 2, 'location_exact': true})).locationExact, isTrue);
    });
    test('form has the map and GPS; ad page says which kind of point it is', () {
      final f = read('lib/features/market/presentation/market_edit_screen.dart');
      expect(f.contains("key: const ValueKey('mk-place-map'),"), isTrue);
      expect(f.contains('onTap: (_, p) => _markPlace(p),'), isTrue);
      expect(read('lib/features/market/presentation/market_detail_screen.dart')
          .contains("l.locationExact ? 'mk_location_exact' : 'mk_location_city_only'"), isTrue);
    });
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
      expect(home.contains('_VipGrid(items: vipTop)'), isTrue);
    });
    test('banner edit button only for an admin', () {
      final d = read('lib/features/market/presentation/market_home_desktop.dart');
      expect(d.contains('final isAdmin = ref.watch(currentUserProvider)?.role == AppConstants.roleAdmin;'), isTrue);
      expect(d.contains('if (isAdmin)'), isTrue);
    });
  });

  group('0054 — a successful TEST payment makes the ad VIP', () {
    test('result text', () {
      expect(checkoutResultKey(ok: true, test: true, vip: true), 'pay_success_vip_test');
      expect(checkoutResultKey(ok: true, test: false, vip: true), 'pay_success_vip');
      // Ad (banner) orders: unchanged.
      expect(checkoutResultKey(ok: true, test: true, vip: false), 'pay_success_test');
      expect(checkoutResultKey(ok: true, test: false, vip: false), 'pay_success');
      expect(checkoutResultKey(ok: false, test: true, vip: true), 'pay_failed');
    });

    test('new texts in all 6 languages', () {
      for (final lang in ['az', 'tr', 'en', 'ru', 'ka', 'zh']) {
        final j = File('assets/i18n/$lang.json').readAsStringSync();
        expect(j.contains('"pay_success_vip_test"'), isTrue, reason: lang);
        expect(j.contains('"pay_test_banner_vip"'), isTrue, reason: lang);
      }
    });

    test('server: VIP applied on any success, ad orders only LIVE', () {
      final m = File('supabase/migrations/0054_market_vip_test_activates.sql').readAsStringSync();
      expect(m.contains("if v_new = 'succeeded' and v_pay.market_vip_order_id is not null then"), isTrue);
      expect(m.contains("if v_new = 'succeeded' and v_pay.mode = 'live' then\n    update ad_orders"), isTrue);
      expect(m.contains('drop '), isFalse);
    });
  });
}
