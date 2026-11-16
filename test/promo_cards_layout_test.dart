// "Önə çıxar" cards (owner's picture, 16.11.2026): three plain dark cards side
// by side — on the phone too — white title, "3 AZN-dən" in blue, the owner's
// flat icons. Never an overflow: 6 languages × 320 / 360 / 390 pt × text size.
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freightlink/core/localization/app_strings.dart';
import 'package:freightlink/features/market/domain/market_models.dart';
import 'package:freightlink/features/market/presentation/market_promo.dart';
import 'package:freightlink/features/finance/presentation/card_checkout.dart' show VipCheckoutTarget;
import 'package:flutter/rendering.dart';

Future<void> _loadFonts() async {
  final arial = FontLoader('Arial');
  for (final f in ['Regular', 'Bold']) {
    arial.addFont(Future.value(ByteData.sublistView(File('assets/fonts/LiberationSans-$f.ttf').readAsBytesSync())));
  }
  await arial.load();
}

final _plans = {
  MarketPromoKind.bump: const [MarketPromoPlan(kind: MarketPromoKind.bump, qty: 1, price: 3)],
  MarketPromoKind.vip: const [MarketPromoPlan(kind: MarketPromoKind.vip, qty: 1, price: 5)],
  MarketPromoKind.premium: const [MarketPromoPlan(kind: MarketPromoKind.premium, qty: 1, price: 7)],
};

class _Target extends PromoTarget {
  @override
  ProviderListenable<AsyncValue<List<MarketPromoPlan>>> plans(MarketPromoKind kind) =>
      Provider((ref) => AsyncData(_plans[kind]!));
  @override
  DateTime? paidUntil(MarketPromoKind kind) => null;
  @override
  Future<VipCheckoutTarget> order(WidgetRef ref, MarketPromoKind kind, int qty, {Set<PromoPlace>? places}) =>
      throw UnimplementedError();
  @override
  void refresh(ProviderContainer c) {}
  @override
  String get failedKey => 'mk_vip_failed';
}

AppStrings _strings(String lang) =>
    AppStrings(Map<String, String>.from(jsonDecode(File('assets/i18n/$lang.json').readAsStringSync()) as Map));

Widget _app(AppStrings s, double width, double scale, {Key? key}) => ProviderScope(
      child: MaterialApp(
        theme: ThemeData(fontFamily: 'Arial', brightness: Brightness.dark),
        home: MediaQuery(
          data: MediaQueryData(size: Size(width, 400), textScaler: TextScaler.linear(scale)),
          child: Scaffold(
            backgroundColor: Colors.black,
            body: Align(
              alignment: Alignment.topCenter,
              child: RepaintBoundary(
                key: key,
                child: Container(
                  width: width,
                  color: const Color(0xFF0B0F17),
                  padding: const EdgeInsets.all(16),
                  child: MarketPromoOptions(s: s, target: _Target()),
                ),
              ),
            ),
          ),
        ),
      ),
    );

void main() {
  setUpAll(_loadFonts);

  test('whole prices lose ".00", others keep it', () {
    expect(promoFromPrice(const MarketPromoPlan(kind: MarketPromoKind.bump, qty: 1, price: 3)), '3 AZN');
    expect(promoFromPrice(const MarketPromoPlan(kind: MarketPromoKind.bump, qty: 1, price: 2.5)), '2.50 AZN');
    expect(promoFromPrice(const MarketPromoPlan(kind: MarketPromoKind.bump, qty: 1, price: 1200)), '1 200 AZN');
  });

  for (final lang in ['az', 'tr', 'en', 'ru', 'ka', 'zh']) {
    testWidgets('$lang: three cards in one row, nothing overflows', (t) async {
      for (final width in [320.0, 360.0, 390.0]) {
        for (final scale in [1.0, 1.25]) {
          t.view.physicalSize = Size(width, 400);
          t.view.devicePixelRatio = 1;
          await t.pumpWidget(_app(_strings(lang), width, scale));
          await t.pump();
          expect(t.takeException(), isNull, reason: '$lang $width $scale');
          final tops = [
            for (final k in MarketPromoKind.values) t.getTopLeft(find.byKey(ValueKey('mk-promo-${k.name}'))).dy,
          ];
          expect(tops.toSet().length, 1, reason: 'side by side ($lang $width)');
        }
      }
      t.view.reset();
    });
  }

  testWidgets('the card look of the owner\'s picture', (t) async {
    await t.pumpWidget(_app(_strings('az'), 390, 1));
    expect(find.text('3 AZN-dən'), findsOneWidget);
    final price = t.widget<Text>(find.byKey(const ValueKey('mk-promo-from-bump')));
    expect(price.style!.color, isNot(Colors.transparent));
    final src = File('lib/features/market/presentation/market_promo.dart').readAsStringSync();
    expect(src, contains('color: AppColors.card,'));
    expect(src, contains('style: TextStyle(color: AppColors.blue, fontSize: 14'));
    expect(src, contains('MarketPromoIcon(kind, size: 26)'));
  });

  // PROMO_PREVIEW=<dir> flutter test test/promo_cards_layout_test.dart → PNGs.
  final out = Platform.environment['PROMO_PREVIEW'];
  if (out != null) {
    testWidgets('preview pictures', (t) async {
      for (final (lang, width) in [('az', 390.0), ('ru', 390.0), ('az', 320.0)]) {
        t.view.physicalSize = Size(width * 3, 400 * 3);
        t.view.devicePixelRatio = 3;
        final key = GlobalKey();
        await t.pumpWidget(_app(_strings(lang), width, 1, key: key));
        await t.runAsync(() async {
          for (final k in MarketPromoKind.values) {
            await precacheImage(AssetImage(k.asset), key.currentContext!);
          }
        });
        await t.pump();
        await t.runAsync(() async {
          final b = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
          final img = await b.toImage(pixelRatio: 3);
          final png = await img.toByteData(format: ui.ImageByteFormat.png);
          File('$out/promo_${lang}_${width.toInt()}.png').writeAsBytesSync(png!.buffer.asUint8List());
        });
      }
      t.view.reset();
    });
  }
}
