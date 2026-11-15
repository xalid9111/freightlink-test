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

/// Set when such a link was opened; the app shows the notice once.
final ValueNotifier<int> authLinkProblems = ValueNotifier<int>(0);

void reportAuthLinkProblem() => authLinkProblems.value++;
