// "Daşıyıcılar" — empty truck ads on Yüklər (owner, 13.11.2026, SQL 0118):
// their own kind, the place now and the route on the card and the page,
// the form's checks, the owner's controls; loads untouched.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freightlink/core/localization/app_strings.dart';
import 'package:freightlink/core/localization/locale_controller.dart';
import 'package:freightlink/core/router/guest_access.dart';
import 'package:freightlink/features/auth/domain/app_user.dart';
import 'package:freightlink/features/auth/presentation/providers/auth_providers.dart';
import 'package:freightlink/features/cargo/domain/cargo_categories.dart';
import 'package:freightlink/features/cargo/presentation/providers/cargo_media_providers.dart';
import 'package:freightlink/features/cargo/presentation/providers/route_filter.dart';
import 'package:freightlink/features/empty_trucks/data/empty_truck_repository.dart';
import 'package:freightlink/features/empty_trucks/domain/empty_truck.dart';
import 'package:freightlink/features/empty_trucks/presentation/empty_truck_detail_screen.dart';
import 'package:freightlink/features/empty_trucks/presentation/empty_truck_form_screen.dart';
import 'package:freightlink/features/empty_trucks/presentation/empty_truck_widgets.dart';

String src(String p) => File(p).readAsStringSync();
final _az = AppStrings(Map<String, String>.from(jsonDecode(src('assets/i18n/az.json')) as Map));

EmptyTruck truck({
  String id = 't1',
  String owner = 'o1',
  String fromCity = 'Baku',
  String fromCountry = 'Azerbaijan',
  String? fromCode = 'AZ',
  bool any = false,
  String? toCity = 'Istanbul',
  String? toCountry = 'Turkey',
  String? toCode = 'TR',
  String type = 'tent',
  double tons = 20,
  List<String> bodies = const [],
  DateTime? from,
  String status = 'active',
  String? phone = '+994501112233',
}) =>
    EmptyTruck(
      id: id,
      ownerId: owner,
      fromCity: fromCity,
      fromCountry: fromCountry,
      fromCode: fromCode,
      anyDirection: any,
      toCity: any ? null : toCity,
      toCountry: any ? null : toCountry,
      toCode: any ? null : toCode,
      truckType: type,
      freeTons: tons,
      bodyTypes: bodies,
      availableFrom: from,
      phone: phone,
      status: status,
      createdAt: DateTime(2026, 11, 13),
    );

void main() {
  group('the place now and the route', () {
    test('"Bakı, Azərbaycan" and "Bakı → İstanbul"', () {
      final t = truck();
      expect(t.placeLabel('az'), 'Bakı, Azərbaycan');
      expect(t.routeLabel('az', anyLabel: 'istənilən istiqamət'), '🇦🇿 Bakı → 🇹🇷 İstanbul');
      expect(truck(any: true).routeLabel('az', anyLabel: 'istənilən istiqamət'), '🇦🇿 Bakı → istənilən istiqamət');
    });

    test('the Loads page filters: route search and load-type tile', () {
      final t = truck();
      expect(t.matchesRoute(const RouteFilter(from: 'AZ', to: 'TR')), isTrue);
      expect(t.matchesRoute(const RouteFilter(from: 'AZ', fromCity: 'Baku')), isTrue);
      expect(t.matchesRoute(const RouteFilter(from: 'GE')), isFalse);
      expect(t.matchesRoute(const RouteFilter(to: 'RU')), isFalse);
      expect(truck(any: true).matchesRoute(const RouteFilter(to: 'RU')), isTrue, reason: 'any direction fits every destination');
      expect(t.matchesCategory(const CargoCategoryFilter(truckType: 'tent')), isTrue);
      expect(t.matchesCategory(const CargoCategoryFilter(truckType: 'ref')), isFalse);
      expect(t.matchesCategory(const CargoCategoryFilter(groupage: true)), isFalse);
      expect(truck(bodies: ['groupage']).matchesCategory(const CargoCategoryFilter(groupage: true)), isTrue);
    });

    test('from JSON (as the server sends it)', () {
      final t = EmptyTruck.fromJson({
        'id': 'x',
        'owner_id': 'o',
        'from_city': 'Baku',
        'from_country': 'Azerbaijan',
        'from_code': 'AZ',
        'any_direction': false,
        'to_city': 'Tbilisi',
        'to_country': 'Georgia',
        'to_code': 'GE',
        'truck_type': 'ref',
        'free_tons': 12.5,
        'body_types': ['cooled'],
        'available_from': null,
        'status': 'paused',
        'created_at': '2026-11-13T10:00:00Z',
      });
      expect((t.freeTons, t.status, t.isActive, t.phone), (12.5, 'paused', false, null));
      expect(t.bodyTypes, ['cooled']);
      expect(t.freeNow(DateTime.now()), isTrue);
    });
  });

  group('the form checks', () {
    final now = DateTime(2026, 11, 13, 12);
    String? err({String fromCity = 'Baku', bool any = false, String? to = 'Istanbul', String? type = 'tent', double? tons = 20, DateTime? at}) =>
        emptyTruckFormError(
            fromCity: fromCity,
            fromCountry: 'Azerbaijan',
            anyDirection: any,
            toCity: to,
            toCountry: to == null ? null : 'Turkey',
            truckType: type,
            freeTons: tons,
            availableFrom: at,
            now: now);
    test('every field', () {
      expect(err(), isNull);
      expect(err(fromCity: ' '), 'et_err_from');
      expect(err(to: null), 'et_err_to');
      expect(err(to: null, any: true), isNull, reason: '"İstiqamət fərq etmir" needs no destination');
      expect(err(type: null), 'et_err_truck');
      expect(err(tons: 0), 'et_err_tons');
      expect(err(tons: 150), 'et_err_tons');
      expect(err(tons: null), 'et_err_tons');
      expect(err(at: now.subtract(const Duration(days: 3))), 'et_err_time');
      for (final k in ['et_err_from', 'et_err_to', 'et_err_truck', 'et_err_tons', 'et_err_time']) {
        expect(_az.t(k), isNot(k), reason: k);
      }
    });
  });

  Widget host(Widget child, {String? uid, List<Override> extra = const []}) => ProviderScope(
        key: UniqueKey(),
        overrides: [
          stringsProvider.overrideWithValue(_az),
          allCargoTemplatesProvider.overrideWith((ref) async => const []),
          authStateProvider.overrideWith((ref) =>
              Stream.value(uid == null ? null : AppUser(id: uid, email: 'a@b.az', fullName: 'A', role: 'carrier', isVerified: false))),
          ...extra,
        ],
        child: MaterialApp(home: Scaffold(body: child)),
      );

  testWidgets('Yüklər | Daşıyıcılar: two buttons, the choice is kept', (t) async {
    late WidgetRef r;
    await t.pumpWidget(host(Consumer(builder: (c, ref, _) {
      r = ref;
      return LoadsSectionSwitch(strings: _az);
    })));
    expect(find.text('Yüklər'), findsOneWidget);
    expect(find.text('Daşıyıcılar'), findsOneWidget);
    expect(r.read(loadsSectionProvider), LoadsSection.loads, reason: 'Yüklər first, as before');
    await t.tap(find.byKey(const ValueKey('loads-section-carriers')));
    await t.pump();
    expect(r.read(loadsSectionProvider), LoadsSection.carriers);
  });

  testWidgets('the card: route, the place now, tonnes, truck, "İndi"', (t) async {
    await t.pumpWidget(host(SizedBox(width: 170, child: EmptyTruckTile(truck: truck(), strings: _az, onTap: () {}))));
    await t.pump();
    expect(find.text('🇦🇿 Bakı → 🇹🇷 İstanbul'), findsOneWidget);
    expect(find.text('Bakı, Azərbaycan'), findsOneWidget);
    expect(find.text('20 t boş'), findsOneWidget);
    expect(find.text('İndi'), findsOneWidget);
    expect(find.text('BOŞ'), findsOneWidget);
  });

  testWidgets('the page: a stranger contacts; the owner edits, pauses, closes ("Maşın doldu")', (t) async {
    final ad = truck(owner: 'o1');
    await t.pumpWidget(host(const EmptyTruckDetailScreen(id: 't1'),
        uid: 'u2', extra: [emptyTruckProvider('t1').overrideWith((ref) async => ad)]));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('et-detail-route')), findsOneWidget);
    expect(find.text('Bakı, Azərbaycan'), findsOneWidget);
    expect(find.byKey(const ValueKey('et-call')), findsOneWidget);
    expect(find.byKey(const ValueKey('et-message')), findsOneWidget);
    expect(find.byKey(const ValueKey('et-edit')), findsNothing);

    await t.pumpWidget(host(const EmptyTruckDetailScreen(id: 't1'),
        uid: 'o1', extra: [emptyTruckProvider('t1').overrideWith((ref) async => ad)]));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('et-edit')), findsOneWidget);
    expect(find.byKey(const ValueKey('et-pause')), findsOneWidget);
    expect(find.byKey(const ValueKey('et-filled')), findsOneWidget);
    expect(find.byKey(const ValueKey('et-call')), findsNothing);
  });

  testWidgets('the form: the six parts in order; an empty form says what is missing; the GPS place is only offered', (t) async {
    t.view.physicalSize = const Size(800, 3200);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(host(const EmptyTruckFormScreen()));
    await t.pumpAndSettle();
    final order = ['et-from', 'et-gps', 'et-map', 'et-to', 'et-any-direction', 'et-truck-tent', 'et-tons', 'et-body-groupage',
      'et-time-now', 'et-time-pick', 'et-phone', 'et-whatsapp', 'et-save'];
    double y(String k) => t.getTopLeft(find.byKey(ValueKey(k))).dy;
    for (var i = 1; i < order.length; i++) {
      expect(y(order[i]) >= y(order[i - 1]), isTrue, reason: '${order[i - 1]} before ${order[i]}');
    }
    expect(find.text('Boş maşın elanını paylaş'), findsOneWidget);
    expect(find.byKey(const ValueKey('et-suggest')), findsNothing, reason: 'nothing is shared without the user');
    await t.tap(find.byKey(const ValueKey('et-save')));
    await t.pump();
    expect(find.text(_az.t('et_err_from')), findsOneWidget);
    // "İstiqamət fərq etmir" switches the destination off.
    await t.tap(find.byKey(const ValueKey('et-any-direction')));
    await t.pump();
    final tile = t.widget<ListTile>(find.byKey(const ValueKey('et-to')));
    expect(tile.onTap, isNull);
  });

  group('wiring', () {
    test('visitors may open an ad, not the form', () {
      debugSignedOut = () => true;
      addTearDown(() => debugSignedOut = null);
      expect(isGuestPath('/trucks/abc'), isTrue);
      expect(isGuestPath('/trucks/new'), isFalse);
      expect(isGuestPath('/trucks/mine'), isFalse);
      expect(isGuestPath('/trucks/abc/edit'), isFalse);
    });

    test('the Loads page: the switch under the route search; the + keeps its place, its name follows the choice', () {
      final m = src('lib/features/cargo/presentation/cargo_marketplace_screen.dart');
      final route = m.indexOf('SliverToBoxAdapter(child: _RouteSearch(strings: strings)),');
      final sw = m.indexOf('LoadsSectionSwitch(strings: strings');
      expect(route, greaterThan(0));
      expect(sw, greaterThan(route));
      expect(m.contains("label: strings.t('et_add_button'),") && m.contains("onTap: () => context.pushOnce('/trucks/new'))"), isTrue);
      expect(m.contains("_AddLoadButton(label: strings.t('nav_add_cargo'), onTap: () => context.pushOnce('/cargo/create'))"), isTrue,
          reason: 'the loads button is unchanged');
      final d = src('lib/features/cargo/presentation/cargo_marketplace_desktop.dart');
      expect(d.contains('LoadsSectionSwitch(') && d.contains('_deskCarrierSlivers('), isTrue);
    });

    test('its own table, written only through the server functions; loads untouched', () {
      final r = src('lib/features/empty_trucks/data/empty_truck_repository.dart');
      expect(r.contains(".from('empty_truck_ads')"), isTrue);
      expect(r.contains(".from('cargo')"), isFalse);
      expect(RegExp(r'\.(insert|update|delete|upsert)\(').hasMatch(r), isFalse);
      final sql = src('supabase/migrations/0118_empty_truck_ads.sql');
      expect(sql.contains('create table if not exists public.empty_truck_ads'), isTrue);
      expect(RegExp(r'alter\s+table\s+public\.cargo|drop\s+table|truncate', caseSensitive: false).hasMatch(sql), isFalse);
      expect(sql.contains("status in ('active', 'paused', 'filled')"), isTrue);
    });
  });
}
