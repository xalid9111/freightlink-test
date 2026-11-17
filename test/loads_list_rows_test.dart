// The phone's Loads page as the owner's picture (17.11.2026): one load per
// row — small picture with the heart, route with flags, "22 t | Refrijerator
// | 30 noy", the price in the accent colour with the currency under it, ›.
// Daşıyıcılar the same way. VIP order: load, VIP, load, VIP …
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:freightlink/core/localization/app_strings.dart';
import 'package:freightlink/core/theme/app_theme.dart';
import 'package:freightlink/features/auth/domain/app_user.dart';
import 'package:freightlink/features/auth/presentation/providers/auth_providers.dart';
import 'package:freightlink/features/cargo/data/cargo_media_repository.dart';
import 'package:freightlink/features/cargo/domain/vip_rows.dart';
import 'package:freightlink/features/cargo/presentation/providers/cargo_media_providers.dart';
import 'package:freightlink/features/cargo/presentation/widgets/cargo_card.dart';
import 'package:freightlink/core/localization/locale_controller.dart';
import 'package:freightlink/models/cargo_model.dart';

String src(String p) => File(p).readAsStringSync();
AppStrings lang(String l) => AppStrings(Map<String, String>.from(jsonDecode(src('assets/i18n/$l.json')) as Map));

CargoModel load(String id, {bool vip = false, double price = 5100, String type = 'ref'}) => CargoModel.fromJson({
      'id': id,
      'owner_id': 'o1',
      'pickup_country': 'Azerbaijan',
      'pickup_city': 'Baku',
      'destination_country': 'Russia',
      'destination_city': 'Saint Petersburg',
      'weight_kg': 22000,
      'pickup_date': '2026-11-30',
      'offered_price': price,
      'currency': 'USD',
      'truck_type': type,
      'created_at': '2026-11-16T10:00:00Z',
      if (vip) 'is_featured': true,
      if (vip) 'featured_until': '2099-01-01T00:00:00Z',
    });

class _Media implements CargoMediaRepository {
  @override
  Future<Set<String>> favoriteIds() async => const {};
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

Widget host(Widget child, AppStrings s, {double width = 390, double scale = 1}) => ProviderScope(
      overrides: [
        stringsProvider.overrideWithValue(s),
        allCargoTemplatesProvider.overrideWith((ref) async => const []),
        cargoFavoriteIdsProvider.overrideWith((ref) => CargoFavoritesController(_Media())),
        authStateProvider.overrideWith(
            (ref) => Stream.value(const AppUser(id: 'u2', email: 'a@b.az', fullName: 'A', role: 'carrier', isVerified: false))),
      ],
      child: MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(size: Size(width, 800), textScaler: TextScaler.linear(scale)),
          child: Scaffold(body: Center(child: SizedBox(width: width - 24, child: child))),
        ),
      ),
    );

void main() {
  setUpAll(() => initializeDateFormatting());

  test('one load per row: load, VIP, load, VIP … (the chessboard in one column)', () {
    final l = [
      for (var i = 0; i < 3; i++) load('n$i'),
      for (var i = 0; i < 3; i++) load('v$i', vip: true),
    ];
    final rows = buildLoadRows(l, columns: 1, now: DateTime(2026, 11, 17), rotation: 0);
    expect(rows.every((r) => r.length == 1), isTrue);
    expect([for (final r in rows) r.single.vip], [false, true, false, true, false, true]);
  });

  testWidgets('the row shows what the picture shows', (t) async {
    final s = lang('az');
    await t.pumpWidget(host(CargoListRow(cargo: load('c1'), strings: s, onTap: () {}), s));
    await t.pump();
    expect(find.textContaining('Bakı →'), findsOneWidget);
    expect(find.textContaining('22 T', findRichText: true), findsOneWidget, reason: 'capital T (owner, 17.11.2026)');
    expect(find.textContaining('Refrijerator', findRichText: true), findsOneWidget);
    expect(find.textContaining('30 noy', findRichText: true), findsOneWidget);
    expect(find.text('5 100'), findsOneWidget);
    expect(find.text('USD'), findsOneWidget);
    expect(find.byIcon(Icons.chevron_right), findsOneWidget);
    expect(find.byKey(const ValueKey('cargo-heart-c1')), findsOneWidget, reason: 'the heart stays on the picture');
    expect(t.getSize(find.byIcon(Icons.favorite_border)).width, greaterThanOrEqualTo(18), reason: 'bigger heart (owner, 17.11.2026)');
    final price = t.widget<Text>(find.text('5 100'));
    expect(price.style!.color, AppColors.accent, reason: 'the price in the accent colour');
  });

  testWidgets('VIP / Premium marks stay by the price', (t) async {
    final s = lang('az');
    await t.pumpWidget(host(CargoListRow(cargo: load('c1', vip: true), strings: s, vip: true, onTap: () {}), s));
    await t.pump();
    expect(find.byKey(const ValueKey('row-marks')), findsOneWidget);
  });

  testWidgets('never overflows: 6 languages × 320–390 pt × text size up to 125 %', (t) async {
    for (final l in ['az', 'tr', 'en', 'ru', 'ka', 'zh']) {
      final s = lang(l);
      for (final w in [320.0, 360.0, 390.0]) {
        for (final sc in [1.0, 1.25]) {
          await t.pumpWidget(host(
              Column(mainAxisSize: MainAxisSize.min, children: [
                CargoListRow(cargo: load('c1', price: 1250000, type: 'container'), strings: s, vip: true, onTap: () {}),
              ]),
              s,
              width: w,
              scale: sc));
          await t.pump();
          expect(t.takeException(), isNull, reason: '$l $w $sc');
        }
      }
    }
  });

  test('wired: the phone page uses the rows; the computer keeps its tiles', () {
    final m = src('lib/features/cargo/presentation/cargo_marketplace_screen.dart');
    expect(m, contains('CargoListRow('));
    expect(m, contains('EmptyTruckCarrierCard('));
    expect(m.contains('CargoTile('), isFalse);
    final d = src('lib/features/cargo/presentation/cargo_marketplace_desktop.dart');
    expect(d, contains('CargoTile('));
  });
}
