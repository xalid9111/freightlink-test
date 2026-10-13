import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_config.dart';

/// True while the signed-in session came from a password-reset link and
/// the user has not set a new password yet. While true the router keeps
/// the user on /reset-password (a recovery session must not be used to
/// browse the app — and the reset screen must not be usable WITHOUT one,
/// otherwise it would bypass the current-password check).
///
/// Driven by Supabase auth events. onAuthStateChange replays every past
/// event to a new listener in order, so processing them as a small state
/// machine gives the right result even if this listener starts late:
///   passwordRecovery           -> true
///   userUpdated / signedIn / signedOut -> false
class PasswordRecoveryState extends ValueNotifier<bool> {
  PasswordRecoveryState(Stream<AuthState> events) : super(false) {
    _sub = events.listen((s) {
      switch (s.event) {
        case AuthChangeEvent.passwordRecovery:
          value = true;
        case AuthChangeEvent.userUpdated:
        case AuthChangeEvent.signedIn:
        case AuthChangeEvent.signedOut:
          value = false;
        default:
          break;
      }
    });
  }

  late final StreamSubscription<AuthState> _sub;

  /// Called by the reset screen right after the new password was saved.
  void complete() => value = false;

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}

/// One instance for the app's lifetime (the router listens to it).
final passwordRecoveryProvider = Provider<PasswordRecoveryState>((ref) {
  final s = PasswordRecoveryState(SupabaseConfig.client.auth.onAuthStateChange);
  ref.onDispose(s.dispose);
  return s;
});
