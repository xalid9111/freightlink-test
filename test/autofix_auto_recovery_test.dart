// AutoFix list of 15.11.2026 (owner: "bunları həll et və avtomatik həll yolunu
// tap"): realtime drops are one reconnect for all chat streams, pictures that
// did not arrive retry by themselves and count as network, expired /
// other-browser e-mail links give the user a clear notice instead of an error.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:freightlink/core/auth/auth_link_notice.dart';
import 'package:freightlink/core/auth/auth_link_problem.dart';
import 'package:freightlink/core/autofix/autofix_logic.dart';
import 'package:freightlink/core/localization/app_strings.dart';
import 'package:freightlink/core/localization/locale_controller.dart';
import 'package:freightlink/core/widgets/retry_asset_image.dart';

String src(String p) => File(p).readAsStringSync();

void main() {
  group('the 10 reports of 15.11.2026 are classified right', () {
    test('1–2 realtime drop: messaging, recoverable', () {
      for (final t in [
        'RealtimeSubscribeException(status: channelError, details: null)',
        'RealtimeSubscribeException(status: channelError, details: WebSocketChannelException: WebSocket connection failed.)',
      ]) {
        final i = classifyError('RealtimeSubscribeException', t, messaging: true);
        expect(i.kind, AutoFixKind.messaging, reason: t);
        expect(i.transient, isTrue, reason: t);
      }
    });

    test('3–4 a picture that did not arrive: network, recoverable', () {
      for (final t in [
        'AbortError: Aborted by failure.\nimage resource service: resolving an image frame',
        'Unable to load asset: "assets/images/cargo/type_dump_night.png".\nimage resource service: resolving an image codec',
      ]) {
        final i = classifyError('JSObject', t);
        expect(i.kind, AutoFixKind.network, reason: t);
        expect(i.code, 'image', reason: t);
        expect(i.transient, isTrue, reason: t);
      }
      // A picture that arrived but cannot be decoded stays a runtime "image".
      expect(classifyError('x', 'Invalid image data\nimage resource service').kind, AutoFixKind.runtime);
    });

    test('5–7, 10 e-mail link: auth_link, the user is told', () {
      for (final t in [
        'AuthException(message: Email link is invalid or has expired, statusCode: otp_expired, code: access_denied)',
        'AuthException(message: Code verifier could not be found in local storage., statusCode: null, code: null)',
      ]) {
        final i = classifyError('minified:jz', t);
        expect(i.kind, AutoFixKind.auth, reason: t);
        expect(i.code, 'auth_link', reason: t);
        expect(isAuthLinkProblem(t), isTrue, reason: t);
      }
      expect(isAuthLinkProblem('AuthException(message: Invalid login credentials)'), isFalse);
    });
  });

  test('one reconnect covers every chat stream that failed with the socket', () {
    final a = src('lib/core/autofix/autofix.dart');
    expect(a, contains('if (_chatReconnectPending) return true;'));
    expect(a, contains('_chatReconnectPending = true;'));
    expect(a, contains("if (classified.code == 'auth_link') {"));
    // The auth stream goes on after such a link (no broken sign-in state).
    expect(src('lib/features/auth/data/auth_repository_impl.dart'), contains('if (isAuthLinkProblem(e)) {'));
  });

  testWidgets('an app picture that fails tries again by itself, then shows the fallback', (t) async {
    await t.pumpWidget(const MaterialApp(
      home: Scaffold(body: RetryAssetImage('assets/images/cargo/__missing__.png', fallback: Text('fallback'))),
    ));
    await t.pumpAndSettle();
    expect(find.text('fallback'), findsOneWidget);
    expect(find.byKey(const ValueKey('assets/images/cargo/__missing__.png#0')), findsOneWidget);
    await t.pump(RetryAssetImage.delayFor(1));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('assets/images/cargo/__missing__.png#1')), findsOneWidget, reason: 'tried again');
    await t.pump(RetryAssetImage.delayFor(2));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('assets/images/cargo/__missing__.png#2')), findsOneWidget);
    await t.pump(const Duration(seconds: 30));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('assets/images/cargo/__missing__.png#2')), findsOneWidget,
        reason: 'stops after 2');
    expect(find.text('fallback'), findsOneWidget);
    expect(src('lib/features/cargo/presentation/widgets/cargo_picture.dart'), contains('RetryAssetImage('));
    expect(src('lib/features/cargo/presentation/widgets/cargo_category_bar.dart'), contains('RetryAssetImage('));
  });

  testWidgets('an expired link shows the notice with "Giriş"', (t) async {
    const strings = AppStrings({'auth_link_problem': 'Bu link artıq işləmir', 'auth_link_login': 'Giriş'});
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (c, s) => const Scaffold(body: Text('home'))),
      GoRoute(path: '/login', builder: (c, s) => const Scaffold(body: Text('login page'))),
    ]);
    await t.pumpWidget(ProviderScope(
      overrides: [stringsProvider.overrideWithValue(strings)],
      child: MaterialApp.router(
        routerConfig: router,
        scaffoldMessengerKey: appMessengerKey,
        builder: (c, child) => AuthLinkNotice(router: router, child: child!),
      ),
    ));
    await t.pumpAndSettle();
    reportAuthLinkProblem();
    await t.pump();
    await t.pump(const Duration(milliseconds: 300));
    expect(find.text('Bu link artıq işləmir'), findsOneWidget);
    await t.tap(find.text('Giriş'));
    await t.pumpAndSettle();
    expect(find.text('login page'), findsOneWidget);
    expect(src('lib/main.dart'), contains('scaffoldMessengerKey: appMessengerKey,'));
  });
}
