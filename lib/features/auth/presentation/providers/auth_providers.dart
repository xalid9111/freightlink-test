import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/auth_repository_impl.dart';
import '../../domain/app_user.dart';
import '../../domain/auth_repository.dart';

/// Single instance for the app's lifetime — repositories are cheap
/// wrappers around the (also-singleton) Supabase client, so a plain
/// Provider (not a family/factory) is correct here.
final authRepositoryProvider = Provider<AuthRepository>((ref) => AuthRepositoryImpl());

/// The stream every auth-aware widget/router should watch. `null` means
/// signed out. This is intentionally the ONLY place `authStateChanges()`
/// is subscribed to — Riverpod shares one subscription across every
/// listener, so screens/router don't each open their own stream.
final authStateProvider = StreamProvider<AppUser?>((ref) {
  return ref.watch(authRepositoryProvider).authStateChanges();
});

/// Convenience sync accessor for widgets that just need "who is logged
/// in right now" without handling AsyncValue's loading/error states
/// themselves (e.g. an AppBar greeting).
final currentUserProvider = Provider<AppUser?>((ref) {
  // .valueOrNull (not .asData?.value, which is older/possibly-deprecated
  // API in recent riverpod versions) — returns the last known value
  // during loading/error too, which is exactly "who is logged in right
  // now" semantics for a sync accessor like this.
  return ref.watch(authStateProvider).valueOrNull;
});

/// Just the signed-in user's id (null when signed out). Every provider
/// that fetches user-specific data watches THIS, so logging out and
/// logging in as a different account re-runs those fetches instead of
/// serving the previous account's cached results (e.g. a carrier's
/// carrier-id/offer form missing after switching accounts). Provider
/// only notifies dependents when the id actually changes, so token
/// refreshes for the same user don't trigger needless re-fetches.
final currentUserIdProvider = Provider<String?>((ref) {
  return ref.watch(currentUserProvider)?.id;
});
