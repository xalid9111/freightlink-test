import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/config/supabase_config.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../../../repositories/profile_repository.dart' show isMissingRelation;
import '../../../../models/cargo_model.dart';
import '../../data/cargo_repository_impl.dart';
import '../../domain/cargo_repository.dart';

final cargoRepositoryProvider = Provider<CargoRepository>((ref) => CargoRepositoryImpl());

/// Immutable filter state for the Search tab. Also used, empty, by the
/// Home tab (no filters = full open marketplace).
class CargoFilter {
  final String? pickupCountry;
  final String? destinationCountry;
  final String? cargoType;
  final String? truckType;
  final double? minPrice;
  final double? maxPrice;
  final double? maxWeightKg;

  const CargoFilter({
    this.pickupCountry,
    this.destinationCountry,
    this.cargoType,
    this.truckType,
    this.minPrice,
    this.maxPrice,
    this.maxWeightKg,
  });

  bool get isEmpty =>
      pickupCountry == null &&
      destinationCountry == null &&
      cargoType == null &&
      truckType == null &&
      minPrice == null &&
      maxPrice == null &&
      maxWeightKg == null;
}

/// Home tab: the open marketplace, no filters. A FutureProvider (not
/// StreamProvider/Realtime) is the deliberate choice here — cargo rows
/// don't need live-update-while-staring-at-the-screen semantics yet,
/// and pull-to-refresh (wired in the screen) covers "see new listings"
/// without holding an open Realtime subscription on every device that
/// has the Home tab open. `ref.invalidate(marketplaceProvider)` is how
/// the create-cargo screen and pull-to-refresh both force a re-fetch.
final marketplaceProvider = FutureProvider<List<CargoModel>>((ref) {
  ref.watch(currentUserIdProvider); // re-fetch when the signed-in account changes
  return ref.watch(cargoRepositoryProvider).fetchMarketplace();
});

/// Search tab: same fetch, parameterized by whatever filter is active.
/// `.family` keys the cache by filter value, so switching filters and
/// switching back doesn't always re-fetch.
// autoDispose: fresh results each time Search opens (the cached first
// result never changed before).
final filteredCargoProvider = FutureProvider.autoDispose.family<List<CargoModel>, CargoFilter>((ref, filter) {
  ref.watch(currentUserIdProvider); // re-fetch when the signed-in account changes
  return ref.watch(cargoRepositoryProvider).fetchMarketplace(
        pickupCountry: filter.pickupCountry,
        destinationCountry: filter.destinationCountry,
        cargoType: filter.cargoType,
        truckType: filter.truckType,
        minPrice: filter.minPrice,
        maxPrice: filter.maxPrice,
        maxWeightKg: filter.maxWeightKg,
      );
});

/// Cargo detail screen. Keyed by cargo id so navigating between two
/// different cargo details doesn't show stale data from the first one.
final cargoDetailProvider = FutureProvider.family<CargoModel, String>((ref, cargoId) {
  ref.watch(currentUserIdProvider); // re-fetch when the signed-in account changes
  return ref.watch(cargoRepositoryProvider).fetchById(cargoId);
});

/// The signed-in cargo owner's own loads (all statuses), newest first —
/// "My loads" in the profile, where they can open, edit or close them.
final myCargoProvider = FutureProvider<List<CargoModel>>((ref) async {
  final uid = ref.watch(currentUserIdProvider);
  if (uid == null) return const [];
  final rows = await SupabaseConfig.client
      .from('cargo')
      .select()
      .eq('owner_id', uid)
      .order('created_at', ascending: false);
  return (rows as List).map((r) => CargoModel.fromJson(r as Map<String, dynamic>)).toList();
});

/// Home counters — real numbers, counted in the database (no rows sent).
/// Active carriers = carrier accounts that are not deactivated.
final activeCarriersCountProvider = FutureProvider<int>((ref) async {
  ref.watch(currentUserIdProvider);
  // Public profile view (migration 0019); public.users is own-row only.
  Future<int> countIn(String table) async {
    final res = await SupabaseConfig.client
        .from(table)
        .select('id')
        .eq('role', 'carrier')
        .eq('is_active', true)
        .count(CountOption.exact);
    return res.count;
  }
  try {
    return await countIn('user_profiles');
  } on PostgrestException catch (e) {
    if (!isMissingRelation(e)) rethrow;
    return countIn('users'); // 0019 not applied yet
  }
});

/// Loads posted in the last 24 hours (hidden ones excluded by RLS).
final newCargo24hCountProvider = FutureProvider<int>((ref) async {
  ref.watch(currentUserIdProvider);
  final since = DateTime.now().toUtc().subtract(const Duration(hours: 24)).toIso8601String();
  final res = await SupabaseConfig.client
      .from('cargo')
      .select('id')
      .gte('created_at', since)
      .count(CountOption.exact);
  return res.count;
});
