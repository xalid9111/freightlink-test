// Typography (owner, 25.10.2026): Turbo.az-like balance — text, names,
// routes, cities, dates, technical data, filters w400; buttons and active
// choices w500; prices and main headings w600. Heavier weights only where
// emphasis is really needed (VIP / PRO badges, the advertiser's banner).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Files allowed to keep w700 / w800 / w900, and why.
const _heavyAllowed = {
  'lib/core/widgets/vip_frame.dart', // VIP medal
  'lib/features/market/presentation/market_card.dart', // VIP badge
  'lib/features/cargo/presentation/widgets/cargo_card.dart', // VIP medal letter
  'lib/features/services/presentation/service_widgets.dart', // PRO badge
  'lib/features/market/presentation/market_brand_picker.dart', // letters in place of a logo
  'lib/features/ads/presentation/ad_creative_view.dart', // advertiser's banner design (1200×400)
};

void main() {
  test('no heavy font weights outside the allowed emphasis', () {
    final heavy = RegExp(r'FontWeight\.(w700|w800|w900|bold)\b');
    final offenders = <String>[];
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'))) {
      final path = f.path.replaceAll(r'\', '/');
      if (_heavyAllowed.contains(path)) continue;
      final lines = f.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (heavy.hasMatch(lines[i])) offenders.add('$path:${i + 1}');
      }
    }
    expect(offenders, isEmpty, reason: 'use w400 / w500 / w600 (see this test)');
  });

  test('theme: headings and prices w600, buttons w500, chips w400; one font', () {
    final t = File('lib/core/theme/app_theme.dart').readAsStringSync();
    expect(t, contains('FontWeight weight = FontWeight.w600, double? height}) =>')); // display
    expect(t, contains('FontWeight weight = FontWeight.w500, double letterSpacing = 0.6}) =>')); // mono
    expect(RegExp(r'textStyle: const TextStyle\(fontWeight: FontWeight\.w500, fontSize: 15\)').allMatches(t).length, 2);
    expect(t, contains('labelStyle: TextStyle(color: AppColors.text, fontWeight: FontWeight.w400'));
    expect(t, contains("static const family = 'Arial';"));
  });
}
