import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/supabase_config.dart';
import '../../../core/router/guest_access.dart';
import '../../auth/presentation/providers/auth_providers.dart';
import '../../cargo/presentation/providers/category_providers.dart';
import '../../cargo/presentation/providers/route_filter.dart';
import '../domain/empty_truck.dart';

/// SQL 0118 not run yet.
class EmptyTruckNotReady implements Exception {
  const EmptyTruckNotReady();
}

/// The server refused: 'from_required', 'to_required', 'invalid_tons', …
class EmptyTruckRefused implements Exception {
  final String reason;
  const EmptyTruckRefused(this.reason);
}

/// Empty truck ads (0118): read straight from the table (RLS: active ads
/// for everybody, own ads for the owner; visitors without the contact
/// columns); written only through the server functions.
class EmptyTruckRepository {
  SupabaseClient get _c => SupabaseConfig.client;
  static const _timeout = Duration(seconds: 15);

  /// Visitors may not read the phone / WhatsApp columns (0118).
  static const _guestCols = 'id, owner_id, from_city, from_country, from_code, from_lat, from_lng, any_direction, '
      'to_city, to_country, to_code, truck_type, free_tons, body_types, available_from, note, status, created_at, updated_at';

  String get _cols => isSignedOut() ? _guestCols : '*';

  Future<T> _run<T>(Future<T> Function() f) async {
    try {
      return await f();
    } on PostgrestException catch (e) {
      if (e.code == 'PGRST205' || e.code == '42P01' || e.code == 'PGRST202' || e.code == '42883') throw const EmptyTruckNotReady();
      for (final r in ['from_required', 'to_required', 'invalid_tons', 'truck_required', 'invalid_time', 'too_many', 'not_allowed', 'blocked']) {
        if (e.message.contains(r)) throw EmptyTruckRefused(r);
      }
      rethrow;
    }
  }

  /// The active ads, newest first (bounded).
  Future<List<EmptyTruck>> active({int limit = 500}) => _run(() async {
        final rows = await _c
            .from('empty_truck_ads')
            .select(_cols)
            .eq('status', 'active')
            .order('created_at', ascending: false)
            .limit(limit)
            .timeout(_timeout);
        return [for (final r in rows as List) EmptyTruck.fromJson(Map<String, dynamic>.from(r as Map))];
      });

  Future<List<EmptyTruck>> mine(String uid) => _run(() async {
        final rows = await _c.from('empty_truck_ads').select().eq('owner_id', uid).order('created_at', ascending: false).timeout(_timeout);
        return [for (final r in rows as List) EmptyTruck.fromJson(Map<String, dynamic>.from(r as Map))];
      });

  Future<EmptyTruck?> byId(String id) => _run(() async {
        final row = await _c.from('empty_truck_ads').select(_cols).eq('id', id).maybeSingle().timeout(_timeout);
        return row == null ? null : EmptyTruck.fromJson(Map<String, dynamic>.from(row));
      });

  Future<String> save({
    String? id,
    required String fromCity,
    required String fromCountry,
    String? fromCode,
    double? fromLat,
    double? fromLng,
    required bool anyDirection,
    String? toCity,
    String? toCountry,
    String? toCode,
    required String truckType,
    required double freeTons,
    List<String> bodyTypes = const [],
    DateTime? availableFrom,
    String? phone,
    String? whatsapp,
    String? note,
  }) =>
      _run(() async => (await _c.rpc('empty_truck_save', params: {
            'p_id': id,
            'p_from_city': fromCity,
            'p_from_country': fromCountry,
            'p_from_code': fromCode,
            'p_from_lat': fromLat,
            'p_from_lng': fromLng,
            'p_any_direction': anyDirection,
            'p_to_city': anyDirection ? null : toCity,
            'p_to_country': anyDirection ? null : toCountry,
            'p_to_code': anyDirection ? null : toCode,
            'p_truck_type': truckType,
            'p_free_tons': freeTons,
            'p_body_types': bodyTypes,
            'p_available_from': availableFrom?.toUtc().toIso8601String(),
            'p_phone': phone,
            'p_whatsapp': whatsapp,
            'p_note': note,
          }).timeout(_timeout)) as String);

  /// 'active' | 'paused' | 'filled' (Maşın doldu).
  Future<void> setStatus(String id, String status) =>
      _run(() => _c.rpc('empty_truck_set_status', params: {'p_id': id, 'p_status': status}).timeout(_timeout));
}

final emptyTruckRepositoryProvider = Provider<EmptyTruckRepository>((ref) => EmptyTruckRepository());

/// The Daşıyıcılar list (all active ads); filtered on the device by the
/// Loads page's route search and load-type tile.
final emptyTrucksProvider = FutureProvider.autoDispose<List<EmptyTruck>>((ref) {
  ref.watch(currentUserIdProvider);
  return ref.watch(emptyTruckRepositoryProvider).active();
});

final emptyTrucksShownProvider = Provider.autoDispose<AsyncValue<List<EmptyTruck>>>((ref) {
  final route = ref.watch(routeFilterProvider);
  final cat = ref.watch(cargoCategoryFilterProvider);
  return ref.watch(emptyTrucksProvider).whenData((l) => [for (final t in l) if (t.matchesRoute(route) && t.matchesCategory(cat)) t]);
});

final myEmptyTrucksProvider = FutureProvider.autoDispose<List<EmptyTruck>>((ref) async {
  final uid = ref.watch(currentUserIdProvider);
  if (uid == null) return const [];
  try {
    return await ref.watch(emptyTruckRepositoryProvider).mine(uid);
  } on EmptyTruckNotReady {
    return const [];
  }
});

final emptyTruckProvider =
    FutureProvider.autoDispose.family<EmptyTruck?, String>((ref, id) => ref.watch(emptyTruckRepositoryProvider).byId(id));

/// Yüklər | Daşıyıcılar (owner, 13.11.2026): which list the Loads page shows.
enum LoadsSection { loads, carriers }

final loadsSectionProvider = StateProvider<LoadsSection>((ref) => LoadsSection.loads);
