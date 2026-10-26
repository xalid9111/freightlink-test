// İş Mərkəzi — "Vakansiya yerləşdir" in 4 steps as in the owner's picture
// (26.10.2026, migration 0070). Server rules:
// supabase/tests/local/107_job_vacancy_wizard.sql.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freightlink/core/localization/app_strings.dart';
import 'package:freightlink/core/localization/locale_controller.dart';
import 'package:freightlink/features/auth/presentation/providers/auth_providers.dart';
import 'package:freightlink/features/jobs/data/jobs_repository.dart';
import 'package:freightlink/features/jobs/domain/job_models.dart';
import 'package:freightlink/features/jobs/presentation/job_vacancy_form.dart';
import 'package:freightlink/features/jobs/presentation/jobs_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

String src(String p) => File(p).readAsStringSync();

class _FakeRepo implements JobsRepository {
  JobVacancy? saved;
  @override
  Future<JobVacancy> saveVacancy(JobVacancy v) async => saved = v;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final _az = AppStrings(Map<String, String>.from(jsonDecode(src('assets/i18n/az.json')) as Map));

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('ticking: documents / categories → Mütləq, skills → Arzuolunan, an existing level is kept', () {
    var r = toggleRequirement(const {}, const {}, 'cpc', true, ReqLevel.must);
    expect(r.req, {'cpc': ReqLevel.must});
    r = toggleRequirement(r.req, r.help, 'night', true, ReqLevel.nice);
    expect(r.req, {'cpc': ReqLevel.must, 'night': ReqLevel.nice});
    r = toggleRequirement({'tachograph': ReqLevel.nice}, {'tachograph'}, 'tachograph', true, ReqLevel.must);
    expect(r.req['tachograph'], ReqLevel.nice, reason: 'an older "Arzuolunan" is not changed');
    expect(r.help, {'tachograph'});
    r = toggleRequirement(r.req, r.help, 'tachograph', false, ReqLevel.must);
    expect(r.req, isEmpty);
    expect(r.help, isEmpty, reason: 'unticking also drops "I can help"');
  });

  test('picture order: B C C1 D CE · Peşə, Taxoqraf, ADR · server extras after', () {
    final lic = orderedCatalog(kJobSkills.where((k) => k.kind == 'license').toList(), ['lic_b', 'lic_c', 'lic_c1', 'lic_d', 'lic_ce']);
    expect([for (final k in lic) k.name], ['B', 'C', 'C1', 'D', 'CE']);
    final docs = orderedCatalog(
        [...kJobSkills.where((k) => k.kind == 'document'), const JobCatalogItem('x_new', 'Yeni', 'document')], ['cpc', 'tachograph', 'adr']);
    expect([for (final k in docs) k.code], ['cpc', 'tachograph', 'adr', 'x_new']);
  });

  test('model: İş növü and "Layihə əsasında"; job_type only sent when chosen', () {
    expect(kJobSchedules, contains('project'));
    expect(kJobSchedules.take(4), ['full_time', 'part_time', 'rotation', 'flexible'], reason: 'old values stay');
    final v = JobVacancy.fromJson({'id': 'v', 'owner_id': 'o', 'company_name': 'A', 'job_type': 'tir', 'schedule': 'project'});
    expect(v.jobType, 'tir');
    expect(v.toRow()['job_type'], 'tir');
    expect(JobVacancy.fromJson({'id': 'v', 'owner_id': 'o', 'company_name': 'A', 'job_type': 'boss'}).jobType, isNull);
    expect(const JobVacancy(ownerId: 'o', companyName: 'A').toRow().containsKey('job_type'), isFalse,
        reason: 'an older database (before 0070) still saves');
    expect(src('lib/features/jobs/data/jobs_repository.dart'), contains("e.code != 'PGRST204' || !data.containsKey('job_type')"));
  });

  test('0070 is safe and every new text is in all 6 languages', () {
    final sql = src('supabase/migrations/0070_job_vacancy_wizard.sql').toLowerCase();
    for (final bad in ['drop table', 'truncate', 'delete from', 'drop column']) {
      expect(sql.contains(bad), isFalse, reason: bad);
    }
    expect(sql, contains('add column if not exists job_type text'));
    expect(sql, contains("'phone', case when v.show_phone or v_admin or v.owner_id = auth.uid() then v.phone end"));
    expect(sql, contains('on conflict (code) do nothing'));
    for (final s in kJobSkills.where((k) => ['adr', 'route_mix', 'night'].contains(k.code))) {
      expect(sql, contains("('${s.code}', '${s.kind}', "), reason: s.code);
    }
    final keys = [
      for (final k in (jsonDecode(src('assets/i18n/az.json')) as Map).keys)
        if ('$k'.startsWith('job_wz_') || '$k'.startsWith('job_chip_')) '$k',
      'job_sch_project', 'job_sch_short_rotation', 'job_skill_adr', 'job_skill_route_mix', 'job_skill_night',
    ];
    expect(keys.length, greaterThan(30));
    for (final lang in ['az', 'tr', 'en', 'ru', 'ka', 'zh']) {
      final m = jsonDecode(src('assets/i18n/$lang.json')) as Map;
      for (final k in keys) {
        expect((m[k] as String?)?.isNotEmpty, isTrue, reason: '$lang $k');
      }
    }
  });

  Future<_FakeRepo> pump(WidgetTester tester, {double width = 390, double height = 844}) async {
    tester.view.physicalSize = Size(width, height);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final repo = _FakeRepo();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        stringsProvider.overrideWithValue(_az),
        jobsRepositoryProvider.overrideWithValue(repo),
        myVacanciesProvider.overrideWith((ref) async => const <JobVacancy>[]),
        jobSpecialtiesProvider.overrideWith((ref) async => kJobSpecialties),
        jobSkillsProvider.overrideWith((ref) async => kJobSkills),
        currentUserProvider.overrideWithValue(null),
        currentUserIdProvider.overrideWithValue('u1'),
      ],
      child: const MaterialApp(home: JobVacancyFormScreen()),
    ));
    await tester.pumpAndSettle();
    return repo;
  }

  Future<void> tap(WidgetTester tester, String key) async {
    final f = find.byKey(ValueKey(key));
    // The step is a lazy list: scroll until the control is built and seen.
    await tester.scrollUntilVisible(f, 200, scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    await tester.tap(f);
    await tester.pumpAndSettle();
  }

  testWidgets('4 steps as in the picture: fill, go on, back, publish', (tester) async {
    // Tall enough to see a whole step at once.
    final repo = await pump(tester, height: 2200);
    for (final t in ['Vakansiya yerləşdir', 'Sürücü və işçi axtarın', 'Əsas məlumat', 'Tələblər', 'Marşrut', 'Dərc et',
      'İş növü', 'TIR sürücüsü', 'Digər sürücü / işçi', 'Maaş', 'İş qrafiki', 'Tam iş günü', 'Növbəli', 'Layihə əsasında',
      'Sürücülük kateqoriyası', 'İş ölkələri', 'Marşrut əlavə et (istəyə bağlı)', 'Davam et']) {
      expect(find.text(t), findsWidgets, reason: t);
    }
    await tester.enterText(find.byKey(const ValueKey('job-salary-min')), '1500');
    await tester.enterText(find.byKey(const ValueKey('job-salary-max')), '2500');
    await tap(tester, 'job-sch-project');
    await tap(tester, 'job-lic-lic_ce');
    await tap(tester, 'job-country-AZ');
    await tap(tester, 'job-wz-next');

    // 2 Tələblər
    for (final t in ['Tələb olunan sənədlər', 'Peşə sertifikatı', 'Taxoqraf kartı', 'ADR sertifikatı', 'Bacarıqlar və təcrübə',
      'Minimum təcrübə', 'Beynəlxalq daşıma', 'Məsuliyyətli', 'Nizam-intizam', 'Texniki bilik', 'Yük qısa/uzun marşrut',
      'Gecə sürüşü', 'Əlavə şərtlər (istəyə bağlı)', 'Geri']) {
      expect(find.text(t), findsWidgets, reason: t);
    }
    expect(find.text('0/500'), findsOneWidget);
    await tap(tester, 'job-doc-cpc');
    await tap(tester, 'job-doc-tachograph');
    await tap(tester, 'job-skill-intl_exp');
    await tap(tester, 'job-skill-responsibility');
    await tap(tester, 'job-wz-back');
    expect(find.byKey(const ValueKey('job-type-tir')), findsOneWidget, reason: 'Geri returns to step 1, nothing lost');
    await tap(tester, 'job-wz-next');
    await tap(tester, 'job-wz-next');

    // 3 Marşrut
    await tester.enterText(find.byKey(const ValueKey('job-routes')), 'Bakı – Tbilisi – İstanbul');
    await tap(tester, 'job-wz-next');

    // 4 Dərc et
    await tester.enterText(find.byKey(const ValueKey('job-company')), 'Ref Trans');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('job-wz-summary')), findsOneWidget);
    await tap(tester, 'job-save');
    final v = repo.saved!;
    expect(v.jobType, 'tir');
    expect(v.companyName, 'Ref Trans');
    expect(v.schedule, 'project');
    expect([v.salaryMin, v.salaryMax, v.currency], [1500, 2500, null]);
    expect(v.countries, ['Azerbaijan']);
    expect(v.routes, 'Bakı – Tbilisi – İstanbul');
    expect(v.requirements, {
      'lic_ce': ReqLevel.must,
      'cpc': ReqLevel.must,
      'tachograph': ReqLevel.must,
      'intl_exp': ReqLevel.nice,
      'responsibility': ReqLevel.nice,
    });
    expect(v.showPhone, isFalse, reason: 'phone hidden by default');
    expect(v.isActive, isTrue);
  });

  testWidgets('narrow phone (320 pt): every step without overflow', (tester) async {
    await pump(tester, width: 320);
    for (var i = 0; i < 3; i++) {
      await tap(tester, 'job-wz-next');
    }
    expect(find.byKey(const ValueKey('job-save')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
