// The "+" on each map opens its own form (owner, 06.11.2026): Servislər →
// the service registration, Mağazalar → the shop form (spare_parts ticked),
// Parklar → the TIR Parkı page; TIR Parkı → "Dayanacaq əlavə et" places a
// plain parking spot on the map (the existing tir_park_add, no manager, so
// no booking / capacity / owner panel); a park already there opens.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freightlink/core/localization/app_strings.dart';
import 'package:freightlink/core/localization/locale_controller.dart';
import 'package:freightlink/features/tirpark/data/tir_park_repository.dart';
import 'package:freightlink/features/tirpark/domain/tir_park.dart';
import 'package:freightlink/features/tirpark/presentation/tir_park_screen.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

String src(String p) => File(p).readAsStringSync();
final _az = AppStrings(Map<String, String>.from(jsonDecode(src('assets/i18n/az.json')) as Map));

class _FakeParks extends TirParkRepository {
  List<NearbyPark> nearby = const [];
  final added = <String>[];
  @override
  Future<List<NearbyPark>> near(double lat, double lng, {int radiusM = 500}) async => nearby;
  @override
  Future<String> add({required String name, required double lat, required double lng, String? city, List<String> amenities = const [], String? note}) async {
    added.add(name);
    return 'new';
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  GoRouter router(String initial) => GoRouter(initialLocation: initial, routes: [
        GoRoute(path: '/tirpark', builder: (c, st) => TirParkScreen(addRequest: st.uri.queryParameters['add']), routes: [
          GoRoute(path: 'p/:id', builder: (c, st) => Scaffold(body: Text('park ${st.pathParameters['id']}'))),
        ]),
        GoRoute(path: '/profile/tirpark', builder: (c, st) => const Scaffold(body: Text('TIR Parkı page'))),
      ]);

  Widget app(GoRouter r, _FakeParks repo) => ProviderScope(
        overrides: [
          stringsProvider.overrideWithValue(_az),
          tirParkRepositoryProvider.overrideWithValue(repo),
          tirParksProvider.overrideWith((ref) async => const <TirPark>[]),
        ],
        child: MaterialApp.router(routerConfig: r),
      );

  testWidgets('Parklar: "TIR parkı əlavə et" opens the TIR Parkı page, back returns to the map', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final r = router('/tirpark');
    await tester.pumpWidget(app(r, _FakeParks()));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byKey(const ValueKey('tp-add')));
    await tester.pumpAndSettle();
    expect(find.text('TIR Parkı page'), findsOneWidget);
    r.pop();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('tp-add')), findsOneWidget);
    expect(find.byKey(const ValueKey('tp-add-here')), findsNothing, reason: 'no park placing from the map "+"');
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('Dayanacaq əlavə et: place on the map → name → saved as a plain spot', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final repo = _FakeParks();
    await tester.pumpWidget(app(router('/tirpark?add=1'), repo));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byKey(const ValueKey('tp-add-here')));
    await tester.pumpAndSettle();
    expect(find.text('Yeni dayanacaq'), findsOneWidget);
    expect(find.text(_az.t('tp_stop_hint')), findsOneWidget, reason: 'no booking / capacity / owner said plainly');
    await tester.enterText(find.byKey(const ValueKey('tp-name')), 'Ələt yolu dayanacağı');
    await tester.ensureVisible(find.byKey(const ValueKey('tp-save')));
    await tester.tap(find.byKey(const ValueKey('tp-save')));
    await tester.pumpAndSettle();
    expect(repo.added, ['Ələt yolu dayanacağı']);
    expect(find.text(_az.t('tp_stop_sent')), findsOneWidget);
    expect(find.byKey(const ValueKey('tp-add-here')), findsNothing, reason: 'back on the map');
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('a park already there: shown, a tap opens it, nothing is added', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final repo = _FakeParks()..nearby = const [NearbyPark(id: 'p9', name: 'Utep TIR Parkı', status: 'approved', distanceM: 30)];
    await tester.pumpWidget(app(router('/tirpark?add=1'), repo));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byKey(const ValueKey('tp-add-here')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Utep TIR Parkı'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('tp-nearby-p9')));
    await tester.pumpAndSettle();
    expect(find.text('park p9'), findsOneWidget);
    expect(repo.added, isEmpty);
    await tester.pump(const Duration(seconds: 1));
  });

  test('no admin approval for services, shops and parking spots (0099); "Park işlədirəm" keeps it', () {
    final sql = src('supabase/migrations/0099_no_admin_approval_services_spots.sql');
    expect(sql, contains('create trigger zz_service_publish before insert or update on public.service_providers'));
    expect(sql, contains("v_uid, 'approved', now())"), reason: 'a parking spot is shown at once');
    expect(sql, contains("where status = 'pending' and manager_id is null;"), reason: 'a manager application keeps waiting');
    expect(sql.toLowerCase().contains('tir_park_owner_apply'), isFalse, reason: 'the park owner request flow is untouched');
    expect(_az.t('tp_stop_sent'), contains('xəritədə'));
  });

  test('Servislər "+" → the registration page; Mağazalar "+" → the shop form; routes kept', () {
    final svc = src('lib/features/services/presentation/services_map_screen.dart');
    expect(svc, contains("const kServiceAddRoute = '/service-join';"));
    expect(svc, contains("const kShopAddRoute = '/service-edit?kind=center&shop=1';"));
    expect(svc, contains('onTap: () => context.pushOnce(widget.shops ? kShopAddRoute : kServiceAddRoute),'));
    final r = src('lib/core/router/app_router.dart');
    expect(r, contains("path: '/service-join'"));
    expect(r, contains("shop: state.uri.queryParameters['shop'] == '1'"));
    expect(r, contains("GoRoute(path: 'bookings'"), reason: 'the bookings screen itself unchanged');
  });
}
