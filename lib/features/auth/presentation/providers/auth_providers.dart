import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/config/supabase_config.dart';
import '../../data/auth_repository_impl.dart';
import '../../domain/app_user.dart';
import '../../domain/auth_repository.dart';

/// Single instance for the app's lifetime — repositories are cheap
/// wrappers around the (also-singleton) Supabase client, so a plain
/// Provider (not a family/factory) is correct here.
final authRepositoryProvider = Provider<AuthRepository>((ref) => AuthRepositoryImpl());

/// Google / Apple sign-in switched on in Supabase (07.11.2026); the login
/// buttons are active only for these.
final oauthProvidersProvider = FutureProvider<Set<String>>((ref) => ref.watch(authRepositoryProvider).oauthProviders());

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
///
/// At start-up (owner, 22.11.2026: "ilk açanda 0 maşın, sonra yenidən
/// yüklənir"): until the auth stream's first answer arrives (it also reads
/// the public.users row over the network) the id is taken from the session
/// Supabase restored from the device BEFORE runApp(). Before, it was null
/// for that moment, so every page asked "signed out?", showed an empty
/// screen and then loaded everything a second time. The same id from the
/// stream later changes nothing, so nothing is fetched twice; a session
/// the server ends (sign-out / expired) still turns it null.
final currentUserIdProvider = Provider<String?>((ref) {
  final auth = ref.watch(authStateProvider);
  if (auth.hasValue) return auth.value?.id;
  return ref.watch(sessionUserIdProvider);
});

/// The restored session's user id, read once at start (a provider so tests
/// can give one).
final sessionUserIdProvider = Provider<String?>((ref) => restoredSessionUserId());

/// The user id of the session restored on this device (null if none, or in
/// tests where Supabase is not started).
String? restoredSessionUserId() {
  try {
    return SupabaseConfig.client.auth.currentUser?.id;
  } catch (_) {
    return null;
  }
}
