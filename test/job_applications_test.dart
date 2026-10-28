// İş Mərkəzi PR 2 (owner, 28.10.2026): applications / job offers, their
// statuses (hired only when both sides confirm — server: 0069,
// supabase/tests/local/106_job_center.sql A1–A13) and the job notices.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freightlink/core/localization/app_strings.dart';
import 'package:freightlink/core/localization/locale_controller.dart';
import 'package:freightlink/features/auth/presentation/providers/auth_providers.dart';
import 'package:freightlink/features/jobs/data/jobs_repository.dart';
import 'package:freightlink/features/jobs/domain/job_applications.dart';
import 'package:freightlink/features/jobs/domain/job_models.dart';
import 'package:freightlink/features/jobs/presentation/job_applications_screen.dart';
import 'package:freightlink/features/jobs/presentation/job_item_screen.dart';
import 'package:freightlink/features/jobs/presentation/jobs_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

String src(String p) => File(p).readAsStringSync();
final _az = AppStrings(Map<String, String>.from(jsonDecode(src('assets/i18n/az.json')) as Map));

JobApplication app(String status, {String by = 'seeker', bool sOk = false, bool eOk = false, String id = 'a1'}) => JobApplication(
      id: id,
      vacancyId: 'v1',
      seekerId: 'drv',
      employerId: 'emp',
      initiatedBy: by,
      status: status,
      seekerOk: sOk,
      employerOk: eOk,
    );

class _FakeRepo implements JobsRepository {
  final statuses = <(String, String)>[];
  final sent = <(String, String?, String?)>[];
  final read = <String>[];
  @override
  Future<JobApplication> setApplicationStatus(String id, String status) async {
    statuses.add((id, status));
    return app(status, id: id);
  }

  @override
  Future<JobApplication> sendApplication(String vacancyId, {String? seekerId, String? message}) async {
    sent.add((vacancyId, seekerId, message));
    return app('sent');
  }

  @override
  Future<Map<String, ({String name, String? avatar})>> people(Iterable<String> ids) async =>
      {for (final i in ids) i: (name: 'Ad $i', avatar: null)};

  @override
  Future<void> markNoticesRead(List<String> ids) async => read.addAll(ids);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('statuses and buttons (the server decides; the app only shows)', () {
    test('a driver applied: the employer can talk, confirm or decline; the driver can confirm or withdraw', () {
      final a = app('sent');
      expect(a.actionsFor('emp'), [JobAppAction.talk, JobAppAction.accept, JobAppAction.reject]);
      expect(a.actionsFor('drv'), [JobAppAction.accept, JobAppAction.withdraw]);
      expect(a.incomingFor('emp'), isTrue);
      expect(a.otherOf('emp'), 'drv');
    });

    test('hired only when both confirm: one side confirmed → the other is asked', () {
      final a = app('talking', eOk: true);
      expect(a.actionsFor('emp'), [JobAppAction.reject, JobAppAction.close], reason: 'already confirmed');
      expect(a.actionsFor('drv'), [JobAppAction.accept, JobAppAction.reject, JobAppAction.close]);
      expect(a.waitingNoteFor('emp'), 'job_app_wait_other');
      expect(a.waitingNoteFor('drv'), 'job_app_wait_me');
      final hired = app('accepted', sOk: true, eOk: true);
      expect(hired.actionsFor('drv'), [JobAppAction.close]);
      expect(hired.waitingNoteFor('drv'), isNull);
    });

    test('rejected / closed are final; status for each button', () {
      expect(app('rejected').actionsFor('emp'), isEmpty);
      expect(app('closed').isFinal, isTrue);
      expect(JobApplication.statusFor(JobAppAction.withdraw), 'closed');
      expect(JobApplication.statusFor(JobAppAction.accept), 'accepted');
      expect(JobApplication.statusFor(JobAppAction.talk), 'talking');
    });

    test('open ones first, then the newest', () {
      final list = sortApplications([
        JobApplication(id: 'old', vacancyId: 'v', seekerId: 's', employerId: 'e', initiatedBy: 'seeker', status: 'sent', updatedAt: DateTime(2026, 10, 1)),
        JobApplication(id: 'done', vacancyId: 'v', seekerId: 's', employerId: 'e', initiatedBy: 'seeker', status: 'closed', updatedAt: DateTime(2026, 10, 28)),
        JobApplication(id: 'new', vacancyId: 'v', seekerId: 's', employerId: 'e', initiatedBy: 'seeker', status: 'talking', updatedAt: DateTime(2026, 10, 27)),
      ]);
      expect([for (final a in list) a.id], ['new', 'old', 'done']);
    });

    test('notices: text in the user\'s language, the right page on tap', () {
      JobNotice n(String type, String title, Map<String, dynamic> data) => JobNotice(id: 'n', type: type, title: title, data: data);
      expect(n('job_application', 'Yeni müraciət', {}).textKey, 'job_ntf_new_app');
      expect(n('job_application', 'Yeni iş təklifi', {}).textKey, 'job_ntf_new_offer');
      expect(n('job_application', 'İşə qəbul təsdiqləndi', {}).textKey, 'job_ntf_accepted');
      expect(n('job_application', 'x', {}).route, '/jobs/applications');
      expect(n('job_match_vacancy', 'x', {'vacancy_id': 'v9'}).route, '/jobs/v/v9');
      expect(n('job_match_seeker', 'x', {'seeker_id': 'd9'}).route, '/jobs/d/d9');
      // Every key the app can show exists in all 6 languages.
      final keys = [
        for (final k in (jsonDecode(src('assets/i18n/az.json')) as Map).keys)
          if (RegExp(r'^job_(app_|apps_|apply_|offer_|ntf_)').hasMatch('$k')) '$k',
      ];
      expect(keys.length, greaterThan(35));
      for (final lang in ['az', 'tr', 'en', 'ru', 'ka', 'zh']) {
        final m = jsonDecode(src('assets/i18n/$lang.json')) as Map;
        for (final k in keys) {
          expect((m[k] as String?)?.isNotEmpty, isTrue, reason: '$lang $k');
        }
      }
    });

    test('wired: server functions of 0069 (no new SQL), routes, notices from the existing table', () {
      final repo = src('lib/features/jobs/data/jobs_repository.dart');
      expect(repo, contains("rpc('job_application_send'"));
      expect(repo, contains("rpc('job_application_set_status'"));
      expect(repo, contains("from('user_profiles')"), reason: 'public names only, no phone / e-mail');
      expect(repo, contains(".inFilter('type', kJobNoticeTypes)"));
      final router = src('lib/core/router/app_router.dart');
      expect(router, contains("path: '/jobs/applications',"));
      expect(router, contains("path: '/jobs/notifications',"));
    });
  });

  List<Override> base(_FakeRepo repo, {String me = 'emp', List<JobApplication> apps = const [], JobSeeker? profile}) => [
        stringsProvider.overrideWithValue(_az),
        jobsRepositoryProvider.overrideWithValue(repo),
        currentUserIdProvider.overrideWithValue(me),
        myApplicationsProvider.overrideWith((ref) async => apps),
        myJobProfileProvider.overrideWith((ref) async => profile),
        myVacanciesProvider.overrideWith((ref) async => me == 'emp'
            ? const [JobVacancy(id: 'v1', ownerId: 'emp', companyName: 'Ref MMC', specialties: ['ref'])]
            : const <JobVacancy>[]),
        jobVacanciesProvider.overrideWith((ref) async =>
            const [JobVacancy(id: 'v1', ownerId: 'emp', companyName: 'Ref MMC', specialties: ['ref'])]),
        jobSeekersProvider.overrideWith((ref) async => const [JobSeeker(userId: 'drv', fullName: 'Sürücü', specialties: ['ref'])]),
        jobSpecialtiesProvider.overrideWith((ref) async => kJobSpecialties),
        jobSkillsProvider.overrideWith((ref) async => kJobSkills),
        jobNoticesProvider.overrideWith((ref) async => const <JobNotice>[]),
      ];

  testWidgets('applications page: incoming one marked "Baxıldı", confirming hiring sends "accepted"', (tester) async {
    tester.view.physicalSize = const Size(390, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final repo = _FakeRepo();
    await tester.pumpWidget(ProviderScope(
      overrides: base(repo, apps: [app('sent')]),
      child: const MaterialApp(home: JobApplicationsScreen()),
    ));
    await tester.pumpAndSettle();
    expect(repo.statuses, [('a1', 'seen')], reason: 'opening the page marks what came to me as seen');
    expect(find.text('Sizə müraciət'), findsOneWidget);
    expect(find.text('REF sürücüsü tələb olunur'), findsOneWidget);
    expect(find.text('Ad drv'), findsOneWidget);
    expect(find.text('Göndərildi'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('job-app-accept-a1')));
    await tester.pumpAndSettle();
    expect(repo.statuses.last, ('a1', 'accepted'));
    // Declining asks first.
    await tester.tap(find.byKey(const ValueKey('job-app-reject-a1')));
    await tester.pumpAndSettle();
    expect(find.text('Bunu geri qaytarmaq olmaz. Davam edilsin?'), findsOneWidget);
    await tester.tap(find.text('Ləğv et'));
    await tester.pumpAndSettle();
    expect(repo.statuses.last, ('a1', 'accepted'), reason: 'cancel sends nothing');
    expect(tester.takeException(), isNull);
  });

  testWidgets('vacancy page: a driver with a profile applies with a message', (tester) async {
    tester.view.physicalSize = const Size(390, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final repo = _FakeRepo();
    await tester.pumpWidget(ProviderScope(
      overrides: base(repo, me: 'drv', profile: const JobSeeker(userId: 'drv', fullName: 'Sürücü')),
      child: const MaterialApp(home: JobItemScreen(vacancy: true, id: 'v1')),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('job-apply')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('job-apply-message')), 'Salam, CE var');
    await tester.tap(find.byKey(const ValueKey('job-apply-send')));
    await tester.pumpAndSettle();
    expect(repo.sent, [('v1', null, 'Salam, CE var')]);
  });

  testWidgets('vacancy page: an open application shows its status instead of the button', (tester) async {
    final repo = _FakeRepo();
    await tester.pumpWidget(ProviderScope(
      overrides: base(repo, me: 'drv', apps: [app('talking')], profile: const JobSeeker(userId: 'drv', fullName: 'S')),
      child: const MaterialApp(home: JobItemScreen(vacancy: true, id: 'v1')),
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('job-apply')), findsNothing);
    expect(find.byKey(const ValueKey('job-apply-status')), findsOneWidget);
    expect(find.text('Müraciət: Danışıq gedir'), findsOneWidget);
  });

  testWidgets('driver page: an employer with an active vacancy offers the job', (tester) async {
    tester.view.physicalSize = const Size(390, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final repo = _FakeRepo();
    await tester.pumpWidget(ProviderScope(
      overrides: base(repo),
      child: const MaterialApp(home: JobItemScreen(vacancy: false, id: 'drv')),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('job-offer')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('job-apply-send')));
    await tester.pumpAndSettle();
    expect(repo.sent, [('v1', 'drv', null)]);
  });

  testWidgets('notices page: shown in the user\'s language and marked as read', (tester) async {
    final repo = _FakeRepo();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        ...base(repo),
        jobNoticesProvider.overrideWith((ref) async => const [
              JobNotice(id: 'n1', type: 'job_application', title: 'Yeni müraciət'),
              JobNotice(id: 'n2', type: 'job_match_seeker', title: 'Yeni uyğun sürücü', isRead: true),
            ]),
      ],
      child: const MaterialApp(home: JobNoticesScreen()),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Yeni müraciət'), findsOneWidget);
    expect(find.text('Vakansiyanıza uyğun yeni sürücü'), findsOneWidget);
    expect(repo.read, ['n1']);
  });
}
