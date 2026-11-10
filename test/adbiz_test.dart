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
import 'package:freightlink/core/theme/app_theme.dart';
import 'package:freightlink/features/adbiz/presentation/adbiz_company_screen.dart';
import 'package:freightlink/features/adbiz/presentation/adbiz_notebook_screen.dart';
import 'package:freightlink/features/adbiz/presentation/adbiz_providers.dart';
import 'package:freightlink/features/adbiz/presentation/adbiz_widgets.dart';
import 'package:freightlink/features/auth/presentation/profile_screen.dart';
import 'package:freightlink/features/auth/presentation/providers/auth_providers.dart';

String src(String p) => File(p).readAsStringSync();

class _Repo implements AdbizRepository {
  int opens = 0;
  final adds = <(String, String, double, String)>[];
  final cards = <bool?>[];
  final ticks = <(String, bool)>[];
  @override
  Future<void> setEntryCard(String id, bool on) async => ticks.add((id, on));
  int failAdds = 0;
  final closes = <String>[];
  @override
  Future<String> openDay() async {
    opens++;
    await Future<void>.delayed(const Duration(milliseconds: 20));
    return 'd1';
  }

  @override
  Future<String> addEntry(String dayId, String title, double amount, String clientKey, {bool? card}) async {
    adds.add((dayId, title, amount, clientKey));
    cards.add(card);
    if (failAdds > 0) {
      failAdds--;
      throw Exception('offline');
    }
    return 'e${adds.length}';
  }

  @override
  Future<void> closeDay(String dayId) async => closes.add(dayId);

  int sweeps = 0;
  @override
  Future<void> sweep() async => sweeps++;

  final deleted = <String>[];
  @override
  Future<void> deleteDay(String dayId) async => deleted.add(dayId);
  @override
  Future<List<AdbizDay>> daysOn(String companyId, DateTime date) async =>
      [AdbizDay(id: 'dX', companyId: companyId, userId: 'u1', workDate: date, status: 'closed', target: 235)];
  @override
  Future<List<AdbizEntry>> entries(String dayId) async => const [AdbizEntry(id: 'e', dayId: 'dX', title: 'Test', amount: 270)];
  @override
  Future<List<AdbizExpense>> dayExpenses(String dayId) async => [AdbizExpense(id: 'x', title: 'Çay', spentOn: _today, amount: 8)];

  final reopens = <String>[];
  @override
  Future<void> reopenDay(String dayId) async => reopens.add(dayId);

  final dayX = <(String, String, double, String)>[];
  @override
  Future<String> addDayExpense(String dayId, String title, double amount, String clientKey) async {
    dayX.add((dayId, title, amount, clientKey));
    return 'x${dayX.length}';
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

const _s = AppStrings({});
final _today = bakuToday();

AdbizDay _day({String status = 'open', double target = 235, String? closedBy}) =>
    AdbizDay(id: 'd1', companyId: 'c', userId: 'me', workDate: _today, status: status, target: target, closedBy: closedBy);

/// The company after SQL 0113 (the card tick, the owner's words, the switch).
const _c113 = AdbizCompany(id: 'c', name: 'UTEP Reklam', dailyTarget: 235, v113: true);

Future<void> _pumpNotebook(WidgetTester t, _Repo repo,
    {List<AdbizDay> days = const [],
    List<AdbizEntry> entries = const [],
    List<AdbizExpense> expenses = const [],
    AdbizCompany? company,
    String? task}) async {
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
      adbizDayExpensesProvider('d1').overrideWith((ref) => Stream.value(expenses)),
      adbizCompaniesProvider.overrideWith((ref) async => [if (company != null) company]),
      adbizMemberTaskProvider('me').overrideWith((ref) async => task),
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

    test('the owner\'s example: 120 income, 30 rasxod → 90 left, 145 to 235, 38.3 %', () {
      final e = [
        for (final (i, a) in [20.0, 25.0, 35.0, 40.0].indexed) AdbizEntry(id: '$i', dayId: 'd', title: 'x', amount: a),
      ];
      final x = [AdbizExpense(id: 'x', title: 'Yanacaq', spentOn: DateTime(2026, 11, 10), amount: 30)];
      final p = DayProgress.of(e, 235, x);
      expect((p.collected, p.spent, p.net, p.remaining), (120.0, 30.0, 90.0, 145.0));
      expect(p.percentExact, 38.3);
      expect(p.percentLabel, '38.3%');
      expect(p.bar, closeTo(0.383, 0.001));
      expect(adbizCalcLine(p), '120 − 30 = 90 AZN');
      expect(adbizTargetLine(p), '235 − 90 = 145 AZN');
      expect(adbizTargetLine(const DayProgress(250, 235)), '0 AZN', reason: 'target passed');
      expect(adbizTargetLine(const DayProgress(10, 235, 40)), '235 − (-30) = 265 AZN');
      expect(adbizCalcLine(const DayProgress(20.5, 235, 8)), '20.50 − 8 = 12.50 AZN');
      // More rasxod than income: nothing left, the bar empty, the target whole.
      const minus = DayProgress(20, 235, 50);
      expect((minus.net, minus.bar, minus.percentExact), (-30.0, 0.0, 0.0));
      expect(const DayProgress(100, 200).percentLabel, '50%');
    });

    test('a day ends at 23:59 (Baku): an open day of an earlier date counts as closed', () {
      final today = DateTime(2026, 11, 10);
      final y = AdbizDay(id: 'y', companyId: 'c', userId: 'me', workDate: DateTime(2026, 11, 9));
      expect(y.openOn(today), isFalse);
      expect(y.closedAutomatically(today), isTrue);
      final t = AdbizDay(id: 't', companyId: 'c', userId: 'me', workDate: today);
      expect(t.openOn(today), isTrue);
      final mine = AdbizDay(id: 'm', companyId: 'c', userId: 'me', workDate: today, status: 'closed', closedBy: 'me');
      expect((mine.openOn(today), mine.closedAutomatically(today)), (false, false));
      expect(AdbizDay.fromJson({'id': 'x', 'company_id': 'c', 'user_id': 'u', 'work_date': '2026-11-09', 'status': 'closed'})
          .closedAutomatically(today), isTrue, reason: 'closed by nobody = automatic');
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
      expect(t.widget<Text>(find.byKey(const ValueKey('adb-target'))).data, '235 AZN');
      expect(t.widget<Text>(find.byKey(const ValueKey('adb-minus'))).data, '190 AZN');
      expect(t.widget<Text>(find.byKey(const ValueKey('adb-progress-label'))).data, '45/235');
      expect(t.widget<Text>(find.byKey(const ValueKey('adb-to-target'))).data, '190 AZN');
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

    testWidgets('rasxod: added by the worker (Enter), taken off the money left; no changes to saved rows', (t) async {
      final repo = _Repo();
      await _pumpNotebook(t, repo, days: [_day()], entries: const [
        AdbizEntry(id: 'e1', dayId: 'd1', title: 'Nömrə', amount: 20),
        AdbizEntry(id: 'e2', dayId: 'd1', title: 'Kalçuk', amount: 25),
        AdbizEntry(id: 'e3', dayId: 'd1', title: 'Banner', amount: 35),
        AdbizEntry(id: 'e4', dayId: 'd1', title: 'Vinil', amount: 40),
      ], expenses: [
        AdbizExpense(id: 'x1', title: 'Yanacaq', spentOn: _today, amount: 30, dayId: 'd1', userId: 'me'),
      ]);
      // The owner's design (10.11.2026): Hədəf · Mənfi · Rasxod, "90/235" over the
      // living bar, "Hədəfə qalan" in big numbers; 120 − 30 = 90 left → 145 short.
      expect(t.widget<Text>(find.byKey(const ValueKey('adb-spent'))).data, '30 AZN');
      expect(t.widget<Text>(find.byKey(const ValueKey('adb-minus'))).data, '145 AZN');
      expect(t.widget<Text>(find.byKey(const ValueKey('adb-progress-label'))).data, '90/235');
      expect(t.widget<Text>(find.byKey(const ValueKey('adb-to-target'))).data, '145 AZN');
      expect(find.byKey(const ValueKey('adb-star')), findsOneWidget, reason: 'the blinking star at the target');
      expect(find.byKey(const ValueKey('adb-calc')), findsNothing, reason: 'no calculation box in the design');
      // No percent anywhere on the worker's panel — the amount left is shown (owner, 10.11.2026).
      expect(find.textContaining('%'), findsNothing);
      expect(find.byKey(const ValueKey('adb-percent')), findsNothing);
      expect(t.widget<Text>(find.byKey(const ValueKey('adb-total'))).data, '120.00 AZN');
      expect(t.widget<Text>(find.byKey(const ValueKey('adb-spent-total'))).data, '30.00 AZN');
      // The worker: no edit / delete on saved jobs or expenses, the lock note.
      expect(find.byIcon(Icons.edit_outlined), findsNothing);
      expect(find.byIcon(Icons.delete_outline), findsNothing);
      expect(find.byKey(const ValueKey('adb-fix-admin-only')), findsOneWidget);
      // No net-profit card for the worker (the owner's panel only).
      expect(find.text('adb_net'), findsNothing);
      await t.enterText(find.byKey(const ValueKey('adb-exp-title')), 'Boya');
      await t.enterText(find.byKey(const ValueKey('adb-exp-amount')), '12,5');
      await t.testTextInput.receiveAction(TextInputAction.done);
      await t.pump();
      expect(repo.dayX.single.$2, 'Boya');
      expect(repo.dayX.single.$3, 12.5);
    });

    testWidgets('an open day says it closes by itself at 23:59; the notebook sweeps forgotten days', (t) async {
      final repo = _Repo();
      await _pumpNotebook(t, repo, days: [_day()]);
      expect(find.byKey(const ValueKey('adb-auto-close-note')), findsOneWidget);
      expect(repo.sweeps, 1);
    });

    testWidgets('closed today by mistake: the worker opens it again', (t) async {
      final repo = _Repo();
      await _pumpNotebook(t, repo, days: [_day(status: 'closed', closedBy: 'me')]);
      expect(find.byKey(const ValueKey('adb-worker-reopen')), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('adb-worker-reopen')));
      await t.pump();
      await t.pump(const Duration(milliseconds: 400)); // the star keeps blinking: no pumpAndSettle
      await t.tap(find.byKey(const ValueKey('adb-confirm')));
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
      expect(repo.reopens, ['d1']);
    });

    testWidgets('closed by the owner (or automatically): not the worker\'s to re-open', (t) async {
      await _pumpNotebook(t, _Repo(), days: [_day(status: 'closed', closedBy: 'owner')]);
      expect(find.byKey(const ValueKey('adb-worker-reopen')), findsNothing);
      expect(find.text('adb_closed_note'), findsOneWidget);
    });

    testWidgets('a closed day: the worker cannot write or close any more', (t) async {
      await _pumpNotebook(t, _Repo(), days: [_day(status: 'closed')]);
      expect(find.byKey(const ValueKey('adb-job-title')), findsNothing);
      expect(find.byKey(const ValueKey('adb-exp-title')), findsNothing);
      expect(find.byKey(const ValueKey('adb-close-day')), findsNothing);
      expect(find.byKey(const ValueKey('adb-reopen-day')), findsNothing, reason: 're-opening is the owner''s / Baş admin''s');
      expect(find.byKey(const ValueKey('adb-worker-reopen')), findsNothing, reason: 'closed by nobody = automatic');
      expect(find.text('adb_closed_auto'), findsOneWidget);
    });
  });

  group('the owner\'s words, the card tick, the day\'s result (0113)', () {
    testWidgets('before SQL 0113: no tick, the old call', (t) async {
      final repo = _Repo();
      await _pumpNotebook(t, repo, days: [_day()]);
      expect(find.byKey(const ValueKey('adb-job-card')), findsNothing);
      await t.enterText(find.byKey(const ValueKey('adb-job-title')), 'Nömrə');
      await t.enterText(find.byKey(const ValueKey('adb-job-amount')), '20');
      await t.tap(find.byKey(const ValueKey('adb-add-job')));
      await t.pump();
      expect(repo.cards.single, isNull, reason: 'no p_card before 0113');
    });

    testWidgets('a tick = paid by card; a second tap takes it off; the tick at the end of a saved job', (t) async {
      final repo = _Repo();
      await _pumpNotebook(t, repo, days: [_day()], company: _c113, entries: const [
        AdbizEntry(id: 'e1', dayId: 'd1', title: 'Nömrə', amount: 20, paidCard: true),
        AdbizEntry(id: 'e2', dayId: 'd1', title: 'Kalçuk', amount: 25),
      ]);
      expect(t.widget<Text>(find.byKey(const ValueKey('adb-card-total'))).data, '20.00 AZN');
      await t.tap(find.byKey(const ValueKey('adb-job-card')));
      await t.pump();
      await t.tap(find.byKey(const ValueKey('adb-job-card')));
      await t.pump();
      await t.tap(find.byKey(const ValueKey('adb-job-card')));
      await t.pump();
      await t.enterText(find.byKey(const ValueKey('adb-job-title')), 'Banner');
      await t.enterText(find.byKey(const ValueKey('adb-job-amount')), '35');
      await t.testTextInput.receiveAction(TextInputAction.done);
      await t.pump();
      expect(repo.cards.single, isTrue);
      // A mistake on a saved job: the worker takes the tick off / puts it on (his open day).
      await t.tap(find.byKey(const ValueKey('adb-card-e1')));
      await t.pump();
      await t.tap(find.byKey(const ValueKey('adb-card-e2')));
      await t.pump();
      expect(repo.ticks, [('e1', false), ('e2', true)]);
      // …but still no edit / delete of the name or amount.
      expect(find.byIcon(Icons.edit_outlined), findsNothing);
    });

    testWidgets('a closed day: the worker\'s tick is shown, not changeable', (t) async {
      final repo = _Repo();
      await _pumpNotebook(t, repo, days: [_day(status: 'closed', closedBy: 'owner')], company: _c113, entries: const [
        AdbizEntry(id: 'e1', dayId: 'd1', title: 'Nömrə', amount: 20, paidCard: true),
      ]);
      await t.tap(find.byKey(const ValueKey('adb-card-e1')), warnIfMissed: false);
      await t.pump();
      expect(repo.ticks, isEmpty);
    });

    testWidgets('the owner\'s caption and tasks on the worker\'s panel', (t) async {
      await _pumpNotebook(t, _Repo(),
          days: [_day()],
          company: const AdbizCompany(id: 'c', name: 'U', v113: true, targetLabel: 'Bu gün 235-ə çatırıq!', taskNote: 'Yeni nömrələr'),
          task: 'Gəncə yolunda 3 vitrin');
      expect(t.widget<Text>(find.byKey(const ValueKey('adb-caption'))).data, 'Bu gün 235-ə çatırıq!');
      expect(find.byKey(const ValueKey('adb-task-card')), findsOneWidget);
      expect(find.text('Yeni nömrələr'), findsOneWidget);
      expect(find.text('Gəncə yolunda 3 vitrin'), findsOneWidget);
    });

    testWidgets('the owner switched the target off: no target, bar or Mənfi', (t) async {
      await _pumpNotebook(t, _Repo(),
          days: [_day()],
          company: const AdbizCompany(id: 'c', name: 'U', v113: true, showTarget: false),
          entries: const [AdbizEntry(id: 'e1', dayId: 'd1', title: 'Nömrə', amount: 20)]);
      expect(find.byKey(const ValueKey('adb-minus')), findsNothing);
      expect(find.byKey(const ValueKey('adb-star')), findsNothing);
      expect(find.byKey(const ValueKey('adb-to-target')), findsNothing);
      expect(t.widget<Text>(find.byKey(const ValueKey('adb-collected'))).data, '20 AZN');
    });

    Future<void> closeWith(WidgetTester t, List<AdbizEntry> e) async {
      final repo = _Repo();
      await _pumpNotebook(t, repo, days: [_day()], company: _c113, entries: e);
      await t.tap(find.byKey(const ValueKey('adb-close-day')));
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
      await t.tap(find.byKey(const ValueKey('adb-confirm')));
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
      expect(repo.closes, ['d1']);
    }

    testWidgets('closing below the target: what stayed in the minus, at once', (t) async {
      await closeWith(t, const [AdbizEntry(id: 'e1', dayId: 'd1', title: 'Nömrə', amount: 52)]);
      expect(find.byKey(const ValueKey('adb-result-minus')), findsOneWidget);
      expect(find.text('adb_result_minus'), findsOneWidget);
      expect(adbizDayResult(_s, const DayProgress(52, 235)).$1, isFalse);
    });

    testWidgets('closing at / over the target: Təbriklər', (t) async {
      await closeWith(t, const [AdbizEntry(id: 'e1', dayId: 'd1', title: 'Vitrin', amount: 250)]);
      expect(find.byKey(const ValueKey('adb-result-reached')), findsOneWidget);
    });

    test('the owner\'s own result message (0114): the day\'s numbers filled in; empty = the app\'s words', () {
      const p = DayProgress(182, 235);
      expect(adbizFillResult('Bu gün {qalan} AZN çatmadı ({gəlir}/{hədəf})', p), 'Bu gün 53 AZN çatmadı (182/235)');
      const c = AdbizCompany(id: 'c', name: 'U', v114: true, resultMissText: 'Sabah {qalan} AZN çox!', resultHitText: 'Əla, {gəlir}!');
      expect(adbizDayResult(_s, p, company: c).$3, 'Sabah 53 AZN çox!');
      expect(adbizDayResult(_s, const DayProgress(250, 235), company: c).$3, 'Əla, 250!');
      expect(adbizDayResult(_s, p, company: const AdbizCompany(id: 'c', name: 'U')).$3, 'adb_result_minus', reason: 'no own text');
      final j = AdbizCompany.fromJson({'id': 'c', 'name': 'U', 'show_target': true, 'result_miss_text': ' ', 'result_hit_text': 'x'});
      expect((j.v114, j.resultMissText, j.resultHitText), (true, null, 'x'));
      expect(AdbizCompany.fromJson({'id': 'c', 'name': 'U', 'show_target': true}).v114, isFalse);
    });

    testWidgets('closing the day shows the owner\'s own message', (t) async {
      final repo = _Repo();
      await _pumpNotebook(t, repo, days: [_day()],
          company: const AdbizCompany(id: 'c', name: 'U', v113: true, v114: true, resultMissText: 'Bu gün {qalan} AZN çatmadı. Sabah güclü ol!'),
          entries: const [AdbizEntry(id: 'e1', dayId: 'd1', title: 'Nömrə', amount: 182)]);
      await t.tap(find.byKey(const ValueKey('adb-close-day')));
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
      await t.tap(find.byKey(const ValueKey('adb-confirm')));
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
      expect(find.text('Bu gün 53 AZN çatmadı. Sabah güclü ol!'), findsOneWidget);
    });

    testWidgets('a closed day (also at 23:59 automatically) shows its result', (t) async {
      await _pumpNotebook(t, _Repo(), days: [_day(status: 'closed')], company: _c113,
          entries: const [AdbizEntry(id: 'e1', dayId: 'd1', title: 'Nömrə', amount: 52)]);
      expect(find.byKey(const ValueKey('adb-banner-minus')), findsOneWidget);
    });

    test('the star at the bar\'s end: green by day, the accent at night', () {
      AppColors.use(AppPalette.light);
      expect(AppColors.adbStar, AppColors.online);
      AppColors.use(AppPalette.dark);
      expect(AppColors.adbStar, AppColors.accent);
      expect(src('lib/features/adbiz/presentation/adbiz_notebook_screen.dart'), contains('final glow = AppColors.adbStar;'));
    });

    test('the model: card money, the words, 0113 known by its columns', () {
      final c = AdbizCompany.fromJson({'id': 'c', 'name': 'U', 'target_label': '  ', 'task_note': 'Tapşırıq', 'show_target': false});
      expect((c.v113, c.showTarget, c.targetLabel, c.taskNote), (true, false, null, 'Tapşırıq'));
      expect(AdbizCompany.fromJson({'id': 'c', 'name': 'U'}).v113, isFalse);
      expect(cardTotal(const [
        AdbizEntry(id: '1', dayId: 'd', title: 'a', amount: 20, paidCard: true),
        AdbizEntry(id: '2', dayId: 'd', title: 'b', amount: 25),
        AdbizEntry(id: '3', dayId: 'd', title: 'c', amount: 15.5, paidCard: true),
      ]), 35.5);
      final r = AdbizReport.fromJson({'income': 60, 'card': 40, 'workers': [{'user_id': 'u', 'card': 40, 'task_note': 'x'}]});
      expect((r.card, r.cash, r.workers.single.card, r.workers.single.taskNote), (40.0, 20.0, 40.0, 'x'));
    });
  });

  group('the owner\'s panel (owner\'s picture)', () {
    Future<_Repo> pumpPanel(WidgetTester t, {bool v113 = true, bool chief = false, bool v114 = false}) async {
      t.view.physicalSize = const Size(412, 2400);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final repo = _Repo();
      final rep = AdbizReport.fromJson({
        'income': 60, 'card': 40, 'expenses': 8, 'net': 52, 'days_open': 1, 'days_closed': 0,
        'workers': [{'user_id': 'u1', 'name': 'İmran MMC', 'role': 'worker', 'total': 60, 'card': 40, 'days': 1}],
      });
      await t.pumpWidget(ProviderScope(
        overrides: [
          stringsProvider.overrideWithValue(_s),
          adbizRepositoryProvider.overrideWithValue(repo),
          adbizMeProvider.overrideWith((ref) async => AdbizMe(chief: chief, companyId: 'c', companyName: 'UTEP Reklam', role: 'owner')),
          adbizCompaniesProvider.overrideWith((ref) async =>
              [AdbizCompany(id: 'c', name: 'UTEP Reklam', dailyTarget: 245, v113: v113, taskNote: v113 ? 'Hamıya' : null,
                  v114: v114, resultMissText: v114 ? 'Sabah {qalan} AZN çox!' : null)]),
          adbizReportProvider.overrideWith((ref, k) async => AdbizReport.fromJson({
                'income': rep.income, 'card': rep.card, 'expenses': rep.expenses, 'net': rep.net, 'days_open': 1, 'days_closed': 0,
                'workers': [{'user_id': 'u1', 'name': 'İmran MMC', 'role': 'worker', 'total': 60, 'card': 40, 'days': 1}],
                'by_day': [{'date': isoDate(_today), 'income': 270}],
              })),
          adbizPeriodsProvider.overrideWith((ref, k) async => AdbizPeriods.fromJson({
                'months': [for (var m = 1; m <= 12; m++) {'key': m, 'net': m == 1 ? 5784 : 0, 'gap': m == 1 ? -215 : (m == 3 ? 11 : 0)}],
                'years': [{'key': 2025, 'net': 100, 'gap': -135}, {'key': _today.year, 'net': 61792, 'gap': -10197}],
              })),
          adbizExpensesProvider.overrideWith((ref, k) async => const <AdbizExpense>[]),
        ],
        child: const MaterialApp(home: AdbizCompanyScreen(companyId: 'c')),
      ));
      await t.pump();
      await t.pump();
      return repo;
    }

    testWidgets('Gün · Ay · İl, the three totals, card / cash, the days, the worker, the target card', (t) async {
      await pumpPanel(t);
      expect(find.byKey(const ValueKey('adb-period-day')), findsOneWidget);
      expect(find.byKey(const ValueKey('adb-period-label')), findsOneWidget);
      expect(t.widget<Text>(find.byKey(const ValueKey('adb-income'))).data, '60 AZN');
      expect(t.widget<Text>(find.byKey(const ValueKey('adb-expenses'))).data, '8 AZN');
      expect(t.widget<Text>(find.byKey(const ValueKey('adb-net'))).data, '52 AZN');
      final line = t.widget<Text>(find.byKey(const ValueKey('adb-card-line'))).textSpan!.toPlainText();
      expect(line, contains('40 AZN'));
      expect(line, contains('20 AZN'));
      expect(find.byKey(const ValueKey('adb-days-line')), findsOneWidget);
      expect(t.widget<Text>(find.byKey(const ValueKey('adb-worker-total-u1'))).data, '60 AZN');
      expect(t.widget<Text>(find.byKey(const ValueKey('adb-worker-card-u1'))).data, '40 AZN');
      expect(t.widget<Text>(find.byKey(const ValueKey('adb-company-target-value'))).data, '245 AZN');
      expect(find.byKey(const ValueKey('adb-company-edit')), findsNothing, reason: 'the target is the Baş admin\'s');
      expect(find.byKey(const ValueKey('adb-show-target')), findsOneWidget);
      expect(find.text('Hamıya'), findsOneWidget);
      expect(find.byKey(const ValueKey('adb-words-edit')), findsOneWidget);
      expect(find.byKey(const ValueKey('utep-logo')), findsOneWidget);
    });

    testWidgets('before SQL 0113: no card line, the switch and the words wait', (t) async {
      await pumpPanel(t, v113: false);
      expect(find.byKey(const ValueKey('adb-card-line')), findsNothing);
      expect(t.widget<Switch>(find.byKey(const ValueKey('adb-show-target'))).onChanged, isNull);
      expect(find.byKey(const ValueKey('adb-words-edit')), findsNothing);
    });

    testWidgets('SQL 0114: the result messages on the words card and in its editor', (t) async {
      await pumpPanel(t, v114: true);
      expect(t.widget<Text>(find.byKey(const ValueKey('adb-words-miss'))).data, 'Sabah {qalan} AZN çox!');
      expect(t.widget<Text>(find.byKey(const ValueKey('adb-words-hit'))).data, 'adb_result_default');
      await t.tap(find.byKey(const ValueKey('adb-words-edit')));
      await t.pump();
      await t.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const ValueKey('adb-words-miss-field')), findsOneWidget);
      expect(find.byKey(const ValueKey('adb-words-hit-field')), findsOneWidget);
    });

    testWidgets('before SQL 0114: no result-message fields', (t) async {
      await pumpPanel(t);
      expect(find.byKey(const ValueKey('adb-words-miss')), findsNothing);
      await t.tap(find.byKey(const ValueKey('adb-words-edit')));
      await t.pump();
      await t.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const ValueKey('adb-words-miss-field')), findsNothing);
      expect(find.byKey(const ValueKey('adb-words-label-field')), findsOneWidget);
    });

    testWidgets('Ay: the 12 month cards (net income over the days\' minus / plus); a tap opens that month', (t) async {
      await pumpPanel(t);
      await t.tap(find.byKey(const ValueKey('adb-period-month')));
      await t.pump();
      await t.pump();
      for (var m = 1; m <= 12; m++) {
        expect(find.byKey(ValueKey('adb-month-$m')), findsOneWidget);
      }
      expect(find.text('5784 AZN'), findsOneWidget);
      expect(find.text('-215 AZN'), findsOneWidget);
      expect(find.text('11 AZN'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('adb-month-3')));
      await t.pump();
      expect(t.widget<Text>(find.byKey(const ValueKey('adb-period-label'))).data, '03.${_today.year}');
    });

    testWidgets('İl: the year cards; a tap opens that year\'s months', (t) async {
      await pumpPanel(t);
      await t.tap(find.byKey(const ValueKey('adb-period-year')));
      await t.pump();
      await t.pump();
      expect(find.text('61792 AZN'), findsOneWidget);
      expect(find.text('-10197 AZN'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('adb-year-2025')));
      await t.pump();
      await t.pump();
      expect(t.widget<Text>(find.byKey(const ValueKey('adb-period-label'))).data, '01.2025');
      expect(find.byKey(const ValueKey('adb-month-1')), findsOneWidget);
    });

    testWidgets('the day view shows no cards', (t) async {
      await pumpPanel(t);
      expect(find.byKey(const ValueKey('adb-month-1')), findsNothing);
    });

    testWidgets('Arxiv: delete a (test) day — asked first, with what goes', (t) async {
      final repo = await pumpPanel(t);
      await t.tap(find.byKey(ValueKey('adb-arch-del-${isoDate(_today)}')));
      await t.pump();
      await t.pump(const Duration(milliseconds: 300));
      expect(find.text('adb_delete_day_title'), findsOneWidget, reason: 'asked before deleting');
      expect(repo.deleted, isEmpty);
      await t.tap(find.byKey(const ValueKey('adb-confirm')));
      await t.pump();
      await t.pump(const Duration(milliseconds: 300));
      expect(repo.deleted, ['dX']);
    });

    testWidgets('the Baş admin edits the target (pencil)', (t) async {
      await pumpPanel(t, chief: true);
      expect(find.byKey(const ValueKey('adb-company-edit')), findsOneWidget);
    });
  });

  group('deleting a day in the notebook (0115)', () {
    testWidgets('the owner / Baş admin: "Günü sil", asked first', (t) async {
      t.view.physicalSize = const Size(390, 1600);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final repo = _Repo();
      final day = AdbizDay(id: 'd9', companyId: 'c', userId: 'w1', workDate: _today, status: 'closed', target: 235);
      await t.pumpWidget(ProviderScope(
        overrides: [
          currentUserIdProvider.overrideWithValue('boss'),
          stringsProvider.overrideWithValue(_s),
          adbizRepositoryProvider.overrideWithValue(repo),
          adbizDaysProvider('w1').overrideWith((ref) => Stream.value([day])),
          adbizEntriesProvider('d9').overrideWith((ref) => Stream.value(const [AdbizEntry(id: 'e', dayId: 'd9', title: 'Test', amount: 270)])),
          adbizDayExpensesProvider('d9').overrideWith((ref) => Stream.value(const <AdbizExpense>[])),
          adbizCompaniesProvider.overrideWith((ref) async => const [_c113]),
          adbizMemberTaskProvider('w1').overrideWith((ref) async => null),
        ],
        child: const MaterialApp(home: AdbizNotebookScreen(userId: 'w1', userName: 'İmran')),
      ));
      await t.pump();
      await t.pump();
      await t.ensureVisible(find.byKey(const ValueKey('adb-delete-day')));
      await t.tap(find.byKey(const ValueKey('adb-delete-day')));
      await t.pump();
      await t.pump(const Duration(milliseconds: 300));
      expect(find.text('adb_delete_day_title'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('adb-confirm')));
      await t.pump();
      await t.pump(const Duration(milliseconds: 300));
      expect(repo.deleted, ['d9']);
    });

    testWidgets('the worker: no "Günü sil"', (t) async {
      await _pumpNotebook(t, _Repo(), days: [_day(status: 'closed')], company: _c113);
      expect(find.byKey(const ValueKey('adb-delete-day')), findsNothing);
    });
  });

  group('the UTEP logo (owner, 10.11.2026): white at night, its own colours by day, no plate', () {
    Future<void> pumpLogo(WidgetTester t, Brightness b) async {
      await t.pumpWidget(MaterialApp(theme: ThemeData(brightness: b), home: const Scaffold(body: Center(child: UtepLogo(height: 30)))));
    }

    String asset(WidgetTester t) => ((t.widget<Image>(find.byType(Image)).image) as AssetImage).assetName;

    testWidgets('night: the white logo', (t) async {
      await pumpLogo(t, Brightness.dark);
      expect(asset(t), 'assets/images/utep/utep_reklam_logo_white.png');
      expect(find.descendant(of: find.byKey(const ValueKey('utep-logo')), matching: find.byType(DecoratedBox)), findsNothing,
          reason: 'no white plate');
    });

    testWidgets('day: the logo in its own colours', (t) async {
      await pumpLogo(t, Brightness.light);
      expect(asset(t), 'assets/images/utep/utep_reklam_logo.png');
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
    // 0111: the worker's rasxod; saved rows changed only by the owner / Baş admin.
    final s111 = src('supabase/migrations/0111_ad_business_day_expenses.sql');
    expect(s111, contains('function public.adbiz_add_day_expense('));
    expect(RegExp(r'adbiz_update_entry[\s\S]*?if not public\.adbiz_can_manage\(d\.company_id\) then').hasMatch(s111), isTrue);
    expect(RegExp(r'adbiz_delete_entry[\s\S]*?if not public\.adbiz_can_manage\(d\.company_id\) then').hasMatch(s111), isTrue);
    expect(src('supabase/tests/local/run_local.sh'), contains('148_ad_business_day_expenses.sql'));
    // 0112: the day closes after 23:59; the worker re-opens only today's day he closed.
    final s112 = src('supabase/migrations/0112_ad_business_day_auto_close.sql');
    expect(s112, contains('and p_day.work_date = public._adbiz_today()'));
    expect(s112, contains('v_own := d.user_id = auth.uid() and d.closed_by = auth.uid() and d.work_date = public._adbiz_today()'));
    expect(s112, contains("cron.schedule('adbiz-auto-close', '0 20 * * *'"));
    expect(src('supabase/tests/local/run_local.sh'), contains('149_ad_business_auto_close.sql'));
    // 0113: the words, the switch, the card tick; the rights checks never null.
    final s113 = src('supabase/migrations/0113_ad_business_texts_card.sql');
    expect(s113, contains('drop function if exists public.adbiz_add_entry(uuid, text, numeric, uuid);'));
    expect(s113, contains('p_card boolean default false'));
    expect(s113, contains("or coalesce(public.adbiz_my_role() = 'owner' and public.adbiz_my_company() = p_company, false);"));
    expect(RegExp(r'adbiz_entry_set_card[\s\S]*?if not public\._adbiz_day_writable\(d\) then').hasMatch(s113), isTrue);
    expect(s113, contains("'card', v_card"));
    expect(src('supabase/tests/local/run_local.sh'), contains('150_ad_business_texts_card.sql'));
    // 0114: the owner's day-result messages, owner / Baş admin only.
    final s114 = src('supabase/migrations/0114_ad_business_result_texts.sql');
    expect(s114, contains('if not public.adbiz_can_manage(p_company) then'));
    expect(s114, contains('public._adbiz_text(p_miss, 200)'));
    expect(src('supabase/tests/local/run_local.sh'), contains('151_ad_business_result_texts.sql'));
    // 0115: delete a day (owner / Baş admin, kept in the history); the month / year cards.
    final s115 = src('supabase/migrations/0115_ad_business_delete_day_months.sql');
    expect(RegExp(r"adbiz_delete_day[\s\S]*?if not public\.adbiz_can_manage\(d\.company_id\) then[\s\S]*?_adbiz_log\(d\.company_id, 'day\.delete'")
        .hasMatch(s115), isTrue);
    expect(s115, contains("and d.status = 'closed' and d.target > 0"));
    expect(src('supabase/tests/local/run_local.sh'), contains('152_ad_business_delete_day_months.sql'));
    // The logo only inside the module (and its Profil entry).
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'))) {
      final p = f.path.replaceAll('\\', '/');
      if (p.contains('features/adbiz/')) continue;
      expect(f.readAsStringSync().contains('utep_reklam_logo'), isFalse, reason: p);
    }
    expect(File('assets/images/utep/utep_reklam_logo.png').existsSync(), isTrue);
    expect(File('assets/images/utep/utep_reklam_logo_white.png').existsSync(), isTrue);
    expect(src('pubspec.yaml'), contains('    - assets/images/utep/'));
    final router = src('lib/core/router/app_router.dart');
    expect(router, contains("path: 'adbiz',"));
    expect(router, isNot(contains("path: '/adbiz")), reason: 'entered only from Profil');
    expect(src('lib/features/auth/presentation/profile_screen.dart'), contains('const AdbizProfileEntry(),'));
  });
}
