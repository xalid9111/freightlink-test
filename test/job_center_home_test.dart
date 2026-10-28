// İş Mərkəzi home page and ad page (owner, 28.10.2026, picture 1): the
// Sürücü / Sahibkar cards, "Uyğun təkliflər" (SmartMatch), "Mənim
// elanlarım" (kept), "Aktiv elanlar" with a filter, the page of one ad.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freightlink/core/localization/app_strings.dart';
import 'package:freightlink/core/localization/locale_controller.dart';
import 'package:freightlink/features/auth/presentation/providers/auth_providers.dart';
import 'package:freightlink/features/jobs/domain/job_feed.dart';
import 'package:freightlink/features/jobs/domain/job_models.dart';
import 'package:freightlink/features/jobs/presentation/job_center_screen.dart';
import 'package:freightlink/features/jobs/presentation/job_feed_widgets.dart';
import 'package:freightlink/features/jobs/presentation/job_item_screen.dart';
import 'package:freightlink/features/jobs/presentation/jobs_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

String src(String p) => File(p).readAsStringSync();
final _az = AppStrings(Map<String, String>.from(jsonDecode(src('assets/i18n/az.json')) as Map));

final _vTir = JobVacancy(
  id: 'v1',
  ownerId: 'e1',
  companyName: 'Şirkət A',
  jobType: 'tir',
  specialties: const ['tent'],
  requirements: const {'lic_ce': ReqLevel.must, 'lic_b': ReqLevel.nice, 'tachograph': ReqLevel.must},
  minExperience: 5,
  routes: 'Bakı — İstanbul',
  salaryMin: 2500,
  salaryMax: 2500,
  currency: 'AZN',
  phone: null,
  updatedAt: DateTime.utc(2026, 10, 28, 10),
);
final _vRef = JobVacancy(
  id: 'v2',
  ownerId: 'e2',
  companyName: 'Şirkət B',
  specialties: const ['ref'],
  countries: const ['Azerbaijan', 'Georgia'],
  status: 'active',
  updatedAt: DateTime.utc(2026, 10, 28, 8),
);
final _vClosed = JobVacancy(id: 'v3', ownerId: 'e1', companyName: 'C', status: 'closed', updatedAt: DateTime.utc(2026, 10, 28, 12));
final _dRef = JobSeeker(
  userId: 'd1',
  fullName: 'Sürücü Bir',
  specialties: const ['ref'],
  skills: const {'lic_ce': SkillState.yes, 'lic_c': SkillState.yes, 'tachograph': SkillState.no},
  experienceYears: 7,
  countries: const ['Azerbaijan', 'Türkiye'],
  updatedAt: DateTime.utc(2026, 10, 28, 9),
);
final _dOff = JobSeeker(userId: 'd2', fullName: 'X', isActive: false, updatedAt: DateTime.utc(2026, 10, 28, 11));

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('Aktiv elanlar', () {
    test('vacancies and drivers in one list, newest first; closed / switched off left out', () {
      final f = buildJobFeed([_vTir, _vRef, _vClosed], [_dRef, _dOff]);
      expect([for (final it in f) '${it.isVacancy ? 'v' : 'd'}:${it.id}'], ['v:v1', 'd:d1', 'v:v2']);
      expect(f[0].route, '/jobs/v/v1');
      expect(f[1].route, '/jobs/d/d1');
    });

    test('filter: what, transport, licence, country', () {
      List<String> ids(JobFeedFilter f) => [for (final it in buildJobFeed([_vTir, _vRef], [_dRef], filter: f)) it.id];
      expect(ids(const JobFeedFilter(kind: JobFeedKind.vacancies)), ['v1', 'v2']);
      expect(ids(const JobFeedFilter(kind: JobFeedKind.drivers)), ['d1']);
      expect(ids(const JobFeedFilter(specialty: 'ref')), ['d1', 'v2']);
      expect(ids(const JobFeedFilter(licence: 'lic_ce')), ['v1', 'd1']);
      expect(ids(const JobFeedFilter(country: 'Georgia')), ['v2']);
      expect(const JobFeedFilter(kind: JobFeedKind.drivers, licence: 'lic_ce').count, 2);
    });

    test('licence shown on the card: the highest one (CE for TIR); a driver\'s "no" is not a licence', () {
      expect(topLicence(['lic_b', 'lic_ce', 'lic_c']), 'lic_ce');
      expect(topLicence(const []), isNull);
      expect(const JobFeedItem.seeker(JobSeeker(userId: 'x', fullName: 'x', skills: {'lic_ce': SkillState.no})).licences, isEmpty);
    });

    test('titles as in the picture', () {
      const specs = kJobSpecialties;
      expect(jobFeedTitle(_az, JobFeedItem.vacancy(_vTir), specs), 'TIR sürücüsü tələb olunur');
      expect(jobFeedTitle(_az, JobFeedItem.vacancy(_vRef), specs), 'REF sürücüsü tələb olunur');
      expect(jobFeedTitle(_az, JobFeedItem.seeker(_dRef), specs), 'REF sürücüsü iş axtarır');
      expect(jobFeedTitle(_az, const JobFeedItem.seeker(JobSeeker(userId: 'y', fullName: 'y')), specs), 'Sürücü iş axtarır');
      expect(jobFeedSalary(JobFeedItem.vacancy(_vTir)), '2 500 AZN');
      expect(jobFeedWhere(JobFeedItem.seeker(_dRef), 'az'), 'Azərbaycan / Türkiyə');
    });
  });

  group('Uyğun təkliflər (SmartMatch)', () {
    test('my driver profile → fitting vacancies; my vacancies → fitting drivers; never my own', () {
      const me = JobSeeker(userId: 'me', fullName: 'Mən', specialties: ['ref'], skills: {'lic_ce': SkillState.yes});
      const mine = JobVacancy(id: 'm1', ownerId: 'me', companyName: 'Mənim', specialties: ['ref'], requirements: {'lic_ce': ReqLevel.must});
      final out = jobSuggestions(
        me: 'me',
        myProfile: me,
        myVacancies: [mine],
        vacancies: [_vTir, _vRef, mine],
        seekers: [_dRef, me],
      );
      final ids = [for (final x in out) x.item.id];
      expect(ids, containsAll(['v2', 'd1']));
      expect(ids, isNot(contains('m1')));
      expect(ids, isNot(contains('me')));
      expect(ids, isNot(contains('v1')), reason: 'Tent is not REF — not suggested');
      expect(out.every((x) => x.match.good), isTrue);
    });

    test('nothing to compare → empty (the hint is shown)', () {
      expect(jobSuggestions(me: 'me', myProfile: null, myVacancies: const [], vacancies: [_vRef], seekers: [_dRef]), isEmpty);
    });
  });

  List<Override> overrides({JobSeeker? profile, List<JobVacancy> mine = const []}) => [
        stringsProvider.overrideWithValue(_az),
        currentUserIdProvider.overrideWithValue('me'),
        myJobProfileProvider.overrideWith((ref) async => profile),
        myVacanciesProvider.overrideWith((ref) async => mine),
        jobVacanciesProvider.overrideWith((ref) async => [_vTir, _vRef]),
        jobSeekersProvider.overrideWith((ref) async => [_dRef]),
        jobSpecialtiesProvider.overrideWith((ref) async => kJobSpecialties),
        jobSkillsProvider.overrideWith((ref) async => kJobSkills),
      ];

  testWidgets('home: the two cards, SmartMatch, my ads kept, the feed and its filter', (tester) async {
    tester.view.physicalSize = const Size(390, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    const mine = JobVacancy(id: 'm1', ownerId: 'me', companyName: 'Mənim MMC', specialties: ['ref']);
    await tester.pumpWidget(ProviderScope(overrides: overrides(mine: [mine]), child: const MaterialApp(home: JobCenterScreen())));
    await tester.pumpAndSettle();
    for (final t in ['İş Mərkəzi', 'Sürücü', 'Profil / Elan ver', 'Sahibkar', 'Vakansiya yerləşdir', 'Uyğun təkliflər', 'SmartMatch',
      'Aktiv elanlar', 'Filtrlə', 'Mənim elanlarım', 'TIR sürücüsü tələb olunur', 'REF sürücüsü iş axtarır', 'Bakı — İstanbul',
      '2 500 AZN', '5 il təcrübə', '7 il təcrübə']) {
      expect(find.text(t), findsWidgets, reason: t);
    }
    // My vacancy keeps edit / on-off / drivers / delete.
    for (final k in ['job-vacancy-switch-m1', 'job-vacancy-edit-m1', 'job-vacancy-match-m1', 'job-vacancy-delete-m1']) {
      expect(find.byKey(ValueKey(k)), findsOneWidget, reason: k);
    }
    // SmartMatch suggests the REF driver for my REF vacancy.
    expect(find.descendant(of: find.byKey(const ValueKey('job-suggestions')), matching: find.byKey(const ValueKey('job-feed-d-d1'))),
        findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('job-filter')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('job-f-kind-drivers')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('job-f-apply')));
    await tester.pumpAndSettle();
    final feed = find.byKey(const ValueKey('job-feed'));
    expect(find.descendant(of: feed, matching: find.byKey(const ValueKey('job-feed-d-d1'))), findsOneWidget);
    expect(find.descendant(of: feed, matching: find.byKey(const ValueKey('job-feed-v-v1'))), findsNothing);
    expect(find.text('Filtrlə (1)'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('home on a 320 pt phone: no overflow', (tester) async {
    tester.view.physicalSize = const Size(320, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(overrides: overrides(), child: const MaterialApp(home: JobCenterScreen())));
    await tester.pumpAndSettle();
    expect(find.text('Profilinə uyğun iş və sürücü təklifləri burada görünəcək.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('ad page: what the ad says, allowed contacts, SmartMatch lines; the hidden phone stays hidden', (tester) async {
    tester.view.physicalSize = const Size(390, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    const me = JobSeeker(userId: 'me', fullName: 'Mən', specialties: ['tent'], skills: {'lic_ce': SkillState.yes});
    await tester.pumpWidget(ProviderScope(
      overrides: overrides(profile: me),
      child: const MaterialApp(home: JobItemScreen(vacancy: true, id: 'v1')),
    ));
    await tester.pumpAndSettle();
    expect(find.text('TIR sürücüsü tələb olunur'), findsOneWidget);
    expect(find.text('Şirkət A'), findsOneWidget);
    expect(find.byKey(const ValueKey('job-item-info')), findsOneWidget);
    expect(find.byKey(const ValueKey('job-message-e1')), findsOneWidget);
    expect(find.byKey(const ValueKey('job-call-e1')), findsNothing, reason: 'phone not shown by its owner');
    expect(find.byKey(const ValueKey('job-item-match')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('my own ad: an edit button instead of contacts', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [...overrides(), jobSeekersProvider.overrideWith((ref) async => [const JobSeeker(userId: 'me', fullName: 'Mən')])],
      child: const MaterialApp(home: JobItemScreen(vacancy: false, id: 'me')),
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('job-item-edit')), findsOneWidget);
    expect(find.byKey(const ValueKey('job-item-contact')), findsNothing);
  });

  test('wired: routes for the ad page; no new SQL', () {
    final router = src('lib/core/router/app_router.dart');
    expect(router, contains("path: '/jobs/v/:id',"));
    expect(router, contains("path: '/jobs/d/:id',"));
    expect(Directory('supabase/migrations').listSync().where((f) => f.path.contains('0072')), isEmpty);
  });
}
