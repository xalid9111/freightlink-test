// Faster site, stage 3 (owner, 16.11.2026): the signs FreightLink Sans lacks
// (₺ ₼ ₽ ₾ and ✓) come from two tiny bundled fonts in the theme's fallback,
// so the browser no longer downloads a 195 KB font from Google for them.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:freightlink/core/theme/app_theme.dart';
import 'package:freightlink/core/theme/flag_font.dart';

String src(String p) => File(p).readAsStringSync();

void main() {
  test('the sign fonts are bundled, tiny and in the fallback', () {
    for (final f in ['TirLinkSigns-Regular', 'TirLinkSigns-Bold', 'TirLinkCheck-Regular']) {
      final file = File('assets/fonts/signs/$f.ttf');
      expect(file.existsSync(), isTrue, reason: f);
      expect(file.lengthSync(), lessThan(8 * 1024), reason: '$f stays tiny');
    }
    final pub = src('pubspec.yaml');
    expect(pub, contains('- family: TirLinkSigns'));
    expect(pub, contains('- family: TirLinkCheck'));
    expect(AppFonts.fallback, [kFlagFontFamily, 'TirLinkSigns', 'TirLinkCheck'], reason: 'flags first, as before');
    expect(src('assets/fonts/signs/README.md'), contains('SIL Open Font License 1.1'));
  });
}
