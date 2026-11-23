// The phone's Loads page as the owner's picture (17.11.2026): one load per
// row — small picture with the heart, route with flags, "22 t | Refrijerator
// | 30 noy", the price in the accent colour with the currency under it, ›.
// Daşıyıcılar the same way. VIP order: load, VIP, load, VIP …
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import 'package:freightlink/repositories/profile_repository.dart';

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
        publicProfileProvider.overrideWith((ref, id) async => PublicProfile(id: id, fullName: 'Aysel Muradova')),
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

  test('short type names as in the design', () {
    final az = lang('az');
    expect(rowKindLabel(az, 'ref', 'az'), 'Ref');
    expect(rowKindLabel(az, 'container', 'az'), 'Konteyner');
    expect(rowKindLabel(az, 'manipulator', 'az'), 'Manipulyator');
    expect(rowKindLabel(az, 'open', 'az'), 'Açıq');
    expect(rowKindLabel(lang('ru'), 'ref', 'ru'), 'Реф');
  });

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
    expect(find.text('22 T'), findsOneWidget, reason: 'capital T (owner, 17.11.2026)');
    expect(find.text('Ref'), findsOneWidget, reason: 'the tile\'s short name (owner\'s design)');
    expect(find.text('30 noy'), findsOneWidget);
    expect(find.text('5 100'), findsOneWidget);
    expect(find.text('USD'), findsOneWidget);
    expect(find.byIcon(Icons.chevron_right), findsOneWidget);
    expect(find.byKey(const ValueKey('cargo-heart-c1')), findsOneWidget, reason: 'the heart stays on the picture');
    expect(t.getSize(find.byIcon(Icons.favorite_border)).width, greaterThanOrEqualTo(18), reason: 'bigger heart (owner, 17.11.2026)');
    final price = t.widget<Text>(find.text('5 100'));
    expect(price.style!.color, AppColors.accent, reason: 'the price in the accent colour');
  });

  testWidgets("owner's design: no load picture; heart, then the poster's picture (else initials); the type's own icon; no icon before T",
      (t) async {
    final s = lang('az');
    await t.pumpWidget(host(CargoListRow(cargo: load('c1'), strings: s, onTap: () {}), s));
    await t.pump();
    await t.pump();
    expect(find.byKey(const ValueKey('row-poster')), findsOneWidget);
    expect(find.text('AM'), findsOneWidget, reason: 'no profile picture → initials');
    expect(find.byKey(const ValueKey('row-kind-ref')), findsOneWidget, reason: 'the load type\'s own truck icon');
    expect(find.byIcon(Icons.scale_outlined), findsNothing, reason: 'no icon before the tonnes');
    expect(find.byType(Image).evaluate().length, 1, reason: 'only the small type icon — no load picture');
    expect(
        t.getTopLeft(find.byKey(const ValueKey('row-poster'))).dy,
        greaterThan(t.getTopLeft(find.byKey(const ValueKey('cargo-heart-c1'))).dy),
        reason: 'the picture under the heart');
  });

  testWidgets("owner's design 21.11.2026: heart + Paylaş on the upper right edge, the route the whole width, the picture by the 2nd line",
      (t) async {
    final s = lang('az');
    await t.pumpWidget(host(CargoListRow(cargo: load('c1'), strings: s, onTap: () {}), s));
    await t.pump();
    await t.pump();
    final card = t.getRect(find.byKey(const ValueKey('cargo-row-c1')));
    final heart = t.getRect(find.byKey(const ValueKey('row-heart')));
    final share = t.getRect(find.byKey(const ValueKey('row-share')));
    final route = t.getRect(find.byKey(const ValueKey('row-route')));
    final poster = t.getRect(find.byKey(const ValueKey('row-poster')));
    final meta = t.getRect(find.byKey(const ValueKey('row-meta')));
    expect(heart.center.dy, closeTo(card.top, 2), reason: 'half over the card\'s top edge');
    expect(share.left, greaterThan(heart.right), reason: 'Paylaş right of the heart');
    expect(share.right, lessThan(card.right) , reason: 'on the right side');
    expect(heart.left, greaterThan(card.center.dx), reason: 'right half of the card');
    expect(route.left, lessThan(poster.right), reason: 'the route starts at the left edge, over the picture');
    expect(route.bottom, lessThanOrEqualTo(poster.top + 2), reason: 'the picture on the second line');
    expect((poster.center.dy - meta.center.dy).abs(), lessThan(14), reason: 'beside the 22 T | Ref | 30 noy line');
    expect(find.byKey(const ValueKey('row-share-c1')), findsOneWidget);
  });

  testWidgets('VIP / Premium marks left of the heart on the card\'s edge (owner, 21.11.2026)', (t) async {
    final s = lang('az');
    await t.pumpWidget(host(CargoListRow(cargo: load('c1', vip: true), strings: s, vip: true, onTap: () {}), s));
    await t.pump();
    final marks = t.getRect(find.byKey(const ValueKey('row-marks')));
    final heart = t.getRect(find.byKey(const ValueKey('row-heart')));
    expect(marks.right, lessThanOrEqualTo(heart.left));
    expect((marks.center.dy - heart.center.dy).abs(), lessThan(4));
    expect(marks.center.dy, lessThan(t.getRect(find.text('5 100')).top), reason: 'not over the price any more');
  });

  testWidgets('Paylaş without a share sheet copies the load link', (t) async {
    final s = lang('az');
    String? copied;
    t.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') copied = (call.arguments as Map)['text'] as String?;
      return null;
    });
    await t.pumpWidget(host(CargoListRow(cargo: load('c1'), strings: s, onTap: () {}), s));
    await t.pump();
    await t.tap(find.byKey(const ValueKey('row-share-c1')));
    await t.pump();
    await t.pump();
    expect(copied, contains('#/cargo/c1'));
    expect(copied, contains('5 100 USD'));
    expect(find.text('Link kopyalandı ✓'), findsOneWidget);
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

  test('wired: the old map section (lights only), the load types open, + Yük əlavə et over the list', () {
    final m = src('lib/features/cargo/presentation/cargo_marketplace_screen.dart');
    // The old map section back (owner, 17.11.2026, later): clouds above /
    // below, İş Mərkəzi and "Yük hovuzu +" under the map.
    expect(m, contains('_CloudScene('));
    expect(m, contains('JobCenterMapButton(strings: strings)'));
    expect(m, contains("_AddLoadButton(label: strings.t('home_add_load'), onTap: () => context.pushOnce('/cargo/create'))"), reason: '"Yük əlavə et" under the map (was "Yük hovuzu")');
    // The map back (owner, 17.11.2026, later): only the city lights blink.
    expect(m, contains("LiveMap(liveLabel: strings.t('map_live_badge'), routes: false, showBadge: false)"));
    expect(RegExp(r'StatCapsule\(\s+key:').allMatches(m).length, 3, reason: 'the three real counters');
    final lm = src('lib/features/cargo/presentation/widgets/live_map.dart');
    expect(lm, contains('if (!routes) return;'), reason: 'no trucks / roads / bursts');
    expect(lm, contains('if (!widget.routes || _speed.slow == true) return _startCalm();'), reason: 'a calm timer, not every frame');
    expect(lm, contains('static const kLightsEvery = Duration(milliseconds: 66);'));
    expect(src('lib/features/cargo/presentation/cargo_marketplace_desktop.dart'), contains("LiveMap(liveLabel: strings.t('map_live_badge'))"),
        reason: 'the computer keeps its moving map');
    // The load types open on the page again (owner, 17.11.2026); no filter button.
    expect(m, contains('CargoTypeTiles(strings: strings, tileHeight: 64, onChanged: _scrollToFeed)'));
    expect(m.contains('_TypeFilterButton'), isFalse);
    expect(m.contains("ValueKey('add-cargo-top')"), isFalse, reason: 'no second add button over the list (owner, 17.11.2026)');
    expect(m, contains('HeaderCircles(strings: strings)'), reason: 'heart + profile picture');
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
