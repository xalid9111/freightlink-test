// "Maşınlarım" (owner's pictures and answers, 20.11.2026, SQL 0130): trucks,
// jobs, expenses; profit = agreed prices − APPROVED expenses per truck and
// currency; a driver's expense waits for the owner (bell notice); the
// driver never sees prices; nothing really deleted. SQL rules are tested in
// supabase/tests/local/166_fleet.sql.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freightlink/core/localization/app_strings.dart';
import 'package:freightlink/core/localization/locale_controller.dart';
import 'package:freightlink/core/theme/app_theme.dart';
import 'package:freightlink/features/auth/presentation/providers/auth_providers.dart';
import 'package:freightlink/features/fleet/data/fleet_repository.dart';
import 'package:freightlink/features/fleet/domain/fleet.dart';
import 'package:freightlink/features/fleet/presentation/fleet_forms.dart';
import 'package:freightlink/features/fleet/presentation/fleet_providers.dart';
import 'package:freightlink/features/fleet/presentation/fleet_screen.dart';
import 'package:freightlink/features/fleet/presentation/fleet_truck_screen.dart';
import 'package:freightlink/features/notices/notices.dart';
import 'package:shared_preferences/shared_preferences.dart';

String _read(String p) => File(p).readAsStringSync();
AppStrings _lang(String l) => AppStrings(Map<String, String>.from(jsonDecode(_read('assets/i18n/$l.json')) as Map));

const _owner = 'u-owner';
const _drv = 'u-driver';

final _now = DateTime.now();
const _volvo = FleetTruck(id: 't1', ownerId: _owner, name: 'Volvo FH 2022', plate: '99-AC-981', driverName: 'Rəşad Məmmədov');
const _man = FleetTruck(id: 't2', ownerId: _owner, name: 'MAN TGX 2021', plate: '90-KD-452', driverName: 'Elvin Əliyev', driverId: _drv);

FleetJob _job(String id, String truck, {Duration from = Duration.zero, double? price, String cur = 'USD', String status = 'planned'}) =>
    FleetJob(id: id, truckId: truck, startAt: _now.add(from), from: 'Bakı', to: 'Gəncə', price: price, currency: cur, status: status);

FleetExpense _exp(String id, String truck, double a, String cur, {String status = 'approved', String by = _owner}) =>
    FleetExpense(id: id, truckId: truck, name: 'Ay-$id', amount: a, currency: cur, status: status, createdBy: by);

class _Repo implements FleetRepository {
  final saved = <String>[];
  final invited = <(String, String)>[];
  final cancelled = <String>[];
  final answers = <(String, bool)>[];
  final asked = <String>[];
  @override
  Future<List<FleetPerson>> searchDrivers(String q) async {
    asked.add(q);
    return const [
      FleetPerson(id: 'u-ali', name: 'Əli Məmmədov', verified: true),
      FleetPerson(id: 'u-ali2', name: 'Əli Həsənov'),
    ];
  }

  @override
  Future<String> saveTruck({String? id, required String name, String? plate, String? driverName}) async {
    saved.add('$name|$driverName');
    return id ?? 't-new';
  }

  @override
  Future<void> inviteDriver(String truckId, String userId) async => invited.add((truckId, userId));
  @override
  Future<void> cancelDriverInvite(String truckId) async => cancelled.add(truckId);
  @override
  Future<String> answerInvite(String inviteId, bool accept) async {
    answers.add((inviteId, accept));
    return 'Volvo FH 2022';
  }

  @override
  Future<String> inviteCode(String truckId) async => 'AB12CD34';
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

Widget _app(Widget home, FleetData data, {String uid = _owner, FleetRepository? repo}) => ProviderScope(
      overrides: [
        if (repo != null) fleetRepositoryProvider.overrideWithValue(repo),
        stringsProvider.overrideWithValue(_lang('az')),
        currentUserIdProvider.overrideWithValue(uid),
        currentUserProvider.overrideWithValue(null),
        fleetProvider.overrideWith((ref) async => data),
        myNoticesProvider.overrideWith((ref) => Stream.value(const <AppNotice>[])),
      ],
      child: MaterialApp(home: home),
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('the money (pure)', () {
    test('profit = agreed prices − approved expenses, per currency, never mixed', () {
      final jobs = [_job('j1', 't1', price: 4500), _job('j2', 't1', price: 300, cur: 'AZN'), _job('j3', 't1', price: 999, status: 'cancelled')];
      final exp = [
        _exp('25', 't1', 450, 'AZN'),
        _exp('24', 't1', 30, 'USD'),
        _exp('26', 't1', 100, 'USD', status: 'pending', by: _drv),
        _exp('27', 't1', 70, 'USD', status: 'rejected', by: _drv),
      ];
      expect(fleetIncome(jobs), {'AZN': 300, 'USD': 4500}, reason: 'a cancelled job does not count');
      expect(fleetSpent(exp), {'AZN': 450, 'USD': 30}, reason: 'only approved expenses count');
      expect(fleetProfit(jobs, exp), {'AZN': -150, 'USD': 4470});
      // The owner's picture: no job price yet → −450 AZN | −30 USD.
      expect(fleetProfit(const [], exp), {'AZN': -450, 'USD': -30});
    });
    test('the five currencies, in order', () {
      expect(kFleetCurrencies, ['AZN', 'USD', 'EUR', 'RUB', 'TRY']);
      expect(sumByCurrency([('TRY', 1), ('AZN', 2), ('EUR', 3)]).keys, ['AZN', 'EUR', 'TRY']);
    });
    test('amounts: spaces between thousands, no ".00", a minus for a loss', () {
      expect(fleetAmount(4500), '4 500');
      expect(fleetAmount(5500.5), '5 500.5');
      expect(fleetAmount(12.25), '12.25');
      expect(fleetAmount(-450), '-450');
      expect(fleetAmount(1234567), '1 234 567');
      expect(parseFleetAmount('1 200,5'), 1200.5);
      expect(parseFleetAmount('0'), isNull);
      expect(parseFleetAmount('abc'), isNull);
    });
    test('Boşdur / İşdədir: a running job makes the truck busy', () {
      final jobs = [_job('a', 't2', from: const Duration(hours: -1)), _job('b', 't1', from: const Duration(days: 1))];
      expect(fleetTruckBusy('t2', jobs, _now), isTrue);
      expect(fleetTruckBusy('t1', jobs, _now), isFalse, reason: 'a job tomorrow does not make it busy today');
      expect(fleetTruckBusy('t2', [_job('a', 't2', from: const Duration(hours: -1), status: 'done')], _now), isFalse);
      expect(fleetCurrentJob('t2', jobs, _now)?.id, 'a');
    });
    test('upcoming / today: open jobs from today on, soonest first', () {
      final today = DateTime(_now.year, _now.month, _now.day, 23, 50);
      final jobs = [
        FleetJob(id: 'late', truckId: 't1', startAt: today),
        _job('tom', 't1', from: const Duration(days: 1)),
        _job('old', 't1', from: const Duration(days: -3)),
        _job('done', 't1', status: 'done'),
      ];
      expect([for (final j in fleetUpcoming(jobs, _now)) j.id], ['late', 'tom']);
      expect([for (final j in fleetToday(jobs, _now)) j.id], ['late']);
    });
  });

  testWidgets('Maşınlarım: counters, totals, Boşdur / İşdədir, the job under a busy truck', (tester) async {
    tester.view.physicalSize = const Size(390, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final data = FleetData(
      trucks: [_volvo, _man],
      jobs: [_job('j1', 't2', from: const Duration(minutes: -30), price: 4500)],
      expenses: [_exp('25', 't1', 450, 'AZN'), _exp('26', 't2', 80, 'AZN', status: 'pending', by: _drv)],
    );
    await tester.pumpWidget(_app(const FleetScreen(), data));
    await tester.pumpAndSettle();
    expect(find.text('Maşınlarım'), findsWidgets);
    expect(find.byKey(const ValueKey('map-fleet-switch')), findsOneWidget);
    expect(find.text('2 maşın'), findsOneWidget);
    expect(find.text('1 boş'), findsOneWidget);
    expect(find.text('1 işdə'), findsOneWidget);
    expect(find.byKey(const ValueKey('fl-add-truck')), findsOneWidget);
    expect(find.byKey(const ValueKey('fl-totals')), findsOneWidget);
    // The owner's approved look (design editor, 21.11.2026): glowing card, Gəlir / Qazanc glowing tiles, orange expenses.
    for (final k in ['income','spent','profit']) {
      expect(find.byWidgetPredicate((w) => w.key is ValueKey && '${(w.key as ValueKey).value}'.startsWith('fl-tot-$k-')), findsWidgets, reason: k);
    }
    final card = tester.widget<Container>(find.byKey(const ValueKey('fl-totals')));
    expect((card.decoration as BoxDecoration).boxShadow, isNotEmpty, reason: 'the card glows');
    final spent = tester.widget<Container>(find.byWidgetPredicate((w) => w.key is ValueKey && '${(w.key as ValueKey).value}'.startsWith('fl-tot-spent-')).first);
    expect((spent.decoration as BoxDecoration).boxShadow, isNull, reason: 'expenses: no glow, orange text');
    final inc = tester.widget<Container>(find.byWidgetPredicate((w) => w.key is ValueKey && '${(w.key as ValueKey).value}'.startsWith('fl-tot-income-')).first);
    expect((inc.decoration as BoxDecoration).color, isNotNull, reason: 'a glowing tile keeps the card ground — no blue inside (owner, 21.11.2026)');
    expect((inc.decoration as BoxDecoration).boxShadow!.single.blurRadius, kFleetGlowBlur, reason: 'the same glow as the editor');
    expect(find.text('Volvo FH 2022'), findsOneWidget);
    expect(find.text('99-AC-981'), findsOneWidget);
    expect(find.text('Rəşad Məmmədov'), findsOneWidget);
    expect(find.descendant(of: find.byKey(const ValueKey('fl-status-t1')), matching: find.text('Boşdur')), findsOneWidget);
    expect(find.descendant(of: find.byKey(const ValueKey('fl-status-t2')), matching: find.text('İşdədir')), findsOneWidget);
    expect(find.byKey(const ValueKey('fl-addjob-t1')), findsOneWidget, reason: 'a free truck: "İş əlavə et"');
    expect(find.byKey(const ValueKey('fl-ad-t1')), findsOneWidget, reason: '…and the empty truck ad');
    expect(find.textContaining('Bakı → Gəncə'), findsWidgets, reason: 'the busy truck\'s job');
    expect(find.byKey(const ValueKey('fl-pending-t2')), findsOneWidget, reason: 'a waiting driver expense is shown');
    expect(tester.takeException(), isNull);
  });

  testWidgets('the owner\'s truck page: profit, agreed price, a waiting expense with Təsdiqlə / Rədd et', (tester) async {
    tester.view.physicalSize = const Size(390, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final data = FleetData(
      trucks: [_volvo],
      jobs: [_job('j1', 't1', price: 4500)],
      expenses: [_exp('25', 't1', 450, 'AZN'), _exp('24', 't1', 30, 'USD'), _exp('26', 't1', 80, 'USD', status: 'pending', by: _drv)],
    );
    await tester.pumpWidget(_app(const FleetTruckScreen(id: 't1'), data));
    await tester.pumpAndSettle();
    expect(find.text('Mənfi qazanc'), findsOneWidget, reason: 'one currency below zero');
    expect(find.byKey(const ValueKey('fl-profit-AZN')), findsOneWidget);
    expect(find.text('-450 AZN'), findsOneWidget);
    expect(find.text('4 470 USD'), findsOneWidget, reason: 'the pending 80 USD does not count yet');
    expect(tester.widget<Text>(find.byKey(const ValueKey('fl-agreed'))).data, '4 500 USD');
    expect(find.text('Təsdiq gözləyir'), findsOneWidget);
    expect(find.byKey(const ValueKey('fl-exp-approve-26')), findsOneWidget);
    expect(find.byKey(const ValueKey('fl-exp-reject-26')), findsOneWidget);
    expect(find.byKey(const ValueKey('fl-driver-card')), findsOneWidget);
    // The expenses' total in red on the right (owner, 20.11.2026): only the
    // approved ones; the driver's waiting one apart.
    expect(tester.widget<Text>(find.byKey(const ValueKey('fl-spent-AZN'))).data, '450 AZN');
    expect(tester.widget<Text>(find.byKey(const ValueKey('fl-spent-USD'))).data, '30 USD');
    expect(tester.widget<Text>(find.byKey(const ValueKey('fl-spent-AZN'))).style!.color, AppColors.danger);
    expect(tester.widget<Text>(find.byKey(const ValueKey('fl-spent-wait-USD'))).data, '+ 80 USD təsdiq gözləyir');
    expect(tester.getCenter(find.byKey(const ValueKey('fl-spent-AZN'))).dx,
        greaterThan(tester.getCenter(find.byKey(const ValueKey('fl-profit-AZN'))).dx),
        reason: 'right of the profit');
    expect(tester.takeException(), isNull);
  });

  testWidgets('the driver from the registered users (0131): typed name → the list → Seç → saved and asked', (tester) async {
    tester.view.physicalSize = const Size(390, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final repo = _Repo();
    await tester.pumpWidget(_app(
      Builder(
        builder: (c) => Scaffold(body: Center(child: TextButton(onPressed: () => showFleetTruckForm(c), child: const Text('open')))),
      ),
      const FleetData(),
      repo: repo,
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('fl-truck-name')), 'Volvo FH 2022');
    await tester.enterText(find.byKey(const ValueKey('fl-truck-driver')), 'Əl');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump();
    expect(repo.asked, ['Əl']);
    expect(find.byKey(const ValueKey('fl-driver-found')), findsOneWidget);
    expect(find.text('TırLink istifadəçiləri'), findsOneWidget);
    expect(find.text('Siyahıda yoxdursa, adı sadəcə yazın.'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('fl-driver-user-u-ali')));
    await tester.pump();
    expect(find.byKey(const ValueKey('fl-driver-picked')), findsOneWidget);
    expect(find.text('Əli Məmmədov'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('fl-truck-save')));
    await tester.pumpAndSettle();
    expect(repo.saved.single, 'Volvo FH 2022|Əli Məmmədov');
    expect(repo.invited.single, ('t-new', 'u-ali'), reason: 'asked, never linked without his yes');
  });

  testWidgets('a plain name stays a plain name; ✕ on a waiting driver takes the invitation back', (tester) async {
    tester.view.physicalSize = const Size(390, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final repo = _Repo();
    const waiting = FleetTruck(id: 't1', ownerId: _owner, name: 'Volvo', driverName: 'Əli Məmmədov', pendingDriverId: 'u-ali');
    await tester.pumpWidget(_app(
      Builder(
        builder: (c) => Scaffold(
            body: Center(child: TextButton(onPressed: () => showFleetTruckForm(c, truck: waiting), child: const Text('open')))),
      ),
      const FleetData(),
      repo: repo,
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('fl-driver-picked')), findsOneWidget, reason: 'the waiting one is shown chosen');
    await tester.tap(find.byKey(const ValueKey('fl-driver-unpick')));
    await tester.pump();
    await tester.enterText(find.byKey(const ValueKey('fl-truck-driver')), 'Rəşad');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.tap(find.byKey(const ValueKey('fl-truck-save')));
    await tester.pumpAndSettle();
    expect(repo.saved.single, 'Volvo|Rəşad');
    expect(repo.cancelled, ['t1']);
    expect(repo.invited, isEmpty);
  });

  testWidgets('the truck page: "Sürücünü hesabla bağla" searches the registered users; the code stays a small link', (tester) async {
    tester.view.physicalSize = const Size(390, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final repo = _Repo();
    const free = FleetTruck(id: 't1', ownerId: _owner, name: 'Volvo FH 2022');
    await tester.pumpWidget(_app(const FleetTruckScreen(id: 't1'), const FleetData(trucks: [free]), repo: repo));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('fl-link-driver')));
    await tester.tap(find.byKey(const ValueKey('fl-link-driver')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('fl-link-search')), findsOneWidget, reason: 'a search, not the code');
    expect(find.byKey(const ValueKey('fl-invite-code')), findsNothing);
    await tester.enterText(find.byKey(const ValueKey('fl-link-search')), 'Əl');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump();
    expect(repo.asked, ['Əl']);
    await tester.tap(find.byKey(const ValueKey('fl-link-user-u-ali')));
    await tester.pumpAndSettle();
    expect(repo.invited.single, ('t1', 'u-ali'), reason: 'asked, never linked without his yes');
    expect(find.byKey(const ValueKey('fl-link-search')), findsNothing, reason: 'the sheet closes');

    // The one-time code still works, from the small link.
    await tester.tap(find.byKey(const ValueKey('fl-link-driver')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('fl-link-by-code')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('fl-link-search')), findsNothing);
    expect(find.byKey(const ValueKey('fl-invite-code')), findsOneWidget);
    expect(find.text('AB12CD34'), findsOneWidget);
  });

  testWidgets('"Sürücü təsdiqi gözləyir" on the card and the truck page', (tester) async {
    tester.view.physicalSize = const Size(390, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    const waiting = FleetTruck(id: 't1', ownerId: _owner, name: 'Volvo FH 2022', driverName: 'Əli Məmmədov', pendingDriverId: 'u-ali');
    await tester.pumpWidget(_app(const FleetScreen(), const FleetData(trucks: [waiting])));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('fl-driver-wait-t1')), findsOneWidget);
    expect(find.text('Sürücü təsdiqi gözləyir'), findsOneWidget);
    await tester.pumpWidget(_app(const FleetTruckScreen(id: 't1'), const FleetData(trucks: [waiting])));
    await tester.pumpAndSettle();
    expect(find.descendant(of: find.byKey(const ValueKey('fl-driver-card')), matching: find.text('Sürücü təsdiqi gözləyir')), findsOneWidget);
  });

  testWidgets('the driver answers in Bildirişlər: Qəbul et / Rədd et', (tester) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final repo = _Repo();
    const n = AppNotice(
        id: 'n1',
        type: 'fleet_driver_invite',
        body: 'Volvo FH 2022 · 99-AC-981',
        data: {'invite_id': 'i1', 'owner': 'Kamran Əliyev', 'truck': 'Volvo FH 2022'});
    await tester.pumpWidget(ProviderScope(
      overrides: [
        stringsProvider.overrideWithValue(_lang('az')),
        currentUserIdProvider.overrideWithValue(_drv),
        currentUserProvider.overrideWithValue(null),
        fleetRepositoryProvider.overrideWithValue(repo),
        fleetProvider.overrideWith((ref) async => const FleetData()),
        myNoticesProvider.overrideWith((ref) => Stream.value(const [n])),
        settledNoticesProvider.overrideWith((ref) async => const <String>{}),
        noticesRepositoryProvider.overrideWithValue(_Notices()),
      ],
      child: const MaterialApp(home: NoticesScreen()),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Kamran Əliyev sizi sürücü kimi əlavə edir'), findsOneWidget);
    expect(find.text('Qəbul et'), findsOneWidget);
    expect(find.text('Rədd et'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('notice-accept-n1')));
    await tester.pumpAndSettle();
    expect(repo.answers.single, ('i1', true));
    expect(find.text('«Volvo FH 2022» maşınına qoşuldunuz ✓'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the driver\'s view: no prices, no profit, his waiting expense, no approve buttons', (tester) async {
    tester.view.physicalSize = const Size(390, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final data = FleetData(
      trucks: [_man],
      jobs: [_job('j1', 't2', from: const Duration(hours: 2))], // no price: the server sends none to a driver
      expenses: [_exp('26', 't2', 80, 'AZN', status: 'pending', by: _drv)],
    );
    await tester.pumpWidget(_app(const FleetTruckScreen(id: 't2'), data, uid: _drv));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('fl-profit')), findsNothing);
    expect(find.byKey(const ValueKey('fl-agreed')), findsNothing);
    expect(find.textContaining('USD'), findsNothing);
    expect(find.text('Təsdiq gözləyir'), findsOneWidget);
    expect(find.byKey(const ValueKey('fl-exp-approve-26')), findsNothing);
    expect(find.byKey(const ValueKey('fl-page-addexp')), findsOneWidget, reason: 'the driver writes expenses');
    expect(find.byKey(const ValueKey('fl-page-addjob')), findsNothing);
    expect(find.byKey(const ValueKey('fl-truck-menu')), findsNothing);
  });

  testWidgets('the expense form: the owner\'s picture — name, amount, AZN · USD · EUR · RUB · TRY, Yadda saxla, Sil', (tester) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_app(
      Builder(
        builder: (c) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => showFleetExpenseForm(c, truckId: 't1', expense: _exp('25', 't1', 450, 'AZN'), canRemove: true),
              child: const Text('open'),
            ),
          ),
        ),
      ),
      const FleetData(),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Rasxodu redaktə et'), findsOneWidget);
    for (final c in kFleetCurrencies) {
      expect(find.byKey(ValueKey('fl-cur-$c')), findsOneWidget);
    }
    expect(find.byKey(const ValueKey('fl-exp-save')), findsOneWidget);
    expect(find.byKey(const ValueKey('fl-exp-remove')), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('fl-exp-amount')), '0');
    await tester.tap(find.byKey(const ValueKey('fl-exp-save')));
    await tester.pump();
    expect(find.text('Məbləği düzgün yazın (0-dan böyük).'), findsOneWidget, reason: 'checked before sending');
  });

  testWidgets('never overflows: 6 languages × 320 pt × text 125 % (list and truck page)', (tester) async {
    tester.view.physicalSize = const Size(320, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final data = FleetData(
      trucks: [_volvo, _man],
      jobs: [_job('j1', 't2', from: const Duration(minutes: -30), price: 4500), _job('j2', 't1', from: const Duration(days: 1), price: 1200, cur: 'EUR')],
      expenses: [_exp('25', 't1', 450, 'AZN'), _exp('26', 't1', 80, 'RUB', status: 'pending', by: _drv)],
    );
    for (final l in ['az', 'tr', 'en', 'ru', 'ka', 'zh']) {
      for (final page in const [FleetScreen(), FleetScreen(tab: 'plan'), FleetTruckScreen(id: 't1')]) {
        await tester.pumpWidget(ProviderScope(
          overrides: [
            stringsProvider.overrideWithValue(_lang(l)),
            currentUserIdProvider.overrideWithValue(_owner),
            currentUserProvider.overrideWithValue(null),
            fleetProvider.overrideWith((ref) async => data),
            myNoticesProvider.overrideWith((ref) => Stream.value(const <AppNotice>[])),
          ],
          child: MaterialApp(
            home: MediaQuery(
              data: const MediaQueryData(size: Size(320, 2400), textScaler: TextScaler.linear(1.25)),
              child: page,
            ),
          ),
        ));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: '$l $page');
      }
    }
  });

  group('wired', () {
    test('Xəritə | Maşınlarım on the map pages; /fleet and /fleet/t/:id in the Xəritə tab', () {
      for (final p in ['lib/features/tirpark/presentation/tir_park_screen.dart', 'lib/features/services/presentation/services_map_screen.dart']) {
        expect(_read(p), contains("MapFleetSwitch(s: s, fleet: false, onMap: () {}, onFleet: () => context.go('/fleet')),"));
      }
      final r = _read('lib/core/router/app_router.dart');
      expect(r.indexOf("path: '/fleet'"), greaterThan(r.indexOf("path: '/tirpark',")));
      expect(r, contains("GoRoute(path: 't/:id', builder: (context, state) => NavRoom(child: FleetTruckScreen(id: state.pathParameters['id']!))),"));
      expect(_read('lib/core/router/guest_access.dart').contains('/fleet'), isFalse, reason: 'a visitor signs in first');
      expect(_read('lib/features/tirpark/presentation/tir_park_screen.dart'), contains('FleetTodayCard(s: s),'), reason: '"Bugünkü plan" on the map');
    });
    test('the driver\'s expense notice: text, the truck page, settled when decided', () {
      const n = AppNotice(id: 'n1', type: 'fleet_expense', data: {'truck_id': 't1', 'expense_id': 'e1', 'name': 'Ay-25', 'truck': 'Volvo FH 2022', 'amount': 450, 'currency': 'AZN'});
      final az = _lang('az');
      expect(n.text(az), 'Rasxod təsdiq gözləyir: Ay-25');
      expect(n.detail(), 'Volvo FH 2022 · 450 AZN');
      expect(n.route, '/fleet/t/t1');
      expect(n.opensInTab, isTrue);
      expect(n.isAction, isTrue);
      expect(_read('lib/features/notices/notices.dart'), contains(".from('fleet_expenses')"));
    });
    test('SQL 0130: new tables only, no direct writes, own rows only, the driver gets no price, nothing deleted', () {
      final sql = _read('supabase/migrations/0130_fleet.sql');
      final lower = sql.toLowerCase();
      for (final bad in ['drop table', 'truncate', 'delete from', 'alter table public.users']) {
        expect(lower.contains(bad), isFalse, reason: bad);
      }
      expect(sql, contains('revoke all on public.fleet_trucks, public.fleet_jobs, public.fleet_expenses, public.fleet_driver_invites from anon, authenticated;'));
      expect(sql, contains('grant select on public.fleet_trucks, public.fleet_jobs, public.fleet_expenses to authenticated;'));
      expect(sql, contains('using (owner_id = auth.uid());'), reason: 'jobs (prices) only for the owner');
      final drv = sql.substring(sql.indexOf('function public.fleet_driver_jobs()'));
      expect(drv.substring(0, drv.indexOf(r'end $$')).contains("'price'"), isFalse);
      expect(sql, contains("case when v_driver then 'pending' else 'approved' end"));
      expect(sql, contains("'fleet_expense'"));
      expect(sql, contains("currency in ('AZN', 'USD', 'EUR', 'RUB', 'TRY')"));
      expect(_read('supabase/tests/local/run_local.sh'), contains('166_fleet.sql'));
    });
    test('the driver invitation notices: texts, no route for the invite, the answer opens the truck', () {
      final az = _lang('az');
      const inv = AppNotice(id: 'a', type: 'fleet_driver_invite', body: 'Volvo · 99-AC-981', data: {'invite_id': 'i1', 'owner': 'Kamran'});
      expect(inv.text(az), 'Kamran sizi sürücü kimi əlavə edir');
      expect(inv.detail(), 'Volvo · 99-AC-981');
      expect(inv.isAction, isTrue, reason: 'hidden once answered');
      expect(inv.isDriverInvite, isTrue);
      expect(inv.route, isNull);
      const yes = AppNotice(id: 'b', type: 'fleet_driver_answer', data: {'truck_id': 't1', 'driver': 'Əli', 'accepted': true});
      const no = AppNotice(id: 'c', type: 'fleet_driver_answer', data: {'truck_id': 't1', 'driver': 'Əli', 'accepted': false});
      expect(yes.text(az), 'Əli sürücü kimi qəbul etdi');
      expect(no.text(az), 'Əli sürücü olmağı rədd etdi');
      expect(yes.route, '/fleet/t/t1');
      expect(_read('lib/features/notices/notices.dart'), contains("_c.rpc('fleet_my_driver_invites')"));
    });
    test('SQL 0131: search gives names only, the invite waits for his yes, nothing deleted', () {
      final sql = _read('supabase/migrations/0131_fleet_driver_invite.sql');
      final lower = sql.toLowerCase();
      for (final bad in ['drop table', 'truncate', 'delete from']) {
        expect(lower.contains(bad), isFalse, reason: bad);
      }
      final search = sql.substring(sql.indexOf('function public.fleet_driver_search'), sql.indexOf('function public.fleet_driver_invite_user'));
      expect(search, contains('returns table (id uuid, full_name text, avatar_url text, is_verified boolean)'));
      expect(search.contains('email'), isFalse);
      expect(search.contains('phone'), isFalse);
      expect(search, contains('not public.is_blocked(p.id)'));
      expect(search, contains('limit 10'));
      final answer = sql.substring(sql.indexOf('function public.fleet_driver_answer'));
      expect(answer, contains('v_i.invited_user is distinct from v_me'), reason: 'only the invited account answers');
      expect(sql, contains("'fleet_driver_invite'"));
      expect(_read('supabase/tests/local/run_local.sh'), contains('167_fleet_driver_invite.sql'));
    });
    test('every Maşınlarım text in all 6 languages', () {
      final keys = RegExp(r"'(fl_[a-z_]+)'")
          .allMatches([
            for (final f in Directory('lib/features/fleet').listSync(recursive: true).whereType<File>()) f.readAsStringSync(),
            _read('lib/features/tirpark/presentation/map_page_header.dart'),
          ].join())
          .map((m) => m.group(1)!)
          .toSet();
      expect(keys.length, greaterThan(50));
      for (final l in ['az', 'tr', 'en', 'ru', 'ka', 'zh']) {
        final m = jsonDecode(_read('assets/i18n/$l.json')) as Map;
        for (final k in [...keys, 'ntf_fleet_expense', 'ntf_fleet_invite', 'ntf_fleet_accepted', 'ntf_fleet_declined', 'ntf_fleet_accept', 'ntf_fleet_decline']) {
          expect(m[k], isNotNull, reason: '$l $k');
        }
      }
    });
  });
}

class _Notices implements NoticesRepository {
  @override
  Future<void> markRead(List<String> ids) async {}
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}
