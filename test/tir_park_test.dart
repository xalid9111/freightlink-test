// TIRPark (owner, 31.10.2026, migration 0077): parks on the map, nearby
// list, add with the duplicate check, admin approval, the tab in place of
// Servislər (which opens from TIRPark).
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freightlink/core/localization/app_strings.dart';
import 'package:freightlink/core/localization/locale_controller.dart';
import 'package:freightlink/features/tirpark/data/tir_park_repository.dart';
import 'package:freightlink/features/tirpark/domain/tir_park.dart';
import 'package:freightlink/features/tirpark/presentation/tir_park_add_sheet.dart';
import 'package:freightlink/features/tirpark/presentation/tir_park_screen.dart';
import 'package:freightlink/features/tirpark/presentation/tir_park_widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

String src(String p) => File(p).readAsStringSync();
final _az = AppStrings(Map<String, String>.from(jsonDecode(src('assets/i18n/az.json')) as Map));

const _utep = TirPark(
    id: 'p1', name: 'Utep TIR Parkı', lat: 40.4560, lng: 49.7300, city: 'Xırdalan', amenities: ['secure', '24_7', 'food', 'wc'], status: 'approved');
const _mine = TirPark(id: 'p2', name: 'Yeni park', lat: 40.50, lng: 49.90, status: 'pending');
const _far = TirPark(id: 'p3', name: 'Gəncə Park', lat: 40.68, lng: 46.36, city: 'Gəncə', status: 'approved', amenities: ['fuel']);

class _FakeRepo extends TirParkRepository {
  List<NearbyPark> nearby = const [];
  final added = <String>[];
  @override
  Future<List<NearbyPark>> near(double lat, double lng, {int radiusM = 500}) async => nearby;
  @override
  Future<String> add({required String name, required double lat, required double lng, String? city, List<String> amenities = const [], String? note}) async {
    added.add('$name|${amenities.join(",")}');
    return 'new';
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('distance, nearby list (100 km, nearest first), search and amenities filter', () {
    expect(distanceKm(40.4093, 49.8671, 40.4560, 49.7300), closeTo(12.5, 0.6));
    final near = nearbyParks([_far, _utep, _mine], 40.4093, 49.8671);
    expect([for (final e in near) e.$1.id], ['p2', 'p1'], reason: 'nearest first; Gəncə (~300 km) is out');
    expect(nearbyParks([_far, _utep], 40.4, 49.8, query: 'gəncə').single.$1.id, 'p3', reason: 'search finds far parks too');
    expect(nearbyParks([_utep, _mine], 40.4, 49.8, needs: {'food'}).single.$1.id, 'p1');
    expect(distanceLabel(0.85), '850 m');
    expect(distanceLabel(2.54), '2.5 km');
    final p = TirPark.fromJson({'id': 'x', 'name': 'A', 'lat': '40.1', 'lng': 49, 'amenities': ['wc'], 'status': 'approved', 'rating_avg': 4.7, 'rating_count': 12});
    expect([p.lat, p.isApproved, p.ratingCount], [40.1, true, 12]);
    expect(kTirParkAmenities, containsAll(['secure', '24_7', 'food']));
  });

  testWidgets('the card: name, place · distance, amenities; pending shown; no stars before anybody rated', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Column(children: [
          TirParkCard(park: _utep, km: 2.5, s: _az, onTap: () {}),
          TirParkCard(park: _mine, km: 8, s: _az, onTap: () {}),
        ]),
      ),
    ));
    for (final t in ['Utep TIR Parkı', 'Xırdalan · 2.5 km', 'Təhlükəsiz', '24/7', 'Yemək', '+1', 'Təsdiq gözləyir']) {
      expect(find.text(t), findsWidgets, reason: t);
    }
    expect(find.byIcon(Icons.star_rounded), findsNothing, reason: 'no fake rating');
  });

  testWidgets('the page: banner, search, Parklar | Servislər, add button, nearby list', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        stringsProvider.overrideWithValue(_az),
        tirParksProvider.overrideWith((ref) async => const [_utep, _mine, _far]),
      ],
      child: const MaterialApp(home: TirParkScreen()),
    ));
    await tester.pump(const Duration(milliseconds: 300));
    for (final t in ['TIR', 'Park', 'Yolda özünə uyğun', 'park tap', 'Parklar', 'Servislər', 'TIR parkı əlavə et', 'Yaxınlıqdakı TIR parkları', '2 park · 100 km']) {
      expect(find.text(t), findsWidgets, reason: t);
    }
    expect(find.byKey(const ValueKey('tp-pin-p1')), findsOneWidget);
    expect(find.byKey(const ValueKey('tp-card-p2')), findsOneWidget, reason: 'the nearest park first');
    // Add: the place pin and "Bu yeri seç".
    await tester.tap(find.byKey(const ValueKey('tp-add')));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const ValueKey('tp-add-here')), findsOneWidget);
    expect(find.text('Bu yeri seç'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('tp-add-cancel')));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const ValueKey('tp-add')), findsOneWidget);
  });

  testWidgets('the switch: the chosen side is orange and does nothing; the other one goes there', (tester) async {
    var went = '';
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Column(children: [
          ParksServicesSwitch(parks: true, s: _az, onParks: () => went = 'p', onServices: () => went = 's'),
          MapAddButton(buttonKey: 'x-add', label: 'Servis əlavə et', onTap: () => went = 'add'),
        ]),
      ),
    ));
    await tester.tap(find.byKey(const ValueKey('tp-tab-parks')));
    expect(went, '', reason: 'already on parks');
    await tester.tap(find.byKey(const ValueKey('tp-tab-services')));
    expect(went, 's');
    await tester.tap(find.byKey(const ValueKey('x-add')));
    expect(went, 'add');
  });

  testWidgets('adding: nearby parks are shown first; closer than 60 m cannot be sent', (tester) async {
    tester.view.physicalSize = const Size(390, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final repo = _FakeRepo()..nearby = const [NearbyPark(id: 'p1', name: 'Utep TIR Parkı', status: 'approved', distanceM: 40)];
    await tester.pumpWidget(ProviderScope(
      overrides: [tirParkRepositoryProvider.overrideWithValue(repo)],
      child: MaterialApp(home: Scaffold(body: TirParkAddSheet(lat: 40.456, lng: 49.73, s: _az))),
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('tp-nearby')), findsOneWidget);
    expect(find.text('• Utep TIR Parkı — 40 m'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.byKey(const ValueKey('tp-save'))).onPressed, isNull, reason: 'duplicate');

    final repo2 = _FakeRepo()..nearby = const [NearbyPark(id: 'p1', name: 'Utep TIR Parkı', status: 'approved', distanceM: 300)];
    await tester.pumpWidget(ProviderScope(
      key: UniqueKey(),
      overrides: [tirParkRepositoryProvider.overrideWithValue(repo2)],
      child: MaterialApp(home: Scaffold(body: TirParkAddSheet(lat: 40.46, lng: 49.74, s: _az))),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Yenə də əlavə et'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('tp-save')));
    await tester.pumpAndSettle();
    expect(find.text('Parkın adını yazın'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('tp-name')), 'Sumqayıt Park');
    await tester.tap(find.byKey(const ValueKey('tp-am-wc')));
    await tester.tap(find.byKey(const ValueKey('tp-am-secure')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('tp-save')));
    await tester.pumpAndSettle();
    expect(repo2.added, ['Sumqayıt Park|secure,wc'], reason: 'amenities in the fixed order');
  });

  test('wired: TIRPark tab in place of Servislər (kept, opened from TIRPark), admin approval, safe SQL', () {
    final shell = src('lib/core/router/main_shell.dart');
    expect(shell, contains("_NavItem(5, Icons.place_outlined, Icons.place, strings.t('nav_tirpark')),"));
    expect(shell.contains("strings.t('nav_services'))"), isFalse);
    expect(shell, contains("5: '/tirpark'"));
    final router = src('lib/core/router/app_router.dart');
    expect(router, contains("path: '/tirpark',"));
    expect(router, contains('builder: (context, state) => const TirParkScreen(),'));
    expect(router, contains("GoRoute(path: '/services', builder: (context, state) => const ServicesMapScreen()),"), reason: 'Servislər kept');
    expect(src('lib/features/tirpark/presentation/tir_park_screen.dart'), contains("onServices: () => context.go('/services')"));
    // The same switch on Servislər, back to the parks, and "Servis əlavə et" there (owner, 31.10.2026).
    final svc = src('lib/features/services/presentation/services_map_screen.dart');
    expect(svc, contains("ParksServicesSwitch(parks: false, s: s, onParks: () => context.go('/tirpark'), onServices: () {}),"));
    expect(svc, contains("buttonKey: 'svc-add',"));
    // Same map colours on both pages, and "Servis əlavə et" low, right
    // above the list, like "TIR parkı əlavə et" (owner, 31.10.2026).
    expect(svc, contains('const ParkMapTiles(),'));
    expect(svc.contains('const AppTileLayer(),'), isFalse);
    expect(src('lib/features/tirpark/presentation/tir_park_screen.dart'), contains('const ParkMapTiles(),'));
    final add = svc.indexOf("buttonKey: 'svc-add',");
    expect(svc.lastIndexOf('height * 0.30 + 10,', add), greaterThan(svc.lastIndexOf('height * 0.30 + 76,', add)));
    expect(svc, contains("context.pushOnce(id != null ? '/service/\$id' : '/service-join');"));
    expect(src('lib/features/admin/presentation/admin_shell.dart'), contains("AdminSection('tirpark', 'TIRPark (parklar)', Icons.local_parking)"));
    final sql = src('supabase/migrations/0077_tir_parks.sql').toLowerCase();
    for (final bad in ['drop table', 'truncate', 'delete from', 'alter table public.users', 'drop column']) {
      expect(sql.contains(bad), isFalse, reason: bad);
    }
    expect(sql, contains("using (status = 'approved' or created_by = auth.uid() or public.is_admin())"));
    expect(sql, contains("raise exception 'duplicate_nearby'"));
    expect(sql, contains('perform public._require_admin();'));
    for (final lang in ['az', 'tr', 'en', 'ru', 'ka', 'zh']) {
      final m = jsonDecode(src('assets/i18n/$lang.json')) as Map;
      for (final k in ['nav_tirpark', 'tp_add', 'tp_nearby', 'tp_pending', 'tp_err_duplicate', for (final a in kTirParkAmenities) 'tp_am_$a']) {
        expect(m[k], isNotNull, reason: '$lang $k');
      }
    }
  });
}
