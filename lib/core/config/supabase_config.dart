import 'package:supabase_flutter/supabase_flutter.dart';
import 'env.dart';

/// Initializes the Supabase client once at app startup (see main.dart).
/// Every repository in lib/repositories/ pulls its client from
/// `SupabaseConfig.client` rather than creating its own instance.
class SupabaseConfig {
  SupabaseConfig._();

  static Future<void> initialize() async {
    await Supabase.initialize(
      url: Env.supabaseUrl,
      // supabase_flutter renamed this parameter from `anonKey` to
      // `publishableKey` (same value — Supabase's own terminology
      // shift for the client-safe key, not a behavior change).
      // `anonKey` is deprecated and slated for removal in a future
      // major version; flagged by flutter analyze against
      // supabase_flutter 2.18.0.
      publishableKey: Env.supabaseAnonKey,
      debug: !Env.isProduction,
    );
  }

  static SupabaseClient get client => Supabase.instance.client;
}
