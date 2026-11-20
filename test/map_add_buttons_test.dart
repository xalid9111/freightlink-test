// The "+" on each map opens its own form (owner, 06.11.2026): Servislər →
// the service registration, Mağazalar → the shop form (spare_parts ticked).
// Parklar (owner, 20.11.2026, SQL 0129): "TIR parkı əlavə et +" → the user
// moves the map under the pin → name, city, amenities → shown at once.
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
        GoRoute(path: '/tirpark', builder: (c, st) => const TirParkScreen(), routes: [
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

  testWidgets('Parklar: "TIR parkı əlavə et +" → pick the place on the map → the form → saved (0129)', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final repo = _FakeParks();
    await tester.pumpWidget(app(router('/tirpark'), repo));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const ValueKey('tp-list')), findsOneWidget, reason: 'the parks list');
    // A round + (its words as a tooltip) on the right over the list (owner, 20.11.2026).
    expect(find.byTooltip('TIR parkı əlavə et'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('tp-add')));
    await tester.pump(const Duration(milliseconds: 300));
    // Choosing the place: the pin in the middle, the list out of the way.
    expect(find.byKey(const ValueKey('tp-add-pin')), findsOneWidget);
    expect(find.byKey(const ValueKey('tp-list')), findsNothing);
    expect(find.text('TIR Parkı page'), findsNothing, reason: 'no longer the management page');
    await tester.tap(find.byKey(const ValueKey('tp-add-here')));
    await tester.pumpAndSettle(const Duration(milliseconds: 100), EnginePhase.sendSemanticsUpdate, const Duration(seconds: 5));
    await tester.enterText(find.byKey(const ValueKey('tp-name')), 'Qobu TIR Parkı');
    await tester.ensureVisible(find.byKey(const ValueKey('tp-save')));
    await tester.tap(find.byKey(const ValueKey('tp-save')));
    await tester.pumpAndSettle(const Duration(milliseconds: 100), EnginePhase.sendSemanticsUpdate, const Duration(seconds: 5));
    expect(repo.added, ['Qobu TIR Parkı']);
    expect(find.byKey(const ValueKey('tp-add-pin')), findsNothing, reason: 'back to the map and the list');
    expect(find.byKey(const ValueKey('tp-list')), findsOneWidget);
  });

  testWidgets('Parklar: "Ləğv et" leaves the place picking without saving', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final repo = _FakeParks();
    await tester.pumpWidget(app(router('/tirpark'), repo));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byKey(const ValueKey('tp-add')));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byKey(const ValueKey('tp-add-cancel')));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const ValueKey('tp-add-pin')), findsNothing);
    expect(repo.added, isEmpty);
  });

  test('Profil → TIR Parkı: no "Dayanacaq əlavə et" (owner, 07.11.2026)', () {
    final p = src('lib/features/auth/presentation/profile_screen.dart');
    expect(p.contains('pf-tirpark-stop'), isFalse);
    expect(p.contains("'tp_stop_add'"), isFalse);
  });

  test('server: tir_park_add works again (0129): checks, shown at once, nothing deleted', () {
    final sql = src('supabase/migrations/0129_users_add_parks.sql');
    expect(sql, contains("raise exception 'duplicate_nearby'"));
    expect(sql, contains("raise exception 'too_many'"));
    expect(sql, contains("raise exception 'name_required'"));
    expect(sql, contains("v_uid, 'approved', now())"), reason: 'shown at once');
    expect(sql.contains('not_available'), isFalse);
    final lower = sql.toLowerCase();
    for (final bad in ['delete from', 'drop table', 'truncate', 'alter table']) {
      expect(lower.contains(bad), isFalse, reason: bad);
    }
    final tp = src('lib/features/tirpark/presentation/tir_park_screen.dart');
    expect(tp, contains('TirParkAddSheet(lat: c.latitude, lng: c.longitude, s: s)'));
    expect(tp, contains("MapAddRoundButton(buttonKey: 'tp-add', tooltip: s.t('tp_add'), onTap: _startAdding)"));
    expect(tp, contains('if (askSignIn(context)) return;'), reason: 'a visitor signs in first');
    expect(src('lib/core/router/app_router.dart'), contains('builder: (context, state) => const NavRoom(child: TirParkScreen()),'));
  });

  test('no admin approval for services, shops and parking spots (0099); "Park işlədirəm" keeps it', () {
    final sql = src('supabase/migrations/0099_no_admin_approval_services_spots.sql');
    expect(sql, contains('create trigger zz_service_publish before insert or update on public.service_providers'));
    expect(sql, contains("v_uid, 'approved', now())"), reason: 'a parking spot is shown at once');
    expect(sql, contains("where status = 'pending' and manager_id is null;"), reason: 'a manager application keeps waiting');
    expect(sql.toLowerCase().contains('tir_park_owner_apply'), isFalse, reason: 'the park owner request flow is untouched');
  });

  test('Servislər "+" → the registration page; Mağazalar "+" → the shop form; routes kept', () {
    final svc = src('lib/features/services/presentation/services_map_screen.dart');
    expect(svc, contains("const kServiceAddRoute = '/service-join';"));
    // Mağaza: the shop kind first (owner, 09.11.2026), then the same shop form.
    expect(svc, contains("const kShopAddRoute = '/shop-join';"));
    expect(svc, contains('onTap: () => context.pushOnce(widget.shops ? kShopAddRoute : kServiceAddRoute),'));
    final r = src('lib/core/router/app_router.dart');
    expect(r, contains("path: '/service-join'"));
    expect(r, contains("shop: state.uri.queryParameters['shop'] == '1'"));
    expect(r, contains("GoRoute(path: 'bookings'"), reason: 'the bookings screen itself unchanged');
  });
}
