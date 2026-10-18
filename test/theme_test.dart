import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freightlink/core/theme/app_theme.dart';
import 'package:freightlink/core/theme/theme_mode.dart';

void main() {
  tearDown(() => AppColors.use(AppPalette.dark));

  test('night mode keeps the approved colours exactly (nothing changes for night users)', () {
    const p = AppPalette.dark;
    final got = [
      p.background, p.hero, p.card, p.cardAlt, p.line, p.lineSoft, p.text, p.textSoft, p.accent, p.accentFill,
      p.myBubble, p.route, p.routeSoft, p.blue, p.online, p.danger, p.urgentBg, p.urgentFg, p.newBg, p.newFg,
    ].map((c) => c.toARGB32()).toList();
    expect(got, [
      0xFF02050C, 0xFF02050C, 0xFF0C1322, 0xFF131B2B, 0xFF1C2638, 0xFF161F30, 0xFFF2F4F7, 0xFF9AA4B5, 0xFFFF6B33, 0xFFD4420E,
      0xFFC93D0C, 0xFF2BB3A9, 0xFF0F2B2A, 0xFF3BA3FF, 0xFF4ADE80, 0xFFFF6B6B, 0xFF3A1A10, 0xFFFF8A5C, 0xFF0F2B2A, 0xFF5FD4C9,
    ]);
    const c = ChatPalette.dark;
    expect([c.background, c.dots, c.mine, c.theirs, c.meta, c.readTick, c.dateChip].map((x) => x.toARGB32()).toList(),
        [0xFF0B141A, 0xFF13212A, 0xFF005C4B, 0xFF1F2C34, 0xFF8696A0, 0xFF53BDEB, 0xFF182229]);
  });

  test('night is the default; only a saved "day" switches', () {
    expect(AppColors.isDay, isFalse);
    expect(paletteFor(null), same(AppPalette.dark));
    expect(paletteFor('night'), same(AppPalette.dark));
    expect(paletteFor('garbage'), same(AppPalette.dark));
    expect(paletteFor('day'), same(AppPalette.light));
  });

  test('the whole app follows the chosen palette', () {
    expect(AppTheme.current.brightness, Brightness.dark);
    expect(AppColors.background.toARGB32(), 0xFF02050C);
    AppColors.use(AppPalette.light);
    expect(AppColors.isDay, isTrue);
    expect(AppTheme.current.brightness, Brightness.light);
    expect(AppColors.background, AppPalette.light.background);
    expect(ChatColors.background, ChatPalette.light.background);
  });

  test('day text is readable on day cards (contrast)', () {
    double lum(Color c) => c.computeLuminance();
    double ratio(Color a, Color b) {
      final x = lum(a), y = lum(b);
      return (x > y ? x + 0.05 : y + 0.05) / (x > y ? y + 0.05 : x + 0.05);
    }
    const p = AppPalette.light;
    expect(ratio(p.text, p.card), greaterThan(7));
    expect(ratio(p.textSoft, p.card), greaterThan(4.5));
    expect(ratio(Colors.white, p.accentFill), greaterThan(3));
  });

  test('saved before the first screen; Settings switch (admins only until every screen is ready)', () {
    final main = File('lib/main.dart').readAsStringSync();
    expect(main.indexOf('await loadSavedTheme();') < main.indexOf('runApp('), isTrue);
    expect(main.contains('themeMode: AppColors.isDay ? ThemeMode.light : ThemeMode.dark'), isTrue);
    final settings = File('lib/features/auth/presentation/settings_screen.dart').readAsStringSync();
    expect(settings.contains('const kDayModeForEveryone = false;'), isTrue);
    expect(settings.contains('onSelectionChanged: (v) => chooseTheme(day: v.first)'), isTrue);
    // Stored on the device only, never on the server.
    final mode = File('lib/core/theme/theme_mode.dart').readAsStringSync();
    expect(mode.contains('supabase'), isFalse);
  });
}
