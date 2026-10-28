// Age at registration (required) and in Profil (owner, 28.10.2026,
// migration 0074; server rules: supabase/tests/local/111_user_birth_date.sql).
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:freightlink/core/localization/app_strings.dart';
import 'package:freightlink/core/localization/locale_controller.dart';
import 'package:freightlink/core/utils/age.dart';
import 'package:freightlink/core/widgets/birth_date_field.dart';
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
  setUpAll(() async => initializeDateFormatting());

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
    expect(reg, contains("'birth_date': birthDateText(_birth!),"), reason: 'the exact date, e.g. 1978-01-23');
    expect(reg, contains("strings0.t('register_birth_required')"));
    expect(reg, contains("if (widget.serviceKind != null) 'service_kind': widget.serviceKind,"), reason: 'Usta / Servis signup kept');
    expect(src('lib/features/auth/data/auth_repository_impl.dart'), contains("birthDate: row['birth_date'] is String"));
    expect(src('lib/repositories/profile_repository.dart'), contains("update({'birth_date': birthDateText(birthDate)})"));
    final prof = src('lib/features/auth/presentation/profile_screen.dart');
    expect(prof, contains("key: const ValueKey('profile-age'),"));
    expect(prof, contains("key: const ValueKey('profile-age-edit'),"), reason: 'a visible "Dəyiş" button (owner, 28.10.2026)');
    expect(prof, contains('BirthDateField('), reason: 'Gün · Ay · İl in Profil too');
    expect(prof, contains("e.code == 'PGRST204' || e.code == '42703'"), reason: 'a clear message while 0074 is not run');
    final sql = src('supabase/migrations/0074_user_birth_date.sql').toLowerCase();
    for (final bad in ['drop table', 'truncate', 'delete from', 'drop column', 'user_profiles as', 'update public.users']) {
      expect(sql.contains(bad), isFalse, reason: bad);
    }
    expect(sql, contains("if v_role is null or v_role not in ('cargo_owner', 'carrier', 'driver') then"), reason: '0018 rule kept');
    expect(sql, contains("raise exception 'invalid_birth_date'"));
    for (final lang in ['az', 'tr', 'en', 'ru', 'ka', 'zh']) {
      final m = jsonDecode(src('assets/i18n/$lang.json')) as Map;
      for (final k in ['register_age_label', 'register_age_required', 'profile_age', 'profile_age_add', 'profile_age_title', 'profile_age_saved', 'profile_age_edit', 'profile_age_not_ready',
        'register_birth_label', 'register_birth_required', 'birth_day', 'birth_month', 'birth_year', 'birth_too_young',
        'profile_birth', 'profile_birth_add', 'profile_birth_title', 'profile_birth_saved']) {
        expect((m[k] as String?)?.isNotEmpty, isTrue, reason: '$lang $k');
      }
    }
  });

  test('birth date: "23 yanvar 1978", days of the month, 16+ only', () {
    expect(birthDateLabel(DateTime(1978, 1, 23), 'az'), '23 yanvar 1978');
    expect(daysIn(2024, 2), 29);
    expect(daysIn(2023, 2), 28);
    final now = DateTime(2026, 10, 28);
    expect(birthDateAllowed(DateTime(1978, 1, 23), now), isTrue);
    expect(birthDateAllowed(DateTime(2010, 12, 1), now), isFalse, reason: '15 years old');
    expect(birthDateAllowed(DateTime(2010, 10, 28), now), isTrue, reason: 'exactly 16 today');
  });

  test('Gün · Ay · İl: a full date only when all three are chosen; 31 → end of February', () {
    expect(composeBirthDate(23, null, 1978), isNull);
    expect(composeBirthDate(null, 1, 1978), isNull);
    expect(composeBirthDate(23, 1, 1978), DateTime(1978, 1, 23));
    expect(composeBirthDate(31, 2, 1980), DateTime(1980, 2, 29));
    expect(composeBirthDate(31, 2, 1981), DateTime(1981, 2, 28));
  });

  testWidgets('the field shows a saved date as Gün · Ay · İl', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: BirthDateField(initial: DateTime(1978, 1, 23), strings: _az, languageCode: 'az', onChanged: (_) {}),
      ),
    ));
    await tester.pumpAndSettle();
    for (final t in ['23', 'yanvar', '1978']) {
      expect(find.text(t), findsWidgets, reason: t);
    }
  });

  testWidgets('an empty field names its boxes Gün · Ay · İl', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 320,
          child: BirthDateField(initial: null, strings: _az, languageCode: 'az', onChanged: (_) {}),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    for (final t in ['Gün', 'Ay', 'İl']) {
      expect(find.text(t), findsWidgets, reason: t);
    }
  });

  testWidgets('registration: the date of birth is required', (tester) async {
    tester.view.physicalSize = const Size(400, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [stringsProvider.overrideWithValue(_az)],
      child: const MaterialApp(home: RegisterScreen(role: 'carrier')),
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('register-birth')), findsOneWidget);
    await tester.tap(find.text(_az.t('register_submit')));
    await tester.pumpAndSettle();
    expect(find.text('Doğum tarixinizi seçin'), findsOneWidget);
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
