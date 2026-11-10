import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/supabase_config.dart';
import '../domain/adbiz_models.dart';

/// SQL 0110 not run yet in Supabase: the module stays hidden.
class AdbizNotReady implements Exception {
  const AdbizNotReady();
}

/// The server refused: 'day_closed', 'not_allowed', 'not_member',
/// 'chief_admin_only', 'invalid_argument', 'not_found', 'other_company'.
class AdbizRefused implements Exception {
  final String reason;
  const AdbizRefused(this.reason);
  @override
  String toString() => 'AdbizRefused($reason)';
}

/// A random id for "the same tap" — a double tap sends the same key and the
/// server gives back the same job / expense (no second row).
String adbizClientKey([Random? r]) {
  final rnd = r ?? Random.secure();
  final b = List<int>.generate(16, (_) => rnd.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  String h(int i) => b[i].toRadixString(16).padLeft(2, '0');
  final s = [for (var i = 0; i < 16; i++) h(i)].join();
  return '${s.substring(0, 8)}-${s.substring(8, 12)}-${s.substring(12, 16)}-${s.substring(16, 20)}-${s.substring(20)}';
}

const kAdbizReasons = [
  'day_closed', 'not_allowed', 'not_member', 'chief_admin_only', 'invalid_argument', 'not_found', 'other_company',
];

/// UTEP Reklam (0110). Reads go through RLS (a member sees only his own
/// company; a worker only his own days), every write through the server
/// functions, which check company, role and rights again.
class AdbizRepository {
  SupabaseClient get _c => SupabaseConfig.client;
  static const _timeout = Duration(seconds: 15);

  Future<T> _run<T>(Future<T> Function() f) async {
    try {
      return await f().timeout(_timeout);
    } on PostgrestException catch (e) {
      if (e.code == 'PGRST202' || e.code == 'PGRST205' || e.code == '42P01' || e.code == '42883') throw const AdbizNotReady();
      for (final r in kAdbizReasons) {
        if (e.message.contains(r)) throw AdbizRefused(r);
      }
      rethrow;
    }
  }

  Future<AdbizMe?> me() => _run(() async {
        final r = await _c.rpc('adbiz_me');
        return r is Map ? AdbizMe.fromJson(Map<String, dynamic>.from(r)) : null;
      });

  // ---- the notebook ----------------------------------------------------------
  Future<AdbizDay?> dayOf(String userId, DateTime date) => _run(() async {
        final r = await _c.from('adbiz_days').select().eq('user_id', userId).eq('work_date', isoDate(date)).maybeSingle();
        return r == null ? null : AdbizDay.fromJson(r);
      });

  Future<List<AdbizDay>> days(String userId, {int limit = 60}) => _run(() async {
        final r = await _c.from('adbiz_days').select().eq('user_id', userId).order('work_date', ascending: false).limit(limit);
        return [for (final x in r) AdbizDay.fromJson(x)];
      });

  /// One day's expenses (rasxod) once.
  Future<List<AdbizExpense>> dayExpenses(String dayId) => _run(() async {
        final r = await _c.from('adbiz_expenses').select().eq('day_id', dayId);
        return [for (final x in r) AdbizExpense.fromJson(x)];
      });

  /// The company's days of one date (every worker's; owner / Baş admin).
  Future<List<AdbizDay>> daysOn(String companyId, DateTime date) => _run(() async {
        final r = await _c.from('adbiz_days').select().eq('company_id', companyId).eq('work_date', isoDate(date));
        return [for (final x in r) AdbizDay.fromJson(x)];
      });

  /// Deletes one work day with its jobs and rasxod (owner / Baş admin; kept
  /// whole in the history, 0115).
  Future<void> deleteDay(String dayId) => _run(() => _c.rpc('adbiz_delete_day', params: {'p_day': dayId}));

  /// The month / year cards of a year (0115).
  Future<AdbizPeriods> periods(String companyId, int year) => _run(() async {
        final r = await _c.rpc('adbiz_report_periods', params: {'p_company': companyId, 'p_year': year});
        return AdbizPeriods.fromJson(Map<String, dynamic>.from(r as Map));
      });

  Future<List<AdbizEntry>> entries(String dayId) => _run(() async {
        final r = await _c.from('adbiz_entries').select().eq('day_id', dayId).order('created_at');
        return [for (final x in r) AdbizEntry.fromJson(x)];
      });

  /// Live: the jobs of a day as they change on any device (realtime, RLS).
  Stream<List<AdbizEntry>> watchEntries(String dayId) => _c
      .from('adbiz_entries')
      .stream(primaryKey: ['id'])
      .eq('day_id', dayId)
      .order('created_at', ascending: true)
      .map((rows) => [for (final x in rows) AdbizEntry.fromJson(x)]);

  /// Live: one person's days (status changes: closed / re-opened elsewhere).
  Stream<List<AdbizDay>> watchDays(String userId) => _c
      .from('adbiz_days')
      .stream(primaryKey: ['id'])
      .eq('user_id', userId)
      .order('work_date', ascending: false)
      .map((rows) => [for (final x in rows) AdbizDay.fromJson(x)]);

  /// Live: one day's expenses (rasxod, 0111) — the worker sees his own.
  Stream<List<AdbizExpense>> watchDayExpenses(String dayId) => _c
      .from('adbiz_expenses')
      .stream(primaryKey: ['id'])
      .eq('day_id', dayId)
      .order('created_at', ascending: true)
      .map((rows) => [for (final x in rows) AdbizExpense.fromJson(x)]);

  /// A day expense into the worker's own open day (the owner / Baş admin:
  /// any day); a double tap sends the same key = one expense.
  Future<String> addDayExpense(String dayId, String title, double amount, String clientKey) => _run(() async =>
      (await _c.rpc('adbiz_add_day_expense',
          params: {'p_day': dayId, 'p_title': title, 'p_amount': amount, 'p_client_key': clientKey})) as String);

  /// Closes the forgotten open days of earlier dates (each day ends at 23:59
  /// Baku, 0112). Before SQL 0112 there is nothing to do.
  Future<void> sweep() async {
    try {
      await _run(() => _c.rpc('adbiz_sweep'));
    } catch (_) {}
  }

  Future<String> openDay() => _run(() async => (await _c.rpc('adbiz_open_day')) as String);

  Future<String> openDayFor(String userId, DateTime date) =>
      _run(() async => (await _c.rpc('adbiz_open_day_for', params: {'p_user': userId, 'p_date': isoDate(date)})) as String);

  /// [card] is sent only once SQL 0113 is run (null = the old call).
  Future<String> addEntry(String dayId, String title, double amount, String clientKey, {bool? card}) => _run(() async =>
      (await _c.rpc('adbiz_add_entry', params: {
        'p_day': dayId,
        'p_title': title,
        'p_amount': amount,
        'p_client_key': clientKey,
        if (card != null) 'p_card': card,
      })) as String);

  /// The card tick of a saved job (0113): the worker on his own open day,
  /// the owner / Baş admin on any day; audited.
  Future<void> setEntryCard(String id, bool on) => _run(() => _c.rpc('adbiz_entry_set_card', params: {'p_entry': id, 'p_on': on}));

  Future<void> updateEntry(String id, String title, double amount) =>
      _run(() => _c.rpc('adbiz_update_entry', params: {'p_entry': id, 'p_title': title, 'p_amount': amount}));

  Future<void> deleteEntry(String id) => _run(() => _c.rpc('adbiz_delete_entry', params: {'p_entry': id}));

  Future<void> closeDay(String dayId) => _run(() => _c.rpc('adbiz_close_day', params: {'p_day': dayId}));

  Future<void> reopenDay(String dayId) => _run(() => _c.rpc('adbiz_reopen_day', params: {'p_day': dayId}));

  // ---- company: reports, expenses -----------------------------------------------
  Future<List<AdbizCompany>> companies() => _run(() async {
        final r = await _c.from('adbiz_companies').select().order('name');
        return [for (final x in r) AdbizCompany.fromJson(x)];
      });

  Future<AdbizReport> report(String companyId, DateTime from, DateTime to) => _run(() async {
        final r = await _c.rpc('adbiz_report', params: {'p_company': companyId, 'p_from': isoDate(from), 'p_to': isoDate(to)});
        return AdbizReport.fromJson(Map<String, dynamic>.from(r as Map));
      });

  Future<List<AdbizExpense>> expenses(String companyId, DateTime from, DateTime to) => _run(() async {
        final r = await _c
            .from('adbiz_expenses')
            .select()
            .eq('company_id', companyId)
            .gte('spent_on', isoDate(from))
            .lte('spent_on', isoDate(to))
            .order('spent_on', ascending: false);
        return [for (final x in r) AdbizExpense.fromJson(x)];
      });

  Future<String> expenseSave({String? id, String? companyId, required DateTime spentOn, required String title, required double amount, String? clientKey}) =>
      _run(() async => (await _c.rpc('adbiz_expense_save', params: {
            'p_id': id,
            'p_company': companyId,
            'p_spent_on': isoDate(spentOn),
            'p_title': title,
            'p_amount': amount,
            'p_client_key': clientKey,
          })) as String);

  Future<void> expenseDelete(String id) => _run(() => _c.rpc('adbiz_expense_delete', params: {'p_id': id}));

  /// The owner's words for the workers (0113): the caption instead of
  /// "Hədəfə qalan" and the task for every worker (empty = none).
  Future<void> companyTexts(String companyId, String? label, String? task) =>
      _run(() => _c.rpc('adbiz_company_texts_save', params: {'p_company': companyId, 'p_label': label, 'p_task': task}));

  /// The owner's day-result messages (0114): below / at the target; empty =
  /// the app's own words.
  Future<void> companyResultTexts(String companyId, String? miss, String? hit) => _run(
      () => _c.rpc('adbiz_company_result_texts_save', params: {'p_company': companyId, 'p_miss': miss, 'p_hit': hit}));

  /// The workers see the target or not (0113).
  Future<void> companyShowTarget(String companyId, bool on) =>
      _run(() => _c.rpc('adbiz_company_show_target', params: {'p_company': companyId, 'p_on': on}));

  /// A task for one worker (0113).
  Future<void> memberTask(String userId, String? task) =>
      _run(() => _c.rpc('adbiz_member_task_save', params: {'p_user': userId, 'p_task': task}));

  /// One member's task (the worker reads his own row, the owner his
  /// company's; null before 0113 or none).
  Future<String?> memberTaskOf(String userId) => _run(() async {
        final r = await _c.from('adbiz_members').select().eq('user_id', userId).maybeSingle();
        final t = '${r?['task_note'] ?? ''}'.trim();
        return t.isEmpty ? null : t;
      });

  // ---- Baş admin ------------------------------------------------------------------
  Future<String> companySave({String? id, required String name, required double dailyTarget, bool ownerManagesStaff = false}) =>
      _run(() async => (await _c.rpc('adbiz_admin_company_save', params: {
            'p_id': id,
            'p_name': name,
            'p_daily_target': dailyTarget,
            'p_owner_manages_staff': ownerManagesStaff,
          })) as String);

  Future<void> companySetActive(String id, bool on) =>
      _run(() => _c.rpc('adbiz_admin_company_set_active', params: {'p_id': id, 'p_on': on}));

  Future<List<AdbizUserHit>> searchUsers(String q) => _run(() async {
        final r = await _c.rpc('adbiz_admin_search_users', params: {'p_q': q});
        return [for (final x in (r as List)) AdbizUserHit.fromJson(Map<String, dynamic>.from(x as Map))];
      });

  Future<void> memberSet(String userId, String companyId, String role) =>
      _run(() => _c.rpc('adbiz_admin_member_set', params: {'p_user': userId, 'p_company': companyId, 'p_role': role}));

  Future<void> memberSetActive(String userId, bool on) =>
      _run(() => _c.rpc('adbiz_member_set_active', params: {'p_user': userId, 'p_on': on}));

  Future<void> memberTarget(String userId, double? target) =>
      _run(() => _c.rpc('adbiz_admin_member_target', params: {'p_user': userId, 'p_target': target}));

  Future<String> ownerAddWorker(String email) =>
      _run(() async => (await _c.rpc('adbiz_owner_add_worker', params: {'p_email': email})) as String);
}

final adbizRepositoryProvider = Provider<AdbizRepository>((ref) => AdbizRepository());
