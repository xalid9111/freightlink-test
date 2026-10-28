import 'package:equatable/equatable.dart';

/// Domain entity — plain Dart, no Supabase types. This is what the
/// rest of the app (state management, UI) works with.
class AppUser extends Equatable {
  final String id;
  final String email;
  final String? phone;
  final String fullName;
  final String role; // cargo_owner | carrier | driver | admin
  final bool isVerified;

  /// Picked as an age at registration / in Profil (0074); private.
  final DateTime? birthDate;

  const AppUser({
    required this.id,
    required this.email,
    this.phone,
    required this.fullName,
    required this.role,
    required this.isVerified,
    this.birthDate,
  });

  @override
  List<Object?> get props => [id, email, phone, fullName, role, isVerified, birthDate];
}

/// Result of signUp(). Split from a bare AppUser because Supabase
/// projects with "Confirm email" enabled (the default) return no
/// active session immediately after signup — there is no signed-in
/// AppUser yet, only a pending registration. The UI needs to tell
/// those two outcomes apart to show the right message (see
/// RegisterScreen and the note in AuthRepositoryImpl.signUp).
class SignUpResult extends Equatable {
  final AppUser? user;
  final bool needsEmailConfirmation;

  const SignUpResult({required this.user, required this.needsEmailConfirmation});

  @override
  List<Object?> get props => [user, needsEmailConfirmation];
}
