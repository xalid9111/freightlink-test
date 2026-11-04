// "Önə çıxar" for Servislər and TIRPark (owner, 04.11.2026, 0093): the
// TIR Bazarı sheets / packs / checkout; a promoted service or park stands
// first around its own place (list and map) and opens its own page; never
// among Loads.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freightlink/core/localization/app_strings.dart';
import 'package:freightlink/features/finance/domain/finance_models.dart';
import 'package:freightlink/features/finance/presentation/finance_providers.dart';
import 'package:freightlink/features/market/domain/market_models.dart';
import 'package:freightlink/features/promo/place_promo.dart';
import 'package:freightlink/features/tirpark/domain/tir_park.dart';
import 'package:freightlink/features/tirpark/presentation/tir_park_widgets.dart';

String src(String p) => File(p).readAsStringSync();
final _az = AppStrings(Map<String, String>.from(jsonDecode(src('assets/i18n/az.json')) as Map));

final _now = DateTime(2026, 11, 4, 12);
PlacePromo _p(String id, {int? vipDays, int? premDays, int? liftedHoursAgo}) => PlacePromo(
      id: id,
      vipUntil: vipDays == null ? null : _now.add(Duration(days: vipDays)),
      premiumUntil: premDays == null ? null : _now.add(Duration(days: premDays)),
      liftedAt: liftedHoursAgo == null ? null : _now.subtract(Duration(hours: liftedHoursAgo)),
    );

List<MarketPromoPlan> _plans(MarketPromoKind k) => switch (k) {
      MarketPromoKind.bump => const [
          MarketPromoPlan(kind: MarketPromoKind.bump, qty: 1, price: 3),
          MarketPromoPlan(kind: MarketPromoKind.bump, qty: 3, price: 6),
        ],
      MarketPromoKind.vip => const [MarketPromoPlan(kind: MarketPromoKind.vip, qty: 1, price: 5)],
      MarketPromoKind.premium => const [
          MarketPromoPlan(kind: MarketPromoKind.premium, qty: 1, price: 7),
          MarketPromoPlan(kind: MarketPromoKind.premium, qty: 5, price: 20),
        ],
    };

Widget _app(Widget child, {Map<String, PlacePromo> state = const {}}) => ProviderScope(
      key: UniqueKey(),
      overrides: [
        placePromoStateProvider.overrideWith((ref, key) async => state),
        placePromoPlansProvider.overrideWith((ref, k) async => _plans(k.$2)),
        checkoutAvailabilityProvider.overrideWith((ref) async => const CheckoutAvailability(available: false, mode: 'off')),
      ],
      child: MaterialApp(home: Scaffold(body: SingleChildScrollView(child: child))),
    );

void main() {
  group('order: promoted first, the rest as before', () {
    test('Premium on top, then VIP / İrəli çək by the last lift, the rest nearest first', () {
      final items = ['near', 'vip-old', 'mid', 'prem', 'bump-new', 'far'];
      final promos = {
        'vip-old': _p('vip-old', vipDays: 3, liftedHoursAgo: 20),
        'prem': _p('prem', premDays: 5, vipDays: 5, liftedHoursAgo: 30),
        'bump-new': _p('bump-new', liftedHoursAgo: 1),
      };
      expect(promotedFirst(items, (s) => s, promos, now: _now), ['prem', 'bump-new', 'vip-old', 'near', 'mid', 'far']);
    });

    test('expired: back in its own place; nothing running = the list unchanged', () {
      final items = ['a', 'b', 'c'];
      final expired = {'c': PlacePromo(id: 'c', vipUntil: _now.subtract(const Duration(hours: 1)))};
      expect(promotedFirst(items, (s) => s, expired, now: _now), ['a', 'b', 'c']);
      expect(expired['c']!.isVipAt(_now), isFalse);
      expect(promotedFirst(items, (s) => s, const {}), same(items));
    });

    test('parks keep their distance with them', () {
      final found = [('p1', 2.0), ('p2', 40.0)];
      final out = promotedFirst(found, (e) => e.$1, {'p2': _p('p2', vipDays: 1, liftedHoursAgo: 2)}, now: _now);
      expect(out.first, ('p2', 40.0));
    });

    test('server answer is read', () {
      final p = PlacePromo.fromJson({
        'id': 'x',
        'vip_until': '2099-01-01T00:00:00Z',
        'premium_until': null,
        'bump_left': 2,
        'lifted_at': '2026-11-04T10:00:00Z',
      });
      expect(p.isVip, isTrue);
      expect(p.isPremium, isFalse);
      expect(p.bumpLeft, 2);
      expect(p.isPromoted, isTrue);
    });
  });

  group('the owner\'s own page', () {
    testWidgets('service: the three ways with the Loads prices, the area explained, the sheet opens', (tester) async {
      tester.view.physicalSize = const Size(400, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_app(PlacePromoSection(s: _az, target: PlaceTarget.service, id: 's1', open: true)));
      await tester.pumpAndSettle();
      for (final k in ['bump', 'vip', 'premium']) {
        expect(find.byKey(ValueKey('mk-promo-$k')), findsOneWidget, reason: k);
      }
      expect(find.byKey(const ValueKey('pp-area')), findsOneWidget);
      expect(find.text(_az.t('pp_area_service')), findsOneWidget);
      expect(_az.t('pp_area_service'), contains('Yüklər səhifəsində göstərilmir'));
      expect(_az.t('pp_area_service'), contains('Ölkə ayrıca seçilmir'));
      await tester.tap(find.byKey(const ValueKey('mk-promo-premium')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('mk-promo-sheet-premium')), findsOneWidget);
      expect(find.text(_az.t('pp_svc_premium_body')), findsOneWidget);
      expect(find.byKey(const ValueKey('promo-plan-premium-5')), findsOneWidget);
      expect(find.byKey(const ValueKey('promo-pay-soon')), findsOneWidget, reason: 'checkout off: no payment');
    });

    testWidgets('running promotion: the date it is paid to', (tester) async {
      await tester.pumpWidget(_app(PlacePromoSection(s: _az, target: PlaceTarget.tirpark, id: 'p1', open: true),
          state: {'p1': PlacePromo(id: 'p1', vipUntil: DateTime(2099, 1, 2), liftedAt: DateTime.now())}));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('pp-running')), findsOneWidget);
      expect(find.textContaining('02.01.2099'), findsOneWidget);
      expect(find.text(_az.t('pp_area_tirpark')), findsOneWidget);
    });

    testWidgets('not open: the reason instead of the packs', (tester) async {
      await tester.pumpWidget(_app(PlacePromoSection(s: _az, target: PlaceTarget.service, id: 's1', open: false)));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('mk-promo-options')), findsNothing);
      expect(find.text(_az.t('pp_not_open_service')), findsOneWidget);
      await tester.pumpWidget(
          _app(PlacePromoSection(s: _az, target: PlaceTarget.service, id: 's1', open: false, closedKey: 'pp_no_area')));
      await tester.pumpAndSettle();
      expect(find.text(_az.t('pp_no_area')), findsOneWidget);
    });
  });

  group('lists and maps', () {
    testWidgets('pin: the mark only while a promotion runs', (tester) async {
      const pin = SizedBox(width: 30, height: 30);
      await tester.pumpWidget(MaterialApp(home: PlacePromoPin(pin: pin, promo: _p('a', vipDays: 2, liftedHoursAgo: 1))));
      expect(find.byKey(const ValueKey('pp-pin-a')), findsOneWidget);
      await tester.pumpWidget(MaterialApp(
          home: PlacePromoPin(pin: pin, promo: PlacePromo(id: 'b', vipUntil: DateTime.now().subtract(const Duration(days: 1))))));
      expect(find.byKey(const ValueKey('pp-pin-b')), findsNothing, reason: 'expired');
      await tester.pumpWidget(const MaterialApp(home: PlacePromoPin(pin: pin, promo: null)));
      expect(find.byType(Stack), findsNothing);
    });

    testWidgets('park card: the "Reklam" mark, a tap on the name opens the park page', (tester) async {
      var opened = false;
      const park = TirPark(id: 'p1', name: 'Park A', lat: 40.4, lng: 49.8, status: 'approved');
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: TirParkCard(
            park: park,
            km: 3,
            s: _az,
            selected: true,
            onTap: () {},
            onOpen: () => opened = true,
            badge: PlacePromoTag(s: _az, promo: PlacePromo(id: 'p1', premiumUntil: DateTime(2099))),
          ),
        ),
      ));
      expect(find.byKey(const ValueKey('pp-tag-p1')), findsOneWidget);
      expect(find.text('Reklam'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('tp-name-p1')));
      expect(opened, isTrue);
    });
  });

  test('wired: Servislər + TIRPark lists / maps / pages, admin prices, checkout; not on Loads', () {
    final svc = src('lib/features/services/presentation/services_map_screen.dart');
    expect(svc, contains('promotedFirst(List.of(items)'));
    expect(svc, contains('PlacePromoPin(promo: promos[p.id]'));
    expect(svc, contains('PlacePromoTag(s: s, promo: promo!)'));
    expect(svc, contains("context.pushOnce('/service/\${p.id}')"), reason: 'a tap opens the service page');
    final tp = src('lib/features/tirpark/presentation/tir_park_screen.dart');
    expect(tp, contains('promotedFirst(found'));
    expect(tp, contains('PlacePromoPin('));
    expect(tp, contains("context.pushOnce('/tirpark/p/\${p.id}')"), reason: 'a tap opens the park page');
    expect(src('lib/features/services/presentation/service_detail_screen.dart'), contains('PlaceTarget.service'));
    expect(src('lib/features/tirpark/presentation/tir_park_detail_screen.dart'),
        contains("park.managerId == me.id && park.managerStatus == 'approved'"));
    expect(src('lib/features/admin/presentation/admin_services_page.dart'), contains('PlacePromoPrices(PlaceTarget.service'));
    expect(src('lib/features/admin/presentation/admin_tir_parks_page.dart'), contains('PlacePromoPrices(PlaceTarget.tirpark'));
    final promo = src('lib/features/promo/place_promo.dart');
    expect(promo, contains('place: true'));
    expect(src('lib/features/finance/presentation/card_checkout.dart'), contains('startPlacePromoCheckout'));
    expect(src('supabase/functions/payments-checkout/index.ts'), contains('place_promo_order_id'));
    // Never among Loads.
    for (final f in Directory('lib/features/cargo').listSync(recursive: true).whereType<File>()) {
      expect(f.readAsStringSync(), isNot(contains('place_promo')), reason: f.path);
    }
  });
}
