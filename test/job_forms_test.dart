// İş Mərkəzi — the employer and driver forms as in the owner's pictures 2
// and 3 (28.10.2026, migration 0072). Server rules:
// supabase/tests/local/109_job_forms.sql.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freightlink/core/constants/countries.dart';
import 'package:freightlink/core/localization/app_strings.dart';
import 'package:freightlink/core/localization/locale_controller.dart';
import 'package:freightlink/features/auth/presentation/providers/auth_providers.dart';
import 'package:freightlink/features/jobs/data/jobs_repository.dart';
import 'package:freightlink/features/jobs/domain/job_match.dart';
import 'package:freightlink/features/jobs/domain/job_models.dart';
import 'package:freightlink/features/jobs/presentation/job_form_kit.dart';
import 'package:freightlink/features/jobs/presentation/job_seeker_form.dart';
import 'package:freightlink/features/jobs/presentation/job_vacancy_form.dart';
import 'package:freightlink/features/jobs/presentation/jobs_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

String src(String p) => File(p).readAsStringSync();
final _az = AppStrings(Map<String, String>.from(jsonDecode(src('assets/i18n/az.json')) as Map));

class _FakeRepo implements JobsRepository {
  JobVacancy? vacancy;
  JobSeeker? profile;
  @override
  Future<JobVacancy> saveVacancy(JobVacancy v) async => vacancy = v;
  @override
  Future<void> saveProfile(JobSeeker p) async => profile = p;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('rules', () {
    test('ticking: documents / categories → Mütləq, skills → Arzuolunan, an existing level is kept', () {
      var r = toggleRequirement(const {}, const {}, 'cpc', true, ReqLevel.must);
      expect(r.req, {'cpc': ReqLevel.must});
      r = toggleRequirement({'tachograph': ReqLevel.nice}, {'tachograph'}, 'tachograph', true, ReqLevel.must);
      expect(r.req['tachograph'], ReqLevel.nice);
      r = toggleRequirement(r.req, r.help, 'tachograph', false, ReqLevel.must);
      expect(r.req, isEmpty);
      expect(r.help, isEmpty);
    });

    test('licence categories: B and CE kept, D1 · C1E · D1E · DE added; QRUPAJ is not a vehicle', () {
      final lic = [for (final k in kJobSkills) if (k.kind == 'license') k.name];
      expect(lic, containsAll(['B', 'C1', 'C', 'CE', 'D1', 'D', 'C1E', 'D1E', 'DE']));
      expect(kJobSpecialties.any((k) => k.code == 'open'), isTrue);
      expect(kJobSpecialties.any((k) => k.code == 'groupage' || k.name.toUpperCase() == 'QRUPAJ'), isFalse);
      expect(kJobSkills.any((k) => k.code == 'idp' && k.kind == 'document'), isTrue);
      // Existing documents / skills are kept.
      for (final c in ['tachograph', 'cpc', 'adr', 'intl_exp', 'tech', 'discipline', 'responsibility', 'route_mix', 'night']) {
        expect(kJobSkills.any((k) => k.code == c), isTrue, reason: c);
      }
    });

    test('İş rejimi: Daimi · Müvəqqəti · Uzun marşrut · Regional; older values stay valid', () {
      expect(kJobFormSchedules, ['permanent', 'temporary', 'long_haul', 'regional']);
      expect(kJobSchedules, containsAll(['full_time', 'part_time', 'rotation', 'flexible', 'project', ...kJobFormSchedules]));
    });

    test('capitals keep the dotted İ (SİSTERN, AÇIQ)', () {
      expect(jobUpper('Sistern', 'az'), 'SİSTERN');
      expect(jobUpper('Açıq', 'az'), 'AÇIQ');
      expect(jobUpper('Tanker', 'en'), 'TANKER');
    });

    test('several İş rejimi: older single value read as a list; the first is kept in the old column; one in common fits', () {
      final old = JobVacancy.fromJson({'id': 'v', 'owner_id': 'o', 'company_name': 'A', 'schedule': 'rotation'});
      expect(old.allSchedules, ['rotation']);
      const v = JobVacancy(ownerId: 'o', companyName: 'A', schedules: ['permanent', 'long_haul']);
      expect(v.toRow()['schedule'], 'permanent');
      expect(v.toRow()['schedules'], ['permanent', 'long_haul']);
      expect(kJobNewColumns, contains('schedules'));
      CheckState sch(List<String> mine) => matchJob(JobSeeker(userId: 'd', fullName: 'd', schedules: mine), v)
          .checks.firstWhere((c) => c.kind == CheckKind.schedule).state;
      expect(sch(['regional', 'long_haul']), CheckState.yes);
      expect(sch(['temporary']), CheckState.no);
      final sql = src('supabase/migrations/0073_job_schedules.sql').toLowerCase();
      for (final bad in ['drop table', 'truncate', 'delete from', 'drop column', 'update public.']) {
        expect(sql.contains(bad), isFalse, reason: bad);
      }
      expect(sql, contains("'phone', case when v.show_phone or v_admin or v.owner_id = auth.uid() then v.phone end"));
    });

    test('age: the picked age is shown again and grows by itself', () {
      final now = DateTime(2026, 10, 28);
      expect(ageOn(birthForAge(28, now), now), 28);
      expect(ageOn(birthForAge(28, now), DateTime(2027, 2, 1)), 29);
    });

    test('Avropa İttifaqı covers its members', () {
      String? code(String x) => Countries.find(x)?.code;
      expect(jobCountryFits(kJobEu, 'Germany', code), isTrue);
      expect(jobCountryFits('Poland', kJobEu, code), isTrue);
      expect(jobCountryFits(kJobEu, 'Türkiye', code), isFalse);
      expect(jobCountryFits('Azerbaijan', 'azerbaijan', code), isTrue);
    });

    test('SmartMatch: age range, licence, documents, transport and countries (EU) count', () {
      const v = JobVacancy(
        ownerId: 'e',
        companyName: 'A',
        specialties: ['tent'],
        requirements: {'lic_ce': ReqLevel.must, 'adr': ReqLevel.must},
        ageMin: 25,
        ageMax: 45,
        minExperience: 3,
        countries: [kJobEu],
      );
      final young = JobSeeker(
        userId: 'd',
        fullName: 'd',
        birthDate: DateTime(DateTime.now().year - 20, 1, 1),
        specialties: const ['tent'],
        skills: const {'lic_ce': SkillState.yes, 'adr': SkillState.yes},
        experienceYears: 5,
        countries: const ['Germany'],
      );
      final m = matchJob(young, v);
      expect(m.checks.firstWhere((c) => c.kind == CheckKind.age).state, CheckState.no);
      expect(m.checks.firstWhere((c) => c.kind == CheckKind.countries).state, CheckState.yes);
      final right = JobSeeker(
        userId: 'd',
        fullName: 'd',
        birthDate: DateTime(DateTime.now().year - 30, 1, 1),
        specialties: const ['tent'],
        skills: const {'lic_ce': SkillState.yes, 'adr': SkillState.yes},
        experienceYears: 5,
        countries: const ['Germany'],
      );
      expect(matchJob(right, v).percent, 100);
      expect(matchJob(const JobSeeker(userId: 'x', fullName: 'x', specialties: ['tent']), v)
          .checks.firstWhere((c) => c.kind == CheckKind.age).state, CheckState.unknown, reason: 'age not given');
    });

    test('model: new fields read / saved; an older database still saves the rest', () {
      final v = JobVacancy.fromJson({'id': 'v', 'owner_id': 'o', 'company_name': 'A', 'age_min': 25, 'age_max': 45, 'salary_negotiable': true});
      expect([v.ageMin, v.ageMax, v.salaryNegotiable], [25, 45, true]);
      expect(v.toRow()['age_min'], 25);
      expect(JobSeeker.fromJson({'user_id': 'u', 'full_name': 'x', 'salary_negotiable': true}).salaryNegotiable, isTrue);
      expect(kJobNewColumns, containsAll(['job_type', 'age_min', 'age_max', 'salary_negotiable']));
      final repo = src('lib/features/jobs/data/jobs_repository.dart');
      expect(repo, contains("upsert(_withoutNew(data), onConflict: 'user_id')"));
      expect(repo, contains('save(_withoutNew(data))'));
    });

    test('0072 is safe; every new text is in all 6 languages', () {
      final sql = src('supabase/migrations/0072_job_forms.sql').toLowerCase();
      for (final bad in ['drop table', 'truncate', 'delete from', 'drop column', 'update public.']) {
        expect(sql.contains(bad), isFalse, reason: bad);
      }
      expect(sql, contains("'phone', case when p.show_phone or v_admin or p.user_id = auth.uid() then p.phone end"));
      expect(sql, contains("'phone', case when v.show_phone or v_admin or v.owner_id = auth.uid() then v.phone end"));
      expect(sql.contains("'birth_date'"), isFalse, reason: 'age only');
      final keys = [
        for (final k in (jsonDecode(src('assets/i18n/az.json')) as Map).keys)
          if (RegExp(r'^job_(eu|negotiable|age_range|contact_|emp_banner|drv_banner|short_|sch_(permanent|temporary|long_haul|regional)|skill_(idp|lic_d1|lic_c1e|lic_d1e|lic_de)|spec_open)')
              .hasMatch('$k'))
            '$k',
      ];
      expect(keys.length, greaterThan(20));
      for (final lang in ['az', 'tr', 'en', 'ru', 'ka', 'zh']) {
        final m = jsonDecode(src('assets/i18n/$lang.json')) as Map;
        for (final k in keys) {
          expect((m[k] as String?)?.isNotEmpty, isTrue, reason: '$lang $k');
        }
      }
      for (final f in ['banner_employer.jpg', 'banner_driver.jpg']) {
        expect(File('assets/images/jobs/$f').existsSync(), isTrue, reason: f);
      }
    });
  });

  Future<_FakeRepo> pump(WidgetTester tester, Widget screen, {double width = 390, JobSeeker? profile}) async {
    tester.view.physicalSize = Size(width, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final repo = _FakeRepo();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        stringsProvider.overrideWithValue(_az),
        jobsRepositoryProvider.overrideWithValue(repo),
        myVacanciesProvider.overrideWith((ref) async => const <JobVacancy>[]),
        myJobProfileProvider.overrideWith((ref) async => profile),
        jobSpecialtiesProvider.overrideWith((ref) async => kJobSpecialties),
        jobSkillsProvider.overrideWith((ref) async => kJobSkills),
        currentUserProvider.overrideWithValue(null),
        currentUserIdProvider.overrideWithValue('u1'),
      ],
      child: MaterialApp(home: screen),
    ));
    await tester.pumpAndSettle();
    return repo;
  }

  Future<void> tap(WidgetTester tester, String key) async {
    // Also finds a truck picture waiting to the right of the sideways row.
    final f = find.byKey(ValueKey(key), skipOffstage: false);
    await tester.ensureVisible(f);
    await tester.pumpAndSettle();
    await tester.tap(f);
    await tester.pumpAndSettle();
  }

  testWidgets('employer form (picture 2): one page, no Sürücü | Sahibkar switch, publishes the vacancy', (tester) async {
    final repo = await pump(tester, const JobVacancyFormScreen());
    for (final t in ['Şirkət adı', 'İşlədiyim ölkələr', 'Avropa İttifaqı', 'Başqa', 'Lazım olan nəqliyyat növü', 'TENT', 'REF',
      'Sürücülük vəsiqəsi kateqoriyası', 'B', 'CE', 'C1E', 'DE', 'Təcrübə tələbi', 'Yaş aralığı', 'Sənəd tələbləri', 'Taxo kart',
      'Sürücülük sertifikatı (95 kod)', 'ADR kart', 'Beynəlxalq sürücülük vəsiqəsi', 'Əlavə tələblər', 'İş rejimi', 'Daimi',
      'Müvəqqəti', 'Uzun marşrut', 'Regional', 'Təklif etdiyim maaş aralığı', 'Danışılacaq', 'Əlaqə məlumatı',
      'Tələblərimi yerləşdir', 'Sürücü', 'axtarıram']) {
      expect(find.textContaining(t), findsWidgets, reason: t);
    }
    expect(find.text('Sahibkar'), findsNothing, reason: 'no Sürücü | Sahibkar switch on the form');
    expect(find.byKey(const ValueKey('job-wz-dot-0')), findsNothing, reason: 'no 4-step wizard');
    await tester.enterText(find.byKey(const ValueKey('job-company')), 'Test MMC');
    await tap(tester, 'job-country-AZ');
    await tap(tester, 'job-country-EU');
    await tap(tester, 'job-transport-tent');
    await tap(tester, 'job-transport-open');
    await tap(tester, 'job-lic-lic_ce');
    await tap(tester, 'job-doc-tachograph');
    await tap(tester, 'job-doc-adr');
    await tap(tester, 'job-skill-intl_exp');
    await tap(tester, 'job-sch-long_haul');
    await tap(tester, 'job-sch-permanent');
    await tester.enterText(find.byKey(const ValueKey('job-salary-min')), '1500');
    await tester.enterText(find.byKey(const ValueKey('job-salary-max')), '2500');
    await tap(tester, 'job-negotiable');
    await tap(tester, 'job-save');
    final v = repo.vacancy!;
    expect(v.companyName, 'Test MMC');
    expect(v.countries, ['Azerbaijan', kJobEu]);
    expect(v.specialties, ['tent', 'open']);
    expect(v.requirements, {
      'lic_ce': ReqLevel.must,
      'tachograph': ReqLevel.must,
      'adr': ReqLevel.must,
      'intl_exp': ReqLevel.nice,
    });
    expect([v.schedule, v.salaryMin, v.salaryMax, v.salaryNegotiable], ['long_haul', 1500, 2500, true]);
    expect(v.schedules, ['long_haul', 'permanent'], reason: 'several İş rejimi at once (owner, 28.10.2026)');
    expect(v.showPhone, isFalse, reason: 'phone hidden by default (Yalnız mesajla)');
    expect(v.isActive, isTrue);
    expect(v.jobType, 'tir');
  });

  testWidgets('driver form (picture 3): one page, ticks = has it, publishes the profile', (tester) async {
    final old = JobSeeker(
      userId: 'u1',
      fullName: 'Köhnə Ad',
      birthDate: DateTime(1990, 6, 15),
      city: 'Baku',
      country: 'Azerbaijan',
      routes: 'Bakı – Tbilisi',
      skills: const {'cpc': SkillState.ready, 'tech': SkillState.no},
      isActive: false,
    );
    final repo = await pump(tester, const JobSeekerFormScreen(), profile: old);
    for (final t in ['Ad Soyad', 'Yaş', 'Təcrübə', 'Nəqliyyat növü', 'Sürücülük vəsiqəsi', 'Sənədlərim var', 'İşlədiyim ölkələr',
      'İş rejimi', 'Arzu etdiyim maaş', 'Danışılacaq', 'Əlavə məlumat', 'Profilimi dərc et', 'İş axtarıram', 'Sürücü']) {
      expect(find.textContaining(t), findsWidgets, reason: t);
    }
    expect(find.text('Sahibkar'), findsNothing);
    await tester.enterText(find.byKey(const ValueKey('job-name')), 'Yeni Ad');
    await tap(tester, 'job-transport-ref');
    await tap(tester, 'job-lic-lic_ce');
    await tap(tester, 'job-lic-lic_c');
    await tap(tester, 'job-doc-tachograph');
    await tap(tester, 'job-country-TR');
    await tap(tester, 'job-sch-regional');
    await tap(tester, 'job-sch-temporary');
    await tap(tester, 'job-sch-long_haul');
    await tester.enterText(find.byKey(const ValueKey('job-salary-min')), '1500');
    await tap(tester, 'job-save');
    final p = repo.profile!;
    expect(p.fullName, 'Yeni Ad');
    expect(p.specialties, ['ref']);
    expect(p.skills, {
      'lic_ce': SkillState.yes,
      'lic_c': SkillState.yes,
      'tachograph': SkillState.yes,
      'cpc': SkillState.ready,
      'tech': SkillState.no,
    }, reason: 'answers the form does not show are kept');
    expect(p.countries, ['Türkiye']);
    expect([p.schedule, p.salaryMin], ['regional', 1500]);
    expect(p.schedules, ['regional', 'temporary', 'long_haul']);
    expect(p.birthDate, DateTime(1990, 6, 15), reason: 'age not changed → the stored date stays');
    expect([p.city, p.country, p.routes], ['Baku', 'Azerbaijan', 'Bakı – Tbilisi'], reason: 'fields not on the form are kept');
    expect(p.isActive, isTrue, reason: '"Profilimi dərc et" publishes it');
    expect(p.showPhone, isFalse);
  });

  for (final (name, screen) in [('employer', const JobVacancyFormScreen()), ('driver', const JobSeekerFormScreen())]) {
    testWidgets('$name form on a 320 pt phone: no overflow', (tester) async {
      await pump(tester, screen, width: 320);
      expect(tester.takeException(), isNull);
    });
  }
}
