// Daşıyıcılar as the owner's picture 1 (17.11.2026): the carrier's own
// picture (else initials) in an accent ring, name + blue badge (no made-up
// rating), route, the truck kind's own icon + "Tent • 20 T", "Bu gün
// hazırdır" / "25 noyabrdan", "Zəng et" + "Mesaj"; the information opens the
// ad; one's own ad shows Redaktə et; a hidden number leaves only Mesaj.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freightlink/core/localization/app_strings.dart';
import 'package:freightlink/core/localization/locale_controller.dart';
import 'package:freightlink/features/auth/domain/app_user.dart';
import 'package:freightlink/features/auth/presentation/providers/auth_providers.dart';
import 'package:freightlink/features/empty_trucks/domain/empty_truck.dart';
import 'package:freightlink/features/empty_trucks/presentation/empty_truck_widgets.dart';
import 'package:freightlink/repositories/profile_repository.dart';
import 'package:intl/date_symbol_data_local.dart';

String src(String p) => File(p).readAsStringSync();
AppStrings lang(String l) => AppStrings(Map<String, String>.from(jsonDecode(src('assets/i18n/$l.json')) as Map));

EmptyTruck truck({String owner = 'o1', String? phone = '+994501112233', DateTime? from, String type = 'tent'}) =>
    EmptyTruck.fromJson({
      'id': 't1',
      'owner_id': owner,
      'from_city': 'Baku',
      'from_country': 'Azerbaijan',
      'from_code': 'AZ',
      'to_city': 'Moscow',
      'to_country': 'Russia',
      'to_code': 'RU',
      'truck_type': type,
      'free_tons': 20,
      'status': 'active',
      'phone': phone,
      if (from != null) 'available_from': from.toUtc().toIso8601String(),
      'created_at': '2026-11-16T10:00:00Z',
    });

Widget host(Widget child, AppStrings s, {String? uid = 'u2', String? avatar, double width = 390, double scale = 1}) =>
    ProviderScope(
      overrides: [
        stringsProvider.overrideWithValue(s),
        authStateProvider.overrideWith((ref) => Stream.value(
            uid == null ? null : AppUser(id: uid, email: 'a@b.az', fullName: 'A', role: 'carrier', isVerified: false))),
        publicProfileProvider.overrideWith((ref, id) async =>
            PublicProfile(id: id, fullName: 'Caspian Trans', avatarUrl: avatar, isVerified: true)),
      ],
      child: MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(size: Size(width, 900), textScaler: TextScaler.linear(scale)),
          child: Scaffold(body: Center(child: SizedBox(width: width - 24, child: child))),
        ),
      ),
    );

void main() {
  setUpAll(() => initializeDateFormatting());

  test('ready: "Bu gün hazırdır" today, "25 noyabrdan" later (aprel → dən)', () {
    final az = lang('az');
    final now = DateTime(2026, 11, 17, 10);
    expect(emptyTruckReadyLabel(az, truck(), 'az', now: now), 'Bu gün hazırdır');
    expect(emptyTruckReadyLabel(az, truck(from: DateTime(2026, 11, 17, 22)), 'az', now: now), 'Bu gün hazırdır');
    expect(emptyTruckReadyLabel(az, truck(from: DateTime(2026, 11, 25, 9)), 'az', now: now), '25 noyabrdan');
    expect(emptyTruckReadyLabel(az, truck(from: DateTime(2027, 4, 3, 9)), 'az', now: now), '3 apreldən');
    expect(carrierTonsLabel(20), '20 T', reason: 'capital T (owner, 17.11.2026)');
    expect(carrierTonsLabel(22.5), '22.5 T');
    expect(carrierInitials('Caspian Trans'), 'CT');
    expect(carrierInitials('Rəşad Məmmədov'), 'RM');
    expect(carrierInitials(''), '?');
  });

  testWidgets('the card shows what picture 1 shows; no made-up rating', (t) async {
    final s = lang('az');
    var opened = 0;
    await t.pumpWidget(host(EmptyTruckCarrierCard(truck: truck(), strings: s, onTap: () => opened++), s));
    await t.pump();
    await t.pump();
    expect(find.text('Caspian Trans'), findsOneWidget);
    expect(find.text('CT'), findsOneWidget, reason: 'no picture → initials');
    expect(find.byIcon(Icons.verified), findsOneWidget, reason: 'the real blue badge');
    expect(find.byKey(const ValueKey('carrier-rating')), findsNothing, reason: 'no rating system yet — nothing made up');
    expect(find.textContaining('Bakı'), findsOneWidget);
    expect(find.text('Tent • 20 T'), findsOneWidget);
    expect(find.text('Bu gün hazırdır'), findsOneWidget);
    expect(find.byKey(const ValueKey('carrier-kind-tent')), findsOneWidget, reason: 'the chosen kind\'s own icon');
    expect(find.text('Zəng et'), findsOneWidget);
    expect(find.text('Mesaj'), findsOneWidget);
    await t.tap(find.text('Caspian Trans'));
    expect(opened, 1, reason: 'the information opens the ad');
  });

  testWidgets('a real rating shows when there is one', (t) async {
    final s = lang('az');
    await t.pumpWidget(host(EmptyTruckCarrierCard(truck: truck(), strings: s, rating: 4.9, onTap: () {}), s));
    await t.pump();
    expect(find.text('4.9'), findsOneWidget);
  });

  testWidgets('the kind icon follows the chosen truck kind', (t) async {
    final s = lang('az');
    await t.pumpWidget(host(EmptyTruckCarrierCard(truck: truck(type: 'ref'), strings: s, onTap: () {}), s));
    await t.pump();
    expect(find.byKey(const ValueKey('carrier-kind-ref')), findsOneWidget);
  });

  testWidgets('no number (hidden / none): only Mesaj; one\'s own ad: Redaktə et', (t) async {
    final s = lang('az');
    await t.pumpWidget(host(EmptyTruckCarrierCard(truck: truck(phone: null), strings: s, onTap: () {}), s));
    await t.pump();
    expect(find.text('Zəng et'), findsNothing);
    expect(find.text('Mesaj'), findsOneWidget);
    await t.pumpWidget(host(EmptyTruckCarrierCard(truck: truck(owner: 'u2'), strings: s, onTap: () {}), s));
    await t.pump();
    expect(find.byKey(const ValueKey('carrier-edit')), findsOneWidget);
    expect(find.text('Zəng et'), findsNothing);
  });

  testWidgets('never overflows: 6 languages × 320–390 pt × text size 125 %', (t) async {
    for (final l in ['az', 'tr', 'en', 'ru', 'ka', 'zh']) {
      final s = lang(l);
      for (final w in [320.0, 360.0, 390.0]) {
        for (final sc in [1.0, 1.25]) {
          await t.pumpWidget(host(
              EmptyTruckCarrierCard(truck: truck(from: DateTime(2026, 12, 25)), strings: s, rating: 4.8, onTap: () {}), s,
              width: w, scale: sc));
          await t.pump();
          expect(t.takeException(), isNull, reason: '$l $w $sc');
        }
      }
    }
  });

  test('wired: the phone list uses the cards, Boş maşın əlavə et above them; the photo upload stays shrunk', () {
    final m = src('lib/features/cargo/presentation/cargo_marketplace_screen.dart');
    expect(m, contains('EmptyTruckCarrierCard('));
    expect(m, contains("key: const ValueKey('empty-truck-add-top')"));
    expect(m, contains("key: const ValueKey('empty-truck-mine')"));
    final p = src('lib/features/auth/presentation/profile_screen.dart');
    expect(p, contains('maxWidth: 1024'));
    expect(p, contains('imageQuality: 85'));
  });
}
