// Premium places (owner, 07.11.2026, 0102): a park's, a service's or a
// shop's Premium picks where it is shown — Parklar · Servislər · Mağazalar
// (cards side by side, one or more); nothing chosen = no order; the price =
// the chosen sections' Premium prices added up; the places go to the server
// with the order; each map's list shows the others' Premium in a strip that
// opens the page. Yüklər takes no advertising: no "Önə çıxar" on a load, a
// TIR Bazarı ad has no place cards. İrəli çək / VIP unchanged.
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
import 'package:freightlink/features/promo/promo_cross.dart';

String src(String p) => File(p).readAsStringSync();
final _az = AppStrings(Map<String, String>.from(jsonDecode(src('assets/i18n/az.json')) as Map));

// Servis prices (own section of a service, also Mağazalar) and TIRPark prices (Parklar).
const _s5 = MarketPromoPlan(kind: MarketPromoKind.premium, qty: 5, price: 20);
const _s30 = MarketPromoPlan(kind: MarketPromoKind.premium, qty: 30, price: 60);
const _p5 = MarketPromoPlan(kind: MarketPromoKind.premium, qty: 5, price: 30);

final _servicePlans = FutureProvider<List<MarketPromoPlan>>((ref) async => const [_s5, _s30]);
final _parkPlans = FutureProvider<List<MarketPromoPlan>>((ref) async => const [_p5]);
final _vipPlans = FutureProvider<List<MarketPromoPlan>>((ref) async => const [MarketPromoPlan(kind: MarketPromoKind.vip, qty: 5, price: 15)]);

/// A service (home = Servislər) that records the order; [home] null = no
/// place choice (as a TIR Bazarı ad).
class _Target extends PromoTarget {
  final PromoPlace? homePlace;
  Set<PromoPlace>? orderedPlaces;
  int orders = 0;
  _Target({this.homePlace = PromoPlace.services});

  @override
  ProviderListenable<AsyncValue<List<MarketPromoPlan>>> plans(MarketPromoKind kind) => kind == MarketPromoKind.vip ? _vipPlans : _servicePlans;
  @override
  PromoPlace? get home => homePlace;
  @override
  List<PromoPlace> get placeChoices => homePlace == null ? const [] : PromoPlace.values;
  @override
  ProviderListenable<AsyncValue<List<MarketPromoPlan>>> premiumPlansAt(PromoPlace place) => place == PromoPlace.parks ? _parkPlans : _servicePlans;
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

Future<_Target> _open(WidgetTester tester, MarketPromoKind kind, {PromoPlace? home = PromoPlace.services}) async {
  tester.view.physicalSize = const Size(390, 1400);
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
  group('price: the chosen sections\' Premium prices added up', () {
    final others = {PromoPlace.parks: const [_p5], PromoPlace.shops: const [_s5, _s30]};
    ({double amount, String currency})? price(Set<PromoPlace> places, MarketPromoPlan own, [Map<PromoPlace, List<MarketPromoPlan>>? o]) =>
        premiumPlacesPrice(home: PromoPlace.services, places: places, own: own, others: o ?? others);

    test('own section = its own price; another one = that section\'s price; all = the sum', () {
      expect(price({PromoPlace.services}, _s5)?.amount, 20);
      expect(price({PromoPlace.parks}, _s5)?.amount, 30);
      expect(price({PromoPlace.services, PromoPlace.shops}, _s5)?.amount, 40);
      expect(price(PromoPlace.values.toSet(), _s5)?.amount, 70);
    });
    test('nothing chosen, a section without that pack, or another currency: no price (no made-up amount)', () {
      expect(price(const {}, _s5), isNull);
      expect(price({PromoPlace.services, PromoPlace.parks}, _s30), isNull);
      expect(price({PromoPlace.parks}, _s5, {PromoPlace.parks: const [MarketPromoPlan(kind: MarketPromoKind.premium, qty: 5, price: 30, currency: 'USD')]}), isNull);
      expect(promoPlacesWire({PromoPlace.shops, PromoPlace.parks}), ['parks', 'shops']);
    });
  });

  group('the Premium sheet of a park / service / shop', () {
    testWidgets('three place cards side by side on a phone; the own section is chosen first', (tester) async {
      await _open(tester, MarketPromoKind.premium);
      final a = tester.getRect(find.byKey(const ValueKey('promo-place-parks')));
      final b = tester.getRect(find.byKey(const ValueKey('promo-place-services')));
      final c = tester.getRect(find.byKey(const ValueKey('promo-place-shops')));
      expect([a.top, b.top], [c.top, c.top], reason: 'side by side');
      expect(b.left, greaterThan(a.right));
      expect(c.left, greaterThan(b.right));
      expect(c.right, lessThanOrEqualTo(390));
      expect(find.text('Seçilmiş yerlər: Servislər'), findsOneWidget);
      expect(find.text('Yekun məbləğ: 20.00 AZN'), findsOneWidget);
    });

    testWidgets('all three: the places and the total before paying; the order carries them', (tester) async {
      final t = await _open(tester, MarketPromoKind.premium);
      await tester.tap(find.byKey(const ValueKey('promo-place-parks')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('promo-place-shops')));
      await tester.pump();
      expect(find.text('Seçilmiş yerlər: Parklar + Servislər + Mağazalar'), findsOneWidget);
      expect(find.text('Yekun məbləğ: 70.00 AZN'), findsOneWidget);
      expect(find.textContaining('70.00 AZN'), findsWidgets, reason: 'the pay button shows the total');
      await tester.tap(find.byKey(const ValueKey('promo-pay')));
      await tester.pumpAndSettle();
      expect(t.orders, 1);
      expect(t.orderedPlaces, PromoPlace.values.toSet());
    });

    testWidgets('only another section: that section\'s price; the order carries that place', (tester) async {
      final t = await _open(tester, MarketPromoKind.premium);
      await tester.tap(find.byKey(const ValueKey('promo-place-parks')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('promo-place-services')));
      await tester.pump();
      expect(find.text('Seçilmiş yerlər: Parklar'), findsOneWidget);
      expect(find.text('Yekun məbləğ: 30.00 AZN'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('promo-pay')));
      await tester.pumpAndSettle();
      expect(t.orderedPlaces, {PromoPlace.parks});
    });

    testWidgets('nothing chosen: the order cannot be confirmed', (tester) async {
      final t = await _open(tester, MarketPromoKind.premium);
      await tester.tap(find.byKey(const ValueKey('promo-place-services')));
      await tester.pump();
      expect(find.byKey(const ValueKey('promo-places-none')), findsOneWidget);
      expect(_payButton(tester).onPressed, isNull);
      await tester.tap(find.byKey(const ValueKey('promo-pay')), warnIfMissed: false);
      expect(t.orders, 0);
    });

    testWidgets('a section without that pack: said plainly, blocked', (tester) async {
      await _open(tester, MarketPromoKind.premium);
      await tester.tap(find.byKey(const ValueKey('promo-plan-premium-30')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('promo-place-parks')));
      await tester.pump();
      expect(find.byKey(const ValueKey('promo-places-missing')), findsOneWidget);
      expect(_payButton(tester).onPressed, isNull);
    });

    testWidgets('VIP, and a TIR Bazarı ad\'s Premium: no place cards (Yüklər is never offered)', (tester) async {
      await _open(tester, MarketPromoKind.vip);
      expect(find.byKey(const ValueKey('promo-place-parks')), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await _open(tester, MarketPromoKind.premium, home: null);
      expect(find.byKey(const ValueKey('promo-place-parks')), findsNothing);
      expect(find.textContaining('20.00 AZN'), findsWidgets, reason: 'the old price, the old way');
    });
  });

  test('the strip opens the page of the park / service / shop', () {
    PlaceCrossItem it(String kind, {bool shop = false}) =>
        PlaceCrossItem.fromJson({'source_kind': kind, 'source_id': 'x1', 'name': 'N', 'city': 'Bakı', 'shop': shop});
    expect(it('tirpark').route, '/tirpark/p/x1');
    expect(it('service').route, '/service/x1');
    expect(_az.t(it('service', shop: true).labelKey()), 'Mağaza');
    expect(_az.t(it('tirpark').labelKey()), 'TIR park');
  });

  test('wired: places to the server, the own section, a strip on every map, SQL 0102', () {
    final pp = src('lib/features/promo/place_promo.dart');
    expect(pp, contains("if (places != null) 'p_places': places,"));
    expect(pp, contains('target == PlaceTarget.tirpark ? PromoPlace.parks : (shop ? PromoPlace.shops : PromoPlace.services)'));
    expect(pp, contains('places: kind == MarketPromoKind.premium && places != null ? promoPlacesWire(places) : null'));
    expect(src('lib/features/services/presentation/service_detail_screen.dart'), contains('shop: p.isShop,'));
    expect(src('lib/features/tirpark/presentation/tir_park_screen.dart'),
        contains("PlaceCrossStrip(s: s, place: 'parks', lat: _center.latitude, lng: _center.longitude)"));
    expect(src('lib/features/services/presentation/services_map_screen.dart'),
        contains("PlaceCrossStrip(s: s, place: shops ? 'shops' : 'services', lat: query.lat, lng: query.lng)"));
    final sql = src('supabase/migrations/0102_place_premium_places.sql');
    expect(sql, contains("raise exception 'places_not_available'"));
    expect(sql, contains('v_amount := v_amount + v_plan.price;'));
    expect(sql.toLowerCase().contains('delete from'), isFalse);
    expect(sql.toLowerCase().contains('drop table'), isFalse);
  });

  test('Yüklər: no advertising — no "Önə çıxar" on a load, no ads strip, no Yüklər card', () {
    expect(File('lib/features/cargo/presentation/widgets/cargo_promo.dart').existsSync(), isFalse);
    expect(src('lib/features/cargo/presentation/my_cargo_screen.dart').contains('my-cargo-promo'), isFalse);
    expect(src('lib/features/cargo/presentation/cargo_detail_screen.dart').contains('cargo-promo-open'), isFalse);
    expect(src('lib/features/cargo/presentation/cargo_marketplace_screen.dart').contains('CrossPremium'), isFalse);
    expect(PromoPlace.values.map((p) => p.name), ['parks', 'services', 'shops']);
    final sql = src('supabase/migrations/0102_place_premium_places.sql');
    expect(sql, contains("raise exception 'not_available' using errcode = '42501';"));
    expect(sql, contains("if p_kind = 'premium' and (p_places is null or p_places <> array['market']) then"));
  });
}
