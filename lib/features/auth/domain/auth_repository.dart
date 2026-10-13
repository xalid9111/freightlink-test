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

  /// Google/Apple sign-in — architecture placeholders per brief §5
  /// ("gələcəkdə Google/Apple login üçün arxitektura hazır olsun").
  /// Left unimplemented on purpose: wiring these up needs native
  /// platform configuration (Google Cloud OAuth client, Apple Developer
  /// Sign in with Apple capability + entitlements) that can't be set up
  /// or tested from this sandbox. The interface and call sites exist now
  /// so adding the real implementation later touches one file, not the
  /// UI.
  Future<AppUser> signInWithGoogle();
  Future<AppUser> signInWithApple();

  Future<void> signOut();

  Stream<AppUser?> authStateChanges();

  AppUser? get currentUser;
}
