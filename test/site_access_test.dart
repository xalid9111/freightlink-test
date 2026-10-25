// Site open / closed (owner, 25.10.2026, migration 0068): while closed
// only administrators use the app; everybody else sees the owner's notice.
// Server rules: supabase/tests/local/105_site_access.sql.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freightlink/core/localization/app_strings.dart';
import 'package:freightlink/core/localization/locale_controller.dart';
import 'package:freightlink/core/site/site_access.dart';

String src(String p) => File(p).readAsStringSync();

void main() {
  test('who is kept out: only non-admins while the site is closed', () {
    expect(SiteStatus.fromJson({'closed': false, 'message': 'x', 'admin': false}).blocks, isFalse);
    expect(SiteStatus.fromJson({'closed': true, 'message': 'x', 'admin': true}).blocks, isFalse);
    final s = SiteStatus.fromJson({'closed': true, 'message': '  Saat 18:00-da açılacaq.  ', 'admin': false});
    expect(s.blocks, isTrue);
    expect(s.message, 'Saat 18:00-da açılacaq.');
    expect(SiteStatus.fromJson({'closed': true, 'message': '   '}).message, isNull, reason: 'empty → default text');
    expect(SiteStatus.open.blocks, isFalse);
  });

  Future<void> pump(WidgetTester tester, {String? message, required bool signedIn, VoidCallback? onAdminLogin}) {
    return tester.pumpWidget(ProviderScope(
      overrides: [
        stringsProvider.overrideWithValue(const AppStrings({
          'site_closed_title': 'Sayt müvəqqəti bağlıdır',
          'site_closed_default': 'Saytda texniki işlər aparılır.',
          'site_closed_admin_login': 'Admin girişi',
          'site_closed_sign_out': 'Çıxış',
          'site_closed_retry': 'Yenidən yoxla',
        })),
      ],
      child: MaterialApp(
        home: SiteClosedScreen(
          message: message,
          signedIn: signedIn,
          onAdminLogin: onAdminLogin ?? () {},
          onSignOut: () async {},
          onRetry: () {},
        ),
      ),
    ));
  }

  testWidgets('the notice: the owner\'s text, or the default one', (tester) async {
    await pump(tester, message: 'Saat 18:00-da açılacaq.', signedIn: false);
    expect(find.text('Saat 18:00-da açılacaq.'), findsOneWidget);
    expect(find.text('Sayt müvəqqəti bağlıdır'), findsOneWidget);
    await pump(tester, message: null, signedIn: false);
    expect(find.text('Saytda texniki işlər aparılır.'), findsOneWidget);
  });

  testWidgets('signed out: "Admin girişi" opens the login; signed in: "Çıxış"', (tester) async {
    var tapped = false;
    await pump(tester, signedIn: false, onAdminLogin: () => tapped = true);
    await tester.tap(find.byKey(const ValueKey('site-closed-admin-login')));
    expect(tapped, isTrue);
    expect(find.byKey(const ValueKey('site-closed-sign-out')), findsNothing);
    await pump(tester, signedIn: true);
    expect(find.byKey(const ValueKey('site-closed-sign-out')), findsOneWidget);
    expect(find.byKey(const ValueKey('site-closed-admin-login')), findsNothing);
  });

  test('wired: the whole app is behind the gate; admin switch with the notice dialog', () {
    expect(src('lib/main.dart'), contains('SiteGate(child: applyDesktopPreview('));
    final gate = src('lib/core/site/site_access.dart');
    // Admin comes from the server, a glitch never locks everybody out.
    expect(gate, contains("rpc('site_status')"));
    expect(gate, contains('return SiteStatus.open;'));
    expect(gate, contains('kSiteStatusEvery'));
    final admin = src('lib/features/admin/presentation/admin_pages.dart');
    expect(admin, contains('const SiteAccessCard()'));
    expect(admin, contains("askText(context, 'Saytı bağla"));
    expect(admin, contains('setSiteStatus(closed: close, message: message)'));
    for (final l in ['az', 'tr', 'en', 'ru', 'ka', 'zh']) {
      final j = src('assets/i18n/$l.json');
      for (final k in ['site_closed_title', 'site_closed_default', 'site_closed_admin_login', 'site_closed_sign_out', 'site_closed_retry']) {
        expect(j, contains('"$k"'), reason: '$l $k');
      }
    }
  });

  test('0068 is safe: one new table, server checks, nothing dropped, starts open', () {
    final sql = src('supabase/migrations/0068_site_access.sql').toLowerCase();
    for (final bad in ['drop table', 'truncate', 'delete from']) {
      expect(sql.contains(bad), isFalse, reason: bad);
    }
    expect(sql, contains('closed boolean not null default false'));
    expect(sql, contains('perform public._require_admin();'));
    expect(sql, contains('perform public._admin_log('));
    expect(sql, contains('revoke all on public.site_settings from anon, authenticated;'));
    expect(sql, contains('0068: final check failed'));
    final run = src('supabase/tests/local/run_local.sh');
    expect(run, contains('0068_site_access.sql'));
    expect(run, contains('105_site_access.sql'));
  });
}
