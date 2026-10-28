// Age at registration (required) and in Profil (owner, 28.10.2026,
// migration 0074; server rules: supabase/tests/local/111_user_birth_date.sql).
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freightlink/core/localization/app_strings.dart';
import 'package:freightlink/core/localization/locale_controller.dart';
import 'package:freightlink/core/utils/age.dart';
import 'package:freightlink/features/auth/domain/app_user.dart';
import 'package:freightlink/features/auth/presentation/providers/auth_providers.dart';
import 'package:freightlink/features/auth/presentation/register_screen.dart';
import 'package:freightlink/features/jobs/domain/job_models.dart';
import 'package:freightlink/features/jobs/presentation/job_seeker_form.dart';
import 'package:freightlink/features/jobs/presentation/jobs_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

String src(String p) => File(p).readAsStringSync();
final _az = AppStrings(Map<String, String>.from(jsonDecode(src('assets/i18n/az.json')) as Map));

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('age ↔ birth date: the picked age comes back and grows every year', () {
    final now = DateTime(2026, 10, 28);
    final b = birthDateForAge(34, now);
    expect(birthDateText(b), '1992-01-01');
    expect(ageFromBirthDate(b, now), 34);
    expect(ageFromBirthDate(b, DateTime(2027, 1, 2)), 35);
    expect(kAgeChoices.first, 16, reason: 'the server allows 16+');
    expect(kAgeChoices.last, 90);
  });

  test('wired: signup sends the age, Profil saves it, accounts read it; 0074 is safe and private', () {
    final reg = src('lib/features/auth/presentation/register_screen.dart');
    expect(reg, contains("'birth_date': birthDateText(birthDateForAge(_age!, DateTime.now())),"));
    expect(reg, contains("validator: (v) => v == null ? strings.t('register_age_required') : null,"));
    expect(reg, contains("if (widget.serviceKind != null) 'service_kind': widget.serviceKind,"), reason: 'Usta / Servis signup kept');
    expect(src('lib/features/auth/data/auth_repository_impl.dart'), contains("birthDate: row['birth_date'] is String"));
    expect(src('lib/repositories/profile_repository.dart'), contains("update({'birth_date': birthDateText(birthDate)})"));
    expect(src('lib/features/auth/presentation/profile_screen.dart'), contains("key: const ValueKey('profile-age'),"));
    final sql = src('supabase/migrations/0074_user_birth_date.sql').toLowerCase();
    for (final bad in ['drop table', 'truncate', 'delete from', 'drop column', 'user_profiles as', 'update public.users']) {
      expect(sql.contains(bad), isFalse, reason: bad);
    }
    expect(sql, contains("if v_role is null or v_role not in ('cargo_owner', 'carrier', 'driver') then"), reason: '0018 rule kept');
    expect(sql, contains("raise exception 'invalid_birth_date'"));
    for (final lang in ['az', 'tr', 'en', 'ru', 'ka', 'zh']) {
      final m = jsonDecode(src('assets/i18n/$lang.json')) as Map;
      for (final k in ['register_age_label', 'register_age_required', 'profile_age', 'profile_age_add', 'profile_age_title', 'profile_age_saved']) {
        expect((m[k] as String?)?.isNotEmpty, isTrue, reason: '$lang $k');
      }
    }
  });

  testWidgets('registration: the age is required', (tester) async {
    tester.view.physicalSize = const Size(400, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [stringsProvider.overrideWithValue(_az)],
      child: const MaterialApp(home: RegisterScreen(role: 'carrier')),
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('register-age')), findsOneWidget);
    await tester.tap(find.text(_az.t('register_submit')));
    await tester.pumpAndSettle();
    expect(find.text('Yaşınızı seçin'), findsOneWidget);
  });

  testWidgets('İş Mərkəzi: a new driver profile starts with the age from the account', (tester) async {
    tester.view.physicalSize = const Size(390, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final now = DateTime.now();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        stringsProvider.overrideWithValue(_az),
        currentUserProvider.overrideWithValue(AppUser(
            id: 'u1', email: 'a@b.az', fullName: 'Sürücü', role: 'carrier', isVerified: false, birthDate: DateTime(now.year - 34, 1, 1))),
        currentUserIdProvider.overrideWithValue('u1'),
        myJobProfileProvider.overrideWith((ref) async => null),
        jobSpecialtiesProvider.overrideWith((ref) async => kJobSpecialties),
        jobSkillsProvider.overrideWith((ref) async => kJobSkills),
      ],
      child: const MaterialApp(home: JobSeekerFormScreen()),
    ));
    await tester.pumpAndSettle();
    expect(find.descendant(of: find.byKey(const ValueKey('job-age')), matching: find.text('34')), findsOneWidget);
  });
}
