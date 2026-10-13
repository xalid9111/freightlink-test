import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/config/supabase_config.dart';
import '../../../core/errors/app_exception.dart';
import '../domain/app_user.dart';
import '../domain/auth_repository.dart';

/// Data-layer implementation backed by Supabase Auth + the `public.users`
/// table (role, full_name live in Postgres so RLS policies can read them
/// — see supabase/migrations/0002_rls.sql).
///
/// Design decision for Phase 3: **email + password is the Supabase Auth
/// identity.** The brief asks for "telefon nömrəsi, email, password" at
/// registration; Supabase Auth supports phone as an *alternate* identity
/// (OTP-based, separate sign-in flow) rather than a field alongside
/// email/password on one identity. Rather than run two parallel auth
/// identities per user (which complicates account recovery and RLS's
/// `auth.uid()` assumptions), phone is collected and stored as a profile
/// field on `public.users` now; phone-OTP as a second sign-in *method*
/// for the same account is a clean follow-up (Supabase supports linking
/// identities) and doesn't require a schema change since `users.phone`
/// already exists.
class AuthRepositoryImpl implements AuthRepository {
  final SupabaseClient _client = SupabaseConfig.client;

  AppUser? _cachedUser;

  @override
  Future<SignUpResult> signUp({
    required String email,
    required String password,
    required String fullName,
    required String role,
    String? phone,
    Map<String, dynamic>? extraData,
  }) async {
    try {
      // Profile fields travel as auth user metadata, NOT as a
      // client-side insert into public.users. The row is created
      // server-side by the trigger in migration 0005
      // (handle_new_auth_user), which reads these back out of
      // raw_user_meta_data. This works whether or not "Confirm email"
      // is enabled on the Supabase project, and does not depend on
      // public.users RLS at all — see that migration's header for the
      // two bugs this replaced.
      final res = await _client.auth.signUp(
        email: email,
        password: password,
        data: {
          'full_name': fullName,
          'role': role,
          if (phone != null && phone.isNotEmpty) 'phone': phone,
          ...?extraData,
        },
      );

      final authUser = res.user;
      if (authUser == null) {
        throw const AppException('Qeydiyyat tamamlanmadı. Yenidən cəhd edin.', code: 'signup_failed');
      }

      if (res.session == null) {
        // "Confirm email" is enabled on this project: signUp()
        // succeeded (the auth.users row — and via the trigger, the
        // public.users row — now exist) but there is no active
        // session until the user clicks the link emailed to them.
        // Nothing more to do here; the UI must tell the user to check
        // their email rather than assume they're signed in.
        return const SignUpResult(user: null, needsEmailConfirmation: true);
      }

      // "Confirm email" is disabled (or was already satisfied) — a
      // session exists immediately. The trigger ran inside the same
      // server-side transaction as the auth.users insert, so the
      // public.users row is guaranteed to already exist by the time
      // this response reaches the client; reading it back is safe.
      final row = await _client.from('users').select().eq('id', authUser.id).single();
      return SignUpResult(user: _cachedUser = _mapRow(row), needsEmailConfirmation: false);
    } on AuthException catch (e) {
      throw AppException(_friendlyAuthMessage(e), code: _authErrorCode(e));
    } on PostgrestException catch (e) {
      if (e.code == '23505') {
        throw const AppException('Bu email və ya telefon artıq istifadə olunur.', code: 'duplicate_user');
      }
      throw AppException(e.message, code: e.code);
    }
  }

  @override
  Future<AppUser> signIn({required String email, required String password}) async {
    try {
      final res = await _client.auth.signInWithPassword(email: email, password: password);
      final authUser = res.user;
      if (authUser == null) throw const AppException('Email və ya şifrə yanlışdır.', code: 'invalid_credentials');

      // The public.users row is normally created by the signup trigger
      // (migration 0005). If it is missing — or cannot be read — do NOT
      // leave the user half signed in (an auth session without a
      // profile): end the session and report a clear, localizable error.
      Map<String, dynamic>? row;
      try {
        row = await _client.from('users').select().eq('id', authUser.id).maybeSingle();
      } on PostgrestException {
        await _endHalfSession();
        throw const AppException('Profil məlumatları yüklənmədi. Yenidən cəhd edin.', code: 'profile_load_failed');
      }
      if (row == null) {
        await _endHalfSession();
        throw const AppException(
          'Bu hesab üçün profil tapılmadı. Dəstək xidməti ilə əlaqə saxlayın.',
          code: 'profile_missing',
        );
      }
      return _cachedUser = _mapRow(row);
    } on AuthException catch (e) {
      throw AppException(_friendlyAuthMessage(e), code: _authErrorCode(e));
    }
  }

  /// Signs out after a sign-in that has an auth session but no usable
  /// profile row. Never throws: the caller reports the real reason.
  Future<void> _endHalfSession() async {
    _cachedUser = null;
    try {
      await _client.auth.signOut();
    } catch (_) {
      // Even if the network call fails, the local session is cleared by
      // supabase_flutter; the user simply stays on the sign-in screen.
    }
  }

  @override
  Future<AppUser> signInWithGoogle() {
    throw const AppException(
      'Google ilə giriş hələ qoşulmayıb. Email/şifrə istifadə edin.',
      code: 'not_implemented',
    );
  }

  @override
  Future<AppUser> signInWithApple() {
    throw const AppException(
      'Apple ilə giriş hələ qoşulmayıb. Email/şifrə istifadə edin.',
      code: 'not_implemented',
    );
  }

  @override
  Future<void> signOut() async {
    await _client.auth.signOut();
    _cachedUser = null;
  }

  @override
  Stream<AppUser?> authStateChanges() {
    return _client.auth.onAuthStateChange.asyncMap((state) async {
      final authUser = state.session?.user;
      if (authUser == null) {
        _cachedUser = null;
        return null;
      }
      try {
        final row = await _client.from('users').select().eq('id', authUser.id).single();
        return _cachedUser = _mapRow(row);
      } on PostgrestException {
        // Expected to be unreachable in normal operation: the
        // migration 0005 trigger creates the public.users row
        // synchronously inside the same transaction as the
        // auth.users insert, before signUp() even returns to the
        // client. This guards only against something going wrong with
        // that trigger (e.g. it was never applied to this project) —
        // treat it as signed out rather than crash the stream, so the
        // failure is visible (stuck on /login) instead of silent.
        return null;
      }
    });
  }

  @override
  AppUser? get currentUser => _cachedUser;

  AppUser _mapRow(Map<String, dynamic> row) => AppUser(
        id: row['id'] as String,
        email: row['email'] as String,
        phone: row['phone'] as String?,
        fullName: row['full_name'] as String,
        role: row['role'] as String,
        isVerified: row['is_verified'] as bool? ?? false,
      );

  String _friendlyAuthMessage(AuthException e) {
    switch (e.statusCode) {
      case '400':
        return 'Məlumatlar yanlışdır. Yenidən yoxlayın.';
      case '422':
        return 'Bu email artıq qeydiyyatdan keçib.';
      default:
        return e.message;
    }
  }

  /// Stable, UI-localizable codes (used by AppStrings.error(code) —
  /// see core/localization/app_strings.dart) instead of keying off
  /// Supabase's raw HTTP statusCode strings directly in the UI layer.
  String _authErrorCode(AuthException e) {
    switch (e.statusCode) {
      case '400':
        return 'invalid_input';
      case '422':
        return 'email_taken';
      default:
        return 'auth_generic';
    }
  }
}
