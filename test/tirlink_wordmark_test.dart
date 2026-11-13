// TırLink brand (owner, 13.11.2026): "Tır" white, "Link" in the accent
// colour (a new night design changes only "Link"), www.tirlink.app small
// under it; every visible "FreightLink" text reads "TırLink".
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freightlink/core/constants/app_constants.dart';
import 'package:freightlink/core/theme/app_theme.dart';
import 'package:freightlink/core/theme/night_theme.dart';
import 'package:freightlink/core/widgets/tirlink_wordmark.dart';

List<TextSpan> _spans(WidgetTester t) {
  final rich = t.widget<Text>(find.byKey(const ValueKey('tirlink-wordmark')));
  return [for (final c in (rich.textSpan! as TextSpan).children!) c as TextSpan];
}

Future<void> _pump(WidgetTester t, {bool site = true}) => t.pumpWidget(MaterialApp(
      key: UniqueKey(),
      home: Scaffold(body: Center(child: TirLinkWordmark(size: 26, showSite: site))),
    ));

void main() {
  tearDown(() => AppColors.use(AppPalette.dark));

  testWidgets('night: Tır white, Link accent, www.tirlink.app white under it', (t) async {
    AppColors.use(AppPalette.dark);
    await _pump(t);
    final s = _spans(t);
    expect(s.map((e) => e.text).join(), 'TırLink');
    expect(s[0].text, 'Tır');
    expect(s[0].style!.color, Colors.white);
    expect(s[1].text, 'Link');
    expect(s[1].style!.color, AppPalette.dark.accent);
    final site = t.widget<Text>(find.byKey(const ValueKey('tirlink-site')));
    expect(site.data, 'www.tirlink.app');
    expect(site.style!.color, Colors.white);
    expect(site.style!.fontSize! < 26 / 2, isTrue, reason: 'small');
    expect(t.getTopLeft(find.byKey(const ValueKey('tirlink-site'))).dy,
        greaterThan(t.getTopLeft(find.byKey(const ValueKey('tirlink-wordmark'))).dy), reason: 'under the name');
  });

  testWidgets('another night design changes only the colour of Link', (t) async {
    final bordo = NightThemeSpec.bordo.toPalette();
    expect(bordo.accent, isNot(AppPalette.dark.accent));
    AppColors.use(bordo);
    await _pump(t);
    final s = _spans(t);
    expect(s[0].style!.color, Colors.white, reason: 'Tır stays white');
    expect(s[1].style!.color, bordo.accent);
  });

  testWidgets('day: Tır is dark on the light ground, Link accent', (t) async {
    AppColors.use(AppPalette.light);
    await _pump(t, site: false);
    final s = _spans(t);
    expect(s[0].style!.color, AppPalette.light.text);
    expect(s[1].style!.color, AppPalette.light.accent);
    expect(find.byKey(const ValueKey('tirlink-site')), findsNothing);
  });

  test('the wordmark is used everywhere; no visible FreightLink left', () {
    String src(String p) => File(p).readAsStringSync();
    expect(AppConstants.appName, 'TırLink');
    for (final p in [
      'lib/features/cargo/presentation/cargo_marketplace_screen.dart',
      'lib/core/router/main_shell.dart',
      'lib/features/admin/presentation/admin_shell.dart',
      'lib/features/auth/presentation/login_screen.dart',
    ]) {
      expect(src(p), contains('TirLinkWordmark('), reason: p);
      expect(src(p), isNot(contains("text: 'Freight'")), reason: p);
    }
    for (final l in ['az', 'tr', 'en', 'ru', 'ka', 'zh']) {
      final m = jsonDecode(src('assets/i18n/$l.json')) as Map<String, dynamic>;
      for (final e in m.entries) {
        expect('${e.value}', isNot(contains('FreightLink')), reason: '$l ${e.key}');
      }
    }
    final manifest = jsonDecode(src('web/manifest.json')) as Map<String, dynamic>;
    expect(manifest['short_name'], 'TırLink');
    final html = src('web/index.html');
    expect(html, contains('<title>TırLink'));
    expect(html, contains('apple-mobile-web-app-title" content="TırLink"'));
    expect(html.replaceAll('FreightLinkSans', ''), isNot(contains('FreightLink')));
  });
}
