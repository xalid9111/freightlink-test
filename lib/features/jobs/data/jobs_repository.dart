import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/supabase_config.dart';
import '../domain/job_applications.dart';
import '../domain/job_models.dart';

const _timeout = Duration(seconds: 20);

/// Thrown while the database does not have İş Mərkəzi yet (0069 not run):
/// the screens say "tezliklə" instead of an error.
class JobsNotReady implements Exception {
  const JobsNotReady();
}

Map<String, dynamic> _withoutNew(Map<String, dynamic> data) => {...data}..removeWhere((k, _) => kJobNewColumns.contains(k));

bool _missing(PostgrestException e) => e.code == 'PGRST202' || e.code == '42P01' || e.code == 'PGRST205';

/// İş Mərkəzi (0069). Other people's profiles and vacancies come only from
/// the server lists (signed in, no birth date, the phone only if shown);
/// my own rows straight from the tables (RLS: own rows only).
class JobsRepository {
  final SupabaseClient _c = SupabaseConfig.client;
  String? get _me => _c.auth.currentUser?.id;

  Future<T> _guard<T>(Future<T> Function() f) async {
    try {
      return await f();
    } on PostgrestException catch (e) {
      if (_missing(e)) throw const JobsNotReady();
      rethrow;
    }
  }

  Future<List<JobCatalogItem>> specialties() => _guard(() async {
        final rows = await _c.from('job_specialties').select('code,name').eq('is_active', true).order('sort_order').timeout(_timeout);
        return [for (final r in rows as List) JobCatalogItem.fromJson(Map<String, dynamic>.from(r as Map))];
      });

  Future<List<JobCatalogItem>> skills() => _guard(() async {
        final rows = await _c.from('job_skills').select('code,name,kind').eq('is_active', true).order('sort_order').timeout(_timeout);
        return [for (final r in rows as List) JobCatalogItem.fromJson(Map<String, dynamic>.from(r as Map))];
      });

  /// My work profile (null = not filled yet).
  Future<JobSeeker?> myProfile() => _guard(() async {
        final me = _me;
        if (me == null) return null;
        final row = await _c.from('job_seeker_profiles').select().eq('user_id', me).maybeSingle().timeout(_timeout);
        return row == null ? null : JobSeeker.fromJson(row);
      });

  Future<void> saveProfile(JobSeeker p) => _guard(() async {
        final data = p.toRow();
        try {
          await _c.from('job_seeker_profiles').upsert(data, onConflict: 'user_id').timeout(_timeout);
        } on PostgrestException catch (e) {
          // 0072 not run yet: save everything but the new column.
          if (e.code != 'PGRST204') rethrow;
          await _c.from('job_seeker_profiles').upsert(_withoutNew(data), onConflict: 'user_id').timeout(_timeout);
        }
      });

  /// "İş axtarıram" / "İş axtarışını dayandırmışam".
  Future<void> setSeeking(bool on) => _guard(() async {
        final me = _me;
        if (me == null) return;
        await _c.from('job_seeker_profiles').update({'is_active': on}).eq('user_id', me).timeout(_timeout);
      });

  Future<List<JobVacancy>> myVacancies() => _guard(() async {
        final me = _me;
        if (me == null) return const [];
        final rows = await _c.from('job_vacancies').select().eq('owner_id', me).order('created_at', ascending: false).timeout(_timeout);
        return [
          for (final r in rows as List)
            if ((r as Map)['status'] != 'deleted') JobVacancy.fromJson(Map<String, dynamic>.from(r))
        ];
      });

  Future<JobVacancy> saveVacancy(JobVacancy v) => _guard(() async {
        Future<Map<String, dynamic>> save(Map<String, dynamic> data) => v.id.isEmpty
            ? _c.from('job_vacancies').insert(data).select().single().timeout(_timeout)
            : _c.from('job_vacancies').update(data).eq('id', v.id).select().single().timeout(_timeout);
        final data = v.toRow();
        try {
          return JobVacancy.fromJson(await save(data));
        } on PostgrestException catch (e) {
          // 0070 / 0072 not run yet: a new column is missing — save the rest.
          if (e.code != 'PGRST204') rethrow;
          return JobVacancy.fromJson(await save(_withoutNew(data)));
        }
      });

  /// "Vakansiya aktivdir" / "Vakansiya bağlanıb".
  Future<void> setVacancyActive(String id, bool on) => _guard(() async {
        await _c.from('job_vacancies').update({'status': on ? 'active' : 'closed'}).eq('id', id).timeout(_timeout);
      });

  /// "Sil" from the profile (0071): the vacancy is marked deleted — no row
  /// is removed, the drivers' applications to it are kept.
  Future<void> deleteVacancy(String id) => _guard(() async {
        try {
          await _c.from('job_vacancies').update({'status': 'deleted'}).eq('id', id).timeout(_timeout);
        } on PostgrestException catch (e) {
          // 0071 not run yet: 'deleted' is not an allowed status.
          if (e.code == '23514') throw const JobsNotReady();
          rethrow;
        }
      });

  /// Everyone looking for work (safe columns only).
  Future<List<JobSeeker>> seekers() => _guard(() async {
        final res = await _c.rpc('job_seekers_list', params: {'p_limit': 500}).timeout(_timeout);
        return [for (final r in (res as List? ?? const [])) JobSeeker.fromJson(Map<String, dynamic>.from(r as Map))];
      });

  /// Every active vacancy (safe columns only).
  Future<List<JobVacancy>> vacancies() => _guard(() async {
        final res = await _c.rpc('job_vacancies_list', params: {'p_limit': 500}).timeout(_timeout);
        return [for (final r in (res as List? ?? const [])) JobVacancy.fromJson(Map<String, dynamic>.from(r as Map))];
      });

  /// Admin: hide / show a profile ('seeker') or a vacancy ('vacancy'), logged.
  Future<void> adminSetHidden(String kind, String id, bool hidden) => _guard(() async {
        await _c.rpc('admin_job_set_hidden', params: {'p_kind': kind, 'p_id': id, 'p_hidden': hidden}).timeout(_timeout);
      });

  // ---- PR 2: applications, offers, notices (server rules: 0069) ----------

  /// My applications and offers, both sides (RLS: only mine).
  Future<List<JobApplication>> applications() => _guard(() async {
        final rows = await _c.from('job_applications').select().order('updated_at', ascending: false).limit(300).timeout(_timeout);
        return [for (final r in rows as List) JobApplication.fromJson(Map<String, dynamic>.from(r as Map))];
      });

  /// "Müraciət et" ([seekerId] null) or "İş təklif et" (the employer, for
  /// a driver).
  Future<JobApplication> sendApplication(String vacancyId, {String? seekerId, String? message}) => _guard(() async {
        final res = await _c.rpc('job_application_send', params: {
          'p_vacancy': vacancyId,
          'p_seeker': seekerId,
          'p_message': message,
        }).timeout(_timeout);
        return JobApplication.fromJson(Map<String, dynamic>.from(res as Map));
      });

  Future<JobApplication> setApplicationStatus(String id, String status) => _guard(() async {
        final res = await _c.rpc('job_application_set_status', params: {'p_id': id, 'p_status': status}).timeout(_timeout);
        return JobApplication.fromJson(Map<String, dynamic>.from(res as Map));
      });

  /// Public names / pictures (the user_profiles view, 0019).
  Future<Map<String, ({String name, String? avatar})>> people(Iterable<String> ids) async {
    final list = ids.toSet().toList();
    if (list.isEmpty) return const {};
    final rows = await _c.from('user_profiles').select('id,full_name,avatar_url').inFilter('id', list).timeout(_timeout);
    return {
      for (final r in rows as List)
        '${r['id']}': (name: '${r['full_name'] ?? ''}'.trim(), avatar: r['avatar_url'] as String?),
    };
  }

  /// My job notices (the existing notifications table).
  Future<List<JobNotice>> notices() => _guard(() async {
        final rows = await _c
            .from('notifications')
            .select('id,type,title,data,is_read,created_at')
            .inFilter('type', kJobNoticeTypes)
            .order('created_at', ascending: false)
            .limit(100)
            .timeout(_timeout);
        return [for (final r in rows as List) JobNotice.fromJson(Map<String, dynamic>.from(r as Map))];
      });

  Future<void> markNoticesRead(List<String> ids) async {
    if (ids.isEmpty) return;
    await _c.from('notifications').update({'is_read': true}).inFilter('id', ids).timeout(_timeout);
  }
}
