// İş Mərkəzi — the owner deletes a vacancy from the profile (owner,
// 27.10.2026, migration 0071). Server rules:
// supabase/tests/local/108_job_vacancy_delete.sql.
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
import 'package:freightlink/features/jobs/presentation/job_center_screen.dart';
import 'package:freightlink/features/jobs/presentation/jobs_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

String src(String p) => File(p).readAsStringSync();

class _FakeRepo implements JobsRepository {
  final deleted = <String>[];
  @override
  Future<void> deleteVacancy(String id) async => deleted.add(id);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('0071 is safe: nothing removed, applications kept, only an admin brings it back', () {
    final sql = src('supabase/migrations/0071_job_vacancy_delete.sql').toLowerCase();
    for (final bad in ['drop table', 'truncate', 'delete from', 'grant delete']) {
      expect(sql.contains(bad), isFalse, reason: bad);
    }
    expect(sql, contains("check (status in ('active', 'closed', 'deleted'))"));
    expect(sql, contains("if old.status = 'deleted' and not public.is_admin() then"));
    final repo = src('lib/features/jobs/data/jobs_repository.dart');
    expect(repo, contains(".update({'status': 'deleted'}).eq('id', id)"));
    expect(repo, contains("if ((r as Map)['status'] != 'deleted')"), reason: 'deleted vacancies leave my list');
    expect(repo.contains("from('job_vacancies').delete()"), isFalse);
  });

  testWidgets('"Sil" asks first, then deletes only that vacancy', (tester) async {
    final repo = _FakeRepo();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        stringsProvider.overrideWithValue(AppStrings(Map<String, String>.from(jsonDecode(src('assets/i18n/az.json')) as Map))),
        jobsRepositoryProvider.overrideWithValue(repo),
        myJobProfileProvider.overrideWith((ref) async => null),
        myVacanciesProvider.overrideWith((ref) async => const [
              JobVacancy(id: 'v1', ownerId: 'u1', companyName: 'Ref Trans'),
              JobVacancy(id: 'v2', ownerId: 'u1', companyName: 'Tent MMC'),
            ]),
        jobSpecialtiesProvider.overrideWith((ref) async => kJobSpecialties),
        currentUserIdProvider.overrideWithValue('u1'),
      ],
      child: const MaterialApp(home: JobCenterScreen()),
    ));
    await tester.pumpAndSettle();
    final del = find.byKey(const ValueKey('job-vacancy-delete-v1'));
    await tester.scrollUntilVisible(del, 200, scrollable: find.byType(Scrollable).first);
    await tester.tap(del);
    await tester.pumpAndSettle();
    expect(find.text('Vakansiya silinsin?'), findsOneWidget);
    await tester.tap(find.text('Ləğv et'));
    await tester.pumpAndSettle();
    expect(repo.deleted, isEmpty, reason: 'cancel deletes nothing');
    await tester.tap(del);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('job-vacancy-delete-ok')));
    await tester.pumpAndSettle();
    expect(repo.deleted, ['v1']);
    expect(find.text('Vakansiya silindi'), findsOneWidget);
  });
}
