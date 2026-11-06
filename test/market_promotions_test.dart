// TIR Bazarı ways to the front (owner, 25.10.2026, 0066, like Turbo.az):
// İrəli çək, VIP (daily lift), Premium; the owner's icons; prices from the
// server; card payment as VIP. Server side:
// supabase/tests/local/103_market_promotions.sql.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:freightlink/features/market/domain/market_models.dart';

String _read(String p) => File(p).readAsStringSync();

Map<String, dynamic> _row([Map<String, dynamic> more = const {}]) => {
      'id': 'x', 'listing_no': 1, 'owner_id': 'o', 'status': 'active', 'category': 'truck', //
      'created_at': '2026-10-25T10:00:00Z', ...more,
    };

void main() {
  group('models', () {
    test('Premium is read and runs out', () {
      final now = DateTime.now();
      final on = MarketListing.fromJson(_row({'premium_until': now.add(const Duration(days: 2)).toUtc().toIso8601String()}));
      final off = MarketListing.fromJson(_row({'premium_until': now.subtract(const Duration(hours: 1)).toUtc().toIso8601String()}));
      expect((on.premiumActive(), off.premiumActive(), MarketListing.fromJson(_row()).premiumActive()), (true, false, false));
    });

    test('plans: kinds, lowest active price, VIP in the same shape', () {
      final b = MarketPromoPlan.fromJson({'kind': 'bump', 'qty': 3, 'price': 6, 'currency': 'AZN', 'is_active': true});
      final p = MarketPromoPlan.fromJson({'kind': 'premium', 'qty': 1, 'price': 7});
      expect((b.kind, b.qty, b.price, p.kind), (MarketPromoKind.bump, 3, 6.0, MarketPromoKind.premium));
      final list = [
        const MarketPromoPlan(kind: MarketPromoKind.bump, qty: 10, price: 15),
        const MarketPromoPlan(kind: MarketPromoKind.bump, qty: 1, price: 3),
        const MarketPromoPlan(kind: MarketPromoKind.bump, qty: 2, price: 1, isActive: false),
      ];
      expect(marketPromoFrom(list)!.price, 3);
      expect(marketPromoFrom(const []), isNull);
      final v = MarketPromoPlan.vip(const MarketVipPlan(days: 5, price: 15));
      expect((v.kind, v.qty, v.price), (MarketPromoKind.vip, 5, 15.0));
      expect((MarketPromoKind.bump.countsDays, MarketPromoKind.vip.countsDays, MarketPromoKind.premium.countsDays),
          (false, true, true));
    });

    test('feed: Premium first, never twice, order moves on', () {
      final rest = [('a', false), ('p1', true), ('b', false)];
      final out = marketFeedWithPremium(['p1', 'p2'], rest, id: (x) => x);
      expect(out.map((e) => e.$1).toList(), ['p1', 'p2', 'a', 'b']);
      expect(marketFeedWithPremium(['p1', 'p2'], rest, id: (x) => x, rotation: 1).map((e) => e.$1).take(2), ['p2', 'p1']);
      expect(marketFeedWithPremium(<String>[], rest, id: (x) => x), rest);
    });
  });

  test("the owner's icons are packaged (transparent PNG)", () {
    for (final k in MarketPromoKind.values) {
      final f = File(k.asset);
      expect(f.existsSync(), isTrue, reason: k.asset);
      final b = f.readAsBytesSync();
      expect(b.sublist(1, 4), Uint8List.fromList('PNG'.codeUnits));
      expect(b[25], 6, reason: 'RGBA (colour type 6) = transparent background');
    }
    expect(_read('pubspec.yaml'), contains('- assets/images/promo/'));
  });

  test('wired: marks on cards, Premium on top, Önə çıxar, admin prices, checkout', () {
    final card = _read('lib/features/market/presentation/market_card.dart');
    expect(card, contains('MarketPromoMarks(l)'));
    final promo = _read('lib/features/market/presentation/market_promo.dart');
    for (final k in ["'mk-promo-options'", "ValueKey('mk-promo-\${kind.name}')", "ValueKey('promo-plan-\${kind.name}-\${p.qty}')",
      "ValueKey('promo-pay')", "ValueKey('promo-pay-soon')", 'repo.createVipOrder(l.id, qty)',
      'repo.createPromoOrder(l.id, kind, qty)', 'promo: true', 'class MarketPromoTarget extends PromoTarget']) {
      expect(promo, contains(k));
    }
    final home = _read('lib/features/market/presentation/market_home_screen.dart');
    expect(home, contains('marketFeedWithPremium('));
    expect(home, contains('marketPremiumQueueProvider(filter.category)'));
    final desk = _read('lib/features/market/presentation/market_home_desktop.dart');
    expect(desk, contains('marketPremiumQueueProvider(filter.category)'));
    final detail = _read('lib/features/market/presentation/market_detail_screen.dart');
    expect(detail, contains("key: const ValueKey('mk-promo-open')"));
    expect(detail, contains('showMarketPromoChooser(context, s, l)'));
    final admin = _read('lib/features/market/presentation/admin_market_page.dart');
    expect(admin, contains('_PromoPricesCard(MarketPromoKind.bump)'));
    expect(admin, contains('_PromoPricesCard(MarketPromoKind.premium)'));
    // The app never sends a price: the server's order sets the amount.
    final repo = _read('lib/features/market/data/market_repository.dart');
    final start = repo.indexOf('Future<MarketPromoOrder> createPromoOrder');
    expect(repo.substring(start, repo.indexOf('}', start)).contains('price'), isFalse);
    expect(_read('lib/features/finance/data/finance_repository.dart'), contains("'promo_order_id': promoOrderId"));
    expect(_read('lib/features/finance/presentation/card_checkout.dart'), contains('repo.startPromoCheckout('));
    final fn = _read('supabase/functions/payments-checkout/index.ts');
    expect(fn, contains('rpc/market_promo_payment_create'));
    expect(_read('docs/payments/payments-checkout.dashboard.ts'), contains('rpc/market_promo_payment_create'));
  });

  test('six languages', () {
    for (final lang in ['az', 'tr', 'en', 'ru', 'ka', 'zh']) {
      final j = _read('assets/i18n/$lang.json');
      for (final k in ['mk_promo_title', 'mk_promo_from', 'mk_promo_paid_until', 'mk_promo_days', 'mk_promo_times', 'mk_promo_soon',
        for (final kind in MarketPromoKind.values) ...['mk_promo_${kind.name}', 'mk_promo_${kind.name}_title',
          'mk_promo_${kind.name}_body', 'mk_promo_${kind.name}_gift']]) {
        expect(j.contains('"$k"'), isTrue, reason: '$lang $k');
      }
      expect(j, contains('{price}'));
    }
  });

  test('0066 is safe and in the SQL suite', () {
    final sql = _read('supabase/migrations/0066_market_promotions.sql').toLowerCase();
    for (final bad in ['drop table', 'truncate', 'delete from', 'drop column']) {
      expect(sql.contains(bad), isFalse, reason: bad);
    }
    // Only the two VIP packs that still have their first prices change.
    expect(RegExp(r'update public\.(\w+)').allMatches(sql).map((m) => m.group(1)).toSet(), {'market_vip_plans'});
    expect(sql, contains('where days = 30 and price = 15'));
    expect(RegExp(r'drop constraint (\w+)').allMatches(sql).map((m) => m.group(1)).toSet(), {'ad_payments_one_target3'});
    expect(sql.contains('\nbegin;\n'), isTrue);
    expect(sql.trimRight().endsWith('commit;'), isTrue);
    expect(sql, contains('0066: final check failed'));
    final run = _read('supabase/tests/local/run_local.sh');
    expect(run, contains('0066_market_promotions.sql'));
    expect(run, contains('103_market_promotions.sql'));
  });
}
