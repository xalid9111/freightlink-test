// İş Mərkəzi — SmartMatch (owner, 26.10.2026, migration 0069). Server
// rules: supabase/tests/local/106_job_center.sql.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:freightlink/features/jobs/domain/job_match.dart';
import 'package:freightlink/features/jobs/domain/job_models.dart';

String src(String p) => File(p).readAsStringSync();

JobSeeker driver(String id,
        {List<String> specialties = const ['ref'],
        Map<String, SkillState> skills = const {},
        int? experience,
        String? country,
        String? city,
        List<String> countries = const [],
        double? salary,
        String? schedule}) =>
    JobSeeker(
      userId: id,
      fullName: id,
      specialties: specialties,
      skills: skills,
      experienceYears: experience,
      country: country,
      city: city,
      countries: countries,
      salaryMin: salary,
      currency: salary == null ? null : 'AZN',
      schedule: schedule,
    );

JobVacancy vacancy(
        {List<String> specialties = const ['ref'],
        Map<String, ReqLevel> req = const {},
        Set<String> help = const {},
        int? minExperience,
        String? country,
        String? city,
        double? salaryMax,
        String? schedule}) =>
    JobVacancy(
      id: 'v1',
      ownerId: 'e1',
      companyName: 'Ref Trans',
      specialties: specialties,
      requirements: req,
      canHelp: help,
      minExperience: minExperience,
      country: country,
      city: city,
      salaryMax: salaryMax,
      currency: salaryMax == null ? null : 'AZN',
      schedule: schedule,
    );

void main() {
  group('✓ / ✗ / not given are kept apart', () {
    test('a code missing from the map is "not given", never "no"', () {
      final p = JobSeeker.fromJson({
        'user_id': 'u1',
        'full_name': ' Elvin ',
        'skills': {'lic_ce': 'yes', 'tachograph': 'no', 'cpc': 'ready', 'bad': 'maybe'},
        'specialties': ['ref', 'tent'],
        'age': 35,
      });
      expect(p.fullName, 'Elvin');
      expect(p.skills, {'lic_ce': SkillState.yes, 'tachograph': SkillState.no, 'cpc': SkillState.ready});
      expect(p.skills.containsKey('intl_exp'), isFalse);
      expect(p.age, 35);
      expect(p.toRow()['skills'], {'lic_ce': 'yes', 'tachograph': 'no', 'cpc': 'ready'});
      expect(p.toRow().containsKey('is_hidden'), isFalse, reason: 'only an admin hides');
    });

    test('the comparison lines show each state', () {
      final m = matchJob(
        driver('d', skills: {'lic_ce': SkillState.yes, 'tachograph': SkillState.no, 'cpc': SkillState.ready}),
        vacancy(req: {'lic_ce': ReqLevel.must, 'tachograph': ReqLevel.must, 'cpc': ReqLevel.nice, 'intl_exp': ReqLevel.nice},
            help: {'tachograph'}),
      );
      CheckState st(String code) => m.checks.firstWhere((c) => c.code == code && c.kind == CheckKind.skill).state;
      expect(st('lic_ce'), CheckState.yes);
      expect(st('tachograph'), CheckState.no);
      expect(st('cpc'), CheckState.ready);
      expect(st('intl_exp'), CheckState.unknown);
      expect(m.checks.firstWhere((c) => c.code == 'tachograph').canHelp, isTrue);
      // must lines before nice ones
      final skillCodes = [for (final c in m.checks) if (c.kind == CheckKind.skill) c.code];
      expect(skillCodes.take(2).toSet(), {'lic_ce', 'tachograph'});
    });
  });

  group('SmartMatch percentage (information only)', () {
    test('not given neither adds nor takes points', () {
      final full = matchJob(driver('a', skills: {'lic_ce': SkillState.yes}), vacancy(req: {'lic_ce': ReqLevel.must}));
      final unknown = matchJob(driver('b'), vacancy(req: {'lic_ce': ReqLevel.must}));
      expect(full.percent, 100);
      expect(unknown.percent, 100, reason: 'only the specialty is known — and it fits');
      final no = matchJob(driver('c', skills: {'lic_ce': SkillState.no}), vacancy(req: {'lic_ce': ReqLevel.must}));
      expect(no.percent, (40 * 100 / 50).round());
    });

    test('a vacancy without any requirement works (no error, specialty only)', () {
      final m = matchJob(driver('a'), vacancy());
      expect(m.checks.length, 1);
      expect(m.percent, 100);
      final none = matchJob(driver('a', specialties: const []), vacancy(specialties: const []));
      expect(none.checks, isEmpty);
      expect(none.percent, isNull);
      expect(none.good, isFalse);
    });

    test('experience, country, city, salary and schedule lines', () {
      final m = matchJob(
        driver('a', experience: 5, country: 'Azerbaijan', city: 'Baku', salary: 1500, schedule: 'rotation'),
        vacancy(minExperience: 3, country: 'Azerbaijan', city: 'Ganja', salaryMax: 2000, schedule: 'rotation'),
      );
      CheckState st(CheckKind k) => m.checks.firstWhere((c) => c.kind == k).state;
      expect(st(CheckKind.experience), CheckState.yes);
      expect(st(CheckKind.place), CheckState.yes);
      expect(st(CheckKind.city), CheckState.no);
      expect(st(CheckKind.salary), CheckState.yes);
      expect(st(CheckKind.schedule), CheckState.yes);
      final abroad = matchJob(driver('b', country: 'Georgia', countries: const ['Azerbaijan']), vacancy(country: 'Azerbaijan'));
      expect(abroad.checks.firstWhere((c) => c.kind == CheckKind.place).state, CheckState.yes,
          reason: 'he wants to work in that country');
      final tooMuch = matchJob(driver('c', salary: 3000), vacancy(salaryMax: 2000));
      expect(tooMuch.checks.firstWhere((c) => c.kind == CheckKind.salary).state, CheckState.no);
    });
  });

  group('lists: REF first, nobody hidden', () {
    final people = [
      driver('tent-only', specialties: const ['tent']),
      driver('ref-no-docs', skills: {'lic_ce': SkillState.no}),
      driver('ref-full', skills: {'lic_ce': SkillState.yes}),
      driver('nothing', specialties: const []),
    ];
    final v = vacancy(req: {'lic_ce': ReqLevel.must});

    test('"Bütün sürücülər": everybody, the best REF first', () {
      final all = rankMatches(people, (p) => matchJob(p, v));
      expect(all.length, people.length);
      expect(all.first.userId, 'ref-full');
      expect(all.last.userId, 'tent-only', reason: 'another specialty is last, but still shown');
    });

    test('"Uyğun sürücülər": the specialty fits and at least 60 %', () {
      final good = rankMatches(people, (p) => matchJob(p, v), only: true);
      expect([for (final p in good) p.userId], ['ref-full', 'ref-no-docs'],
          reason: 'no specialty and nothing else to compare → only under "Bütün"');
    });

    test('the driver side uses the same rule ("Mənə uyğun işlər")', () {
      final jobs = [vacancy(specialties: const ['tent']), vacancy()];
      final ranked = rankMatches(jobs, (j) => matchJob(driver('me'), j));
      expect(ranked.first.specialties, ['ref']);
      expect(ranked.length, 2);
    });
  });

  test('vacancy round trip: requirements, can-help only for asked ones', () {
    final v = JobVacancy.fromJson({
      'id': 'v1',
      'owner_id': 'e1',
      'company_name': 'Ref Trans',
      'requirements': {'lic_ce': 'must', 'tachograph': 'nice', 'x': 'maybe'},
      'can_help': ['tachograph', 'cpc'],
      'status': 'closed',
    });
    expect(v.requirements, {'lic_ce': ReqLevel.must, 'tachograph': ReqLevel.nice});
    expect(v.isActive, isFalse);
    expect(v.toRow()['can_help'], ['tachograph']);
    expect(v.toRow().containsKey('is_hidden'), isFalse);
    expect(v.toRow().containsKey('id'), isFalse);
  });

  test('catalogues: the 10 specialties and the document / skill template', () {
    expect([for (final s in kJobSpecialties) s.code],
        ['tent', 'ref', 'tow', 'container', 'dump', 'tanker', 'open', 'car_carrier', 'bus', 'excavator', 'other']);
    for (final code in ['lic_c', 'lic_ce', 'tachograph', 'cpc', 'intl_exp', 'tech', 'discipline', 'responsibility']) {
      expect(kJobSkills.any((k) => k.code == code), isTrue, reason: code);
    }
    // 0070 adds ADR, route_mix, night; 0072 Açıq, D1, C1E, D1E, DE, idp.
    final sql = src('supabase/migrations/0069_job_center.sql') +
        src('supabase/migrations/0070_job_vacancy_wizard.sql') +
        src('supabase/migrations/0072_job_forms.sql');
    for (final s in kJobSpecialties) {
      expect(sql, contains("('${s.code}', "), reason: s.code);
    }
    for (final s in kJobSkills) {
      expect(sql, contains("('${s.code}', '${s.kind}', "), reason: s.code);
    }
  });

  test('icons: the approved picture without a background (PNG with alpha), day and night', () {
    for (final f in ['job_center_day', 'job_center_night']) {
      final b = File('assets/images/jobs/$f.png').readAsBytesSync();
      expect(b.sublist(0, 8), [137, 80, 78, 71, 13, 10, 26, 10], reason: f);
      expect(ByteData.sublistView(Uint8List.fromList(b.sublist(25, 26))).getUint8(0), 6, reason: '$f is RGBA');
    }
    expect(src('pubspec.yaml'), contains('- assets/images/jobs/'));
  });

  test('wired: Loads header, computer header, Profil, routes; existing chat reused', () {
    final loads = src('lib/features/cargo/presentation/cargo_marketplace_screen.dart');
    // Owner, 27.10.2026: on the map under "CANLI", slogan under the logo.
    expect(loads, contains('Positioned(top: 40, right: 14, child: JobCenterMapButton(strings: strings)),'));
    expect(loads, contains("key: const ValueKey('home-slogan'),"));
    expect(loads.contains("strings.t('home_live_map')"), isFalse);
    expect(src('lib/features/cargo/presentation/cargo_marketplace_desktop.dart'), contains("ValueKey('desk-job-center')"));
    expect(src('lib/features/auth/presentation/profile_screen.dart'), contains("onTap: () => context.pushOnce('/jobs'),"));
    final router = src('lib/core/router/app_router.dart');
    for (final r in ['/jobs', '/jobs/profile', '/jobs/vacancy/new', '/jobs/vacancy/:id', '/jobs/work', '/jobs/drivers']) {
      expect(router, contains("path: '$r',"), reason: r);
    }
    final w = src('lib/features/jobs/presentation/job_widgets.dart');
    expect(w, contains('openDirect(widget.userId)'), reason: 'the existing Mesajlar, no second chat system');
    final repo = src('lib/features/jobs/data/jobs_repository.dart');
    expect(repo, contains("rpc('job_seekers_list'"));
    expect(repo, contains("rpc('job_vacancies_list'"));
    expect(repo.contains("from('job_seeker_profiles').select().order"), isFalse, reason: 'others only via the safe list');
    // Phone hidden by default in both forms.
    expect(src('lib/features/jobs/presentation/job_seeker_form.dart'), contains('_showPhone = p?.showPhone ?? false;'));
    expect(src('lib/features/jobs/presentation/job_vacancy_form.dart'), contains('_showPhone = v?.showPhone ?? false;'));
  });

  test('0069 is safe: forward-only, private columns behind the server lists, nothing dropped', () {
    final sql = src('supabase/migrations/0069_job_center.sql').toLowerCase();
    for (final bad in ['drop table', 'truncate', 'delete from']) {
      expect(sql.contains(bad), isFalse, reason: bad);
    }
    expect(sql, contains('begin;'));
    expect(sql, contains('commit;'));
    expect(sql, contains('0069: final check failed'));
    expect(sql, contains('show_phone boolean not null default false'));
    expect(sql, contains('revoke all on public.job_seeker_profiles from anon, authenticated;'));
    expect(sql, contains('revoke all on function public.job_seekers_list(integer, integer) from public, anon;'));
    expect(sql, contains("'phone', case when p.show_phone or v_admin or p.user_id = auth.uid() then p.phone end"));
    expect(sql.contains("'birth_date'"), isFalse, reason: 'age only');
    expect(sql, contains('create unique index if not exists notifications_dedupe_key'));
    final run = src('supabase/tests/local/run_local.sh');
    expect(run, contains('0069_job_center.sql'));
    expect(run, contains('106_job_center.sql'));
  });
}
