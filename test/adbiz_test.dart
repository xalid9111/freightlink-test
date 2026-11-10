// UTEP Reklam (owner, 10.11.2026, SQL 0110): the work notebook, the numbers,
// who sees the module in Profil, and the wiring (server rules, logo, routes).
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freightlink/core/localization/app_strings.dart';
import 'package:freightlink/core/localization/locale_controller.dart';
import 'package:freightlink/features/adbiz/data/adbiz_repository.dart';
import 'package:freightlink/features/adbiz/domain/adbiz_models.dart';
import 'package:freightlink/features/adbiz/presentation/adbiz_notebook_screen.dart';
import 'package:freightlink/features/adbiz/presentation/adbiz_providers.dart';
import 'package:freightlink/features/auth/presentation/profile_screen.dart';
import 'package:freightlink/features/auth/presentation/providers/auth_providers.dart';

String src(String p) => File(p).readAsStringSync();

class _Repo implements AdbizRepository {
  int opens = 0;
  final adds = <(String, String, double, String)>[];
  int failAdds = 0;
  final closes = <String>[];
  @override
  Future<String> openDay() async {
    opens++;
    await Future<void>.delayed(const Duration(milliseconds: 20));
    return 'd1';
  }

  @override
  Future<String> addEntry(String dayId, String title, double amount, String clientKey) async {
    adds.add((dayId, title, amount, clientKey));
    if (failAdds > 0) {
      failAdds--;
      throw Exception('offline');
    }
    return 'e${adds.length}';
  }

  @override
  Future<void> closeDay(String dayId) async => closes.add(dayId);

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

const _s = AppStrings({});
final _today = bakuToday();

AdbizDay _day({String status = 'open', double target = 235}) =>
    AdbizDay(id: 'd1', companyId: 'c', userId: 'me', workDate: _today, status: status, target: target);

Future<void> _pumpNotebook(WidgetTester t, _Repo repo, {List<AdbizDay> days = const [], List<AdbizEntry> entries = const []}) async {
  t.view.physicalSize = const Size(390, 1400);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(ProviderScope(
    overrides: [
      currentUserIdProvider.overrideWithValue('me'),
      stringsProvider.overrideWithValue(_s),
      adbizRepositoryProvider.overrideWithValue(repo),
      adbizDaysProvider('me').overrideWith((ref) => Stream.value(days)),
      adbizEntriesProvider('d1').overrideWith((ref) => Stream.value(entries)),
    ],
    child: const MaterialApp(home: AdbizNotebookScreen()),
  ));
  await t.pump();
  await t.pump();
}

void main() {
  group('the numbers', () {
    test('collected = the sum; remaining never below 0; the target never caps the earnings', () {
      final e = [
        const AdbizEntry(id: '1', dayId: 'd', title: 'Nömrə', amount: 20),
        const AdbizEntry(id: '2', dayId: 'd', title: 'Kalçuk', amount: 25),
      ];
      final p = DayProgress.of(e, 235);
      expect(p.collected, 45);
      expect(p.remaining, 190);
      expect(p.percent, 19);
      expect(p.reached, isFalse);
      const over = DayProgress(300, 235);
      expect(over.remaining, 0);
      expect(over.bar, 1);
      expect(over.percent, 128, reason: 'more than the target is shown, never cut');
      expect(over.reached, isTrue);
      expect(const DayProgress(10, 0).bar, 1, reason: 'no target set: the bar is full once there is work');
    });

    test('amounts as typed', () {
      expect(parseAmount('20'), 20);
      expect(parseAmount('20,5'), 20.5);
      expect(parseAmount('20.555 AZN'), 20.56);
      expect(parseAmount(''), isNull);
      expect(parseAmount('0'), isNull);
      expect(parseAmount('abc'), isNull);
    });

    test('day / month / year; the work day follows Baku', () {
      final d = DateTime(2026, 2, 14);
      expect(periodRange(AdbizPeriod.day, d), (DateTime(2026, 2, 14), DateTime(2026, 2, 14)));
      expect(periodRange(AdbizPeriod.month, d), (DateTime(2026, 2, 1), DateTime(2026, 2, 28)));
      expect(periodRange(AdbizPeriod.year, d), (DateTime(2026, 1, 1), DateTime(2026, 12, 31)));
      expect(bakuToday(DateTime.utc(2026, 11, 10, 21, 0)), DateTime(2026, 11, 11), reason: '01:00 in Baku is the next day');
      expect(isoDate(DateTime(2026, 3, 5)), '2026-03-05');
    });

    test('a double tap sends the same key; every new job a new one', () {
      final a = adbizClientKey(), b = adbizClientKey();
      expect(RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$').hasMatch(a), isTrue);
      expect(a, isNot(b));
    });

    test('the report and who I am', () {
      final r = AdbizReport.fromJson({
        'income': 120, 'expenses': '20.5', 'net': 99.5, 'days_open': 1, 'days_closed': 3,
        'workers': [{'user_id': 'u', 'name': 'Rəşad', 'role': 'worker', 'is_active': true, 'total': 120, 'days': 4, 'personal_target': null}],
        'by_day': [{'date': '2026-11-10', 'income': 120}],
      });
      expect((r.income, r.expenses, r.net, r.daysClosed), (120.0, 20.5, 99.5, 3));
      expect(r.workers.single.name, 'Rəşad');
      expect(r.byDay.single.$1, DateTime(2026, 11, 10));
      final w = AdbizMe.fromJson({'chief': false, 'company_id': 'c', 'company_name': 'UTEP Reklam', 'role': 'worker', 'daily_target': 235});
      expect((w.isWorker, w.isOwner, w.dailyTarget), (true, false, 235.0));
      expect(const AdbizMe(chief: true).isMember, isFalse);
    });
  });

  group('the notebook', () {
    testWidgets('no day yet: "Günü aç"; a double tap opens it once', (t) async {
      final repo = _Repo();
      await _pumpNotebook(t, repo);
      expect(find.byKey(const ValueKey('adb-open-day')), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('adb-open-day')));
      await t.tap(find.byKey(const ValueKey('adb-open-day')), warnIfMissed: false);
      await t.pump(const Duration(milliseconds: 50));
      expect(repo.opens, 1);
    });

    testWidgets('an open day: target / collected / remaining, Enter saves a job, a failure keeps it with the same key', (t) async {
      final repo = _Repo()..failAdds = 1;
      await _pumpNotebook(t, repo, days: [_day()], entries: const [
        AdbizEntry(id: 'e0', dayId: 'd1', title: 'Nömrə', amount: 20),
        AdbizEntry(id: 'e9', dayId: 'd1', title: 'Kalçuk', amount: 25),
      ]);
      expect(find.text('235.00 AZN'), findsWidgets);
      expect(find.text('45.00 AZN'), findsWidgets);
      expect(find.text('190.00 AZN'), findsWidgets);
      expect(find.byKey(const ValueKey('adb-close-day')), findsOneWidget);
      await t.enterText(find.byKey(const ValueKey('adb-job-title')), 'Banner');
      await t.enterText(find.byKey(const ValueKey('adb-job-amount')), '35');
      await t.testTextInput.receiveAction(TextInputAction.done); // Enter
      await t.pump();
      expect(repo.adds.single.$2, 'Banner');
      expect(find.text('Banner'), findsOneWidget, reason: 'a failure keeps what was typed');
      await t.tap(find.byKey(const ValueKey('adb-add-job')));
      await t.pump();
      expect(repo.adds.length, 2);
      expect(repo.adds[1].$4, repo.adds[0].$4, reason: 'the retry is the same job for the server');
      expect(repo.adds[1].$3, 35);
    });

    testWidgets('a closed day: the worker cannot write or close any more', (t) async {
      await _pumpNotebook(t, _Repo(), days: [_day(status: 'closed')]);
      expect(find.byKey(const ValueKey('adb-job-title')), findsNothing);
      expect(find.byKey(const ValueKey('adb-close-day')), findsNothing);
      expect(find.byKey(const ValueKey('adb-reopen-day')), findsNothing, reason: 're-opening is the owner''s / Baş admin''s');
      expect(find.text('adb_closed_note'), findsOneWidget);
    });
  });

  group('Profil', () {
    Future<void> pumpEntry(WidgetTester t, AdbizMe? me) async {
      await t.pumpWidget(ProviderScope(
        overrides: [
          stringsProvider.overrideWithValue(_s),
          adbizMeProvider.overrideWith((ref) async => me),
        ],
        child: const MaterialApp(home: Scaffold(body: AdbizProfileEntry())),
      ));
      await t.pump();
    }

    testWidgets('switched off: nothing at all', (t) async {
      await pumpEntry(t, null);
      expect(find.byKey(const ValueKey('pf-adbiz')), findsNothing);
    });
    testWidgets('a worker: only the notebook', (t) async {
      await pumpEntry(t, const AdbizMe(companyId: 'c', companyName: 'UTEP Reklam', role: 'worker'));
      expect(find.byKey(const ValueKey('pf-adbiz-notebook')), findsOneWidget);
      expect(find.byKey(const ValueKey('pf-adbiz-business')), findsNothing);
      expect(find.byKey(const ValueKey('pf-adbiz-admin')), findsNothing);
      expect(find.byKey(const ValueKey('utep-logo')), findsOneWidget);
    });
    testWidgets('an owner: the business page too', (t) async {
      await pumpEntry(t, const AdbizMe(companyId: 'c', companyName: 'UTEP Reklam', role: 'owner'));
      expect(find.byKey(const ValueKey('pf-adbiz-business')), findsOneWidget);
    });
    testWidgets('the Baş admin: management', (t) async {
      await pumpEntry(t, const AdbizMe(chief: true));
      expect(find.byKey(const ValueKey('pf-adbiz-admin')), findsOneWidget);
      expect(find.byKey(const ValueKey('pf-adbiz-notebook')), findsNothing);
    });
  });

  test('wired: server rules, separate data, logo only in the module, Profil only', () {
    final sql = src('supabase/migrations/0110_ad_business.sql');
    expect(sql, contains("raise exception 'chief_admin_only'"));
    expect(sql, contains("execute format('revoke all on public.%I from anon, authenticated', t);"), reason: 'no direct writes');
    expect(sql, contains('using (public.is_chief_admin() or id = public.adbiz_my_company());'), reason: 'a company sees only itself');
    expect(sql, isNot(contains('update users set role')), reason: 'the FreightLink role is never changed');
    expect(sql, contains("'UTEP Reklam', 0)"), reason: 'the target comes from the Baş admin, nothing hard-coded');
    expect(src('supabase/tests/local/run_local.sh'), contains('147_ad_business.sql'));
    // The logo only inside the module (and its Profil entry).
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'))) {
      final p = f.path.replaceAll('\\', '/');
      if (p.contains('features/adbiz/')) continue;
      expect(f.readAsStringSync().contains('utep_reklam_logo'), isFalse, reason: p);
    }
    expect(File('assets/images/utep/utep_reklam_logo.png').existsSync(), isTrue);
    expect(src('pubspec.yaml'), contains('    - assets/images/utep/'));
    final router = src('lib/core/router/app_router.dart');
    expect(router, contains("path: 'adbiz',"));
    expect(router, isNot(contains("path: '/adbiz")), reason: 'entered only from Profil');
    expect(src('lib/features/auth/presentation/profile_screen.dart'), contains('const AdbizProfileEntry(),'));
  });
}
