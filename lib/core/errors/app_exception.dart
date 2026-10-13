/// Uniform exception type surfaced from the data layer up to the UI,
/// so presentation code never depends on Supabase/Postgrest exception
/// types directly (keeps Domain/Presentation decoupled from Data).
class AppException implements Exception {
  final String message;
  final String? code;
  const AppException(this.message, {this.code});

  @override
  String toString() => 'AppException($code): $message';
}
