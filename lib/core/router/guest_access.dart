import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../config/supabase_config.dart';

/// Browsing without an account (owner, 07.11.2026, SQL 0107): the link
/// opens the app straight away; a visitor may LOOK at Yüklər, TIR Bazarı,
/// TIRPark, Servislər / Mağazalar and public profiles. Anything else — a
/// "+" form, Mesajlar, Profil, a message, a call / phone number, a heart,
/// a booking, a review — sends him to sign in, and after signing in he is
/// brought back to the page he was on.

/// The pages a visitor may open (matched location, no query).
bool isGuestPath(String loc) {
  if (const {'/cargo', '/market', '/tirpark', '/services'}.contains(loc)) return true;
  return _guestPatterns.any((r) => r.hasMatch(loc));
}

final _guestPatterns = [
  RegExp(r'^/cargo/(?!create$|en-route$|favorites$)[^/]+$'), // a load (/cargo/:id)
  RegExp(r'^/load/[^/]+$'),
  RegExp(r'^/market/l/[^/]+$'), // a TIR Bazarı ad
  RegExp(r'^/tirpark/p/[^/]+$'), // a park page
  RegExp(r'^/service/[^/]+$'), // a service / shop page
  RegExp(r'^/user/[^/]+(/catalog)?$'), // a public profile
];

/// Tests set this instead of a real Supabase session.
@visibleForTesting
bool Function()? debugSignedOut;

/// True when nobody is signed in (a visitor).
bool isSignedOut() {
  final f = debugSignedOut;
  if (f != null) return f();
  try {
    return SupabaseConfig.client.auth.currentSession == null;
  } catch (_) {
    return false; // Supabase not started (tests): behave as before
  }
}

/// The sign-in page, coming back to [from] afterwards.
String signInLocation(String from) =>
    from.startsWith('/') && !from.startsWith('/login') ? Uri(path: '/login', queryParameters: {'from': from}).toString() : '/login';

/// Call at the start of an action that needs an account. For a visitor it
/// opens the sign-in page (back to this page afterwards) and returns true:
/// the action stops there. Signed in: returns false and nothing happens.
bool askSignIn(BuildContext context) {
  if (!isSignedOut()) return false;
  String here;
  try {
    here = GoRouter.of(context).routerDelegate.currentConfiguration.uri.toString();
  } catch (_) {
    here = '/cargo';
  }
  try {
    GoRouter.of(context).go(signInLocation(here));
  } catch (_) {}
  return true;
}
