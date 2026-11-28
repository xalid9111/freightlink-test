import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../autofix/autofix.dart';
import '../autofix/autofix_logic.dart';

/// Keeps a valid sign-in when another window signs it out by mistake, and
/// tells AutoFix why every sign-out the user did not ask for happened
/// (owner, 28.11.2026: on the computer — the TırLink app window plus Chrome
/// and Edge — "daxil oluram, 10–15 saniyə sonra giriş səhifəsinə qaytarır").
///
/// On the web every window of the site shares the session and hears the
/// others' sign-in events (Supabase's BroadcastChannel). An old window whose
/// own refresh failed says "signed out" and every other window drops its
/// session too. Then, once a minute at most, this window offers its last
/// refresh token to the server again: if the account was really signed out
/// (the user pressed "Hesabdan çıxış" in any window, or the account was
/// deleted / blocked) the server refuses it and nothing changes; if only a
/// stale window gave up, the sign-in comes back at once.
class SessionGuard {
  SessionGuard._();

  static StreamSubscription<AuthState>? _sub;
  static String? _lastRefresh;
  static String? _lastUser;
  static int? _skewSeconds;
  static DateTime? _lastTry;
  static bool _userSignOut = false;

  /// The user pressed "Hesabdan çıxış" (or deleted the account) in THIS window.
  static void userSignsOut() => _userSignOut = true;

  /// Local clock − the server's (from the token's "iat"), in seconds.
  @visibleForTesting
  static int? skewOf(String accessToken, DateTime now) {
    try {
      final parts = accessToken.split('.');
      if (parts.length < 2) return null;
      final payload = jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(parts[1])))) as Map;
      final iat = payload['iat'];
      if (iat is! num) return null;
      return now.millisecondsSinceEpoch ~/ 1000 - iat.toInt();
    } catch (_) {
      return null;
    }
  }

  /// Whether a sign-out should be offered back to the server.
  @visibleForTesting
  static bool shouldRestore({
    required bool userInitiated,
    required String? lastRefreshToken,
    required DateTime? lastTry,
    required DateTime now,
  }) =>
      !userInitiated &&
      lastRefreshToken != null &&
      (lastTry == null || now.difference(lastTry) > const Duration(minutes: 1));

  static void start(GoTrueClient auth) {
    _sub?.cancel();
    final s = auth.currentSession;
    if (s != null) {
      _lastRefresh = s.refreshToken;
      _lastUser = s.user.id;
    }
    _sub = auth.onAuthStateChange.listen((state) {
      final session = state.session;
      if (session != null) {
        _lastRefresh = session.refreshToken;
        _lastUser = session.user.id;
        if (state.event == AuthChangeEvent.signedIn || state.event == AuthChangeEvent.tokenRefreshed) {
          _skewSeconds = skewOf(session.accessToken, DateTime.now()) ?? _skewSeconds;
        }
        return;
      }
      if (state.event != AuthChangeEvent.signedOut) return;
      final userInitiated = _userSignOut || state.signOutReason == SignOutReason.userInitiated;
      _userSignOut = false;
      final token = _lastRefresh;
      final had = _lastUser != null;
      _lastRefresh = null;
      _lastUser = null;
      if (!had || userInitiated) return;
      final reason = state.fromBroadcast ? 'another window' : (state.signOutReason?.name ?? 'unknown');
      final now = DateTime.now();
      if (!shouldRestore(userInitiated: false, lastRefreshToken: token, lastTry: _lastTry, now: now)) {
        _report(reason, restored: false, tried: false);
        return;
      }
      _lastTry = now;
      unawaited(Future<void>.delayed(const Duration(milliseconds: 500), () async {
        var restored = false;
        try {
          if (auth.currentSession == null) {
            await auth.setSession(token!);
            restored = auth.currentSession != null;
          } else {
            restored = true; // another window's new session already arrived
          }
        } catch (_) {
          restored = false;
        }
        _report(reason, restored: restored, tried: true);
      }));
    });
  }

  static void _report(String reason, {required bool restored, required bool tried}) {
    AutoFix.instance.capture(
      'Signed out without asking (gözlənilməz çıxış)',
      null,
      source: 'auth',
      forceKind: AutoFixKind.auth,
      detail: 'reason=$reason restored=$restored tried=$tried clock_skew_s=${_skewSeconds ?? '?'}',
    );
  }
}
