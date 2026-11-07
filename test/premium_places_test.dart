// Premium of a park / service / shop (owner, 07.11.2026, 0103): always on
// its own map; the sheet picks where else it is shown — TIR Bazarı · Yüklər
// bölməsi (cards side by side, one or both); nothing chosen = no order; one
// place = its own Premium price, both = + the Yüklər Premium price; the
// places go to the server; TIR Bazarı and Yüklər show it in a Premium strip
// that opens the page. A load takes no advertising; a TIR Bazarı ad has no
// place cards. İrəli çək / VIP unchanged.
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
import 'package:freightlink/features/covers/profile_covers.dart';
import 'package:freightlink/features/promo/promo_cross.dart';
import 'package:freightlink/features/services/presentation/services_providers.dart' show serviceByIdProvider;
import 'package:freightlink/models/service_models.dart';
import 'package:go_router/go_router.dart';

String src(String p) => File(p).readAsStringSync();
final _az = AppStrings(Map<String, String>.from(jsonDecode(src('assets/i18n/az.json')) as Map));

// The service's own Premium packs and the Yüklər Premium packs.
const _s5 = MarketPromoPlan(kind: MarketPromoKind.premium, qty: 5, price: 20);
const _s30 = MarketPromoPlan(kind: MarketPromoKind.premium, qty: 30, price: 60);
const _l5 = MarketPromoPlan(kind: MarketPromoKind.premium, qty: 5, price: 25);

final _ownPlans = FutureProvider<List<MarketPromoPlan>>((ref) async => const [_s5, _s30]);
final _loadsPlans = FutureProvider<List<MarketPromoPlan>>((ref) async => const [_l5]);
final _vipPlans = FutureProvider<List<MarketPromoPlan>>((ref) async => const [MarketPromoPlan(kind: MarketPromoKind.vip, qty: 5, price: 15)]);

/// A service that records the order; [places] false = no place choice (as
/// a TIR Bazarı ad).
class _Target extends PromoTarget {
  final bool places;
  Set<PromoPlace>? orderedPlaces;
  int orders = 0;
  _Target({this.places = true});

  @override
  ProviderListenable<AsyncValue<List<MarketPromoPlan>>> plans(MarketPromoKind kind) => kind == MarketPromoKind.vip ? _vipPlans : _ownPlans;
  @override
  List<PromoPlace> get placeChoices => places ? PromoPlace.values : const [];
  @override
  ProviderListenable<AsyncValue<List<MarketPromoPlan>>> secondPlacePlans() => _loadsPlans;
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

Future<_Target> _open(WidgetTester tester, MarketPromoKind kind, {bool places = true}) async {
  tester.view.physicalSize = const Size(390, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final t = _Target(places: places);
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
  group('price (owner\'s "2 OK")', () {
    test('one place = its own Premium price; both = + the Yüklər Premium price', () {
      expect(premiumPlacesPrice(places: {PromoPlace.market}, own: _s5, second: const [_l5])?.amount, 20);
      expect(premiumPlacesPrice(places: {PromoPlace.loads}, own: _s5, second: const [_l5])?.amount, 20);
      expect(premiumPlacesPrice(places: PromoPlace.values.toSet(), own: _s5, second: const [_l5])?.amount, 45);
    });
    test('nothing chosen, or both without a Yüklər pack / currency: no price (no made-up amount)', () {
      expect(premiumPlacesPrice(places: const {}, own: _s5, second: const [_l5]), isNull);
      expect(premiumPlacesPrice(places: PromoPlace.values.toSet(), own: _s30, second: const [_l5]), isNull);
      expect(
          premiumPlacesPrice(
              places: PromoPlace.values.toSet(),
              own: _s5,
              second: const [MarketPromoPlan(kind: MarketPromoKind.premium, qty: 5, price: 25, currency: 'USD')]),
          isNull);
      expect(promoPlacesWire({PromoPlace.loads, PromoPlace.market}), ['market', 'loads']);
    });
  });

  group('the Premium sheet of a park / service / shop', () {
    testWidgets('TIR Bazarı · Yüklər bölməsi side by side; nothing chosen at first = no order', (tester) async {
      final t = await _open(tester, MarketPromoKind.premium);
      final a = tester.getRect(find.byKey(const ValueKey('promo-place-market')));
      final b = tester.getRect(find.byKey(const ValueKey('promo-place-loads')));
      expect(a.top, b.top, reason: 'side by side');
      expect(b.left, greaterThan(a.right));
      expect(find.text('TIR Bazarı'), findsOneWidget);
      expect(find.text('Yüklər bölməsi'), findsOneWidget);
      expect(find.byKey(const ValueKey('promo-places-none')), findsOneWidget);
      expect(_payButton(tester).onPressed, isNull);
      await tester.tap(find.byKey(const ValueKey('promo-pay')), warnIfMissed: false);
      expect(t.orders, 0);
    });

    testWidgets('one place: its own price; the order carries that place', (tester) async {
      final t = await _open(tester, MarketPromoKind.premium);
      await tester.tap(find.byKey(const ValueKey('promo-place-loads')));
      await tester.pump();
      expect(find.text('Seçilmiş yerlər: Yüklər bölməsi'), findsOneWidget);
      expect(find.text('Yekun məbləğ: 20.00 AZN'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('promo-pay')));
      await tester.pumpAndSettle();
      expect(t.orders, 1);
      expect(t.orderedPlaces, {PromoPlace.loads});
    });

    testWidgets('both: the places and the total before paying; the order carries them', (tester) async {
      final t = await _open(tester, MarketPromoKind.premium);
      await tester.tap(find.byKey(const ValueKey('promo-place-market')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('promo-place-loads')));
      await tester.pump();
      expect(find.text('Seçilmiş yerlər: TIR Bazarı + Yüklər bölməsi'), findsOneWidget);
      expect(find.text('Yekun məbləğ: 45.00 AZN'), findsOneWidget);
      expect(find.textContaining('45.00 AZN'), findsWidgets, reason: 'the pay button shows the total');
      await tester.tap(find.byKey(const ValueKey('promo-pay')));
      await tester.pumpAndSettle();
      expect(t.orderedPlaces, PromoPlace.values.toSet());
    });

    testWidgets('both for days Yüklər does not sell: said plainly, blocked', (tester) async {
      await _open(tester, MarketPromoKind.premium);
      await tester.tap(find.byKey(const ValueKey('promo-plan-premium-30')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('promo-place-market')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('promo-place-loads')));
      await tester.pump();
      expect(find.byKey(const ValueKey('promo-places-missing')), findsOneWidget);
      expect(_payButton(tester).onPressed, isNull);
    });

    testWidgets('VIP, and a TIR Bazarı ad\'s Premium: no place cards', (tester) async {
      await _open(tester, MarketPromoKind.vip);
      expect(find.byKey(const ValueKey('promo-place-market')), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await _open(tester, MarketPromoKind.premium, places: false);
      expect(find.byKey(const ValueKey('promo-place-market')), findsNothing);
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

  test('the ad card\'s place line: city · distance, only what is known', () {
    expect(placeAdWhere('Bakı', 5), 'Bakı · 5.0 km');
    expect(placeAdWhere('Bakı', 23.4), 'Bakı · 23 km');
    expect(placeAdWhere('Bakı', null), 'Bakı');
    expect(placeAdWhere(null, null), '');
    expect(firstLine('\n  24/7 təmir və texniki yardım\nikinci'), '24/7 təmir və texniki yardım');
    expect(firstLine('  '), isNull);
  });

  testWidgets('the ad card (owner\'s picture): REKLAM, name, about, city, "Profilə bax" opens the page; swiped with dots', (tester) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    const svc = ServiceProvider(
      id: 's1', ownerId: 'u9', kind: 'center', name: 'Yolüstü TIR Servisi', categories: ['engine'], lat: 40.4, lng: 49.8,
      isMobile: false, is24h: true, isActive: true, status: 'approved', isVerified: false, addedByAdmin: false,
      photos: [], ratingAvg: 0, ratingCount: 0, description: '24/7 təmir və texniki yardım',
    );
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (c, st) => Scaffold(body: ListView(children: [PlaceCrossStrip(s: _az, place: 'market')]))),
      GoRoute(path: '/service/:id', builder: (c, st) => Text('page ${st.pathParameters['id']}')),
    ]);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        placeCrossProvider('market').overrideWith((ref) async => const [
              PlaceCrossItem(kind: 'service', id: 's1', name: 'Yolüstü TIR Servisi', city: 'Bakı'),
              PlaceCrossItem(kind: 'service', id: 's2', name: 'Hissə Mağazası', city: 'Sumqayıt', shop: true),
            ]),
        serviceByIdProvider('s1').overrideWith((ref) async => svc),
        serviceByIdProvider('s2').overrideWith((ref) async => null),
        placeMediaProvider((CoverSection.service, 's1')).overrideWith((ref) async => const PlaceMedia()),
        placeMediaProvider((CoverSection.service, 's2')).overrideWith((ref) async => const PlaceMedia()),
      ],
      child: MaterialApp.router(routerConfig: router),
    ));
    await tester.pumpAndSettle();
    expect(find.text('REKLAM'), findsOneWidget);
    expect(find.text('Yolüstü TIR Servisi'), findsOneWidget);
    expect(find.text('24/7 təmir və texniki yardım'), findsOneWidget);
    expect(find.text('Bakı'), findsOneWidget, reason: 'no GPS asked here: the city only');
    expect(find.text('Profilə bax'), findsOneWidget);
    final card = tester.getRect(find.byKey(const ValueKey('place-ad-s1')));
    expect(card.width, greaterThan(350), reason: 'one big card across the page');
    expect(card.height, lessThanOrEqualTo(92), reason: 'the owner\'s size: a low card, then 20 % smaller (07.11.2026)');
    await tester.drag(find.byKey(const ValueKey('place-ad-s1')), const Offset(-300, 0));
    await tester.pumpAndSettle();
    expect(find.text('Hissə Mağazası'), findsOneWidget, reason: 'the next ad is swiped in');
    await tester.drag(find.byKey(const ValueKey('place-ad-s2')), const Offset(300, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('place-ad-open-s1')));
    await tester.pumpAndSettle();
    expect(find.text('page s1'), findsOneWidget);
  });

  testWidgets('the ad card keeps its size and never overflows with big text (step 5 = 125 %)', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        placeCrossProvider('loads').overrideWith((ref) async => const [
              PlaceCrossItem(kind: 'service', id: 's9', name: 'Çox uzun adlı yolüstü TIR təmir servisi', city: 'Sumqayıt'),
            ]),
        serviceByIdProvider('s9').overrideWith((ref) async => null),
        placeMediaProvider((CoverSection.service, 's9')).overrideWith((ref) async => const PlaceMedia()),
      ],
      child: MaterialApp(
        builder: (c, child) => MediaQuery(data: MediaQuery.of(c).copyWith(textScaler: const TextScaler.linear(1.25)), child: child!),
        home: Scaffold(body: ListView(children: [PlaceCrossStrip(s: _az, place: 'loads')])),
      ),
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(tester.getRect(find.byKey(const ValueKey('place-ad-s9'))).height, lessThanOrEqualTo(116));
  });

  test('wired: places to the server, strips on TIR Bazarı and Yüklər (not on the maps), SQL 0103', () {
    final pp = src('lib/features/promo/place_promo.dart');
    expect(pp, contains("if (places != null) 'p_places': places,"));
    expect(pp, contains('places: kind == MarketPromoKind.premium && places != null ? promoPlacesWire(places) : null'));
    expect(pp, contains('cargoPromoPlansProvider((MarketPromoKind.premium, true))'), reason: 'both = + the Yüklər price');
    expect(src('lib/features/cargo/presentation/cargo_marketplace_screen.dart'), contains("PlaceCrossStrip(s: strings, place: 'loads'),"));
    expect(src('lib/features/market/presentation/market_home_screen.dart'), contains("PlaceCrossStrip(s: s, place: 'market'),"));
    expect(src('lib/features/tirpark/presentation/tir_park_screen.dart').contains('PlaceCrossStrip'), isFalse);
    expect(src('lib/features/services/presentation/services_map_screen.dart').contains('PlaceCrossStrip'), isFalse);
    final sql = src('supabase/migrations/0103_place_premium_tir_bazari_loads.sql');
    expect(sql, contains("p_places <@ array['market', 'loads']"));
    expect(sql, contains('v_amount := v_plan.price + v_loads.price;'));
    expect(sql, contains("raise exception 'places_not_available'"));
    expect(sql.toLowerCase().contains('delete from'), isFalse);
    expect(sql.toLowerCase().contains('drop table'), isFalse);
  });

  test('a load takes no advertising: no "Önə çıxar" on a load, no TIR Bazarı ads in Yüklər', () {
    expect(File('lib/features/cargo/presentation/widgets/cargo_promo.dart').existsSync(), isFalse);
    expect(src('lib/features/cargo/presentation/my_cargo_screen.dart').contains('my-cargo-promo'), isFalse);
    expect(src('lib/features/cargo/presentation/cargo_detail_screen.dart').contains('cargo-promo-open'), isFalse);
    expect(src('lib/features/cargo/presentation/cargo_marketplace_screen.dart').contains('CrossPremium'), isFalse);
    expect(PromoPlace.values.map((p) => p.name), ['market', 'loads']);
    final sql = src('supabase/migrations/0102_place_premium_places.sql');
    expect(sql, contains("raise exception 'not_available' using errcode = '42501';"));
    expect(sql, contains("if p_kind = 'premium' and (p_places is null or p_places <> array['market']) then"));
  });
}
