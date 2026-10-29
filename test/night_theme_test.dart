// Night colours chosen by the admin (owner, 29.10.2026, migration 0076):
// day never changes, "Klassik" is exactly the old night, "Bordo Premium"
// has the owner's colours, the admin page edits / previews / publishes.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freightlink/core/theme/app_theme.dart';
import 'package:freightlink/core/theme/night_theme.dart';
import 'package:freightlink/core/theme/theme_mode.dart';
import 'package:freightlink/features/admin/data/night_theme_repository.dart';
import 'package:freightlink/features/admin/presentation/admin_design_page.dart';

String src(String p) => File(p).readAsStringSync();
String h(Color c) => hexOf(c);

void main() {
  tearDown(() => AppColors.use(AppPalette.dark));

  test('day is untouched: AppPalette.light keeps every colour, and night colours never reach it', () {
    const l = AppPalette.light;
    expect([h(l.background), h(l.card), h(l.cardAlt), h(l.line), h(l.lineSoft), h(l.text), h(l.textSoft), h(l.accent), h(l.accentFill)],
        ['#FFFFFF', '#FFFFFF', '#F2F5F9', '#E2E7EE', '#EDF1F5', '#0F1B2D', '#5B6676', '#E8521A', '#E8521A']);
    expect([l.gradient, l.glow, l.custom], [0, 0, false]);
    expect(paletteFor('day', night: NightThemeSpec.bordo), same(AppPalette.light), reason: 'the admin palette is for night only');
    AppColors.use(AppPalette.light);
    expect(h(AppColors.tileBg), '#FFFFFF');
    expect(ChatColors.background, ChatPalette.light.background);
  });

  test('Klassik FreightLink is exactly the existing night', () {
    expect(NightThemeSpec.classic.isClassic, isTrue);
    expect(NightThemeSpec.classic.toPalette(), same(AppPalette.dark));
    expect(paletteFor(null), same(AppPalette.dark));
    expect(paletteFor('night', night: NightThemeSpec.classic), same(AppPalette.dark));
    AppColors.use(AppPalette.dark);
    expect([h(AppColors.tileBg), h(AppColors.tileLine), h(AppColors.tileSelectedBg)], ['#0E1A2E', '#2A3B57', '#1A1410']);
    expect(ChatColors.mine, ChatPalette.dark.mine);
    final t = AppTheme.current;
    expect(t.appBarTheme.backgroundColor, AppPalette.dark.hero, reason: 'no tint in classic');
    expect(t.cardTheme.elevation, 0, reason: 'no glow in classic');
  });

  test('Bordo Premium: the owner\'s colours; status colours, VIP gold and WhatsApp stay', () {
    const b = NightThemeSpec.bordo;
    expect([for (final k in NightThemeSpec.colorKeys) h(b.colorOf(k))],
        ['#090A0E', '#1C171D', '#8F2945', '#C34467', '#512837', '#F5F2F4', '#A9A4AB']);
    final p = b.toPalette();
    expect(p.brightness, Brightness.dark);
    expect([h(p.background), h(p.card), h(p.accentFill), h(p.accent), h(p.line), h(p.text), h(p.textSoft)],
        ['#090A0E', '#1C171D', '#8F2945', '#C34467', '#512837', '#F5F2F4', '#A9A4AB']);
    for (final (a, c) in [(p.online, AppPalette.dark.online), (p.danger, AppPalette.dark.danger), (p.route, AppPalette.dark.route)]) {
      expect(a, c);
    }
    expect(AppColors.vipGold, const Color(0xFFFFC83D));
    expect(AppColors.whatsapp, const Color(0xFF25D366));
    AppColors.use(p);
    expect(AppColors.tileBg, p.card, reason: 'no navy tiles in Bordo');
    expect(ChatColors.theirs, p.card);
    final t = AppTheme.current;
    expect(t.colorScheme.primary, p.accentFill);
    expect(t.cardTheme.elevation, greaterThan(0), reason: 'soft glow');
    expect(t.appBarTheme.backgroundColor, isNot(p.hero), reason: 'gradient tint');
    expect(readableEnough(b), isTrue, reason: 'Bordo reads well');
  });

  test('colours travel as #RRGGBB JSON; anything else is refused', () {
    final j = NightThemeSpec.bordo.toJson();
    expect(j['button'], '#8F2945');
    expect(NightThemeSpec.fromJson(j)!.sameAs(NightThemeSpec.bordo), isTrue);
    expect(NightThemeSpec.fromJson({...j, 'card': 'red'}), isNull);
    expect(NightThemeSpec.fromJson({...j}..remove('text')), isNull);
    expect(NightThemeSpec.fromJson(null), isNull);
    expect(NightThemeSpec.fromJson({...j, 'glow': 7})!.glow, 1, reason: 'levels are clamped');
    expect(parseHex('c34467'), const Color(0xFFC34467));
    expect(parseHex('#12345'), isNull);
  });

  test('readability check: unreadable text cannot be published', () {
    final bad = NightThemeSpec.bordo.withColor('text', const Color(0xFF1C1C1C));
    expect(readableEnough(bad), isFalse);
    expect(contrastChecks(bad).first.ok, isFalse);
    expect(contrastRatio(Colors.white, Colors.black), closeTo(21, 0.01));
  });

  testWidgets('admin page: presets, live preview, HEX rows, levels, readability, the five actions', (tester) async {
    tester.view.physicalSize = const Size(900, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        publishedNightThemeProvider.overrideWith((ref) async => const PublishedNightTheme()),
        savedNightThemesProvider.overrideWith((ref) async => [const SavedNightTheme(id: 't1', name: 'Black Edition', spec: NightThemeSpec.bordo)]),
      ],
      child: const MaterialApp(home: Scaffold(body: AdminDesignPage())),
    ));
    await tester.pumpAndSettle();
    for (final t in ['Klassik FreightLink', 'Bordo Premium', 'Öz kombinasiyam', 'Black Edition', '1. Əsas fon', '4. Aktiv ikonlar və vurğular',
      '7. Gradientin intensivliyi', '8. Kölgə və yumşaq parıltı', 'Önizlə (yalnız bu cihaz)', 'Yadda saxla', 'Yayımla', 'Əvvəlki temaya qayıt',
      'Sıfırla (Klassik)']) {
      expect(find.text(t), findsWidgets, reason: t);
    }
    expect(find.byKey(const ValueKey('design-preview-panel')), findsOneWidget);
    // Starts from what is published (classic).
    expect(find.byKey(ValueKey('design-row-button-${hexOf(AppPalette.dark.accentFill)}')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('design-bordo')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('design-row-button-#8F2945')), findsOneWidget, reason: 'Bordo fills the colours');
    // Typing a HEX makes it "Öz kombinasiyam".
    await tester.enterText(find.byKey(const ValueKey('design-hex-accent')), '#D05577');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('design-row-accent-#D05577')), findsOneWidget);
    final custom = tester.widget<InputChip>(find.byKey(const ValueKey('design-custom')));
    expect(custom.selected, isTrue);
    // The colour picker opens.
    await tester.tap(find.byKey(const ValueKey('design-swatch-card')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('picker-swatch')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('picker-ok')));
    await tester.pumpAndSettle();
    // Nothing published before → restore is off.
    expect(tester.widget<ButtonStyleButton>(find.byKey(const ValueKey('design-restore'))).onPressed, isNull);
    expect(tester.takeException(), isNull);
  });

  test('wired: start-up loads the published night, admin section, server checks, safe SQL', () {
    final mode = src('lib/core/theme/theme_mode.dart');
    expect(src('lib/core/theme/night_theme_remote.dart'), contains("rpc('night_theme_current')"), reason: 'read only');
    expect(mode, contains('fetchPublishedNightTheme()'));
    expect(mode, contains('if (mode == kThemeDay) {'), reason: 'day returns before any night colour');
    expect(mode, contains('.timeout(const Duration(milliseconds: 1500))'), reason: 'never blocks the start for long');
    expect(src('lib/features/admin/presentation/admin_shell.dart'), contains("AdminSection('design', 'Dizayn və Rənglər', Icons.palette_outlined)"));
    expect(src('lib/main.dart'), contains('NightPreviewBadge('));
    final sql = src('supabase/migrations/0076_night_theme.sql').toLowerCase();
    for (final bad in ['drop table', 'truncate', 'delete from public.', 'update public.', 'alter table public.users', 'drop column']) {
      expect(sql.contains(bad), isFalse, reason: bad);
    }
    for (final fn in ['admin_night_theme_save', 'admin_night_theme_delete', 'admin_night_theme_publish', 'admin_night_theme_restore', 'admin_night_themes']) {
      final body = sql.substring(sql.indexOf('function public.$fn('));
      expect(body.substring(0, body.indexOf(r'end $$')), contains('perform public._require_admin();'), reason: fn);
    }
    expect(sql, contains('revoke all on public.night_theme_state from anon, authenticated;'));
    expect(sql, contains('grant execute on function public.night_theme_current() to anon, authenticated;'));
  });
}
