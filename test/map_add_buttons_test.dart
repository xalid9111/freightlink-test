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

  testWidgets('Parklar: "TIR parkı əlavə et +" stays on the map and opens the TIR Parkı page; no spot placing, an old ?add= link does nothing (0100)', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final repo = _FakeParks();
    await tester.pumpWidget(app(router('/tirpark?add=1'), repo));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const ValueKey('tp-add-here')), findsNothing, reason: 'no "place a spot" mode');
    expect(find.byKey(const ValueKey('tp-list')), findsOneWidget, reason: 'the parks list stays');
    expect(find.byKey(const ValueKey('tp-add')), findsOneWidget);
    expect(find.text('TIR parkı əlavə et'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('tp-add')));
    await tester.pumpAndSettle(const Duration(milliseconds: 100), EnginePhase.sendSemanticsUpdate, const Duration(seconds: 5));
    expect(find.text('TIR Parkı page'), findsOneWidget);
    expect(repo.added, isEmpty);
  });

  test('Profil → TIR Parkı: no "Dayanacaq əlavə et" (owner, 07.11.2026)', () {
    final p = src('lib/features/auth/presentation/profile_screen.dart');
    expect(p.contains('pf-tirpark-stop'), isFalse);
    expect(p.contains("'tp_stop_add'"), isFalse);
  });

  test('server: tir_park_add refuses everybody (0100); the park owner and manager flows stay', () {
    final sql = src('supabase/migrations/0100_no_user_spots_service_chat_context.sql');
    expect(sql, contains("raise exception 'not_available' using errcode = '42501';"));
    expect(sql.contains('function public.tir_park_owner_apply'), isFalse, reason: '"Park işlədirəm" untouched');
    expect(sql.contains('function public.tir_park_manage_apply'), isFalse, reason: 'manager applications untouched');
    expect(sql.toLowerCase().contains('delete from'), isFalse, reason: 'nothing is deleted');
    final tp = src('lib/features/tirpark/presentation/tir_park_screen.dart');
    expect(tp.contains('TirParkAddSheet'), isFalse);
    expect(tp, contains("onTap: () => context.pushOnce('/profile/tirpark'),"), reason: 'the map + opens the TIR Parkı page');
    expect(src('lib/core/router/app_router.dart'), contains('builder: (context, state) => const TirParkScreen(),'));
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
    expect(svc, contains("const kShopAddRoute = '/service-edit?kind=center&shop=1';"));
    expect(svc, contains('onTap: () => context.pushOnce(widget.shops ? kShopAddRoute : kServiceAddRoute),'));
    final r = src('lib/core/router/app_router.dart');
    expect(r, contains("path: '/service-join'"));
    expect(r, contains("shop: state.uri.queryParameters['shop'] == '1'"));
    expect(r, contains("GoRoute(path: 'bookings'"), reason: 'the bookings screen itself unchanged');
  });
}
