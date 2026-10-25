// Loads (Yüklər) promotions (owner, 25.10.2026, migration 0067): the same
// İrəli çək · VIP · Premium as TIR Bazarı (0066). Server rules:
// supabase/tests/local/104_cargo_promotions.sql.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freightlink/features/cargo/domain/cargo_vip.dart';
import 'package:freightlink/features/cargo/domain/vip_rows.dart';
import 'package:freightlink/features/market/presentation/market_promo.dart';
import 'package:freightlink/models/cargo_model.dart';

String src(String p) => File(p).readAsStringSync();

final _now = DateTime.utc(2026, 10, 25, 12);

CargoModel load(String id,
    {Duration age = const Duration(hours: 1),
    bool vip = false,
    DateTime? featuredSince,
    DateTime? premiumUntil,
    DateTime? premiumSince,
    DateTime? bumpStart,
    int? bumpTotal}) {
  return CargoModel.fromJson({
    'id': id,
    'owner_id': 'u1',
    'pickup_country': 'AZ',
    'pickup_city': 'Bakı',
    'destination_country': 'GE',
    'destination_city': 'Tbilisi',
    'weight_kg': 20000,
    'pickup_date': '2026-10-28',
    'offered_price': 1500,
    'status': 'new',
    'created_at': _now.subtract(age).toIso8601String(),
    'is_featured': vip,
    'featured_until': vip ? _now.add(const Duration(days: 9)).toIso8601String() : null,
    'featured_since': featuredSince?.toIso8601String(),
    'premium_until': premiumUntil?.toIso8601String(),
    'premium_since': premiumSince?.toIso8601String(),
    'bump_start': bumpStart?.toIso8601String(),
    'bump_total': bumpTotal,
  });
}

void main() {
  group('the lift time (same rule as cargo_lifted_at in 0067)', () {
    test('posted only: the time it was posted', () {
      final c = load('a', age: const Duration(days: 3));
      expect(c.liftedAt(_now), _now.subtract(const Duration(days: 3)));
      expect(c.isPremiumAt(_now), isFalse);
    });

    test('İrəli çək: at once, then every 24 h until the pack is used', () {
      final start = _now.subtract(const Duration(days: 2, hours: 1));
      expect(load('a', age: const Duration(days: 9), bumpStart: start, bumpTotal: 5).liftedAt(_now),
          start.add(const Duration(days: 2)));
      expect(load('a', age: const Duration(days: 9), bumpStart: start, bumpTotal: 2).liftedAt(_now),
          start.add(const Duration(days: 1)),
          reason: 'a used-up pack lifts no more');
    });

    test('VIP and Premium lift once a day; an older VIP counts from the time it was posted', () {
      final since = _now.subtract(const Duration(days: 3, hours: 12));
      expect(load('a', age: const Duration(days: 9), vip: true, featuredSince: since).liftedAt(_now),
          since.add(const Duration(days: 3)));
      final posted = _now.subtract(const Duration(days: 2, hours: 5));
      expect(load('a', age: const Duration(days: 2, hours: 5), vip: true).liftedAt(_now),
          posted.add(const Duration(days: 2)));
      final p = load('a',
          age: const Duration(days: 9),
          premiumUntil: _now.add(const Duration(days: 4)),
          premiumSince: _now.subtract(const Duration(days: 1, hours: 2)));
      expect(p.isPremiumAt(_now), isTrue);
      expect(p.liftedAt(_now), _now.subtract(const Duration(hours: 2)));
      final over = load('a', age: const Duration(days: 9), premiumUntil: _now.subtract(const Duration(minutes: 1)));
      expect(over.isPremiumAt(_now), isFalse);
    });
  });

  group('Loads page order', () {
    test('Premium on top (newest first), then the chessboard; a lifted load before newer ones', () {
      final loads = [
        load('new1', age: const Duration(hours: 1)),
        load('new2', age: const Duration(hours: 2)),
        load('old-bumped',
            age: const Duration(days: 5), bumpStart: _now.subtract(const Duration(minutes: 5)), bumpTotal: 3),
        load('vip1', vip: true, age: const Duration(days: 1)),
        load('prem-old',
            age: const Duration(days: 4),
            premiumUntil: _now.add(const Duration(days: 3)),
            premiumSince: _now.subtract(const Duration(days: 2))),
        load('prem-new',
            age: const Duration(days: 4),
            premiumUntil: _now.add(const Duration(days: 3)),
            premiumSince: _now.subtract(const Duration(hours: 3))),
      ];
      final flow = [for (final c in buildLoadFlow(loads, columns: 2, now: _now, rotation: 0)) loads[c.index].id];
      expect(flow.take(2), ['prem-new', 'prem-old']);
      // Then load – VIP, VIP – load … with the lifted load first.
      expect(flow.skip(2), ['old-bumped', 'vip1', 'new1', 'new2']);
      expect(flow.toSet().length, loads.length, reason: 'each load once');
    });

    test('without any lift the order stays as it came (newest first from the server)', () {
      final loads = [for (var i = 0; i < 5; i++) load('n$i', age: Duration(hours: i + 1))];
      expect([for (final c in buildLoadFlow(loads, now: _now, rotation: 0)) loads[c.index].id],
          ['n0', 'n1', 'n2', 'n3', 'n4']);
    });
  });

  testWidgets('marks: crown for Premium, V for VIP', (tester) async {
    await tester.pumpWidget(const Directionality(
      textDirection: TextDirection.ltr,
      child: Center(child: PromoMarks(premium: true, vip: true)),
    ));
    expect(find.byKey(const ValueKey('promo-icon-premium')), findsOneWidget);
    expect(find.byKey(const ValueKey('promo-icon-vip')), findsOneWidget);
    await tester.pumpWidget(const Directionality(
      textDirection: TextDirection.ltr,
      child: Center(child: PromoMarks(premium: false, vip: false)),
    ));
    expect(find.byType(Image), findsNothing);
  });

  test('order from the server', () {
    final o = CargoPromoOrder.fromJson({
      'id': 'o1',
      'cargo_id': 'c1',
      'kind': 'premium',
      'qty': 5,
      'amount': 20,
      'currency': 'AZN',
      'status': 'pending_payment'
    });
    expect([o.id, o.cargoId, o.kind, o.qty, o.amount], ['o1', 'c1', 'premium', 5, 20.0]);
  });

  test('wired: Önə çıxar on my load, marks on the tile, checkout, admin prices', () {
    final promo = src('lib/features/cargo/presentation/widgets/cargo_promo.dart');
    expect(promo, contains('class CargoPromoTarget extends PromoTarget'));
    expect(promo, contains('repo.createPromoOrder(cargo.id, kind, qty)'));
    expect(promo, contains('cargo: true, promo: true'));
    expect(promo, contains('cargoPromoPlansProvider((kind, true))'));
    // A load's Premium names the Loads page, not TIR Bazarı (6 languages).
    expect(promo, contains("'cargo_promo_premium_body'"));
    for (final l in ['az', 'tr', 'en', 'ru', 'ka', 'zh']) {
      expect(src('assets/i18n/$l.json'), contains('"cargo_promo_premium_body"'), reason: l);
    }
    // The app never sends a price: the server's order sets the amount.
    final repo = src('lib/features/cargo/data/cargo_media_repository.dart');
    final start = repo.indexOf('Future<CargoPromoOrder> createPromoOrder');
    expect(repo.substring(start, repo.indexOf('}', start)).contains('price'), isFalse);
    expect(src('lib/features/finance/data/finance_repository.dart'), contains("'cargo_promo_order_id': promoOrderId"));
    expect(src('lib/features/finance/presentation/card_checkout.dart'), contains('vip.promo && vip.cargo'));
    final fn = src('supabase/functions/payments-checkout/index.ts');
    expect(fn, contains('rpc/cargo_promo_payment_create'));
    expect(fn, contains('targets !== 1'));
    expect(src('docs/payments/payments-checkout.dashboard.ts'), contains('rpc/cargo_promo_payment_create'));
    final admin = src('lib/features/admin/presentation/admin_pages.dart');
    expect(admin, contains('const CargoPromoPricesCard(MarketPromoKind.bump)'));
    expect(admin, contains('const CargoPromoPricesCard(MarketPromoKind.premium)'));
    expect(src('lib/features/cargo/domain/vip_rows.dart'), contains('loads[i].isPremiumAt(t)'));
  });

  test('0067 is safe: forward-only, nothing dropped, applied only after a verified payment', () {
    final sql = src('supabase/migrations/0067_cargo_promotions.sql').toLowerCase();
    for (final bad in ['drop table', 'truncate', 'delete from']) {
      expect(sql.contains(bad), isFalse, reason: bad);
    }
    expect(sql, contains('begin;'));
    expect(sql, contains('commit;'));
    expect(sql, contains('0067: final check failed'));
    expect(sql, contains('revoke all on function public._cargo_promo_apply(uuid) from public, anon, authenticated;'));
    expect(sql, contains("if v_new = 'succeeded' and v_pay.cargo_promo_order_id is not null then"));
    // Only the first 0062 VIP prices are changed, never an admin's.
    expect(sql, contains('where days = 30 and price = 15'));
    final run = src('supabase/tests/local/run_local.sh');
    expect(run, contains('0067_cargo_promotions.sql'));
    expect(run, contains('104_cargo_promotions.sql'));
  });
}
