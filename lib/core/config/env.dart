import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Central, typed access to environment variables.
///
/// Two sources, in priority order:
///  1. `--dart-define` compile-time values (used for the web/PWA release
///     build). The PWA is hosted on static platforms that may refuse to
///     serve dotfiles, so a runtime `.env` asset is NOT reliable there —
///     see the deployment incident where assets/.env never reached the
///     browser and the app froze on the splash screen.
///  2. `.env` via flutter_dotenv (local dev on mobile/desktop, where the
///     asset is bundled by the local build and always present).
///
/// No secret value is ever hardcoded in source — the anon/publishable
/// key is public-by-design (RLS is the real security boundary), so
/// embedding it via dart-define in the shipped web bundle is equivalent
/// to shipping it in the .env asset.
class Env {
  Env._();

  static const String _urlDefine = String.fromEnvironment('SUPABASE_URL');
  static const String _keyDefine = String.fromEnvironment('SUPABASE_ANON_KEY');
  static const String _envDefine =
      String.fromEnvironment('APP_ENV', defaultValue: '');

  static String get supabaseUrl =>
      _urlDefine.isNotEmpty ? _urlDefine : dotenv.get('SUPABASE_URL');
  static String get supabaseAnonKey =>
      _keyDefine.isNotEmpty ? _keyDefine : dotenv.get('SUPABASE_ANON_KEY');
  static String get mapboxToken => dotenv.get('MAPBOX_ACCESS_TOKEN',
      fallback: 'not-configured-yet');
  static String get appEnv => _envDefine.isNotEmpty
      ? _envDefine
      : dotenv.get('APP_ENV', fallback: 'development');

  static bool get isProduction => appEnv == 'production';
}
