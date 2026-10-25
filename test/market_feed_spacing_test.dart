// TIR Bazarı phone feed (owner, 25.10.2026): VIP keeps its seal but loses
// the gold frame; rows grow with the text size so cards never run into
// each other, with a little more room between them.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freightlink/core/widgets/vip_frame.dart';
import 'package:freightlink/features/market/presentation/market_card.dart';

void main() {
  testWidgets('seal only: no frame painted, picture untouched', (tester) async {
    await tester.pumpWidget(const Directionality(
      textDirection: TextDirection.ltr,
      child: Center(
        child: SizedBox(
          width: 173,
          height: 140,
          child: VipPictureFrame(frame: false, child: ColoredBox(color: Color(0xFF334455), key: ValueKey('pic'))),
        ),
      ),
    ));
    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('vip-seal')), findsOneWidget);
    expect(find.byKey(const ValueKey('vip-frame')), findsNothing);
    expect(find.byKey(const ValueKey('pic')), findsOneWidget);
  });

  testWidgets('row height grows with the text size (1–5)', (tester) async {
    final heights = <double>[];
    for (final k in [0.9, 1.0, 1.08, 1.15, 1.25, 1.6]) {
      await tester.pumpWidget(MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(k)),
        child: Builder(builder: (context) {
          heights.add(MarketFeedCard.extentFor(context));
          return const SizedBox();
        }),
      ));
    }
    expect(heights.every((h) => h >= MarketFeedCard.extent), isTrue);
    for (var i = 1; i < heights.length; i++) {
      expect(heights[i], greaterThanOrEqualTo(heights[i - 1]));
    }
    expect(heights.last, greaterThan(MarketFeedCard.extent));
  });

  test('wired: feed card has no frame, grid uses the measured height and more room', () {
    final card = File('lib/features/market/presentation/market_card.dart').readAsStringSync();
    // 0066: no frame or seal at all — the marks sit on the city line.
    expect(card.contains('VipPictureFrame('), isFalse);
    expect(card, contains("MarketPromoMarks(l, key: const ValueKey('feed-marks'))"));
    final home = File('lib/features/market/presentation/market_home_screen.dart').readAsStringSync();
    expect(home, contains('mainAxisExtent: MarketFeedCard.extentFor(context),'));
    expect(home, contains('mainAxisSpacing: 18,'));
  });
}
