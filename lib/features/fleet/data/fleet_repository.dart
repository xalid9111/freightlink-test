import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/supabase_config.dart';
import '../domain/fleet.dart';

/// SQL 0130 is not run yet (the tables / functions are missing).
class FleetNotReady implements Exception {
  const FleetNotReady();
}

/// The server refused: 'name_required', 'invalid_code', 'own_truck' …
class FleetRefused implements Exception {
  final String reason;
  const FleetRefused(this.reason);
}

/// "Maşınlarım" (0130). Reads: own rows (RLS); a linked driver reads his
/// truck, his own expenses and his jobs without prices. Writes only through
/// the server functions.
class FleetRepository {
  SupabaseClient get _c => SupabaseConfig.client;
  static const _timeout = Duration(seconds: 15);

  static const _reasons = [
    'name_required',
    'invalid_currency',
    'invalid_amount',
    'invalid_argument',
    'invalid_code',
    'own_truck',
    'not_owner',
    'not_allowed',
    'not_found',
    'already_decided',
    'too_many',
    'blocked',
    'invite_closed',
  ];

  Future<T> _run<T>(Future<T> Function() f) async {
    try {
      return await f();
    } on PostgrestException catch (e) {
      if (e.code == 'PGRST205' || e.code == '42P01' || e.code == 'PGRST202' || e.code == '42883') throw const FleetNotReady();
      for (final r in _reasons) {
        if (e.message.contains(r)) throw FleetRefused(r);
      }
      rethrow;
    }
  }

  String? get _me => _c.auth.currentUser?.id;

  Future<List<FleetTruck>> trucks() => _run(() async {
        final rows = await _c.from('fleet_trucks').select().isFilter('deleted_at', null).order('created_at').timeout(_timeout);
        return [for (final r in rows as List) FleetTruck.fromJson(Map<String, dynamic>.from(r as Map))];
      });

  /// The owner's jobs (with prices) + the linked driver's jobs (without).
  Future<List<FleetJob>> jobs() => _run(() async {
        final own = await _c
            .from('fleet_jobs')
            .select()
            .isFilter('deleted_at', null)
            .gte('start_at', DateTime.now().toUtc().subtract(const Duration(days: 400)).toIso8601String())
            .order('start_at')
            .timeout(_timeout);
        final out = [for (final r in own as List) FleetJob.fromJson(Map<String, dynamic>.from(r as Map))];
        final drv = await _c.rpc('fleet_driver_jobs').timeout(_timeout);
        final seen = {for (final j in out) j.id};
        for (final r in (drv as List? ?? const [])) {
          final j = FleetJob.fromJson(Map<String, dynamic>.from(r as Map));
          if (seen.add(j.id)) out.add(j);
        }
        return out;
      });

  Future<List<FleetExpense>> expenses() => _run(() async {
        final rows = await _c.from('fleet_expenses').select().isFilter('deleted_at', null).order('created_at', ascending: false).limit(2000).timeout(_timeout);
        return [for (final r in rows as List) FleetExpense.fromJson(Map<String, dynamic>.from(r as Map))];
      });

  Future<String> saveTruck({String? id, required String name, String? plate, String? driverName}) => _run(() async {
        final res = await _c.rpc('fleet_truck_save', params: {'p_id': id, 'p_name': name, 'p_plate': plate, 'p_driver_name': driverName}).timeout(_timeout);
        return '$res';
      });

  Future<void> removeTruck(String id) => _run(() => _c.rpc('fleet_truck_remove', params: {'p_id': id}).timeout(_timeout));

  Future<String> saveJob({
    String? id,
    required String truckId,
    required DateTime startAt,
    String? from,
    String? to,
    double? price,
    required String currency,
    String? note,
  }) =>
      _run(() async {
        final res = await _c.rpc('fleet_job_save', params: {
          'p_id': id,
          'p_truck': truckId,
          'p_start_at': startAt.toUtc().toIso8601String(),
          'p_from': from,
          'p_to': to,
          'p_price': price,
          'p_currency': currency,
          'p_note': note,
        }).timeout(_timeout);
        return '$res';
      });

  Future<void> setJobStatus(String id, String status) => _run(() => _c.rpc('fleet_job_set_status', params: {'p_id': id, 'p_status': status}).timeout(_timeout));

  Future<void> removeJob(String id) => _run(() => _c.rpc('fleet_job_remove', params: {'p_id': id}).timeout(_timeout));

  /// Returns the status: 'approved' (owner) or 'pending' (driver).
  Future<String> addExpense({required String truckId, required String name, required double amount, required String currency, required String clientKey}) =>
      _run(() async {
        final res = await _c.rpc('fleet_expense_add', params: {
          'p_truck': truckId,
          'p_name': name,
          'p_amount': amount,
          'p_currency': currency,
          'p_client_key': clientKey,
        }).timeout(_timeout);
        return '${(res as Map)['status'] ?? ''}';
      });

  Future<void> updateExpense(String id, {required String name, required double amount, required String currency}) =>
      _run(() => _c.rpc('fleet_expense_update', params: {'p_id': id, 'p_name': name, 'p_amount': amount, 'p_currency': currency}).timeout(_timeout));

  Future<void> decideExpense(String id, bool approve) =>
      _run(() => _c.rpc('fleet_expense_decide', params: {'p_id': id, 'p_approve': approve}).timeout(_timeout));

  Future<void> removeExpense(String id) => _run(() => _c.rpc('fleet_expense_remove', params: {'p_id': id}).timeout(_timeout));

  Future<String> inviteCode(String truckId) => _run(() async {
        final res = await _c.rpc('fleet_invite_create', params: {'p_truck': truckId}).timeout(_timeout);
        return '${(res as Map)['code'] ?? ''}';
      });

  /// The driver joins with the owner's code; returns the truck's name.
  Future<String> join(String code) => _run(() async {
        final res = await _c.rpc('fleet_driver_join', params: {'p_code': code.trim().toUpperCase()}).timeout(_timeout);
        return '${(res as Map)['name'] ?? ''}';
      });

  Future<void> unlinkDriver(String truckId) => _run(() => _c.rpc('fleet_driver_unlink', params: {'p_truck': truckId}).timeout(_timeout));

  /// The registered accounts whose name holds [q] (0131); before 0131 /
  /// on any error: none (the field stays a plain name).
  Future<List<FleetPerson>> searchDrivers(String q) async {
    if (q.trim().length < 2) return const [];
    try {
      final res = await _c.rpc('fleet_driver_search', params: {'p_q': q.trim()}).timeout(_timeout);
      return [for (final r in (res as List? ?? const [])) FleetPerson.fromJson(Map<String, dynamic>.from(r as Map))];
    } catch (_) {
      return const [];
    }
  }

  /// The owner asks a registered account to drive the truck (0131).
  Future<void> inviteDriver(String truckId, String userId) =>
      _run(() => _c.rpc('fleet_driver_invite_user', params: {'p_truck': truckId, 'p_user': userId}).timeout(_timeout));

  /// The owner takes a waiting invitation back.
  Future<void> cancelDriverInvite(String truckId) =>
      _run(() => _c.rpc('fleet_driver_invite_cancel', params: {'p_truck': truckId}).timeout(_timeout));

  /// The invited driver answers; returns the truck's name.
  Future<String> answerInvite(String inviteId, bool accept) => _run(() async {
        final res = await _c.rpc('fleet_driver_answer', params: {'p_invite': inviteId, 'p_accept': accept}).timeout(_timeout);
        return '${(res as Map)['name'] ?? ''}';
      });

  String? get me => _me;
}
