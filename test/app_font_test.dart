// The app uses only one font: Arial (bundled, see pubspec.yaml).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:freightlink/core/theme/app_theme.dart';
import 'package:freightlink/models/ad_models.dart';

void main() {
  test('theme, headings and labels use Arial', () {
    final t = AppTheme.dark;
    expect(t.textTheme.bodyMedium?.fontFamily, 'Arial');
    expect(t.textTheme.titleLarge?.fontFamily, 'Arial');
    expect(AppFonts.display().fontFamily, 'Arial');
    expect(AppFonts.mono().fontFamily, 'Arial');
  });

  test('ads use only Arial', () {
    expect(AdStandardLayout.fonts, ['Arial']);
    expect(AdTextStyle.defaults('company').font, 'Arial');
  });

  test('no other font package or family in lib/', () {
    final bad = RegExp(r"google_fonts|GoogleFonts|fontFamily:\s*'(?!Arial')");
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'))) {
      expect(bad.hasMatch(f.readAsStringSync()), isFalse, reason: f.path);
    }
  });
}
