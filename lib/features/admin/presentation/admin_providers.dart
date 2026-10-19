import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/presentation/providers/auth_providers.dart';
import '../data/admin_repository.dart';

typedef JsonRow = Map<String, dynamic>;

/// Live tables. autoDispose: the Realtime channel is closed as soon as
/// no admin page is listening (leaving /admin disposes everything).
AutoDisposeStreamProvider<List<JsonRow>> _live(String table, {int limit = 500}) =>
    StreamProvider.autoDispose<List<JsonRow>>((ref) {
      ref.watch(currentUserIdProvider);
      return ref.watch(adminRepositoryProvider).watch(table, limit: limit);
    });

final adminUsersProvider = _live('users', limit: 2000);

/// Founder accounts (0045): locked for every other admin.
final adminFounderIdsProvider = FutureProvider.autoDispose<Set<String>>((ref) {
  ref.watch(currentUserIdProvider);
  return ref.watch(adminRepositoryProvider).founderIds();
});
final adminCargoProvider = _live('cargo', limit: 1000);
final adminOffersProvider = _live('offers', limit: 1000);
final adminShipmentsProvider = _live('shipments', limit: 1000);
final adminReportsProvider = _live('reports', limit: 500);
final adminAuditProvider = _live('admin_audit_log', limit: 300);

/// carriers.id -> users.id (offers/shipments reference the carrier row).
final adminCarrierUserIdsProvider = FutureProvider.autoDispose<Map<String, String>>((ref) async {
  final rows = await ref.watch(adminRepositoryProvider).select('carriers', 'id,user_id');
  return {for (final r in rows) r['id'] as String: r['user_id'] as String};
});

/// drivers.id -> driver full name.
final adminDriversProvider = FutureProvider.autoDispose<Map<String, String>>((ref) async {
  final rows = await ref.watch(adminRepositoryProvider).select('drivers', 'id,full_name');
  return {for (final r in rows) r['id'] as String: (r['full_name'] as String?) ?? '—'};
});

/// trucks.id -> "Brand Model" (the trucks table has no plate column).
final adminTrucksProvider = FutureProvider.autoDispose<Map<String, String>>((ref) async {
  final rows = await ref.watch(adminRepositoryProvider).select('trucks', 'id,brand,model');
  return {
    for (final r in rows)
      r['id'] as String: [r['brand'], r['model']].where((v) => v != null && '$v'.isNotEmpty).join(' ').trim(),
  };
});

/// Server-side counters (admin_dashboard_stats RPC). Re-runs whenever a
/// live list changes size, so the dashboard follows Realtime inserts.
final adminStatsProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) {
  ref.watch(adminUsersProvider.select((v) => v.valueOrNull?.length));
  ref.watch(adminCargoProvider.select((v) => v.valueOrNull?.length));
  ref.watch(adminOffersProvider.select((v) => v.valueOrNull?.length));
  ref.watch(adminShipmentsProvider.select((v) => v.valueOrNull?.length));
  ref.watch(adminReportsProvider.select((v) => v.valueOrNull?.where((r) => r['status'] == 'new').length));
  return ref.watch(adminRepositoryProvider).dashboardStats();
});

/// Text in the universal search box (top bar).
final adminSearchProvider = StateProvider<String>((ref) => '');

Map<String, JsonRow> indexById(List<JsonRow>? rows) => {for (final r in rows ?? const <JsonRow>[]) r['id'] as String: r};

/// Case-insensitive "any of these values contains the query".
bool adminMatches(String query, Iterable<Object?> values) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return true;
  for (final v in values) {
    if (v != null && v.toString().toLowerCase().contains(q)) return true;
  }
  return false;
}
