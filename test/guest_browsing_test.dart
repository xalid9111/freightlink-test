// Browsing without an account (owner, 07.11.2026, SQL 0107): the link opens
// Yüklər; a visitor looks at the public pages and is sent to sign in for
// any action, coming back to the same page afterwards. No phone number is
// shown to a visitor.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freightlink/core/localization/app_strings.dart';
import 'package:freightlink/core/router/guest_access.dart';
import 'package:freightlink/core/widgets/guest_sign_in.dart';
import 'package:go_router/go_router.dart';

String src(String p) => File(p).readAsStringSync();
final _az = AppStrings(Map<String, String>.from(jsonDecode(src('assets/i18n/az.json')) as Map));

void main() {
  tearDown(() => debugSignedOut = null);

  test('the public pages a visitor may open', () {
    for (final p in ['/cargo', '/cargo/abc-1', '/load/abc', '/market', '/market/l/42', '/tirpark', '/tirpark/p/7', '/services', '/service/9', '/user/u1', '/user/u1/catalog']) {
      expect(isGuestPath(p), isTrue, reason: p);
    }
    for (final p in ['/cargo/create', '/cargo/favorites', '/cargo/en-route', '/messages', '/profile', '/profile/tirpark', '/market/new', '/market/mine',
      '/market/favorites', '/favorites', '/service-join', '/service-edit', '/tirpark/manage', '/tirpark/bookings', '/admin', '/chat/1', '/my-cargo', '/jobs', '/finance']) {
      expect(isGuestPath(p), isFalse, reason: p);
    }
  });

  test('the sign-in address keeps where to come back to', () {
    expect(signInLocation('/market/l/42'), '/login?from=%2Fmarket%2Fl%2F42');
    expect(signInLocation('/login?from=x'), '/login', reason: 'never back to the login page itself');
  });

  Future<GoRouter> pumpRouter(WidgetTester tester) async {
    final router = GoRouter(initialLocation: '/market/l/42', routes: [
      GoRoute(
        path: '/market/l/:id',
        builder: (c, s) => Scaffold(body: Builder(builder: (c) => Column(children: [
              TextButton(onPressed: () => askSignIn(c) ? null : ScaffoldMessenger.of(c).showSnackBar(const SnackBar(content: Text('done'))), child: const Text('act')),
              GuestSignInButton(s: _az),
            ]))),
      ),
      GoRoute(path: '/login', builder: (c, s) => Scaffold(body: Text('login from ${s.uri.queryParameters['from']}'))),
    ]);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    return router;
  }

  testWidgets('a visitor\'s action opens sign-in, keeping the page to come back to', (tester) async {
    debugSignedOut = () => true;
    await pumpRouter(tester);
    await tester.tap(find.text('act'));
    await tester.pumpAndSettle();
    expect(find.text('login from /market/l/42'), findsOneWidget);
    expect(find.text('done'), findsNothing, reason: 'the action itself did not run');
  });

  testWidgets('signed in: the action runs as before', (tester) async {
    debugSignedOut = () => false;
    await pumpRouter(tester);
    await tester.tap(find.text('act'));
    await tester.pump();
    expect(find.text('done'), findsOneWidget);
  });

  testWidgets('the contact button for a visitor: no number, sign in', (tester) async {
    debugSignedOut = () => true;
    await pumpRouter(tester);
    expect(find.text('Əlaqə üçün daxil olun'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('guest-sign-in')));
    await tester.pumpAndSettle();
    expect(find.text('login from /market/l/42'), findsOneWidget);
  });

  test('wired: Yüklər opens first; the router lets a visitor through only on public pages', () {
    final r = src('lib/core/router/app_router.dart');
    expect(r, contains("initialLocation: '/cargo',"));
    expect(r, contains('if (!signedIn && isGuestPath(loc)) return null;'));
    expect(r, contains("if (state.uri.path == '/' || state.uri.path.isEmpty) return '/cargo';"));
    final l = src('lib/features/auth/presentation/login_screen.dart');
    expect(l, contains("key: const ValueKey('login-close')"));
    expect(l, contains("isGuestPath(Uri.parse(from).path) ? from : '/cargo'"), reason: 'closing never loops back to a closed page');
    expect(l, contains("queryParameters: {'from': from}"), reason: 'registering also comes back');
  });

  test('wired: every action on the public pages asks a visitor to sign in; no number shown', () {
    const gate = 'if (askSignIn(context)) return;';
    final cargo = src('lib/features/cargo/presentation/cargo_detail_screen.dart');
    expect(cargo, contains('if (isSignedOut()) {\n      return Card('), reason: 'load: no contact numbers');
    expect(cargo, contains(gate), reason: 'load: message');
    expect(cargo, contains('if (!isSignedOut()) ...[\n          gap(),\n          _CarrierOfferSection('), reason: 'offer / report need an account');
    final market = src('lib/features/market/presentation/market_detail_screen.dart');
    expect(RegExp(RegExp.escape(gate)).allMatches(market).length, 2, reason: 'ad: message + offer');
    expect(market, contains('askSignIn(context) ? null : showCallOptions(context, s, phone)'));
    expect(src('lib/features/market/presentation/market_card.dart'), contains('askSignIn(context) ? null : ref.read(marketFavoriteIdsProvider.notifier)'));
    expect(src('lib/features/cargo/presentation/widgets/cargo_picture.dart'), contains(gate));
    expect(src('lib/features/favorites/favorites.dart'), contains(gate));
    final svc = src('lib/features/services/presentation/service_detail_screen.dart');
    expect(RegExp(RegExp.escape(gate)).allMatches(svc).length, 3, reason: 'service: report, review, claim');
    expect(svc, contains('if (!isSignedOut() && (p.phone ?? \'\').isNotEmpty)'));
    final w = src('lib/features/services/presentation/service_widgets.dart');
    expect(RegExp(RegExp.escape(gate)).allMatches(w).length, 2, reason: 'service: message + message options');
    expect(w, contains('askSignIn(context) ? null : showCallOptions(context, s, phone)'));
    final park = src('lib/features/tirpark/presentation/tir_park_detail_screen.dart');
    expect(park, contains("if (isSignedOut()) GuestSignInButton(s: s, label: 'guest_book_sign_in') else TirParkBookingSection("));
    expect(park, contains('if (isSignedOut()) GuestSignInButton(s: s) else _PhoneCard('));
    expect(park, contains(gate), reason: 'park: review');
    expect(src('lib/features/ads/presentation/public_profile_screen.dart'), contains(gate), reason: 'profile: message');
  });

  test('SQL 0107: visitors read the public catalogue like a signed-in stranger; nothing private, no writes', () {
    final sql = src('supabase/migrations/0107_guest_browsing.sql');
    expect(sql, contains("execute format('create policy %I on public.%I for select to anon using (%s)', p.policyname || '_guest', t, p.qual);"));
    expect(sql, contains("has_table_privilege('authenticated', 'public.' || t, 'select')"));
    for (final closed in ["'users'", "'messages'", "'conversations'", "'tir_park_bookings'", "'user_favorites'", "'job_seeker_profiles'", "'payments'"]) {
      expect(RegExp(r'tables text\[\] := array\[[^;]*' + RegExp.escape(closed)).hasMatch(sql), isFalse, reason: '$closed stays closed');
    }
    final lower = sql.toLowerCase();
    expect(lower.contains('grant insert') || lower.contains('grant update') || lower.contains('grant delete') || lower.contains('grant all'), isFalse);
    expect(lower.contains('drop table') || lower.contains('truncate') || lower.contains('delete from'), isFalse);
    expect(src('supabase/tests/local/run_local.sh'), contains('144_guest_browsing.sql'));
  });

  test('the texts in all six languages', () {
    for (final l in ['az', 'tr', 'en', 'ru', 'ka', 'zh']) {
      final j = jsonDecode(src('assets/i18n/$l.json')) as Map;
      for (final k in ['guest_browse_back', 'guest_sign_in_needed', 'guest_contact_sign_in', 'guest_book_sign_in']) {
        expect(j.containsKey(k), isTrue, reason: '$l $k');
      }
    }
  });
}
