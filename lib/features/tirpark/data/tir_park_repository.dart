import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/supabase_config.dart';
import '../../auth/presentation/providers/auth_providers.dart';
import '../domain/tir_park.dart';

/// Migration 0077 not run yet in Supabase.
class TirParkNotReady implements Exception {
  const TirParkNotReady();
}

/// The server refused a park: 'duplicate_nearby', 'too_many', 'blocked'…
class TirParkRefused implements Exception {
  final String reason;
  const TirParkRefused(this.reason);
}

/// TIR parks (0077). Approved ones for everybody signed in, plus one's own
/// pending ones (RLS); admins see all. Writes go through the server
/// functions (checked there).
class TirParkRepository {
  SupabaseClient get _c => SupabaseConfig.client;
  static const _timeout = Duration(seconds: 15);
  static const _cols = 'id,name,lat,lng,city,amenities,note,status,photo_urls,rating_avg,rating_count,created_by,created_at';

  Future<T> _run<T>(Future<T> Function() f) async {
    try {
      return await f();
    } on PostgrestException catch (e) {
      if (e.code == 'PGRST205' || e.code == '42P01' || e.code == 'PGRST202' || e.code == '42883') throw const TirParkNotReady();
      for (final r in ['duplicate_nearby', 'too_many', 'blocked', 'admin_only']) {
        if (e.message.contains(r)) throw TirParkRefused(r);
      }
      rethrow;
    }
  }

  /// Parks on the map (bounded so a phone never downloads a huge table).
  Future<List<TirPark>> parks() => _run(() async {
        final rows = await _c
            .from('tir_parks')
            .select(_cols)
            .inFilter('status', ['approved', 'pending'])
            .order('created_at', ascending: false)
            .limit(3000)
            .timeout(_timeout);
        return [for (final r in rows as List) TirPark.fromJson(Map<String, dynamic>.from(r as Map))];
      });

  /// Admin list: every state, pending first.
  Future<List<TirPark>> adminParks() => _run(() async {
        final rows = await _c.from('tir_parks').select(_cols).order('created_at', ascending: false).limit(3000).timeout(_timeout);
        final list = [for (final r in rows as List) TirPark.fromJson(Map<String, dynamic>.from(r as Map))];
        list.sort((a, b) => (a.isPending ? 0 : 1).compareTo(b.isPending ? 0 : 1));
        return list;
      });

  Future<List<NearbyPark>> near(double lat, double lng, {int radiusM = 500}) => _run(() async {
        final res = await _c.rpc('tir_parks_near', params: {'p_lat': lat, 'p_lng': lng, 'p_radius_m': radiusM}).timeout(_timeout);
        return [for (final r in (res as List? ?? const [])) NearbyPark.fromJson(Map<String, dynamic>.from(r as Map))];
      });

  Future<String> add({required String name, required double lat, required double lng, String? city, List<String> amenities = const [], String? note}) =>
      _run(() async {
        final id = await _c.rpc('tir_park_add', params: {
          'p_name': name,
          'p_lat': lat,
          'p_lng': lng,
          'p_city': city,
          'p_amenities': amenities,
          'p_note': note,
        }).timeout(_timeout);
        return '$id';
      });

  Future<void> setStatus(String id, String status) =>
      _run(() => _c.rpc('admin_tir_park_set_status', params: {'p_id': id, 'p_status': status}).timeout(_timeout));
}

final tirParkRepositoryProvider = Provider<TirParkRepository>((ref) => TirParkRepository());

final tirParksProvider = FutureProvider.autoDispose<List<TirPark>>((ref) {
  ref.watch(currentUserIdProvider);
  return ref.watch(tirParkRepositoryProvider).parks();
});

final adminTirParksProvider = FutureProvider.autoDispose<List<TirPark>>((ref) => ref.watch(tirParkRepositoryProvider).adminParks());
