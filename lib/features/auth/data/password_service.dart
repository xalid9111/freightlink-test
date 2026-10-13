import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/supabase_config.dart';
import '../../../core/errors/app_exception.dart';

/// Minimum length enforced in the app. The Supabase project may require
/// more (Dashboard → Authentication → Policies); the server's answer
/// ("weak_password") is always respected.
const int kMinPasswordLength = 8;

const Duration _authTimeout = Duration(seconds: 20);

/// Password management — ONLY through the Supabase Auth API.
///
/// Security notes
/// * Passwords are passed straight to Supabase Auth over HTTPS. They are
///   never written to public.users, local storage, logs or exception
///   messages (AppException.message never contains them).
/// * The current password is verified by Supabase Auth itself
///   (signInWithPassword for the same e-mail). If the project setting
///   "update_password_require_current_password" is ON, Supabase verifies it
///   AGAIN inside updateUser — this is the recommended, server-enforced
///   setting (see docs/reports/PACKAGE_1B_REPORT.md).
/// * After a password change Supabase Auth signs out every OTHER session of
///   the account (GoTrue `LogoutAllExceptMe`), so a stolen session on
///   another device stops working.
class PasswordService {
  final SupabaseClient _c;
  PasswordService([SupabaseClient? client]) : _c = client ?? SupabaseConfig.client;

  GoTrueClient get _auth => _c.auth;

  String? get email => _auth.currentUser?.email;

  /// Sign-in providers of the account, e.g. ['email'] or ['google'].
  List<String> get providers {
    final meta = _auth.currentUser?.appMetadata ?? const {};
    final list = meta['providers'];
    if (list is List) return list.map((e) => '$e').toList();
    final one = meta['provider'];
    return one is String ? [one] : const [];
  }

  /// True when the account can sign in with e-mail + password. Unknown
  /// (no provider info) counts as true — the server will decide.
  bool get hasPasswordLogin {
    final p = providers;
    return p.isEmpty || p.contains('email');
  }

  /// Changes the signed-in user's password.
  /// Throws [AppException] with one of these codes (localized as
  /// `error_<code>`): pw_session_missing, pw_no_password_login,
  /// pw_too_short, pw_same, pw_wrong_current, pw_weak, pw_weak_pwned,
  /// pw_rate_limited, pw_reauth_needed, pw_network (nothing changed),
  /// pw_network_unknown (connection lost while saving — outcome unknown),
  /// pw_generic.
  Future<void> changePassword({required String currentPassword, required String newPassword}) async {
    final user = _auth.currentUser;
    final mail = user?.email;
    if (user == null || mail == null || mail.isEmpty) {
      throw const AppException('No active session.', code: 'pw_session_missing');
    }
    if (!hasPasswordLogin) {
      throw const AppException('Account has no password sign-in.', code: 'pw_no_password_login');
    }
    if (newPassword.length < kMinPasswordLength) {
      throw const AppException('New password too short.', code: 'pw_too_short');
    }
    if (newPassword == currentPassword) {
      throw const AppException('New password equals current one.', code: 'pw_same');
    }

    // 1) Verify the current password with Supabase Auth. Nothing has been
    //    changed if this step fails.
    try {
      await _auth.signInWithPassword(email: mail, password: currentPassword).timeout(_authTimeout);
    } on TimeoutException {
      throw const AppException('Timed out verifying password.', code: 'pw_network');
    } on AuthException catch (e) {
      throw _map(e, saving: false);
    } catch (_) {
      throw const AppException('Unexpected error verifying password.', code: 'pw_network');
    }

    // 2) Set the new password. currentPassword is forwarded so a project
    //    with "require current password" ON re-checks it on the server.
    try {
      await _auth
          .updateUser(UserAttributes(password: newPassword, currentPassword: currentPassword))
          .timeout(_authTimeout);
    } on TimeoutException {
      throw const AppException('Timed out saving password.', code: 'pw_network_unknown');
    } on AuthException catch (e) {
      throw _map(e, saving: true);
    } catch (_) {
      throw const AppException('Unexpected error saving password.', code: 'pw_network_unknown');
    }
  }

  /// Sets a new password inside a password-RECOVERY session (the user opened
  /// the e-mailed reset link). Supabase does not ask for the current password
  /// in a recovery session.
  Future<void> setPasswordAfterRecovery(String newPassword) async {
    if (_auth.currentSession == null) {
      throw const AppException('No recovery session.', code: 'pw_link_invalid');
    }
    if (newPassword.length < kMinPasswordLength) {
      throw const AppException('New password too short.', code: 'pw_too_short');
    }
    try {
      await _auth.updateUser(UserAttributes(password: newPassword)).timeout(_authTimeout);
    } on TimeoutException {
      throw const AppException('Timed out saving password.', code: 'pw_network_unknown');
    } on AuthException catch (e) {
      throw _map(e, saving: true);
    } catch (_) {
      throw const AppException('Unexpected error saving password.', code: 'pw_network_unknown');
    }
  }

  /// Exchanges a `token_hash` from a recovery e-mail link (template variant
  /// that works across browsers / iOS home-screen apps) for a recovery
  /// session. Emits AuthChangeEvent.passwordRecovery on success.
  Future<void> verifyRecoveryToken(String tokenHash) async {
    try {
      await _auth.verifyOTP(type: OtpType.recovery, tokenHash: tokenHash).timeout(_authTimeout);
    } on TimeoutException {
      throw const AppException('Timed out.', code: 'pw_network');
    } on AuthRetryableFetchException {
      throw const AppException('Network error.', code: 'pw_network');
    } on AuthException {
      throw const AppException('Recovery link invalid or expired.', code: 'pw_link_invalid');
    }
  }

  /// Sends a password reset / set-password link. For privacy the caller
  /// shows the same confirmation whether or not an account exists for the
  /// address (Supabase also answers the same way).
  Future<void> sendPasswordReset(String address) async {
    final mail = address.trim();
    if (mail.isEmpty || !mail.contains('@')) {
      throw const AppException('Invalid e-mail.', code: 'pw_invalid_email');
    }
    try {
      await _auth.resetPasswordForEmail(mail, redirectTo: _recoveryRedirect()).timeout(_authTimeout);
    } on TimeoutException {
      throw const AppException('Timed out.', code: 'pw_network');
    } on AuthRetryableFetchException {
      throw const AppException('Network error.', code: 'pw_network');
    } on AuthException catch (e) {
      if (e.statusCode == '429' || (e.code ?? '').startsWith('over_')) {
        throw const AppException('Rate limited.', code: 'pw_rate_limited');
      }
      if (e.code == 'validation_failed' || e.code == 'email_address_invalid') {
        throw const AppException('Invalid e-mail.', code: 'pw_invalid_email');
      }
      // Anything else: do not reveal whether the account exists.
    }
  }

  /// Where the reset link returns to. Web/PWA: this app's own URL with the
  /// hash route /reset-password (the address must be in Supabase →
  /// Authentication → URL Configuration → Redirect URLs). Mobile builds
  /// have no deep link configured yet, so Supabase's Site URL is used.
  String? _recoveryRedirect() {
    if (!kIsWeb) return null;
    final b = Uri.base;
    return '${b.origin}${b.path}#/reset-password';
  }

  AppException _map(AuthException e, {required bool saving}) {
    if (e is AuthRetryableFetchException) {
      return AppException('Network error.', code: saving ? 'pw_network_unknown' : 'pw_network');
    }
    if (e is AuthSessionMissingException) {
      return const AppException('No active session.', code: 'pw_session_missing');
    }
    if (e is AuthWeakPasswordException) {
      return AppException('Weak password.', code: e.reasons.contains('pwned') ? 'pw_weak_pwned' : 'pw_weak');
    }
    switch (e.code) {
      case 'invalid_credentials':
      case 'current_password_invalid':
      case 'current_password_required':
        return const AppException('Current password is wrong.', code: 'pw_wrong_current');
      case 'same_password':
        return const AppException('Same password.', code: 'pw_same');
      case 'weak_password':
        return const AppException('Weak password.', code: 'pw_weak');
      case 'over_request_rate_limit':
      case 'over_email_send_rate_limit':
        return const AppException('Rate limited.', code: 'pw_rate_limited');
      case 'reauthentication_needed':
        return const AppException('Reauthentication needed.', code: 'pw_reauth_needed');
      case 'session_not_found':
      case 'session_expired':
      case 'refresh_token_not_found':
        return const AppException('Session expired.', code: 'pw_session_missing');
    }
    if (e.statusCode == '429') return const AppException('Rate limited.', code: 'pw_rate_limited');
    if (!saving && e.statusCode == '400') {
      return const AppException('Current password is wrong.', code: 'pw_wrong_current');
    }
    return const AppException('Password change failed.', code: 'pw_generic');
  }
}

final passwordServiceProvider = Provider<PasswordService>((ref) => PasswordService());
