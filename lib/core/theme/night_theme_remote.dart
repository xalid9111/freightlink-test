import '../config/supabase_config.dart';
import 'night_theme.dart';

// Reads (never writes) the night colours the admin published (0076). The
// user's own day / night choice stays on the device (theme_mode.dart).

/// The published night palette: [PublishedNightTheme.spec] null = classic.
/// Null when the server does not have it (0076 not run) or cannot be asked.
Future<PublishedNightTheme?> fetchPublishedNightTheme() async {
  try {
    final res = await SupabaseConfig.client.rpc('night_theme_current');
    if (res is! Map) return null;
    return PublishedNightTheme(
      spec: NightThemeSpec.fromJson(res['colors']),
      name: res['name'] as String?,
      updatedAt: DateTime.tryParse('${res['updated_at']}'),
      hasPrevious: res['has_previous'] == true,
    );
  } catch (_) {
    return null;
  }
}

class PublishedNightTheme {
  final NightThemeSpec? spec;
  final String? name;
  final DateTime? updatedAt;
  final bool hasPrevious;
  const PublishedNightTheme({this.spec, this.name, this.updatedAt, this.hasPrevious = false});
}

