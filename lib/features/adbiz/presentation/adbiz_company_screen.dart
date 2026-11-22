import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/localization/app_strings.dart';
import '../../../core/localization/locale_controller.dart';
import '../../../core/router/safe_navigation.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/birth_date_field.dart' show monthName;
import '../../finance/domain/finance_models.dart';
import '../data/adbiz_repository.dart';
import '../domain/adbiz_models.dart';
import 'adbiz_notebook_screen.dart' show adbizAmount, adbizConfirmDeleteDay, adbizMonthTitle, adbizNum;
import 'adbiz_providers.dart';
import 'adbiz_widgets.dart';

/// "Reklam idarəetməsi" of one company (owner, 10.11.2026; the owner's
/// picture of the panel, same day — dark teal glass, a light version by
/// day): Gün · Ay · İl with the date, Ümumi gəlir · Xərclər · Xalis
/// mənfəət, card / cash, open / closed days, the workers (⋯: days, task,
/// …), Gündəlik hədəf with the workers' switch, the owner's words, the
/// expenses and the archive.
/// The company's owner sees only his company; the Baş admin every company,
/// and also manages members, targets and the company itself here.
class AdbizCompanyScreen extends ConsumerStatefulWidget {
  final String companyId;
  const AdbizCompanyScreen({super.key, required this.companyId});

  @override
  ConsumerState<AdbizCompanyScreen> createState() => _AdbizCompanyScreenState();
}

class _AdbizCompanyScreenState extends ConsumerState<AdbizCompanyScreen> {
  AdbizPeriod _period = AdbizPeriod.day;
  DateTime _date = bakuToday();
  bool _busy = false;

  AdbizPeriodKey get _key => (companyId: widget.companyId, period: _period, date: _date);

  String get _viewKey => 'adbiz_view_${widget.companyId}';

  /// Gün / Ay / İl and its date stay as chosen until the owner changes them
  /// (owner, 21.11.2026) — kept on the device, also after a restart.
  void _setView(AdbizPeriod p, DateTime d) {
    setState(() {
      _period = p;
      _date = d;
    });
    final v = adbizViewEncode(p, d);
    SharedPreferences.getInstance().then((prefs) => prefs.setString(_viewKey, v)).catchError((_) => false);
  }

  /// The panel never waits for a manual refresh (owner, 21.11.2026): it is
  /// read again every [kAdbizResyncEvery] (a worker's job on his own phone)
  /// and whenever the owner comes back from a worker's notebook.
  Timer? _tick;

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(kAdbizResyncEvery, (_) {
      if (mounted) _refresh();
    });
    SharedPreferences.getInstance().then((prefs) {
      final v = adbizViewDecode(prefs.getString(_viewKey));
      if (v != null && mounted) {
        setState(() {
          _period = v.$1;
          _date = v.$2;
        });
      }
    }).catchError((_) {});
    // A day ends at 23:59 Baku: forgotten open days are closed first, then
    // the open / closed counts are read again (0112).
    Future.microtask(() async {
      await ref.read(adbizRepositoryProvider).sweep();
      if (mounted) _refresh();
    });
  }

  void _refresh() {
    ref.invalidate(adbizPeriodsProvider);
    ref.invalidate(adbizReportProvider);
    ref.invalidate(adbizExpensesProvider);
    ref.invalidate(adbizCompaniesProvider);
    ref.invalidate(adbizMeProvider);
  }

  void _shift(int dir) => _setView(
      _period,
      switch (_period) {
        AdbizPeriod.day => _date.add(Duration(days: dir)),
        AdbizPeriod.month => DateTime(_date.year, _date.month + dir, 1),
        AdbizPeriod.year => DateTime(_date.year + dir, 1, 1),
      });

  String _periodLabel(AppStrings s) => switch (_period) {
        AdbizPeriod.day => dmy(_date),
        AdbizPeriod.month => '${_date.month.toString().padLeft(2, '0')}.${_date.year}',
        AdbizPeriod.year => '${_date.year}',
      };

  Future<void> _run(AppStrings s, Future<void> Function() f, {String? done}) async {
    if (_busy) return; // a double tap never runs twice
    setState(() => _busy = true);
    try {
      await f();
      _refresh();
      if (done != null && mounted) adbizSnack(context, done);
    } catch (e) {
      if (mounted) adbizSnack(context, adbizError(s, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ---- expenses --------------------------------------------------------------------
  Future<void> _addExpense(AppStrings s) async {
    final r = await askTitleAmount(context, s, heading: s.t('adb_add_expense'));
    if (r == null || !mounted) return;
    final key = adbizClientKey();
    final on = _period == AdbizPeriod.day ? _date : bakuToday();
    await _run(s, () => ref.read(adbizRepositoryProvider).expenseSave(
        companyId: widget.companyId, spentOn: on, title: r.$1, amount: r.$2, clientKey: key), done: s.t('adb_saved'));
  }

  Future<void> _editExpense(AppStrings s, AdbizExpense x) async {
    final r = await askTitleAmount(context, s, heading: s.t('adb_edit_expense'), title: x.title, amount: x.amount);
    if (r == null || !mounted) return;
    await _run(s, () => ref.read(adbizRepositoryProvider).expenseSave(id: x.id, spentOn: x.spentOn, title: r.$1, amount: r.$2),
        done: s.t('adb_saved'));
  }

  Future<void> _deleteExpense(AppStrings s, AdbizExpense x) async {
    if (!await adbizConfirm(context, s, s.t('adb_delete_expense'), '${x.title} · ${money(x.amount)}', ok: s.t('adb_delete'))) return;
    await _run(s, () => ref.read(adbizRepositoryProvider).expenseDelete(x.id));
  }

  // ---- members (Baş admin; an owner only when allowed) ----------------------------------
  Future<void> _addMember(AppStrings s, {required bool chief}) async {
    if (chief) {
      final hit = await showDialog<(AdbizUserHit, String)>(context: context, builder: (_) => AdbizUserPicker(s: s));
      if (hit == null || !mounted) return;
      await _run(s, () => ref.read(adbizRepositoryProvider).memberSet(hit.$1.id, widget.companyId, hit.$2), done: s.t('adb_member_added'));
      return;
    }
    final c = TextEditingController();
    final email = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.t('adb_add_worker')),
        content: TextField(
          key: const ValueKey('adb-worker-email'),
          controller: c,
          keyboardType: TextInputType.emailAddress,
          decoration: InputDecoration(labelText: s.t('adb_worker_email'), helperText: s.t('adb_worker_email_hint')),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(s.t('common_cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: Text(s.t('adb_add'))),
        ],
      ),
    );
    if (email == null || email.isEmpty || !mounted) return;
    await _run(s, () => ref.read(adbizRepositoryProvider).ownerAddWorker(email), done: s.t('adb_member_added'));
  }

  Future<void> _memberTarget(AppStrings s, AdbizWorkerSum w) async {
    final c = TextEditingController(text: w.personalTarget?.toStringAsFixed(2) ?? '');
    final r = await showDialog<(bool, double?)>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.t('adb_personal_target')),
        content: TextField(
          key: const ValueKey('adb-personal-target'),
          controller: c,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(labelText: s.t('adb_target'), suffixText: 'AZN', helperText: s.t('adb_personal_target_hint')),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, (true, null)), child: Text(s.t('adb_use_company_target'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, (true, parseAmount(c.text))), child: Text(s.t('adb_save'))),
        ],
      ),
    );
    if (r == null || !mounted) return;
    await _run(s, () => ref.read(adbizRepositoryProvider).memberTarget(w.userId, r.$2), done: s.t('adb_saved'));
  }

  Future<void> _editCompany(AppStrings s, AdbizCompany c) async {
    final month = ref.read(adbizMonthTargetProvider(widget.companyId)).valueOrNull;
    final r = await showDialog<AdbizCompanyForm>(
        context: context, builder: (_) => AdbizCompanyDialog(s: s, company: c, monthTarget: month));
    if (r == null || !mounted) return;
    await _run(s, () async {
      final repo = ref.read(adbizRepositoryProvider);
      // The monthly target is written; the daily one follows it (÷ 26).
      await repo.companySave(id: c.id, name: r.name, dailyTarget: r.dailyTarget, ownerManagesStaff: r.ownerManagesStaff);
      if (r.monthTarget != month) await repo.setMonthTarget(c.id, bakuToday(), r.monthTarget);
      ref.invalidate(adbizMonthTargetProvider(widget.companyId));
    }, done: s.t('adb_saved'));
  }

  /// The Baş admin's monthly target, counted from this month on (0133).
  Future<void> _editMonthTarget(AppStrings s, double current) async {
    final c = TextEditingController(text: adbizNum(current));
    final v = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.t('adb_month_target')),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          TextField(
            key: const ValueKey('adb-month-target-field'),
            controller: c,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(suffixText: 'AZN'),
          ),
          const SizedBox(height: 8),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: c,
            builder: (_, v, __) => Text(adbizDailyLine(s, parseAmount(v.text) ?? 0),
                key: const ValueKey('adb-month-daily-line'), style: TextStyle(fontSize: 13, color: AppColors.adbText)),
          ),
          const SizedBox(height: 4),
          Text(s.t('adb_month_target_hint'), style: TextStyle(fontSize: 12.5, color: AppColors.adbTextSoft)),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(s.t('common_cancel'))),
          FilledButton(
              key: const ValueKey('adb-month-target-save'), onPressed: () => Navigator.pop(ctx, parseAmount(c.text)), child: Text(s.t('adb_save'))),
        ],
      ),
    );
    if (v == null || !mounted) return;
    await _run(s, () async {
      final repo = ref.read(adbizRepositoryProvider);
      await repo.setMonthTarget(widget.companyId, bakuToday(), v);
      // The daily target follows the monthly one (owner, 22.11.2026: ÷ 26).
      final c = ref.read(adbizCompanyProvider(widget.companyId));
      if (c != null) {
        await repo.companySave(
            id: c.id, name: c.name, dailyTarget: adbizDailyFromMonthly(v), ownerManagesStaff: c.ownerManagesStaff);
      }
      ref.invalidate(adbizMonthTargetProvider(widget.companyId));
    }, done: s.t('adb_saved'));
  }

  // ---- delete a (test) work day from the archive (0115) -----------------------------------
  Future<void> _deleteDayOn(AppStrings s, DateTime date, List<AdbizWorkerSum> workers) async {
    if (_busy) return;
    final repo = ref.read(adbizRepositoryProvider);
    try {
      final days = await repo.daysOn(widget.companyId, date);
      if (days.isEmpty || !mounted) return;
      String nameOf(String uid) => workers.where((w) => w.userId == uid).firstOrNull?.name ?? '';
      var day = days.first;
      if (days.length > 1) {
        // Several workers worked that date: which day goes?
        final picked = await showDialog<AdbizDay>(
          context: context,
          builder: (ctx) => SimpleDialog(
            title: Text(s.t('adb_pick_day')),
            children: [
              for (final d in days)
                SimpleDialogOption(
                  key: ValueKey('adb-pick-${d.id}'),
                  onPressed: () => Navigator.pop(ctx, d),
                  child: Text(nameOf(d.userId)),
                ),
            ],
          ),
        );
        if (picked == null || !mounted) return;
        day = picked;
      }
      final entries = await repo.entries(day.id);
      final expenses = await repo.dayExpenses(day.id);
      if (!mounted) return;
      if (!await adbizConfirmDeleteDay(context, s, day.workDate, nameOf(day.userId), entries, expenses)) return;
      await _run(s, () => repo.deleteDay(day.id), done: s.t('adb_day_deleted'));
    } catch (e) {
      if (mounted) adbizSnack(context, e is AdbizNotReady ? s.t('adb_need_sql115') : adbizError(s, e));
    }
  }

  // ---- the old account (0116): a month's figures from before the program --------------------
  Future<void> _editOldMonth(AppStrings s, int year, int month, String label, AdbizPeriodSum? sum) async {
    final r = await showDialog<(double?, double?)>(
        context: context, builder: (_) => AdbizOldMonthDialog(s: s, title: '${s.t('adb_old_account')} · $label $year', sum: sum));
    if (r == null || !mounted) return;
    await _run(s, () => ref.read(adbizRepositoryProvider).monthImportSave(widget.companyId, year, month, r.$1, r.$2),
        done: s.t('adb_saved'));
  }

  // ---- the owner's words, the target switch, a worker's task (0113) ---------------------
  Future<void> _editWords(AppStrings s, AdbizCompany c) async {
    final r = await showDialog<(String, String, String, String)>(context: context, builder: (_) => AdbizWordsDialog(s: s, company: c));
    if (r == null || !mounted) return;
    await _run(s, () async {
      final repo = ref.read(adbizRepositoryProvider);
      await repo.companyTexts(c.id, r.$1, r.$2);
      // The day-result messages only once SQL 0114 is run.
      if (c.v114) await repo.companyResultTexts(c.id, r.$3, r.$4);
    }, done: s.t('adb_saved'));
  }

  Future<void> _workerTask(AppStrings s, AdbizWorkerSum w) async {
    final c = TextEditingController(text: w.taskNote ?? '');
    final r = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${s.t('adb_task_worker')} · ${w.name}'),
        content: SizedBox(
          width: 440,
          child: TextField(
            key: const ValueKey('adb-worker-task'),
            controller: c,
            maxLength: 500,
            minLines: 3,
            maxLines: 6,
            decoration: InputDecoration(labelText: s.t('adb_task'), helperText: s.t('adb_words_hint')),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(s.t('common_cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: Text(s.t('adb_save'))),
        ],
      ),
    );
    if (r == null || !mounted) return;
    await _run(s, () => ref.read(adbizRepositoryProvider).memberTask(w.userId, r), done: s.t('adb_saved'));
  }

  Future<void> _openWorker(AdbizWorkerSum w) async {
    await context.pushOnce(Uri(path: '/profile/adbiz/worker/${w.userId}', queryParameters: {'name': w.name}).toString());
    if (mounted) _refresh(); // what was written there shows here at once
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    ref.watch(currentLocaleProvider);
    final me = ref.watch(adbizMeProvider).valueOrNull;
    final chief = me?.chief == true;
    final company = ref.watch(adbizCompanyProvider(widget.companyId));
    final v113 = company?.v113 == true;
    final canStaff = chief || (me?.isOwner == true && me?.managesStaff == true && me?.companyId == widget.companyId);
    final rep = ref.watch(adbizReportProvider(_key));
    final exps = ref.watch(adbizExpensesProvider(_key)).valueOrNull ?? const <AdbizExpense>[];
    final r = rep.valueOrNull;
    final title = TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: AppColors.adbText);

    // 1. Gün · Ay · İl | ‹ date ›.
    final periodBar = AdbizGlass(
      padding: const EdgeInsets.all(10),
      child: LayoutBuilder(builder: (context, c) {
        final pills = AdbizPeriodPills(s: s, value: _period, onChanged: (v) => _setView(v, _date));
        final date = Row(mainAxisSize: MainAxisSize.min, children: [
          IconButton(key: const ValueKey('adb-prev'), onPressed: () => _shift(-1), icon: Icon(Icons.chevron_left, color: AppColors.adbText)),
          Text(_periodLabel(s), key: const ValueKey('adb-period-label'),
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: AppColors.adbText)),
          IconButton(key: const ValueKey('adb-next'), onPressed: () => _shift(1), icon: Icon(Icons.chevron_right, color: AppColors.adbText)),
        ]);
        if (c.maxWidth < 340) {
          return Column(children: [pills, const SizedBox(height: 6), date]);
        }
        return Row(children: [
          Expanded(child: pills),
          Container(width: 1, height: 40, margin: const EdgeInsets.symmetric(horizontal: 6), color: AppColors.adbLine),
          date,
        ]);
      }),
    );

    // 2. Four parts (owner, 21.11.2026): Ümumi gəlir · Rasxodlar · Karta
    // köçürülən (jobs paid by card, inside the income) · Xalis gəlir.
    final lang = ref.watch(currentLocaleProvider).languageCode;
    final today = bakuToday();
    // The same panel for Gün · Ay · İl (owner, 21.11.2026), with what it covers.
    final monthCaption = switch (_period) {
      AdbizPeriod.day => '${_date.day} ${monthName(_date.month, lang)} ${_date.year}',
      AdbizPeriod.month => '${adbizMonthTitle(_date, lang)}'
          '${_date.year == today.year && _date.month == today.month ? ' · ${s.t('adb_so_far', {'from': '1', 'to': '${today.day}'})}' : ''}',
      AdbizPeriod.year => '${_date.year}${_date.year == today.year ? ' · ${s.t('adb_so_far_year')}' : ''}',
    };
    // Xalis gəlir = the month / year cards' net: the old account counts too.
    final perSums = _period == AdbizPeriod.day
        ? null
        : ref.watch(adbizPeriodsProvider((companyId: widget.companyId, year: _date.year))).valueOrNull;
    final oldNet = switch (_period) {
      AdbizPeriod.day => 0.0,
      AdbizPeriod.month => perSums?.months.where((m) => m.key == _date.month).firstOrNull?.impNet ?? 0.0,
      AdbizPeriod.year => perSums?.years.where((y) => y.key == _date.year).firstOrNull?.impNet ?? 0.0,
    };
    // Ümumi mənfi instead of Rasxodlar (owner, 22.11.2026: "rasxodlar +
    // mənfilər … cəm o ayın mənfisi"): the period's gap = income − rasxod −
    // the targets (signed; the same number as the month / year cards' red
    // half). Gün: the targets of that date's days (open ones too).
    final double? gap = switch (_period) {
      AdbizPeriod.day => r == null ? null : adbizDayGap(r, [
          for (final w in r.workers) ref.watch(adbizDaysProvider(w.userId)).valueOrNull,
        ], _date),
      AdbizPeriod.month => perSums?.months.where((m) => m.key == _date.month).firstOrNull?.gap,
      AdbizPeriod.year => perSums?.years.where((y) => y.key == _date.year).firstOrNull?.gap,
    };
    final minusText = adbizMinusText(gap);
    final totals = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
          padding: const EdgeInsets.fromLTRB(6, 0, 6, 8),
          child: Text(monthCaption, key: const ValueKey('adb-month-caption'), style: TextStyle(fontSize: 14, color: AppColors.adbTextSoft)),
        ),
      // Variant A (owner, 22.11.2026: "A bəndi"): Xalis gəlir big on top,
      // the old account under it, then Ümumi gəlir · Ümumi mənfi · Karta
      // köçürülən as three chips (one size for the three, adbizFitSize).
      AdbizGlass(
        key: const ValueKey('adb-hero'),
        highlight: true,
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(s.t('adb_net_income').toUpperCase(),
              style: TextStyle(fontSize: 12.5, letterSpacing: 0.5, color: AppColors.adbTextSoft)),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(adbizAmount((r?.net ?? 0) + oldNet),
                key: const ValueKey('adb-net'),
                style: TextStyle(fontSize: 34, fontWeight: FontWeight.w600, color: AppColors.adbGold)),
          ),
          if (oldNet != 0)
            Text(s.t('adb_old_included', {'amount': adbizAmount(oldNet)}),
                key: const ValueKey('adb-old-included'), style: TextStyle(fontSize: 12.5, color: AppColors.adbTextSoft)),
          const SizedBox(height: 12),
          LayoutBuilder(builder: (context, c) {
            const gapW = 8.0;
            final vs = adbizFitSize([adbizAmount(r?.income ?? 0), minusText, adbizAmount(r?.card ?? 0)],
                (c.maxWidth - gapW * 2) / 3 - 18, MediaQuery.textScalerOf(context));
            Widget chip(String label, String value, Color mark, Color color, String k) => Expanded(
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(9, 8, 9, 9),
                    decoration: BoxDecoration(
                      color: AppColors.adbBg.withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.adbLine),
                    ),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Container(width: 8, height: 8, decoration: BoxDecoration(color: mark, borderRadius: BorderRadius.circular(2))),
                        ),
                        const SizedBox(width: 5),
                        Expanded(child: Text(label, style: TextStyle(fontSize: 11.5, color: AppColors.adbTextSoft))),
                      ]),
                      const SizedBox(height: 3),
                      Text(value, key: ValueKey(k), maxLines: 1, softWrap: false,
                          style: TextStyle(fontSize: vs, fontWeight: FontWeight.w600, color: color)),
                    ]),
                  ),
                );
            return IntrinsicHeight(
              child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                chip(s.t('adb_income'), adbizAmount(r?.income ?? 0), AppColors.adbIncome, AppColors.adbText, 'adb-income'),
                const SizedBox(width: gapW),
                // "Mənfi", red, always with "-" (owner, 22.11.2026).
                chip(s.t('adb_minus'), minusText, AppColors.adbSpend, AppColors.adbSpend, 'adb-minus'),
                const SizedBox(width: gapW),
                chip(s.t('adb_card_moved'), adbizAmount(r?.card ?? 0), AppColors.adbNet, AppColors.adbText, 'adb-card'),
              ]),
            );
          }),
        ]),
      ),
    ]);
    final soft = TextStyle(fontSize: 15, color: AppColors.adbTextSoft);
    // The card money is the third part of the totals (owner, 21.11.2026);
    // the old "Kartla … · Nağd …" line is gone.
    final daysLine = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(children: [
        Icon(Icons.calendar_today_outlined, size: 20, color: AppColors.adbTextSoft),
        const SizedBox(width: 10),
        Flexible(
          child: Text('${s.t('adb_days_open')}: ${r?.daysOpen ?? 0}  ·  ${s.t('adb_days_closed')}: ${r?.daysClosed ?? 0}',
              key: const ValueKey('adb-days-line'), style: soft),
        ),
      ]),
    );

    // 3. İşçilər + "İşçi əlavə et".
    final workersHead = Row(children: [
      Expanded(child: Text(s.t('adb_workers'), style: title)),
      if (canStaff)
        FilledButton.icon(
          key: const ValueKey('adb-add-member'),
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.adbTeal,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          onPressed: _busy ? null : () => _addMember(s, chief: chief),
          icon: const Icon(Icons.add),
          label: Text(s.t(chief ? 'adb_add_member' : 'adb_add_worker'), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
        ),
    ]);
    final workerRows = <Widget>[
      if (r != null && r.workers.isEmpty)
        Padding(padding: const EdgeInsets.all(12), child: Text(s.t('adb_no_workers'), style: soft)),
      for (final w in r?.workers ?? const <AdbizWorkerSum>[])
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: AdbizWorkerRow(
            key: ValueKey('adb-worker-${w.userId}'),
            s: s,
            w: w,
            showCard: v113,
            onTap: () => _openWorker(w),
            menu: PopupMenuButton<String>(
              key: ValueKey('adb-member-menu-${w.userId}'),
              icon: Icon(Icons.more_horiz, color: AppColors.adbTextSoft),
              onSelected: (v) => switch (v) {
                'days' => _openWorker(w),
                'task' => _workerTask(s, w),
                'active' => _run(s, () => ref.read(adbizRepositoryProvider).memberSetActive(w.userId, !w.isActive), done: s.t('adb_saved')),
                'target' => _memberTarget(s, w),
                'owner' => _run(s, () => ref.read(adbizRepositoryProvider).memberSet(w.userId, widget.companyId, 'owner'), done: s.t('adb_saved')),
                'worker' => _run(s, () => ref.read(adbizRepositoryProvider).memberSet(w.userId, widget.companyId, 'worker'), done: s.t('adb_saved')),
                _ => null,
              },
              itemBuilder: (_) => [
                PopupMenuItem(value: 'days', child: Text(s.t('adb_open_days'))),
                if (v113) PopupMenuItem(value: 'task', key: ValueKey('adb-menu-task-${w.userId}'), child: Text(s.t('adb_task_worker'))),
                if (canStaff && (chief || w.role == 'worker'))
                  PopupMenuItem(value: 'active', child: Text(s.t(w.isActive ? 'adb_deactivate' : 'adb_activate'))),
                if (chief) PopupMenuItem(value: 'target', child: Text(s.t('adb_personal_target'))),
                if (chief && w.role == 'worker') PopupMenuItem(value: 'owner', child: Text(s.t('adb_make_owner'))),
                if (chief && w.role == 'owner') PopupMenuItem(value: 'worker', child: Text(s.t('adb_make_worker'))),
              ],
            ),
          ),
        ),
    ];

    // 4. Gündəlik hədəf: ✏️ (Baş admin) | the switch (the workers see it or not).
    final monthTarget = ref.watch(adbizMonthTargetProvider(widget.companyId)).valueOrNull;
    final targetCard = company == null
        ? null
        : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            AdbizGlass(
              highlight: true,
              padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
              child: Row(children: [
                Icon(Icons.track_changes, size: 40, color: AppColors.adbTeal),
                Container(width: 1, height: 50, margin: const EdgeInsets.symmetric(horizontal: 14), color: AppColors.adbLine),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(s.t('adb_daily_target'), style: TextStyle(fontSize: 16, color: AppColors.adbText)),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(adbizAmount(company.dailyTarget), key: const ValueKey('adb-company-target-value'),
                          style: TextStyle(fontSize: 30, fontWeight: FontWeight.w600, color: AppColors.adbText)),
                    ),
                  ]),
                ),
                // The target is set by the Baş admin only (0110).
                if (chief)
                  IconButton(
                    key: const ValueKey('adb-company-edit'),
                    icon: Icon(Icons.edit_outlined, color: AppColors.adbText),
                    onPressed: () => _editCompany(s, company),
                  ),
                Container(width: 1, height: 36, margin: const EdgeInsets.symmetric(horizontal: 6), color: AppColors.adbLine),
                Switch(
                  key: const ValueKey('adb-show-target'),
                  value: company.showTarget,
                  activeTrackColor: AppColors.adbTeal,
                  onChanged: !v113 || _busy
                      ? null
                      : (v) => _run(s, () => ref.read(adbizRepositoryProvider).companyShowTarget(company.id, v), done: s.t('adb_saved')),
                ),
              ]),
            ),
            // The monthly target (0133): set by the Baş admin from this month on.
            if (monthTarget != null) ...[
              const SizedBox(height: 10),
              AdbizGlass(
                key: const ValueKey('adb-month-target-card'),
                padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
                child: Row(children: [
                  Icon(Icons.calendar_month_outlined, size: 28, color: AppColors.adbTeal),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(s.t('adb_month_target'), style: TextStyle(fontSize: 15, color: AppColors.adbText)),
                      Text(adbizAmount(monthTarget), key: const ValueKey('adb-month-target-value'),
                          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: AppColors.adbText)),
                    ]),
                  ),
                  if (chief)
                    IconButton(
                      key: const ValueKey('adb-month-target-edit'),
                      icon: Icon(Icons.edit_outlined, color: AppColors.adbText),
                      onPressed: _busy ? null : () => _editMonthTarget(s, monthTarget),
                    ),
                ]),
              ),
            ],
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
              child: Text(!v113 ? s.t('adb_need_sql') : s.t(company.showTarget ? 'adb_show_target' : 'adb_hide_target_note'),
                  key: const ValueKey('adb-show-target-note'), style: TextStyle(fontSize: 13, color: AppColors.adbTextSoft)),
            ),
          ]);

    // 5. The owner's words: the caption instead of "Hədəfə qalan" + the task for everybody.
    final wordsCard = company == null
        ? null
        : AdbizGlass(
            padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Padding(padding: const EdgeInsets.only(top: 2), child: Icon(Icons.campaign_outlined, size: 30, color: AppColors.adbTeal)),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(s.t('adb_words'), style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: AppColors.adbText)),
                  Text(s.t('adb_words_hint'), style: TextStyle(fontSize: 12.5, color: AppColors.adbTextSoft)),
                  const SizedBox(height: 10),
                  if (!v113)
                    Text(s.t('adb_need_sql'), style: TextStyle(color: AppColors.adbTextSoft))
                  else ...[
                    Text(s.t('adb_caption'), style: TextStyle(fontSize: 12.5, color: AppColors.adbTextSoft)),
                    Text(company.targetLabel ?? s.t('adb_to_target'), key: const ValueKey('adb-words-caption'),
                        style: TextStyle(fontSize: 15.5, color: company.targetLabel == null ? AppColors.adbTextSoft : AppColors.adbText)),
                    const SizedBox(height: 8),
                    Text(s.t('adb_task_all'), style: TextStyle(fontSize: 12.5, color: AppColors.adbTextSoft)),
                    Text(company.taskNote ?? s.t('adb_task_none'), key: const ValueKey('adb-words-task'),
                        style: TextStyle(fontSize: 15.5, color: company.taskNote == null ? AppColors.adbTextSoft : AppColors.adbText)),
                    if (company.v114) ...[
                      const SizedBox(height: 8),
                      Text(s.t('adb_result_miss_text'), style: TextStyle(fontSize: 12.5, color: AppColors.adbTextSoft)),
                      Text(company.resultMissText ?? s.t('adb_result_default'), key: const ValueKey('adb-words-miss'),
                          style: TextStyle(fontSize: 15.5, color: company.resultMissText == null ? AppColors.adbTextSoft : AppColors.adbText)),
                      const SizedBox(height: 8),
                      Text(s.t('adb_result_hit_text'), style: TextStyle(fontSize: 12.5, color: AppColors.adbTextSoft)),
                      Text(company.resultHitText ?? s.t('adb_result_default'), key: const ValueKey('adb-words-hit'),
                          style: TextStyle(fontSize: 15.5, color: company.resultHitText == null ? AppColors.adbTextSoft : AppColors.adbText)),
                    ],
                  ],
                ]),
              ),
              if (v113)
                IconButton(
                  key: const ValueKey('adb-words-edit'),
                  icon: Icon(Icons.edit_outlined, color: AppColors.adbText),
                  onPressed: _busy ? null : () => _editWords(s, company),
                ),
            ]),
          );

    // 6. Xərclər.
    final expenses = AdbizGlass(
      padding: const EdgeInsets.fromLTRB(4, 10, 4, 6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(children: [
            Icon(Icons.receipt_long_outlined, color: AppColors.adbSpend),
            const SizedBox(width: 10),
            Expanded(child: Text(s.t('adb_expenses'), style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: AppColors.adbText))),
            TextButton.icon(
              key: const ValueKey('adb-add-expense'),
              style: TextButton.styleFrom(foregroundColor: AppColors.adbTeal),
              onPressed: _busy ? null : () => _addExpense(s),
              icon: const Icon(Icons.add),
              label: Text(s.t('adb_add_expense')),
            ),
          ]),
        ),
        if (exps.isEmpty) Padding(padding: const EdgeInsets.all(12), child: Text(s.t('adb_no_expenses'), style: soft)),
        for (final x in exps)
          ListTile(
            dense: true,
            title: Text(x.title, style: TextStyle(color: AppColors.adbText)),
            subtitle: Text(dmy(x.spentOn), style: TextStyle(color: AppColors.adbTextSoft)),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              Text(money(x.amount), style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.adbSpend)),
              IconButton(visualDensity: VisualDensity.compact, icon: Icon(Icons.edit_outlined, size: 20, color: AppColors.adbNet), onPressed: () => _editExpense(s, x)),
              IconButton(visualDensity: VisualDensity.compact, icon: Icon(Icons.delete_outline, size: 20, color: AppColors.adbSpend), onPressed: () => _deleteExpense(s, x)),
            ]),
          ),
      ]),
    );

    // 7. Arxiv (a tap opens that day).
    final archive = AdbizGlass(
      padding: const EdgeInsets.fromLTRB(4, 10, 4, 6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(children: [
            Icon(Icons.inventory_2_outlined, color: AppColors.adbTeal),
            const SizedBox(width: 10),
            Text(s.t('adb_archive'), style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: AppColors.adbText)),
          ]),
        ),
        if ((r?.byDay ?? const []).isEmpty) Padding(padding: const EdgeInsets.all(12), child: Text(s.t('adb_no_days'), style: soft)),
        for (final (d, v) in r?.byDay ?? const <(DateTime, double)>[])
          ListTile(
            dense: true,
            leading: Icon(Icons.event_note_outlined, color: AppColors.adbTextSoft),
            title: Text(dmy(d), style: TextStyle(color: AppColors.adbText)),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              Text(money(v), style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.adbIncome)),
              IconButton(
                key: ValueKey('adb-arch-del-${isoDate(d)}'),
                tooltip: s.t('adb_delete_day'),
                visualDensity: VisualDensity.compact,
                icon: Icon(Icons.delete_outline, size: 20, color: AppColors.adbSpend),
                onPressed: _busy ? null : () => _deleteDayOn(s, d, r?.workers ?? const []),
              ),
            ]),
            onTap: () => _setView(AdbizPeriod.day, d),
          ),
      ]),
    );

    // Ay / İl: the month or year cards of the owner's picture (0115).
    Widget? cards;
    if (_period != AdbizPeriod.day) {
      final per = ref.watch(adbizPeriodsProvider((companyId: widget.companyId, year: _date.year)));
      final lang = ref.watch(currentLocaleProvider).languageCode;
      String cap(String t) => t.isEmpty ? t : t[0].toUpperCase() + t.substring(1);
      if (per.hasError) {
        cards = Text(per.error is AdbizNotReady ? s.t('adb_need_sql115') : adbizError(s, per.error!),
            key: const ValueKey('adb-cards-wait'), style: TextStyle(color: AppColors.adbTextSoft));
      } else if (per.valueOrNull != null) {
        final p = per.valueOrNull!;
        final maxNet = [for (final x in _period == AdbizPeriod.month ? p.months : p.years) x.net]
            .fold<double>(0, (a, b) => b > a ? b : a);
        final items = _period == AdbizPeriod.month
            ? [
                for (final m in p.months)
                  AdbizPeriodTile(
                    key: ValueKey('adb-month-${m.key}'),
                    title: cap(monthName(m.key, lang)),
                    sum: m,
                    maxNet: maxNet,
                    gapLabel: s.t('adb_row_gap', {'amount': AdbizPeriodTile.whole(m.gap)}),
                    selected: m.key == _date.month,
                    onTap: () => _setView(AdbizPeriod.month, DateTime(_date.year, m.key, 1)),
                  ),
              ]
            : [
                for (final y in p.years)
                  AdbizPeriodTile(
                    key: ValueKey('adb-year-${y.key}'),
                    title: '${y.key}',
                    sum: y,
                    maxNet: maxNet,
                    gapLabel: s.t('adb_row_gap', {'amount': AdbizPeriodTile.whole(y.gap)}),
                    selected: y.key == _date.year,
                    onTap: () => _setView(AdbizPeriod.month, DateTime(y.key, 1, 1)),
                  ),
              ];
        final sel = _period == AdbizPeriod.month ? p.months.where((m) => m.key == _date.month).firstOrNull : null;
        final soft = TextStyle(fontSize: 13.5, color: AppColors.adbTextSoft);
        cards = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          // Variant A (owner, 22.11.2026): one row per month / year.
          for (final t in items) Padding(padding: const EdgeInsets.only(bottom: 6), child: t),
          const SizedBox(height: 8),
          Text(s.t('adb_tiles_legend'), key: const ValueKey('adb-tiles-legend'), style: TextStyle(fontSize: 12.5, color: AppColors.adbTextSoft)),
          // The chosen month's old account (figures from before the program), ✏️ to fix.
          if (_period == AdbizPeriod.month) ...[
            const SizedBox(height: 10),
            AdbizGlass(
              key: const ValueKey('adb-old-month'),
              padding: const EdgeInsets.fromLTRB(14, 8, 4, 8),
              child: Row(children: [
                Icon(Icons.history, color: AppColors.adbTeal),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${s.t('adb_old_account')} · ${cap(monthName(_date.month, lang))}',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.adbText)),
                    Text(
                        sel?.imported == true
                            ? '${s.t('adb_old_net')}: ${AdbizPeriodTile.whole(sel!.impNet)}  ·  ${s.t('adb_old_gap_short')}: ${AdbizPeriodTile.whole(sel.impGap)}'
                            : s.t('adb_old_account_none'),
                        key: const ValueKey('adb-old-month-text'),
                        style: soft),
                  ]),
                ),
                IconButton(
                  key: const ValueKey('adb-old-month-edit'),
                  icon: Icon(Icons.edit_outlined, color: AppColors.adbText),
                  onPressed: _busy ? null : () => _editOldMonth(s, _date.year, _date.month, cap(monthName(_date.month, lang)), sel),
                ),
              ]),
            ),
          ],
        ]);
      }
    }

    Widget body;
    if (rep.hasError && r == null) {
      body = Center(
          child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(adbizError(s, rep.error!), textAlign: TextAlign.center, style: TextStyle(color: AppColors.adbText))));
    } else {
      body = LayoutBuilder(builder: (context, c) {
        final wide = c.maxWidth >= 900;
        const gap = SizedBox(height: 14);
        final left = <Widget>[
          periodBar,
          gap,
          totals,
          gap,
          if (cards != null) ...[cards, gap],
          daysLine,
          const SizedBox(height: 22),
          workersHead,
          const SizedBox(height: 12),
          ...workerRows,
        ];
        final right = <Widget>[
          if (targetCard != null) ...[targetCard, gap],
          if (wordsCard != null) ...[wordsCard, gap],
          expenses,
          gap,
          archive,
        ];
        return RefreshIndicator(
          onRefresh: () async => _refresh(),
          child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: [
            if (wide)
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(flex: 3, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: left)),
                const SizedBox(width: 16),
                Expanded(flex: 2, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: right)),
              ])
            else ...[
              ...left,
              const SizedBox(height: 4),
              ...right,
            ],
          ]),
        );
      });
    }
    return Scaffold(
      backgroundColor: AppColors.adbBg,
      appBar: AppBar(
        toolbarHeight: 72,
        backgroundColor: AppColors.adbBg,
        surfaceTintColor: Colors.transparent,
        foregroundColor: AppColors.adbText,
        titleSpacing: 0,
        title: Row(children: [
          const UtepLogo(height: 36),
          Container(width: 1.5, height: 40, margin: const EdgeInsets.symmetric(horizontal: 14), color: AppColors.adbLine),
          Flexible(
            child: Text(company?.name ?? me?.companyName ?? 'UTEP Reklam', maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: AppColors.adbText)),
          ),
        ]),
        actions: [
          PopupMenuButton<String>(
            key: const ValueKey('adb-profile-menu'),
            tooltip: '',
            offset: const Offset(0, 56),
            onSelected: (v) {
              switch (v) {
                case 'refresh':
                  _refresh();
                case 'edit':
                  if (company != null) _editCompany(s, company);
                case 'active':
                  if (company != null) _run(s, () => ref.read(adbizRepositoryProvider).companySetActive(company.id, !company.isActive));
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                enabled: false,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(company?.name ?? me?.companyName ?? '', style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.text)),
                  Text(s.t(chief ? 'adb_admin' : 'adb_role_owner'), style: TextStyle(fontSize: 12, color: AppColors.textSoft)),
                ]),
              ),
              PopupMenuItem(value: 'refresh', child: Text(s.t('adb_refresh'))),
              if (chief && company != null) ...[
                PopupMenuItem(value: 'edit', child: Text(s.t('adb_edit_company'))),
                PopupMenuItem(
                  value: 'active',
                  key: const ValueKey('adb-company-active'),
                  child: Text(s.t(company.isActive ? 'adb_company_active' : 'adb_company_off'),
                      style: TextStyle(color: company.isActive ? AppColors.online : AppColors.danger)),
                ),
              ],
            ],
            child: Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                CircleAvatar(
                  radius: 24,
                  backgroundColor: AppColors.adbPanelHi,
                  child: Icon(Icons.person_outline, color: AppColors.adbText, size: 28),
                ),
                const SizedBox(width: 4),
                Icon(Icons.keyboard_arrow_down, color: AppColors.adbText),
              ]),
            ),
          ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
            colors: [AppColors.adbBgGlow, AppColors.adbBg, AppColors.adbBg, AppColors.adbBgGlow],
            stops: const [0, 0.3, 0.75, 1],
          ),
        ),
        child: SafeArea(top: false, child: body),
      ),
    );
  }
}

/// A panel of the owner's picture: dark teal glass (light by day);
/// [highlight] = the brighter teal edge of the totals / target cards.
class AdbizGlass extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final bool highlight;
  const AdbizGlass({super.key, required this.child, this.padding = const EdgeInsets.all(14), this.highlight = false});

  @override
  Widget build(BuildContext context) => Container(
        padding: padding,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: highlight ? [AppColors.adbPanelHi, AppColors.adbPanel] : [AppColors.adbPanel, AppColors.adbPanel],
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: highlight ? AppColors.adbTeal.withValues(alpha: 0.55) : AppColors.adbLine, width: highlight ? 1.3 : 1),
          boxShadow: highlight ? [BoxShadow(color: AppColors.adbTeal.withValues(alpha: 0.16), blurRadius: 18)] : null,
        ),
        child: child,
      );
}

/// Gün · Ay · İl as rounded pills (the owner's picture).
class AdbizPeriodPills extends StatelessWidget {
  final AppStrings s;
  final AdbizPeriod value;
  final ValueChanged<AdbizPeriod> onChanged;
  const AdbizPeriodPills({super.key, required this.s, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final items = [
      (AdbizPeriod.day, s.t('adb_period_day')),
      (AdbizPeriod.month, s.t('adb_period_month')),
      (AdbizPeriod.year, s.t('adb_period_year')),
    ];
    return Container(
      key: const ValueKey('adb-period'),
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(30), border: Border.all(color: AppColors.adbLine)),
      child: Row(children: [
        for (final (p, label) in items)
          Expanded(
            child: GestureDetector(
              key: ValueKey('adb-period-${p.name}'),
              behavior: HitTestBehavior.opaque,
              onTap: () => onChanged(p),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(26),
                  color: p == value ? AppColors.adbTeal.withValues(alpha: AppColors.isDay ? 1 : 0.45) : null,
                ),
                child: Text(label,
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: p == value ? FontWeight.w500 : FontWeight.w400,
                        color: p == value ? (AppColors.isDay ? Colors.white : AppColors.adbText) : AppColors.adbText)),
              ),
            ),
          ),
      ]),
    );
  }
}

/// One big number of the totals card: icon, label, amount.
class AdbizBigStat extends StatelessWidget {
  final IconData icon;
  final String label, value;
  final Color color;
  final String? valueKey;

  /// Four in a row (owner, 21.11.2026): smaller, the label on two lines.
  final bool compact;

  /// The amount's size, the same for the four (adbizFitSize).
  final double? valueSize;
  const AdbizBigStat(
      {super.key,
      required this.icon,
      required this.label,
      required this.value,
      required this.color,
      this.valueKey,
      this.compact = false,
      this.valueSize});

  @override
  Widget build(BuildContext context) => Column(children: [
        Icon(icon, color: color, size: compact ? 24 : 32),
        const SizedBox(height: 8),
        SizedBox(
          height: compact ? 34 : null,
          child: Center(
            child: Text(label,
                textAlign: TextAlign.center,
                maxLines: compact ? 2 : 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: compact ? 12.5 : 15, height: 1.15, color: AppColors.adbText)),
          ),
        ),
        const SizedBox(height: 6),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: compact ? 2 : 0),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(value,
                key: valueKey == null ? null : ValueKey<String>(valueKey!),
                style: TextStyle(fontSize: valueSize ?? (compact ? 20 : 30), fontWeight: FontWeight.w600, color: color)),
          ),
        ),
      ]);
}

/// A worker of the owner's picture: avatar, name + role, the money (and
/// what of it came by card), ⋯.
class AdbizWorkerRow extends StatelessWidget {
  final AppStrings s;
  final AdbizWorkerSum w;
  final bool showCard;
  final VoidCallback onTap;
  final Widget menu;
  const AdbizWorkerRow({super.key, required this.s, required this.w, required this.showCard, required this.onTap, required this.menu});

  @override
  Widget build(BuildContext context) {
    final owner = w.role == 'owner';
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: AdbizGlass(
        padding: const EdgeInsets.fromLTRB(14, 12, 4, 12),
        child: Row(children: [
          CircleAvatar(
            radius: 26,
            backgroundColor: (owner ? AppColors.adbTeal : AppColors.adbNet).withValues(alpha: 0.18),
            child: Icon(owner ? Icons.workspace_premium_outlined : Icons.person_outline,
                color: owner ? AppColors.adbTeal : AppColors.adbNet, size: 28),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(w.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: w.isActive ? AppColors.adbText : AppColors.adbTextSoft)),
              Text([
                s.t(owner ? 'adb_role_owner' : 'adb_role_worker'),
                if (!w.isActive) s.t('adb_inactive'),
                if (w.personalTarget != null) '${s.t('adb_target_short')}: ${adbizAmount(w.personalTarget!)}',
              ].join(' · '), style: TextStyle(fontSize: 14, color: AppColors.adbTextSoft)),
            ]),
          ),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(adbizAmount(w.total), key: ValueKey('adb-worker-total-${w.userId}'),
                style: TextStyle(fontSize: 19, fontWeight: FontWeight.w600, color: AppColors.adbIncome)),
            if (showCard && w.card > 0)
              Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.credit_card, size: 14, color: AppColors.adbNet),
                const SizedBox(width: 4),
                Text(adbizAmount(w.card), key: ValueKey('adb-worker-card-${w.userId}'),
                    style: TextStyle(fontSize: 13, color: AppColors.adbNet)),
              ]),
          ]),
          menu,
        ]),
      ),
    );
  }
}

/// The owner's words (0113): the caption instead of "Hədəfə qalan" and the
/// task for every worker; with 0114 also the day-result messages (below /
/// at the target). Empty = none / the app's own words.
class AdbizWordsDialog extends StatefulWidget {
  final AppStrings s;
  final AdbizCompany company;
  const AdbizWordsDialog({super.key, required this.s, required this.company});

  @override
  State<AdbizWordsDialog> createState() => _AdbizWordsDialogState();
}

class _AdbizWordsDialogState extends State<AdbizWordsDialog> {
  late final _label = TextEditingController(text: widget.company.targetLabel ?? '');
  late final _task = TextEditingController(text: widget.company.taskNote ?? '');
  late final _miss = TextEditingController(text: widget.company.resultMissText ?? '');
  late final _hit = TextEditingController(text: widget.company.resultHitText ?? '');

  AppStrings get s => widget.s;

  @override
  void dispose() {
    for (final c in [_label, _task, _miss, _hit]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(s.t('adb_words')),
        scrollable: true,
        content: SizedBox(
          width: 460,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              key: const ValueKey('adb-words-label-field'),
              controller: _label,
              maxLength: 60,
              decoration: InputDecoration(labelText: s.t('adb_caption'), hintText: s.t('adb_to_target'), helperText: s.t('adb_caption_hint')),
            ),
            const SizedBox(height: 8),
            TextField(
              key: const ValueKey('adb-words-task-field'),
              controller: _task,
              maxLength: 500,
              minLines: 3,
              maxLines: 6,
              decoration: InputDecoration(labelText: s.t('adb_task_all'), helperText: s.t('adb_words_hint')),
            ),
            if (widget.company.v114) ...[
              const SizedBox(height: 8),
              TextField(
                key: const ValueKey('adb-words-miss-field'),
                controller: _miss,
                maxLength: 200,
                minLines: 2,
                maxLines: 4,
                decoration: InputDecoration(
                    labelText: s.t('adb_result_miss_text'),
                    hintText: s.t('adb_result_minus', {'left': '{qalan}'}),
                    helperText: s.t('adb_result_text_hint'),
                    helperMaxLines: 3),
              ),
              const SizedBox(height: 8),
              TextField(
                key: const ValueKey('adb-words-hit-field'),
                controller: _hit,
                maxLength: 200,
                minLines: 2,
                maxLines: 4,
                decoration: InputDecoration(
                    labelText: s.t('adb_result_hit_text'),
                    hintText: s.t('adb_result_reached', {'net': '{gəlir}', 'target': '{hədəf}'}),
                    helperText: s.t('adb_result_text_hint'),
                    helperMaxLines: 3),
              ),
            ],
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(s.t('common_cancel'))),
          FilledButton(
            key: const ValueKey('adb-words-save'),
            onPressed: () => Navigator.pop(context, (_label.text.trim(), _task.text.trim(), _miss.text.trim(), _hit.text.trim())),
            child: Text(s.t('adb_save')),
          ),
        ],
      );
}

/// Baş admin: find an existing account and choose Sahibkar / İşçi.
class AdbizUserPicker extends ConsumerStatefulWidget {
  final AppStrings s;
  const AdbizUserPicker({super.key, required this.s});

  @override
  ConsumerState<AdbizUserPicker> createState() => _AdbizUserPickerState();
}

class _AdbizUserPickerState extends ConsumerState<AdbizUserPicker> {
  final _q = TextEditingController();
  List<AdbizUserHit> _hits = const [];
  bool _loading = false;
  String _role = 'worker';
  String? _error;

  AppStrings get s => widget.s;

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    if (_q.text.trim().length < 2) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await ref.read(adbizRepositoryProvider).searchUsers(_q.text.trim());
      if (mounted) setState(() => _hits = r);
    } catch (e) {
      if (mounted) setState(() => _error = adbizError(s, e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(s.t('adb_add_member')),
        content: SizedBox(
          width: 480,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SegmentedButton<String>(
              segments: [
                ButtonSegment(value: 'worker', label: Text(s.t('adb_role_worker'))),
                ButtonSegment(value: 'owner', label: Text(s.t('adb_role_owner'))),
              ],
              selected: {_role},
              showSelectedIcon: false,
              onSelectionChanged: (v) => setState(() => _role = v.first),
            ),
            const SizedBox(height: 10),
            TextField(
              key: const ValueKey('adb-user-search'),
              controller: _q,
              autofocus: true,
              decoration: InputDecoration(
                labelText: s.t('adb_search_user'),
                suffixIcon: IconButton(icon: const Icon(Icons.search), onPressed: _search),
              ),
              onSubmitted: (_) => _search(),
            ),
            if (_loading) const Padding(padding: EdgeInsets.all(12), child: Center(child: CircularProgressIndicator())),
            if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error!, style: TextStyle(color: AppColors.danger))),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 320),
              child: ListView(shrinkWrap: true, children: [
                for (final h in _hits)
                  ListTile(
                    key: ValueKey('adb-hit-${h.id}'),
                    title: Text(h.name),
                    subtitle: Text([
                      if ((h.email ?? '').isNotEmpty) h.email!,
                      if (h.companyName != null) '${h.companyName} · ${s.t(h.role == 'owner' ? 'adb_role_owner' : 'adb_role_worker')}',
                    ].join('\n')),
                    trailing: const Icon(Icons.add_circle_outline),
                    onTap: () => Navigator.pop(context, (h, _role)),
                  ),
              ]),
            ),
          ]),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: Text(s.t('common_cancel')))],
      );
}

/// Baş admin: a company's name, daily target and whether its owner may add /
/// take off workers.
/// Work days a month counts for the daily target (owner, 22.11.2026: "6110
/// yazıram, sistem onu 26 iş gününə bölür").
const int kAdbizWorkDays = 26;

/// The daily target from the monthly one: 6110 → 235, 7000 → 269.23 (the
/// server keeps two decimals).
double adbizDailyFromMonthly(double month) => month <= 0 ? 0 : (month / kAdbizWorkDays * 100).roundToDouble() / 100;

/// "Gündəlik hədəf: 6110 / 26 = 235 AZN".
String adbizDailyLine(AppStrings s, double month) => s.t('adb_daily_from_month', {
      'month': adbizNum(month),
      'days': '$kAdbizWorkDays',
      'day': adbizAmount(adbizDailyFromMonthly(month)),
    });

/// What the company dialog gives back.
class AdbizCompanyForm {
  final String name;
  final double monthTarget;
  final bool ownerManagesStaff;
  const AdbizCompanyForm(this.name, this.monthTarget, this.ownerManagesStaff);
  double get dailyTarget => adbizDailyFromMonthly(monthTarget);
}

/// A company (Baş admin): name, the MONTHLY target (the daily one is worked
/// out from it, shown live under the field) and the owner's staff switch.
class AdbizCompanyDialog extends StatefulWidget {
  final AppStrings s;
  final AdbizCompany? company;

  /// The month's target already saved (0133); null = worked out from the
  /// daily one (× 26).
  final double? monthTarget;
  const AdbizCompanyDialog({super.key, required this.s, this.company, this.monthTarget});

  @override
  State<AdbizCompanyDialog> createState() => _AdbizCompanyDialogState();
}

class _AdbizCompanyDialogState extends State<AdbizCompanyDialog> {
  late final _name = TextEditingController(text: widget.company?.name ?? '');
  late final _target = TextEditingController(
      text: widget.monthTarget != null
          ? adbizNum(widget.monthTarget!)
          : (widget.company == null ? '' : adbizNum((widget.company!.dailyTarget * kAdbizWorkDays).roundToDouble())));
  late bool _staff = widget.company?.ownerManagesStaff ?? false;
  String? _error;

  AppStrings get s => widget.s;

  @override
  void dispose() {
    _name.dispose();
    _target.dispose();
    super.dispose();
  }

  void _ok() {
    final t = _target.text.trim().isEmpty ? 0.0 : parseAmount(_target.text);
    if (_name.text.trim().length < 2 || t == null) {
      setState(() => _error = s.t('adb_err_form'));
      return;
    }
    Navigator.pop(context, AdbizCompanyForm(_name.text.trim(), t, _staff));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(s.t(widget.company == null ? 'adb_new_company' : 'adb_edit_company')),
        scrollable: true,
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          TextField(key: const ValueKey('adb-company-name'), controller: _name, maxLength: 80, decoration: InputDecoration(labelText: s.t('adb_company_name'))),
          TextField(
            key: const ValueKey('adb-company-target'),
            controller: _target,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(labelText: s.t('adb_month_target'), suffixText: 'AZN'),
          ),
          const SizedBox(height: 6),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: _target,
            builder: (_, v, __) => Text(adbizDailyLine(s, parseAmount(v.text) ?? 0),
                key: const ValueKey('adb-company-daily-line'), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
          ),
          const SizedBox(height: 4),
          Text(s.t('adb_target_note'), style: TextStyle(fontSize: 12, color: AppColors.textSoft)),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _staff,
            onChanged: (v) => setState(() => _staff = v),
            title: Text(s.t('adb_owner_manages_staff')),
          ),
          if (_error != null) Text(_error!, style: TextStyle(color: AppColors.danger)),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(s.t('common_cancel'))),
          FilledButton(key: const ValueKey('adb-company-save'), onPressed: _ok, child: Text(s.t('adb_save'))),
        ],
      );
}

/// The panel's "Ümumi mənfi" of one day (owner, 22.11.2026): income − rasxod
/// − the targets of that date's days (every worker's, open or closed).
/// null while a worker's days are still loading.
double? adbizDayGap(AdbizReport r, List<List<AdbizDay>?> daysPerWorker, DateTime date) {
  var targets = 0.0;
  for (final days in daysPerWorker) {
    if (days == null) return null;
    for (final d in days) {
      if (d.workDate.year == date.year && d.workDate.month == date.month && d.workDate.day == date.day) targets += d.target;
    }
  }
  return r.income - r.expenses - targets;
}

/// "Mənfi" as shown (owner, 22.11.2026: "+3530.50 AZN yerinə sadəcə
/// -3530.50 yazılsın"): always with "-" ("-3530.50 AZN"), 0 as "0 AZN",
/// still loading "…".
String adbizMinusText(double? gap) {
  if (gap == null) return '…';
  final v = ((gap.abs()) * 100).roundToDouble() / 100;
  return v == 0 ? adbizAmount(0) : '-${adbizAmount(v)}';
}

/// A month / year row (owner's variant A, 22.11.2026 — replaces the green /
/// red cards of 10.11.2026): the name, a bar as long as its net income
/// against the largest of the list, the net and under it the days' minus /
/// plus (the same signed figure the red half showed); a tap opens that month
/// (or that year's months).
class AdbizPeriodTile extends StatelessWidget {
  final String title;
  final AdbizPeriodSum sum;
  final bool selected;
  final double maxNet;
  final String gapLabel;
  final VoidCallback onTap;
  const AdbizPeriodTile(
      {super.key, required this.title, required this.sum, required this.onTap, this.selected = false, this.maxNet = 0, this.gapLabel = ''});

  static String whole(double v) => '${v.round()} AZN';

  /// A plain amount for a field: 5784 → "5784", 12.5 → "12.5".
  static String num(double v) => v == v.roundToDouble() ? '${v.toInt()}' : '$v';

  /// The bar's share (0–1): net / the list's largest net; nothing for ≤ 0.
  static double share(double net, double maxNet) => maxNet <= 0 || net <= 0 ? 0 : (net / maxNet).clamp(0.0, 1.0);

  @override
  Widget build(BuildContext context) {
    final f = share(sum.net, maxNet);
    return Material(
      color: selected ? AppColors.adbPanelHi : AppColors.adbPanel,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: selected ? AppColors.adbTeal : AppColors.adbLine, width: selected ? 1.6 : 1),
          ),
          child: Row(children: [
            SizedBox(
              width: 74,
              child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.adbText)),
            ),
            Expanded(
              child: Container(
                height: 8,
                alignment: Alignment.centerLeft,
                decoration: BoxDecoration(color: AppColors.adbLine, borderRadius: BorderRadius.circular(4)),
                child: FractionallySizedBox(
                  key: ValueKey('adb-tile-bar-$title'),
                  widthFactor: f,
                  heightFactor: 1,
                  child: Container(decoration: BoxDecoration(color: AppColors.adbIncome, borderRadius: BorderRadius.circular(4))),
                ),
              ),
            ),
            const SizedBox(width: 12),
            // Never past the edge: a long amount / language shrinks a little.
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: [
                  Text(whole(sum.net), key: ValueKey('adb-tile-net-$title'),
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.adbText)),
                  Text(gapLabel, key: ValueKey('adb-tile-gap-$title'), style: TextStyle(fontSize: 11.5, color: AppColors.adbSpend)),
                ]),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

/// A month's old figures (0116): net income and the minus / plus (signed);
/// "Sil" takes them off (the month then shows only the program's days).
class AdbizOldMonthDialog extends StatefulWidget {
  final AppStrings s;
  final String title;
  final AdbizPeriodSum? sum;
  const AdbizOldMonthDialog({super.key, required this.s, required this.title, this.sum});

  @override
  State<AdbizOldMonthDialog> createState() => _AdbizOldMonthDialogState();
}

class _AdbizOldMonthDialogState extends State<AdbizOldMonthDialog> {
  late final _net = TextEditingController(text: widget.sum?.imported == true ? AdbizPeriodTile.num(widget.sum!.impNet) : '');
  late final _gap = TextEditingController(text: widget.sum?.imported == true ? AdbizPeriodTile.num(widget.sum!.impGap) : '');
  String? _error;

  AppStrings get s => widget.s;

  @override
  void dispose() {
    _net.dispose();
    _gap.dispose();
    super.dispose();
  }

  void _ok() {
    final net = _net.text.trim().isEmpty ? 0.0 : parseSigned(_net.text);
    final gap = _gap.text.trim().isEmpty ? 0.0 : parseSigned(_gap.text);
    if (net == null || gap == null) {
      setState(() => _error = s.t('adb_err_invalid_argument'));
      return;
    }
    Navigator.pop(context, (net, gap));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.title),
        scrollable: true,
        content: SizedBox(
          width: 420,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(s.t('adb_old_hint'), style: TextStyle(fontSize: 13, color: AppColors.textSoft)),
            const SizedBox(height: 10),
            TextField(
              key: const ValueKey('adb-old-net'),
              controller: _net,
              keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
              decoration: InputDecoration(labelText: s.t('adb_old_net'), suffixText: 'AZN'),
            ),
            const SizedBox(height: 8),
            TextField(
              key: const ValueKey('adb-old-gap'),
              controller: _gap,
              keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
              decoration: InputDecoration(labelText: s.t('adb_old_gap'), suffixText: 'AZN'),
            ),
            if (_error != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(_error!, style: TextStyle(color: AppColors.danger))),
          ]),
        ),
        actions: [
          if (widget.sum?.imported == true)
            TextButton(
              key: const ValueKey('adb-old-clear'),
              style: TextButton.styleFrom(foregroundColor: AppColors.danger),
              onPressed: () => Navigator.pop(context, (null, null)),
              child: Text(s.t('adb_old_clear')),
            ),
          TextButton(onPressed: () => Navigator.pop(context), child: Text(s.t('common_cancel'))),
          FilledButton(key: const ValueKey('adb-old-save'), onPressed: _ok, child: Text(s.t('adb_save'))),
        ],
      );
}

/// The largest font size (20 → 11) at which every text fits [width] — so the
/// four amounts of the panel stand in one size.
double adbizFitSize(List<String> texts, double width, TextScaler scaler) {
  for (var size = 20.0; size > 11; size -= 0.5) {
    final fits = texts.every((t) {
      final tp = TextPainter(
        text: TextSpan(text: t, style: TextStyle(fontSize: size, fontWeight: FontWeight.w600)),
        textDirection: TextDirection.ltr,
        textScaler: scaler,
        maxLines: 1,
      )..layout();
      return tp.width <= width;
    });
    if (fits) return size;
  }
  return 11;
}
