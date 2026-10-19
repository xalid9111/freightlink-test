import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/supabase_config.dart';
import 'rpc_migrations.dart';

/// Single data-access point of the Admin Panel. Reads go through the
/// normal tables (RLS lets admins see everything — is_admin() policies
/// from migration 0002/0012); every WRITE goes through a SECURITY
/// DEFINER RPC from migration 0012 that checks is_admin() on the server
/// and writes an audit-log row. The client never holds a service key.
class AdminRepository {
  final SupabaseClient _c = SupabaseConfig.client;

  /// Live list of a table, newest first (Supabase Realtime).
  Stream<List<Map<String, dynamic>>> watch(String table, {int limit = 500}) {
    return _c
        .from(table)
        .stream(primaryKey: ['id'])
        .order('created_at', ascending: false)
        .limit(limit)
        .map((rows) => rows.map((r) => Map<String, dynamic>.from(r)).toList());
  }

  Future<List<Map<String, dynamic>>> select(String table, String columns) async {
    final rows = await _c.from(table).select(columns);
    return (rows as List).map((r) => Map<String, dynamic>.from(r as Map)).toList();
  }

  Future<Map<String, dynamic>> dashboardStats() async {
    final res = await _c.rpc('admin_dashboard_stats');
    return Map<String, dynamic>.from(res as Map);
  }

  // Cargo
  Future<void> updateCargo(String id, Map<String, dynamic> patch) async {
    await _c.rpc('admin_update_cargo', params: {'p_id': id, 'p_patch': patch});
  }
  Future<void> setCargoHidden(String id, bool hidden) async {
    await _c.rpc('admin_set_cargo_hidden', params: {'p_id': id, 'p_hidden': hidden});
  }
  Future<void> deleteCargo(String id, String? reason) async {
    await _c.rpc('admin_delete_cargo', params: {'p_id': id, 'p_reason': reason});
  }

  // Users
  Future<void> updateUser(String id, Map<String, dynamic> patch) async {
    await _c.rpc('admin_update_user', params: {'p_user': id, 'p_patch': patch});
  }
  Future<void> setUserBlock(String id, bool blocked, {DateTime? until, String? reason}) async {
    await _c.rpc('admin_set_user_block', params: {
        'p_user': id,
        'p_blocked': blocked,
        'p_until': until?.toUtc().toIso8601String(),
        'p_reason': reason,
      });
  }
  Future<void> setUserActive(String id, bool active) async {
    await _c.rpc('admin_set_user_active', params: {'p_user': id, 'p_active': active});
  }
  Future<void> deleteUser(String id, String? reason) async {
    await _c.rpc('admin_delete_user', params: {'p_user': id, 'p_reason': reason});
  }
  /// Founder accounts (0045): only their owner can change them.
  Future<Set<String>> founderIds() async {
    try {
      final res = await _c.rpc('founder_ids');
      return {for (final v in (res as List? ?? const [])) '$v'};
    } catch (_) {
      return const {}; // 0045 not run yet: nothing to show
    }
  }

  // Shipments / offers / reports
  Future<void> setShipmentStatus(String id, String status, {String? note}) async {
    await _c.rpc('admin_set_shipment_status', params: {'p_id': id, 'p_status': status, 'p_note': note});
  }
  Future<void> setOfferStatus(String id, String status, {String? note}) async {
    await _c.rpc('admin_set_offer_status', params: {'p_id': id, 'p_status': status, 'p_note': note});
  }
  Future<void> setReportStatus(String id, String status, {String? note}) async {
    await _c.rpc('admin_set_report_status', params: {'p_id': id, 'p_status': status, 'p_note': note});
  }

  /// Round-trip time of a tiny query, for the System page.
  Future<Duration> ping() async {
    final sw = Stopwatch()..start();
    await _c.from('users').select('id').limit(1);
    sw.stop();
    return sw.elapsed;
  }
}

final adminRepositoryProvider = Provider<AdminRepository>((ref) => AdminRepository());

/// Human-readable (Azerbaijani) text for an admin RPC error.
String adminErrorText(Object e) {
  final raw = e is PostgrestException ? '${e.code ?? ''} ${e.message}' : e.toString();
  if (raw.contains('founder_protected')) return 'Bu Founder hesabıdır — onu yalnız hesabın sahibi dəyişə bilər.';
  if (raw.contains('admin_only')) return 'Bu əməliyyat yalnız admin üçündür.';
  if (raw.contains('old_format')) return 'Köhnə formatlı (1350×300) reklam yenidən aktiv edilə bilməz.';
  if (raw.contains('invalid_external_url')) return 'Link https:// ilə başlamalıdır.';
  if (raw.contains('invalid_dates')) return 'Bitmə tarixi başlamadan sonra olmalıdır.';
  if (raw.contains('cargo_has_payments')) {
    return 'Bu yükə bağlı ödəniş qeydi var — silmək olmaz. Əvəzində gizlədin.';
  }
  if (raw.contains('23505')) return 'Bu dəyər (məs. telefon) artıq başqa hesabda istifadə olunur.';
  if (raw.contains('cannot_')) return 'Bu əməliyyatı öz hesabınıza tətbiq edə bilməzsiniz.';
  if (raw.contains('not_found')) return 'Qeyd tapılmadı (artıq silinmiş ola bilər).';
  if (raw.contains('invalid_')) return 'Yanlış dəyər göndərildi.';
  if (raw.contains('PGRST202') || raw.contains('Could not find the function')) {
    return missingFunctionText(raw);
  }
  return 'Xəta: $raw';
}

/// "Function not found" (PGRST202): name the function and the SQL file that
/// creates it, so the owner knows exactly which migration to run.
String missingFunctionText(String raw) {
  final fn = RegExp(r'function (?:public\.)?([a-z0-9_]+)').firstMatch(raw)?.group(1);
  final file = fn == null ? null : kRpcMigration[fn];
  if (file != null) {
    return 'Server funksiyası tapılmadı ($fn) — Supabase-də $file SQL faylı işə salınmayıb.';
  }
  return 'Server funksiyası tapılmadı${fn == null ? '' : ' ($fn)'} — uyğun SQL faylı işə salınmayıb.';
}
