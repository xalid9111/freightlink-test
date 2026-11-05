// Premium map markers (owner, 05.11.2026): the owner's three icons (park,
// service, shop), 20 % bigger, dropped once onto their own point after the
// map is ready (+1 s), one after another, with a squash and one small bounce.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freightlink/core/localization/app_strings.dart';
import 'package:freightlink/features/promo/premium_pin.dart';
import 'package:freightlink/features/tirpark/presentation/tir_park_widgets.dart';

String src(String p) => File(p).readAsStringSync();
final _az = AppStrings(Map<String, String>.from(jsonDecode(src('assets/i18n/az.json')) as Map));

void main() {
  test('the three icons are in the app', () {
    for (final k in PremiumPinKind.values) {
      expect(File(k.asset).existsSync(), isTrue, reason: k.asset);
    }
    expect(src('pubspec.yaml'), contains('- assets/images/premium/'));
  });

  test('20 % bigger than the ordinary markers (their circles)', () {
    // The icon's ring is ~72 % of the picture: 64 × 0.72 ≈ 46 ≈ 38 × 1.2 (service) / 36 × 1.2 (park, 43).
    expect(kPremiumPinSize * 0.72, closeTo(38 * 1.2, 2));
    expect(kPremiumPinSelectedSize, greaterThan(kPremiumPinSize));
  });

  test('a shop is a service that sells spare parts', () {
    expect(premiumKindOfService(['truck_repair', 'spare_parts']), PremiumPinKind.shop);
    expect(premiumKindOfService(['engine']), PremiumPinKind.service);
  });

  test('the drop: from a little above, onto the point, squash, one small bounce, rest', () {
    final (dy0, _, _, op0) = PremiumDrop.at(0);
    expect(dy0, -PremiumDrop.fallPx);
    expect(op0, 0, reason: 'hidden before it starts');
    expect(PremiumDrop.fallPx, lessThan(60), reason: 'a short fall near its point, never from the screen edge');
    final (dyLand, _, _, _) = PremiumDrop.at(0.55);
    expect(dyLand, closeTo(0, 0.001), reason: 'lands on its own point');
    final (_, sx, sy, _) = PremiumDrop.at(0.625);
    expect(sx, greaterThan(1));
    expect(sy, lessThan(1), reason: 'squashed');
    final (dyUp, _, _, _) = PremiumDrop.at(0.85);
    expect(dyUp, closeTo(-PremiumDrop.bouncePx, 0.001), reason: 'one small bounce');
    final (dyEnd, sxEnd, syEnd, opEnd) = PremiumDrop.at(1);
    expect((dyEnd, sxEnd, syEnd, opEnd), (0.0, 1.0, 1.0, 1.0), reason: 'settled');
    // Never more than one bounce: the height rises only once after landing.
    var ups = 0;
    var last = 0.0;
    for (var t = 0.56; t <= 1.0; t += 0.01) {
      final (dy, _, _, _) = PremiumDrop.at(t);
      if (dy < last - 0.01 && (ups == 0 || last >= -0.01)) ups++;
      last = dy;
    }
    expect(ups, 1);
  });

  test('one after another; many markers do not wait forever', () {
    expect(PremiumDrop.local(0, 0), 0);
    expect(PremiumDrop.local(0.2, 0), greaterThan(PremiumDrop.local(0.2, 1)));
    expect(PremiumDrop.local(0.2, 30), PremiumDrop.local(0.2, PremiumDrop.maxStagger));
    expect(PremiumDrop.local(1, 30), 1, reason: 'all settled at the end');
  });

  testWidgets('hidden before the start; shown still if it came later', (tester) async {
    final clock = AnimationController(vsync: const TestVSync(), duration: PremiumDrop.total);
    addTearDown(clock.dispose);
    const pin = SizedBox(key: ValueKey('pin'), width: 10, height: 10);
    await tester.pumpWidget(MaterialApp(home: PremiumDropIn(clock: clock, started: false, index: 0, child: pin)));
    expect(tester.widget<Opacity>(find.ancestor(of: find.byKey(const ValueKey('pin')), matching: find.byType(Opacity))).opacity, 0);
    await tester.pumpWidget(MaterialApp(home: PremiumDropIn(clock: clock, started: true, index: null, child: pin)));
    expect(find.byType(Opacity), findsNothing, reason: 'no animation for one that came after the start');
  });

  testWidgets('Premium label under the icon; the switch: Parklar | Servislər | Mağazalar', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const PremiumMarker(kind: PremiumPinKind.park, label: 'Premium'),
            const SizedBox(height: 40),
            ParksServicesSwitch(parks: false, shops: true, s: _az, onParks: () {}, onServices: () {}, onShops: () {}),
          ]),
        ),
      ),
    ));
    expect(find.byKey(const ValueKey('premium-pin-park')), findsOneWidget);
    expect(find.text('Premium'), findsOneWidget);
    for (final k in ['tp-tab-parks', 'tp-tab-services', 'tp-tab-shops']) {
      expect(find.byKey(ValueKey(k)), findsOneWidget, reason: k);
    }
    expect(find.text('Mağazalar'), findsOneWidget);
  });

  test('wired: only promoted places, real points, once per visit, filters kept', () {
    final tp = src('lib/features/tirpark/presentation/tir_park_screen.dart');
    expect(tp, contains('premiumMapReady();'));
    expect(tp, contains('bool _premium(TirPark p, Map<String, PlacePromo> promos) => p.isApproved && (promos[p.id]?.isPromoted ?? false);'));
    expect(tp, contains('point: LatLng(p.lat, p.lng),'));
    expect(tp, contains("onShops: () => context.go('/services?shops=1')"));
    final svc = src('lib/features/services/presentation/services_map_screen.dart');
    expect(svc, contains('premiumMapReady();'));
    expect(svc, contains('kind: premiumKindOfService(p.categories),'));
    expect(svc, contains("const kShopCategory = 'spare_parts';"));
    expect(svc, contains('if (hasRealCoords(p.lat, p.lng) && !_premium(p, promos)) p'), reason: 'premium never clustered');
    final host = src('lib/features/promo/premium_pin.dart');
    expect(host, contains('Timer(const Duration(seconds: 1)'), reason: '1 s after the map is ready');
    expect(host, contains('if (premiumStarted || !_dropReady || promotedIds == null) return;'), reason: 'once per visit');
    expect(src('lib/core/router/app_router.dart'), contains("ServicesMapScreen(shops: state.uri.queryParameters['shops'] == '1')"));
  });
}
