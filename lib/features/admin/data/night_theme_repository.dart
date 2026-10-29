import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/supabase_config.dart';
import '../../../core/theme/night_theme.dart';
import '../../../core/theme/theme_mode.dart';

/// A named combination the admin saved (0076, night_themes).
class SavedNightTheme {
  final String id, name;
  final NightThemeSpec spec;
  const SavedNightTheme({required this.id, required this.name, required this.spec});
}

/// Thrown while migration 0076 has not been run in Supabase.
class NightThemeNotReady implements Exception {
  const NightThemeNotReady();
}

/// Admin → Dizayn və Rənglər (0076). Every call is checked on the server
/// (admin only, logged); the app never writes the tables itself.
class NightThemeRepository {
  SupabaseClient get _c => SupabaseConfig.client;

  Future<T> _run<T>(Future<T> Function() f) async {
    try {
      return await f();
    } on PostgrestException catch (e) {
      if (e.code == 'PGRST202' || e.code == '42883' || e.code == 'PGRST205' || e.code == '42P01') throw const NightThemeNotReady();
      rethrow;
    }
  }

  Future<PublishedNightTheme?> current() => fetchPublishedNightTheme();

  Future<List<SavedNightTheme>> saved() => _run(() async {
        final res = await _c.rpc('admin_night_themes');
        return [
          for (final r in (res as List? ?? const []))
            if (r is Map && NightThemeSpec.fromJson(r['colors']) != null)
              SavedNightTheme(id: '${r['id']}', name: '${r['name']}', spec: NightThemeSpec.fromJson(r['colors'])!),
        ];
      });

  Future<void> save(String name, NightThemeSpec spec) =>
      _run(() => _c.rpc('admin_night_theme_save', params: {'p_name': name, 'p_colors': spec.toJson()}));

  Future<void> delete(String id) => _run(() => _c.rpc('admin_night_theme_delete', params: {'p_id': id}));

  /// [spec] null = "Klassik FreightLink".
  Future<void> publish(NightThemeSpec? spec, String name) => _run(() => _c.rpc('admin_night_theme_publish',
      params: {'p_colors': spec == null || spec.isClassic ? null : spec.toJson(), 'p_name': name}));

  Future<NightThemeSpec?> restore() => _run(() async {
        final res = await _c.rpc('admin_night_theme_restore');
        return res is Map ? NightThemeSpec.fromJson(res['colors']) : null;
      });
}

final nightThemeRepositoryProvider = Provider<NightThemeRepository>((ref) => NightThemeRepository());

final publishedNightThemeProvider = FutureProvider.autoDispose<PublishedNightTheme?>((ref) => ref.watch(nightThemeRepositoryProvider).current());

final savedNightThemesProvider = FutureProvider.autoDispose<List<SavedNightTheme>>((ref) => ref.watch(nightThemeRepositoryProvider).saved());
