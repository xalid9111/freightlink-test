import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/localization/app_strings.dart';
import '../../../core/localization/locale_controller.dart';
import '../../../core/router/safe_navigation.dart';
import '../../../core/theme/app_theme.dart';
import '../../finance/domain/finance_models.dart';
import '../data/adbiz_repository.dart';
import '../domain/adbiz_models.dart';
import 'adbiz_notebook_screen.dart' show adbizAmount;
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

  @override
  void initState() {
    super.initState();
    // A day ends at 23:59 Baku: forgotten open days are closed first, then
    // the open / closed counts are read again (0112).
    Future.microtask(() async {
      await ref.read(adbizRepositoryProvider).sweep();
      if (mounted) _refresh();
    });
  }

  void _refresh() {
    ref.invalidate(adbizReportProvider(_key));
    ref.invalidate(adbizExpensesProvider(_key));
    ref.invalidate(adbizCompaniesProvider);
    ref.invalidate(adbizMeProvider);
  }

  void _shift(int dir) => setState(() {
        _date = switch (_period) {
          AdbizPeriod.day => _date.add(Duration(days: dir)),
          AdbizPeriod.month => DateTime(_date.year, _date.month + dir, 1),
          AdbizPeriod.year => DateTime(_date.year + dir, 1, 1),
        };
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
    final r = await showDialog<(String, double, bool)>(context: context, builder: (_) => AdbizCompanyDialog(s: s, company: c));
    if (r == null || !mounted) return;
    await _run(s, () => ref.read(adbizRepositoryProvider).companySave(id: c.id, name: r.$1, dailyTarget: r.$2, ownerManagesStaff: r.$3),
        done: s.t('adb_saved'));
  }

  // ---- the owner's words, the target switch, a worker's task (0113) ---------------------
  Future<void> _editWords(AppStrings s, AdbizCompany c) async {
    final r = await showDialog<(String, String)>(context: context, builder: (_) => AdbizWordsDialog(s: s, company: c));
    if (r == null || !mounted) return;
    await _run(s, () => ref.read(adbizRepositoryProvider).companyTexts(c.id, r.$1, r.$2), done: s.t('adb_saved'));
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

  void _openWorker(AdbizWorkerSum w) =>
      context.pushOnce(Uri(path: '/profile/adbiz/worker/${w.userId}', queryParameters: {'name': w.name}).toString());

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
        final pills = AdbizPeriodPills(s: s, value: _period, onChanged: (v) => setState(() => _period = v));
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

    // 2. Ümumi gəlir · Xərclər · Xalis mənfəət.
    final sep = Container(width: 1, height: 70, color: AppColors.adbLine);
    final totals = AdbizGlass(
      highlight: true,
      padding: const EdgeInsets.fromLTRB(8, 20, 8, 20),
      child: Row(children: [
        Expanded(child: AdbizBigStat(icon: Icons.trending_up, label: s.t('adb_income'), value: adbizAmount(r?.income ?? 0), color: AppColors.adbIncome, valueKey: 'adb-income')),
        sep,
        Expanded(child: AdbizBigStat(icon: Icons.receipt_long_outlined, label: s.t('adb_expenses'), value: adbizAmount(r?.expenses ?? 0), color: AppColors.adbSpend, valueKey: 'adb-expenses')),
        sep,
        Expanded(child: AdbizBigStat(icon: Icons.account_balance_wallet_outlined, label: s.t('adb_net'), value: adbizAmount(r?.net ?? 0), color: AppColors.adbNet, valueKey: 'adb-net')),
      ]),
    );
    final soft = TextStyle(fontSize: 15, color: AppColors.adbTextSoft);
    // Card money apart (owner, 10.11.2026): "Kartla … · Nağd …".
    final cardLine = !v113
        ? null
        : Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(children: [
              Icon(Icons.credit_card, size: 20, color: AppColors.adbNet),
              const SizedBox(width: 10),
              Flexible(
                child: Text.rich(
                  TextSpan(children: [
                    TextSpan(text: '${s.t('adb_card_total')}: '),
                    TextSpan(text: adbizAmount(r?.card ?? 0), style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.adbNet)),
                    TextSpan(text: '  ·  ${s.t('adb_cash_total')}: '),
                    TextSpan(text: adbizAmount(r?.cash ?? 0), style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.adbIncome)),
                  ]),
                  key: const ValueKey('adb-card-line'),
                  style: soft,
                ),
              ),
            ]),
          );
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
            trailing: Text(money(v), style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.adbIncome)),
            onTap: () => setState(() {
              _period = AdbizPeriod.day;
              _date = d;
            }),
          ),
      ]),
    );

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
          const SizedBox(height: 12),
          if (cardLine != null) ...[cardLine, const SizedBox(height: 10)],
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
  const AdbizBigStat({super.key, required this.icon, required this.label, required this.value, required this.color, this.valueKey});

  @override
  Widget build(BuildContext context) => Column(children: [
        Icon(icon, color: color, size: 32),
        const SizedBox(height: 8),
        Text(label, textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 15, color: AppColors.adbText)),
        const SizedBox(height: 6),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(value, key: valueKey == null ? null : ValueKey<String>(valueKey!), style: TextStyle(fontSize: 30, fontWeight: FontWeight.w600, color: color)),
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
/// task for every worker; empty = none.
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

  AppStrings get s => widget.s;

  @override
  void dispose() {
    _label.dispose();
    _task.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(s.t('adb_words')),
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
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(s.t('common_cancel'))),
          FilledButton(
            key: const ValueKey('adb-words-save'),
            onPressed: () => Navigator.pop(context, (_label.text.trim(), _task.text.trim())),
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
class AdbizCompanyDialog extends StatefulWidget {
  final AppStrings s;
  final AdbizCompany? company;
  const AdbizCompanyDialog({super.key, required this.s, this.company});

  @override
  State<AdbizCompanyDialog> createState() => _AdbizCompanyDialogState();
}

class _AdbizCompanyDialogState extends State<AdbizCompanyDialog> {
  late final _name = TextEditingController(text: widget.company?.name ?? '');
  late final _target = TextEditingController(text: widget.company == null ? '' : widget.company!.dailyTarget.toStringAsFixed(2));
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
    Navigator.pop(context, (_name.text.trim(), t, _staff));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(s.t(widget.company == null ? 'adb_new_company' : 'adb_edit_company')),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(key: const ValueKey('adb-company-name'), controller: _name, maxLength: 80, decoration: InputDecoration(labelText: s.t('adb_company_name'))),
          TextField(
            key: const ValueKey('adb-company-target'),
            controller: _target,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(labelText: s.t('adb_company_target'), suffixText: 'AZN', helperText: s.t('adb_target_note')),
          ),
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
