// A sign-out the user did not ask for (owner, 28.11.2026: on the computer
// "daxil oluram, 10–15 saniyə sonra giriş səhifəsinə qaytarır"): offered
// back once a minute at most, never after the user's own sign-out; the
// reason and the clock difference go to AutoFix.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:freightlink/core/auth/session_guard.dart';

String _jwt(Map<String, Object> payload) =>
    '${base64Url.encode(utf8.encode('{"alg":"HS256"}'))}.${base64Url.encode(utf8.encode(jsonEncode(payload))).replaceAll('=', '')}.sig';

void main() {
  test('the clock difference from the token (local − server, seconds)', () {
    final now = DateTime.utc(2026, 11, 28, 12);
    final iat = now.millisecondsSinceEpoch ~/ 1000;
    expect(SessionGuard.skewOf(_jwt({'iat': iat - 90}), now), 90, reason: 'the computer 90 s ahead');
    expect(SessionGuard.skewOf(_jwt({'iat': iat + 300}), now), -300, reason: '5 min behind');
    expect(SessionGuard.skewOf('not-a-token', now), isNull);
  });

  test('offered back only when the user did not sign out, and at most once a minute', () {
    final now = DateTime(2026, 11, 28, 12);
    expect(SessionGuard.shouldRestore(userInitiated: false, lastRefreshToken: 'r', lastTry: null, now: now), isTrue);
    expect(SessionGuard.shouldRestore(userInitiated: true, lastRefreshToken: 'r', lastTry: null, now: now), isFalse,
        reason: '"Hesabdan çıxış" stays a sign-out');
    expect(SessionGuard.shouldRestore(userInitiated: false, lastRefreshToken: null, lastTry: null, now: now), isFalse);
    expect(
        SessionGuard.shouldRestore(
            userInitiated: false, lastRefreshToken: 'r', lastTry: now.subtract(const Duration(seconds: 20)), now: now),
        isFalse,
        reason: 'never a loop');
    expect(
        SessionGuard.shouldRestore(
            userInitiated: false, lastRefreshToken: 'r', lastTry: now.subtract(const Duration(minutes: 2)), now: now),
        isTrue);
  });

  test('wired: started after Supabase, the own sign-out marked, reported to AutoFix', () {
    expect(File('lib/main.dart').readAsStringSync(), contains('SessionGuard.start(SupabaseConfig.client.auth);'));
    expect(File('lib/features/auth/data/auth_repository_impl.dart').readAsStringSync(),
        contains('SessionGuard.userSignsOut(); // asked for: never offered back'));
    final g = File('lib/core/auth/session_guard.dart').readAsStringSync();
    expect(g, contains('await auth.setSession(token!);'), reason: 'the server decides: a revoked token is refused');
    expect(g, contains("'reason=\$reason restored=\$restored tried=\$tried clock_skew_s="));
  });
}
