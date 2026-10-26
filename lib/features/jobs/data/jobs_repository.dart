import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/supabase_config.dart';
import '../domain/job_models.dart';

const _timeout = Duration(seconds: 20);

/// Thrown while the database does not have İş Mərkəzi yet (0069 not run):
/// the screens say "tezliklə" instead of an error.
class JobsNotReady implements Exception {
  const JobsNotReady();
}

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
        await _c.from('job_seeker_profiles').upsert(p.toRow(), onConflict: 'user_id').timeout(_timeout);
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
        return [for (final r in rows as List) JobVacancy.fromJson(Map<String, dynamic>.from(r as Map))];
      });

  Future<JobVacancy> saveVacancy(JobVacancy v) => _guard(() async {
        Future<Map<String, dynamic>> save(Map<String, dynamic> data) => v.id.isEmpty
            ? _c.from('job_vacancies').insert(data).select().single().timeout(_timeout)
            : _c.from('job_vacancies').update(data).eq('id', v.id).select().single().timeout(_timeout);
        final data = v.toRow();
        try {
          return JobVacancy.fromJson(await save(data));
        } on PostgrestException catch (e) {
          // 0070 not run yet: no job_type column — save everything else.
          if (e.code != 'PGRST204' || !data.containsKey('job_type')) rethrow;
          return JobVacancy.fromJson(await save({...data}..remove('job_type')));
        }
      });

  /// "Vakansiya aktivdir" / "Vakansiya bağlanıb".
  Future<void> setVacancyActive(String id, bool on) => _guard(() async {
        await _c.from('job_vacancies').update({'status': on ? 'active' : 'closed'}).eq('id', id).timeout(_timeout);
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
}
