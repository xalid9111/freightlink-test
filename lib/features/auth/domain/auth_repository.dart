import 'app_user.dart';

/// Domain-layer contract. Presentation code (screens, view models)
/// depends only on this interface — never on the Data-layer
/// implementation or on Supabase directly.
abstract class AuthRepository {
  Future<SignUpResult> signUp({
    required String email,
    required String password,
    required String fullName,
    required String role, // chosen once at registration, see brief §5
    String? phone,
    /// Extra signup metadata (e.g. service_kind for "Usta / Servis").
    Map<String, dynamic>? extraData,
  });

  Future<AppUser> signIn({required String email, required String password});

  /// Google / Apple sign-in through Supabase OAuth (07.11.2026). Opens the
  /// provider's page (on the web the page itself goes there and comes back
  /// with the session; [authStateChanges] then loads the public.users row).
  /// True = the provider's page was opened. Throws AppException
  /// 'oauth_not_configured' while the provider is off in Supabase.
  Future<bool> signInWithGoogle();
  Future<bool> signInWithApple();

  /// The OAuth providers switched on in the Supabase project (e.g.
  /// {'google'}); empty when unknown (offline) or none.
  Future<Set<String>> oauthProviders();

  Future<void> signOut();

  Stream<AppUser?> authStateChanges();

  AppUser? get currentUser;
}
