import 'package:flutter/foundation.dart';

/// A sign-in / password e-mail link that cannot be used any more (owner,
/// 15.11.2026, AutoFix): it expired ("otp_expired", "Email link is invalid or
/// has expired") or it was opened in another browser than the one that asked
/// for it ("Code verifier could not be found", a Google sign-in started in
/// Safari and finished in Gmail's browser). Not a code bug: the user is told
/// what happened and how to get a new link; AutoFix files it as "auth_link".
bool isAuthLinkProblem(Object error) {
  final t = error.toString().toLowerCase();
  return t.contains('otp_expired') ||
      t.contains('email link is invalid') ||
      t.contains('code verifier') ||
      t.contains('bad_code_verifier') ||
      t.contains('flow_state_not_found') ||
      t.contains('flow_state_expired');
}

/// An address Supabase sent back with a refused e-mail link, e.g.
/// https://tirlink.app/#error=access_denied&error_code=otp_expired&error_description=…
/// (the error replaces the "#/reset-password" route, so the app used to open
/// the login page with no word about the password).
/// Only e-mail link errors — a cancelled Google sign-in (also "#error=…")
/// keeps going to the login page as before.
bool urlHasAuthLinkError(String raw) {
  String t;
  try {
    t = Uri.decodeFull(raw.replaceAll('+', ' ')).toLowerCase();
  } catch (_) {
    t = raw.replaceAll('+', ' ').toLowerCase();
  }
  if (!t.contains('error')) return false;
  return t.contains('otp_expired') || t.contains('email link is invalid');
}

bool _baseLinkErrorSeen = false;

/// The router's check: the location itself, and the browser's address once
/// per start (an error in the query before "#/…" stays in the address bar).
bool authLinkErrorIn(Uri location) {
  if (urlHasAuthLinkError(location.toString())) return true;
  if (_baseLinkErrorSeen || !kIsWeb) return false;
  _baseLinkErrorSeen = true;
  return urlHasAuthLinkError(Uri.base.toString());
}

/// Set when such a link was opened; the app shows the notice once.
final ValueNotifier<int> authLinkProblems = ValueNotifier<int>(0);

void reportAuthLinkProblem() => authLinkProblems.value++;
