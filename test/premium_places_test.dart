// Premium: where it is shown (owner, 07.11.2026, 0101). Only Premium gets
// the two place cards (Yüklər bölməsi · TIR Bazarı, side by side, one or
// both); nothing chosen = no order; both = the two sections' prices added
// up ("a"); the places go to the server with the order; the other section
// shows the item in a Premium strip that opens it. İrəli çək / VIP and the
// service / park promotions are unchanged.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freightlink/core/localization/app_strings.dart';
import 'package:freightlink/features/finance/domain/finance_models.dart';
import 'package:freightlink/features/finance/presentation/card_checkout.dart';
import 'package:freightlink/features/finance/presentation/finance_providers.dart';
import 'package:freightlink/features/market/domain/market_models.dart';
import 'package:freightlink/features/market/presentation/market_promo.dart';

String src(String p) => File(p).readAsStringSync();
final _az = AppStrings(Map<String, String>.from(jsonDecode(src('assets/i18n/az.json')) as Map));

const _p5 = MarketPromoPlan(kind: MarketPromoKind.premium, qty: 5, price: 20);
const _p30 = MarketPromoPlan(kind: MarketPromoKind.premium, qty: 30, price: 60);
const _other5 = MarketPromoPlan(kind: MarketPromoKind.premium, qty: 5, price: 25);

final _ownPlans = FutureProvider<List<MarketPromoPlan>>((ref) async => const [_p5, _p30]);
final _otherPlans = FutureProvider<List<MarketPromoPlan>>((ref) async => const [_other5]);
final _vipPlans = FutureProvider<List<MarketPromoPlan>>((ref) async => const [MarketPromoPlan(kind: MarketPromoKind.vip, qty: 5, price: 15)]);

/// A load-like item (home = Yüklər) that records the order.
class _Target extends PromoTarget {
  final PromoPlace? homePlace;
  Set<PromoPlace>? orderedPlaces;
  int orders = 0;
  _Target({this.homePlace = PromoPlace.loads});

  @override
  ProviderListenable<AsyncValue<List<MarketPromoPlan>>> plans(MarketPromoKind kind) => kind == MarketPromoKind.vip ? _vipPlans : _ownPlans;
  @override
  ProviderListenable<AsyncValue<List<MarketPromoPlan>>>? otherPremiumPlans() => homePlace == null ? null : _otherPlans;
  @override
  PromoPlace? get home => homePlace;
  @override
  DateTime? paidUntil(MarketPromoKind kind) => null;
  @override
  Future<VipCheckoutTarget> order(WidgetRef ref, MarketPromoKind kind, int qty, {Set<PromoPlace>? places}) async {
    orders++;
    orderedPlaces = places;
    throw StateError('stop here (no checkout in the test)');
  }

  @override
  void refresh(ProviderContainer c) {}
  @override
  String get failedKey => 'mk_vip_failed';
}

Future<_Target> _open(WidgetTester tester, MarketPromoKind kind, {PromoPlace? home = PromoPlace.loads}) async {
  tester.view.physicalSize = const Size(400, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final t = _Target(homePlace: home);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      checkoutAvailabilityProvider.overrideWith((ref) async => const CheckoutAvailability(available: true, mode: 'test', methods: [PayMethod.card])),
    ],
    child: MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(child: TextButton(onPressed: () => showPromoSheet(context, _az, t, kind), child: const Text('open'))),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return t;
}

FilledButton _payButton(WidgetTester tester) => tester.widget<FilledButton>(find.byKey(const ValueKey('promo-pay')));

void main() {
  group('price (owner\'s choice "a")', () {
    test('one place = the item\'s current Premium price; both = the two added up', () {
      expect(premiumPlacesPrice(home: PromoPlace.loads, places: {PromoPlace.loads}, own: _p5, other: const [_other5])?.amount, 20);
      expect(premiumPlacesPrice(home: PromoPlace.loads, places: {PromoPlace.market}, own: _p5, other: const [_other5])?.amount, 20);
      expect(premiumPlacesPrice(home: PromoPlace.loads, places: {PromoPlace.loads, PromoPlace.market}, own: _p5, other: const [_other5])?.amount, 45);
    });
    test('nothing chosen, or both without a pack / currency there: no price (no made-up amount)', () {
      expect(premiumPlacesPrice(home: PromoPlace.loads, places: const {}, own: _p5, other: const [_other5]), isNull);
      expect(premiumPlacesPrice(home: PromoPlace.loads, places: {PromoPlace.loads, PromoPlace.market}, own: _p30, other: const [_other5]), isNull);
      expect(
          premiumPlacesPrice(
              home: PromoPlace.loads,
              places: {PromoPlace.loads, PromoPlace.market},
              own: _p5,
              other: const [MarketPromoPlan(kind: MarketPromoKind.premium, qty: 5, price: 25, currency: 'USD')]),
          isNull);
      expect(promoPlacesWire({PromoPlace.market, PromoPlace.loads}), ['loads', 'market']);
    });
  });

  group('the Premium sheet', () {
    testWidgets('the two place cards side by side; the own section is chosen first', (tester) async {
      await _open(tester, MarketPromoKind.premium);
      final a = tester.getRect(find.byKey(const ValueKey('promo-place-loads')));
      final b = tester.getRect(find.byKey(const ValueKey('promo-place-market')));
      expect(a.top, b.top, reason: 'side by side');
      expect(b.left, greaterThan(a.right));
      expect(find.text('Seçilmiş yerlər: Yüklər bölməsi'), findsOneWidget);
      expect(find.text('Yekun məbləğ: 20.00 AZN'), findsOneWidget);
    });

    testWidgets('both places: the total and the places before paying; the order carries them', (tester) async {
      final t = await _open(tester, MarketPromoKind.premium);
      await tester.tap(find.byKey(const ValueKey('promo-place-market')));
      await tester.pump();
      expect(find.text('Seçilmiş yerlər: Yüklər bölməsi + TIR Bazarı'), findsOneWidget);
      expect(find.text('Yekun məbləğ: 45.00 AZN'), findsOneWidget);
      expect(find.textContaining('45.00 AZN'), findsWidgets, reason: 'the pay button shows the total');
      await tester.tap(find.byKey(const ValueKey('promo-pay')));
      await tester.pumpAndSettle();
      expect(t.orders, 1);
      expect(t.orderedPlaces, {PromoPlace.loads, PromoPlace.market});
    });

    testWidgets('only the other section: its own price; the order carries that place', (tester) async {
      final t = await _open(tester, MarketPromoKind.premium);
      await tester.tap(find.byKey(const ValueKey('promo-place-market')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('promo-place-loads')));
      await tester.pump();
      expect(find.text('Seçilmiş yerlər: TIR Bazarı'), findsOneWidget);
      expect(find.text('Yekun məbləğ: 20.00 AZN'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('promo-pay')));
      await tester.pumpAndSettle();
      expect(t.orderedPlaces, {PromoPlace.market});
    });

    testWidgets('nothing chosen: the order cannot be confirmed', (tester) async {
      final t = await _open(tester, MarketPromoKind.premium);
      await tester.tap(find.byKey(const ValueKey('promo-place-loads')));
      await tester.pump();
      expect(find.byKey(const ValueKey('promo-places-none')), findsOneWidget);
      expect(_payButton(tester).onPressed, isNull);
      await tester.tap(find.byKey(const ValueKey('promo-pay')), warnIfMissed: false);
      expect(t.orders, 0);
    });

    testWidgets('both for a pack the other section does not sell: said plainly, blocked', (tester) async {
      await _open(tester, MarketPromoKind.premium);
      await tester.tap(find.byKey(const ValueKey('promo-plan-premium-30')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('promo-place-market')));
      await tester.pump();
      expect(find.byKey(const ValueKey('promo-places-both-missing')), findsOneWidget);
      expect(_payButton(tester).onPressed, isNull);
    });

    testWidgets('VIP and the service / park Premium: no place cards (unchanged)', (tester) async {
      await _open(tester, MarketPromoKind.vip);
      expect(find.byKey(const ValueKey('promo-place-loads')), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await _open(tester, MarketPromoKind.premium, home: null);
      expect(find.byKey(const ValueKey('promo-place-loads')), findsNothing);
      expect(find.textContaining('20.00 AZN'), findsWidgets, reason: 'the old price, the old way');
    });
  });

  test('wired: the places go to the server; the other section shows a Premium strip that opens the item', () {
    final cargo = src('lib/features/cargo/presentation/widgets/cargo_promo.dart');
    expect(cargo, contains('PromoPlace get home => PromoPlace.loads;'));
    expect(cargo, contains('places: kind == MarketPromoKind.premium && places != null ? promoPlacesWire(places) : null'));
    final market = src('lib/features/market/presentation/market_promo.dart');
    expect(market, contains('PromoPlace get home => PromoPlace.market;'));
    expect(src('lib/features/cargo/data/cargo_media_repository.dart'), contains("if (places != null) 'p_places': places,"));
    expect(src('lib/features/market/data/market_repository.dart'), contains("if (places != null) 'p_places': places,"));
    expect(src('lib/features/market/presentation/market_home_screen.dart'), contains('CrossPremiumLoadsStrip(s: s),'));
    expect(src('lib/features/cargo/presentation/cargo_marketplace_screen.dart'), contains('CrossPremiumMarketStrip(s: strings),'));
    final strip = src('lib/features/promo/promo_cross.dart');
    expect(strip, contains("context.pushOnce('/load/\${c.id}')"));
    expect(strip, contains("context.pushOnce('/market/l/\${l.id}')"));
    final sql = src('supabase/migrations/0101_premium_places.sql');
    expect(sql, contains("raise exception 'both_not_available'"));
    expect(sql, contains('v_amount := v_plan.price + v_other.price;'));
    expect(sql.toLowerCase().contains('delete from'), isFalse);
  });
}
