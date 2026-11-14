// TIR Bazarı "Alış-satış | Elan yerləşdir" (owner, 14.11.2026): in Russian at
// text size 5 the title was squeezed to one letter per line. Calibrated for
// all six languages, all five text sizes and narrow to normal phones: the
// title never breaks inside a word, takes at most two lines, never overflows.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freightlink/core/localization/app_strings.dart';
import 'package:freightlink/features/market/presentation/market_home_screen.dart';

AppStrings _lang(String l) =>
    AppStrings(Map<String, String>.from(jsonDecode(File('assets/i18n/$l.json').readAsStringSync()) as Map));

void main() {
  const scales = [0.9, 1.0, 1.08, 1.15, 1.25]; // Profil → text size 1 … 5
  const widths = [320.0, 360.0, 390.0];
  for (final l in ['az', 'tr', 'en', 'ru', 'ka', 'zh']) {
    testWidgets('$l: every text size and phone width', (t) async {
      final s = _lang(l);
      final title = s.t('mk_buy_sell');
      for (final w in widths) {
        for (final k in scales) {
          await t.binding.setSurfaceSize(Size(w, 800));
          await t.pumpWidget(MaterialApp(
            key: UniqueKey(),
            home: MediaQuery(
              data: MediaQueryData(size: Size(w, 800), textScaler: TextScaler.linear(k)),
              child: Scaffold(
                body: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Align(alignment: Alignment.topCenter, child: MarketSellBanner(s: s, onTap: () {})),
                ),
              ),
            ),
          ));
          expect(t.takeException(), isNull, reason: '$l $w × $k');
          final h = t.getSize(find.text(title)).height;
          expect(h, lessThanOrEqualTo(15 * k * 1.6 * 2 + 1), reason: '$l $w × $k: at most two lines (was $h)');
          expect(find.byKey(const ValueKey('mk-new-ad')), findsOneWidget);
        }
      }
      await t.binding.setSurfaceSize(null);
    });
  }

  testWidgets('a wide screen at normal size keeps the old single row', (t) async {
    final s = _lang('az');
    await t.binding.setSurfaceSize(const Size(600, 400));
    await t.pumpWidget(MaterialApp(home: Scaffold(body: MarketSellBanner(s: s, onTap: () {}))));
    expect(find.byKey(const ValueKey('mk-sell-stacked')), findsNothing);
    await t.binding.setSurfaceSize(null);
  });
}
