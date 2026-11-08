// "Mağaza əlavə et" (owner, 09.11.2026): on Mağazalar the add button opens
// the shop kind picker (same look as "Usta / Servis kimi qoşul"): "Mağaza"
// → the existing shop form, "İşlənmiş ehtiyat hissələri" → the same form
// with that kind ticked. Servislər keeps "Usta kimi qoşul" → /service-join.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freightlink/core/localization/app_strings.dart';
import 'package:freightlink/core/localization/locale_controller.dart';
import 'package:freightlink/features/services/presentation/service_edit_screen.dart';
import 'package:go_router/go_router.dart';

String src(String p) => File(p).readAsStringSync();
final _az = AppStrings(Map<String, String>.from(jsonDecode(src('assets/i18n/az.json')) as Map));

void main() {
  Future<GoRouter> pump(WidgetTester tester) async {
    final r = GoRouter(initialLocation: '/start', routes: [
      GoRoute(
        path: '/start',
        builder: (c, st) => Scaffold(body: TextButton(onPressed: () => c.push('/shop-join'), child: const Text('open'))),
      ),
      GoRoute(path: '/shop-join', builder: (c, st) => const ShopJoinScreen()),
      GoRoute(
        path: '/service-edit',
        builder: (c, st) => Scaffold(body: Text('form shop=${st.uri.queryParameters['shop']} kind=${st.uri.queryParameters['shopKind']}')),
      ),
    ]);
    await tester.pumpWidget(ProviderScope(
      overrides: [stringsProvider.overrideWithValue(_az)],
      child: MaterialApp.router(routerConfig: r),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return r;
  }

  testWidgets('the picker: title, intro and the two choices in the join-page look', (tester) async {
    await pump(tester);
    expect(find.text('Mağaza əlavə et'), findsOneWidget);
    expect(find.text(_az.t('shop_join_intro')), findsOneWidget);
    expect(find.descendant(of: find.byKey(const ValueKey('shop-join-shop')), matching: find.text('Mağaza')), findsOneWidget);
    expect(find.descendant(of: find.byKey(const ValueKey('shop-join-used')), matching: find.text('İşlənmiş ehtiyat hissələri')), findsOneWidget);
    expect(find.byType(Card), findsNWidgets(2), reason: 'the same cards as "Usta / Servis kimi qoşul"');
  });

  testWidgets('"Mağaza" → the existing shop form, nothing pre-ticked', (tester) async {
    await pump(tester);
    await tester.tap(find.byKey(const ValueKey('shop-join-shop')));
    await tester.pumpAndSettle();
    expect(find.text('form shop=1 kind=null'), findsOneWidget);
  });

  testWidgets('"İşlənmiş ehtiyat hissələri" → the same shop form with shop_used ticked', (tester) async {
    await pump(tester);
    await tester.tap(find.byKey(const ValueKey('shop-join-used')));
    await tester.pumpAndSettle();
    expect(find.text('form shop=1 kind=shop_used'), findsOneWidget);
  });

  test('wired: both buttons go to their own page; the form ticks only shop_* kinds', () {
    final svc = src('lib/features/services/presentation/services_map_screen.dart');
    expect(svc, contains("const kServiceAddRoute = '/service-join';"));
    expect(svc, contains("const kShopAddRoute = '/shop-join';"));
    expect(svc, contains('onTap: () => context.pushOnce(widget.shops ? kShopAddRoute : kServiceAddRoute),'), reason: 'the map +');
    expect(svc, contains("onPressed: () => context.pushOnce(hasMine ? '/service/\${mine.valueOrNull!.id}' : (shops ? kShopAddRoute : kServiceAddRoute)),"),
        reason: 'the list button: "Usta kimi qoşul" / "Mağaza əlavə et"');
    final r = src('lib/core/router/app_router.dart');
    expect(r, contains("path: '/shop-join',"));
    expect(r, contains("initialShopKind: state.uri.queryParameters['shopKind'])),"));
    final form = src('lib/features/services/presentation/service_edit_screen.dart');
    expect(form, contains('kShopKindOrder.contains(widget.initialShopKind)'));
    expect(ShopJoinScreen.shopRoute, '/service-edit?kind=center&shop=1');
    expect(ShopJoinScreen.usedRoute, '/service-edit?kind=center&shop=1&shopKind=shop_used');
  });
}
