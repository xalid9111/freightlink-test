import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/localization/locale_controller.dart';
import '../../../core/localization/app_strings.dart';
import '../../../core/theme/app_theme.dart';
import '../../auth/presentation/providers/auth_providers.dart';
import '../../finance/domain/finance_models.dart';
import '../data/adbiz_repository.dart';
import '../domain/adbiz_models.dart';
import 'adbiz_providers.dart';
import 'adbiz_widgets.dart';

/// "Reklam iş dəftəri" (owner, 10.11.2026; the owner's picture of the
/// worker panel, same day): the day → target · collected · rasxod → the
/// money left with how it is worked out and the bar → a new job → the jobs
/// done (no changes by the worker) → the day's expenses → close the day.
/// The owner and the Baş admin open the same page for a worker ([userId])
/// and fix any of his days (the server checks who may).
class AdbizNotebookScreen extends ConsumerStatefulWidget {
  final String? userId;
  final String? userName;
  const AdbizNotebookScreen({super.key, this.userId, this.userName});

  @override
  ConsumerState<AdbizNotebookScreen> createState() => _AdbizNotebookScreenState();
}

class _AdbizNotebookScreenState extends ConsumerState<AdbizNotebookScreen> {
  String? _selected;
  bool _busy = false;

  Future<void> _open(AppStrings s, {required bool manager, required String uid, DateTime? date}) async {
    if (_busy) return; // one tap = one day
    setState(() => _busy = true);
    try {
      final repo = ref.read(adbizRepositoryProvider);
      final id = manager ? await repo.openDayFor(uid, date ?? bakuToday()) : await repo.openDay();
      if (mounted) setState(() => _selected = id);
    } catch (e) {
      if (mounted) adbizSnack(context, adbizError(s, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openOtherDate(AppStrings s, String uid) async {
    final today = bakuToday();
    final d = await showDatePicker(context: context, firstDate: DateTime(today.year - 2), lastDate: today, initialDate: today);
    if (d != null && mounted) await _open(s, manager: true, uid: uid, date: d);
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    ref.watch(currentLocaleProvider);
    final myId = ref.watch(currentUserIdProvider);
    final uid = widget.userId ?? myId;
    final manager = widget.userId != null && widget.userId != myId;
    if (uid == null) return const Scaffold(body: SizedBox.shrink());
    final me = ref.watch(adbizMeProvider).valueOrNull;
    final async = ref.watch(adbizDaysProvider(uid));
    final days = async.valueOrNull ?? const <AdbizDay>[];
    final today = bakuToday();
    AdbizDay? find(String? id) => id == null ? null : days.where((d) => d.id == id).firstOrNull;
    final todayDay = days.where((d) => d.workDate == today).firstOrNull;
    final day = find(_selected) ?? todayDay;
    final history = [for (final d in days) if (d.id != day?.id) d];

    // The person whose notebook this is (the owner's picture: name + role).
    final personName = manager ? (widget.userName ?? '') : (ref.watch(currentUserProvider)?.fullName ?? '');
    final personRole = manager || me?.isWorker == true ? s.t('adb_role_worker') : (me?.isOwner == true ? s.t('adb_role_owner') : '');

    Widget body;
    if (async.isLoading && !async.hasValue) {
      body = const Center(child: CircularProgressIndicator());
    } else if (async.hasError && !async.hasValue) {
      body = Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(adbizError(s, async.error!), textAlign: TextAlign.center)));
    } else {
      body = ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 32), children: [
        if (day == null)
          _OpenDayCard(
            s: s,
            busy: _busy,
            manager: manager,
            onOpen: () => _open(s, manager: manager, uid: uid),
          )
        else
          AdbizDayPanel(key: ValueKey('adb-day-${day.id}'), day: day, s: s, manager: manager, isToday: day.workDate == today),
        if (manager) ...[
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              key: const ValueKey('adb-open-other'),
              onPressed: _busy ? null : () => _openOtherDate(s, uid),
              icon: const Icon(Icons.event_outlined),
              label: Text(s.t('adb_open_other_date')),
            ),
          ),
        ],
        if (history.isNotEmpty) ...[
          const SizedBox(height: 18),
          Text(s.t('adb_history'), style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: AppColors.text)),
          const SizedBox(height: 8),
          for (final d in history.take(60))
            Card(
              margin: const EdgeInsets.only(bottom: 6),
              child: ListTile(
                key: ValueKey('adb-hist-${d.id}'),
                leading: Icon(d.isOpen ? Icons.lock_open : Icons.lock_outline, color: d.isOpen ? AppColors.online : AppColors.textSoft),
                title: Text(dmy(d.workDate)),
                subtitle: Text('${s.t(d.isOpen ? 'adb_day_open' : 'adb_day_closed')} · ${s.t('adb_target')}: ${money(d.target)}'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => setState(() => _selected = d.id),
              ),
            ),
        ],
      ]);
    }
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 64,
        titleSpacing: 0,
        title: _UtepHeader(s: s, name: personName, role: personRole),
      ),
      body: SafeArea(top: false, child: body),
    );
  }
}

/// The owner's picture: the UTEP logo | "UTEP Reklam / Reklam idarəetmə
/// sistemi" | the person (name + role).
class _UtepHeader extends StatelessWidget {
  final AppStrings s;
  final String name, role;
  const _UtepHeader({required this.s, required this.name, required this.role});

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, c) {
        final roomy = c.maxWidth >= 330;
        return Row(children: [
          const UtepLogo(height: 30),
          const SizedBox(width: 10),
          Container(width: 1, height: 34, color: AppColors.line),
          const SizedBox(width: 10),
          Expanded(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('UTEP Reklam', maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: AppColors.text)),
              Text(s.t('adb_system'), maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: AppColors.textSoft)),
            ]),
          ),
          if (roomy && name.isNotEmpty)
            Container(
              key: const ValueKey('adb-person'),
              constraints: const BoxConstraints(maxWidth: 170),
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.fromLTRB(6, 4, 12, 4),
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(30), border: Border.all(color: AppColors.line)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                CircleAvatar(
                  radius: 15,
                  backgroundColor: AppColors.blue.withValues(alpha: 0.18),
                  child: Icon(Icons.person, size: 18, color: AppColors.blue),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(name, maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: AppColors.text)),
                    if (role.isNotEmpty) Text(role, style: TextStyle(fontSize: 11.5, color: AppColors.textSoft)),
                  ]),
                ),
              ]),
            ),
        ]);
      });
}

class _OpenDayCard extends StatelessWidget {
  final AppStrings s;
  final bool busy, manager;
  final VoidCallback onOpen;
  const _OpenDayCard({required this.s, required this.busy, required this.manager, required this.onOpen});

  @override
  Widget build(BuildContext context) => AdbizCard(
        padding: const EdgeInsets.all(20),
        child: Column(children: [
          Icon(Icons.wb_sunny_outlined, size: 44, color: AppColors.accent),
          const SizedBox(height: 10),
          Text(s.t(manager ? 'adb_not_opened_worker' : 'adb_open_hint'),
              textAlign: TextAlign.center, style: TextStyle(fontSize: 15, color: AppColors.text)),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: FilledButton.icon(
              key: const ValueKey('adb-open-day'),
              onPressed: busy ? null : onOpen,
              icon: busy
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.play_arrow_rounded),
              label: Text(s.t('adb_open_day'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
            ),
          ),
        ]),
      );
}

/// One day, in the order of the owner's picture.
class AdbizDayPanel extends ConsumerStatefulWidget {
  final AdbizDay day;
  final AppStrings s;
  final bool manager, isToday;
  const AdbizDayPanel({super.key, required this.day, required this.s, required this.manager, required this.isToday});

  @override
  ConsumerState<AdbizDayPanel> createState() => _AdbizDayPanelState();
}

class _AdbizDayPanelState extends ConsumerState<AdbizDayPanel> {
  final _title = TextEditingController();
  final _amount = TextEditingController();
  final _xTitle = TextEditingController();
  final _xAmount = TextEditingController();
  final _titleFocus = FocusNode();
  final _amountFocus = FocusNode();
  final _xTitleFocus = FocusNode();
  final _xAmountFocus = FocusNode();
  bool _busy = false;
  bool _xBusy = false;
  bool _showExpenses = true;
  String? _error, _xError;

  /// The keys of the job / expense being added: the same for a repeated tap,
  /// a new one after it was saved (the server gives back the same row).
  String _key = adbizClientKey();
  String _xKey = adbizClientKey();

  AppStrings get s => widget.s;
  AdbizDay get day => widget.day;

  /// The worker adds jobs and expenses into his own open day; the owner /
  /// Baş admin into any day of his workers.
  bool get _canAdd => widget.manager || day.isOpen;

  /// Changing / deleting a saved job or expense: only the owner / Baş admin
  /// (owner, 10.11.2026; the server refuses the worker too).
  bool get _canFix => widget.manager;

  @override
  void dispose() {
    for (final c in [_title, _amount, _xTitle, _xAmount]) {
      c.dispose();
    }
    for (final f in [_titleFocus, _amountFocus, _xTitleFocus, _xAmountFocus]) {
      f.dispose();
    }
    super.dispose();
  }

  Future<void> _add() async {
    if (_busy) return;
    final title = _title.text.trim();
    final amount = parseAmount(_amount.text);
    if (title.isEmpty || amount == null) {
      setState(() => _error = s.t('adb_err_form'));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(adbizRepositoryProvider).addEntry(day.id, title, amount, _key);
      _key = adbizClientKey();
      _title.clear();
      _amount.clear();
      if (mounted) _titleFocus.requestFocus();
    } catch (e) {
      // The typed job stays in the form; the same key is used again.
      if (mounted) setState(() => _error = adbizError(s, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _addExpense() async {
    if (_xBusy) return;
    final title = _xTitle.text.trim();
    final amount = parseAmount(_xAmount.text);
    if (title.isEmpty || amount == null) {
      setState(() => _xError = s.t('adb_err_form'));
      return;
    }
    setState(() {
      _xBusy = true;
      _xError = null;
    });
    try {
      await ref.read(adbizRepositoryProvider).addDayExpense(day.id, title, amount, _xKey);
      _xKey = adbizClientKey();
      _xTitle.clear();
      _xAmount.clear();
      if (mounted) _xTitleFocus.requestFocus();
    } catch (e) {
      if (mounted) setState(() => _xError = adbizError(s, e));
    } finally {
      if (mounted) setState(() => _xBusy = false);
    }
  }

  Future<void> _edit(AdbizEntry e) async {
    final r = await askTitleAmount(context, s, heading: s.t('adb_edit_job'), title: e.title, amount: e.amount);
    if (r == null) return;
    try {
      await ref.read(adbizRepositoryProvider).updateEntry(e.id, r.$1, r.$2);
    } catch (err) {
      if (mounted) adbizSnack(context, adbizError(s, err));
    }
  }

  Future<void> _delete(AdbizEntry e) async {
    if (!await adbizConfirm(context, s, s.t('adb_delete_job'), '${e.title} · ${money(e.amount)}', ok: s.t('adb_delete'))) return;
    try {
      await ref.read(adbizRepositoryProvider).deleteEntry(e.id);
    } catch (err) {
      if (mounted) adbizSnack(context, adbizError(s, err));
    }
  }

  Future<void> _editExpense(AdbizExpense x) async {
    final r = await askTitleAmount(context, s, heading: s.t('adb_edit_expense'), title: x.title, amount: x.amount);
    if (r == null) return;
    try {
      await ref.read(adbizRepositoryProvider).expenseSave(id: x.id, spentOn: x.spentOn, title: r.$1, amount: r.$2);
    } catch (err) {
      if (mounted) adbizSnack(context, adbizError(s, err));
    }
  }

  Future<void> _deleteExpense(AdbizExpense x) async {
    if (!await adbizConfirm(context, s, s.t('adb_delete_expense'), '${x.title} · ${money(x.amount)}', ok: s.t('adb_delete'))) return;
    try {
      await ref.read(adbizRepositoryProvider).expenseDelete(x.id);
    } catch (err) {
      if (mounted) adbizSnack(context, adbizError(s, err));
    }
  }

  Future<void> _close(DayProgress p) async {
    if (_busy) return;
    final body = s.t('adb_close_body', {'sum': money(p.net), 'target': money(p.target)});
    if (!await adbizConfirm(context, s, s.t('adb_close_day'), body, ok: s.t('adb_close_day'))) return;
    setState(() => _busy = true);
    try {
      await ref.read(adbizRepositoryProvider).closeDay(day.id);
      if (mounted) adbizSnack(context, s.t('adb_closed_done'));
    } catch (e) {
      if (mounted) adbizSnack(context, adbizError(s, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reopen() async {
    if (_busy) return;
    if (!await adbizConfirm(context, s, s.t('adb_reopen'), s.t('adb_reopen_body'))) return;
    setState(() => _busy = true);
    try {
      await ref.read(adbizRepositoryProvider).reopenDay(day.id);
    } catch (e) {
      if (mounted) adbizSnack(context, adbizError(s, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _fieldIcon(IconData i) => Icon(i, size: 20, color: AppColors.textSoft);

  @override
  Widget build(BuildContext context) {
    final entries = ref.watch(adbizEntriesProvider(day.id)).valueOrNull ?? const <AdbizEntry>[];
    final expenses = ref.watch(adbizDayExpensesProvider(day.id)).valueOrNull ?? const <AdbizExpense>[];
    final p = DayProgress.of(entries, day.target, expenses);

    // 1. Bugünkü iş günü.
    final header = AdbizCard(
      child: Row(children: [
        Icon(Icons.calendar_month_outlined, color: AppColors.accent, size: 30),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(s.t(widget.isToday ? 'adb_today' : 'adb_work_day'),
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: AppColors.text)),
            Text(dmy(day.workDate), style: TextStyle(color: AppColors.textSoft)),
          ]),
        ),
        _StatusChip(s: s, open: day.isOpen),
      ]),
    );

    // 2. Hədəf · Toplanan gəlir · Rasxod → Qalan məbləğ + Hesablanma → bar.
    final numbers = DayMoneyCard(s: s, p: p);

    // 3. Yeni iş əlavə et.
    final form = !_canAdd
        ? null
        : AdbizCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                Icon(Icons.add_circle_outline, color: AppColors.accent),
                const SizedBox(width: 10),
                Text(s.t('adb_new_job'), style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.text)),
              ]),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  flex: 3,
                  child: TextField(
                    key: const ValueKey('adb-job-title'),
                    controller: _title,
                    focusNode: _titleFocus,
                    maxLength: 120,
                    textInputAction: TextInputAction.next,
                    decoration: InputDecoration(
                        hintText: s.t('adb_job_name'), counterText: '', prefixIcon: _fieldIcon(Icons.work_outline)),
                    onSubmitted: (_) => _amountFocus.requestFocus(),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: TextField(
                    key: const ValueKey('adb-job-amount'),
                    controller: _amount,
                    focusNode: _amountFocus,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    textInputAction: TextInputAction.done,
                    decoration: InputDecoration(hintText: s.t('adb_amount'), prefixIcon: _fieldIcon(Icons.payments_outlined)),
                    // Enter saves the job (owner, 10.11.2026).
                    onSubmitted: (_) => _add(),
                  ),
                ),
              ]),
              if (_error != null)
                Padding(padding: const EdgeInsets.only(top: 6), child: Text(_error!, style: TextStyle(color: AppColors.danger))),
              const SizedBox(height: 12),
              SizedBox(
                height: 50,
                child: FilledButton.icon(
                  key: const ValueKey('adb-add-job'),
                  onPressed: _busy ? null : _add,
                  icon: const Icon(Icons.add_circle_outline),
                  label: Text(s.t('adb_add_job'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
                ),
              ),
            ]),
          );

    // 4. Görülən işlər + Cəmi (Gəlir).
    final list = AdbizCard(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          alignment: WrapAlignment.spaceBetween,
          runSpacing: 6,
          spacing: 8,
          children: [
            Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.format_list_bulleted, color: AppColors.accent),
              const SizedBox(width: 10),
              Text('${s.t('adb_jobs_today')} (${entries.length})',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.text)),
            ]),
            if (!_canFix)
              Container(
                key: const ValueKey('adb-fix-admin-only'),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(20), border: Border.all(color: AppColors.line)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.lock_outline, size: 15, color: AppColors.accent),
                  const SizedBox(width: 6),
                  Text(s.t('adb_fix_admin_only'), style: TextStyle(fontSize: 12, color: AppColors.textSoft)),
                ]),
              ),
          ],
        ),
        const SizedBox(height: 10),
        if (entries.isEmpty)
          Padding(padding: const EdgeInsets.all(8), child: Text(s.t('adb_no_jobs'), style: TextStyle(color: AppColors.textSoft))),
        for (var i = 0; i < entries.length; i++)
          _Row(
            key: ValueKey('adb-job-${entries[i].id}'),
            n: i + 1,
            title: entries[i].title,
            time: hhmm(entries[i].createdAt),
            amount: money(entries[i].amount),
            onEdit: _canFix ? () => _edit(entries[i]) : null,
            onDelete: _canFix ? () => _delete(entries[i]) : null,
          ),
        const SizedBox(height: 6),
        _TotalBar(
          icon: Icons.functions,
          label: s.t('adb_total_income'),
          value: money(p.collected),
          color: AppColors.online,
          valueKey: 'adb-total',
        ),
      ]),
    );

    // 5. Rasxod (xərc əlavə et) + Günün xərcləri (Cəmi).
    final expenseCard = AdbizCard(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        LayoutBuilder(builder: (context, c) {
          final label = Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.savings_outlined, color: AppColors.danger, size: 28),
            const SizedBox(width: 8),
            Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(s.t('adb_spent'), style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.text)),
              Text(s.t('adb_add_day_expense'), style: TextStyle(fontSize: 12.5, color: AppColors.textSoft)),
            ]),
          ]);
          if (!_canAdd) return Align(alignment: Alignment.centerLeft, child: label);
          final fields = Row(children: [
            Expanded(
              flex: 3,
              child: TextField(
                key: const ValueKey('adb-exp-title'),
                controller: _xTitle,
                focusNode: _xTitleFocus,
                maxLength: 120,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(hintText: s.t('adb_expense_name'), counterText: '', isDense: true),
                onSubmitted: (_) => _xAmountFocus.requestFocus(),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 2,
              child: TextField(
                key: const ValueKey('adb-exp-amount'),
                controller: _xAmount,
                focusNode: _xAmountFocus,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                textInputAction: TextInputAction.done,
                decoration: InputDecoration(hintText: s.t('adb_amount'), isDense: true),
                onSubmitted: (_) => _addExpense(),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              key: const ValueKey('adb-add-expense'),
              tooltip: s.t('adb_add_day_expense'),
              onPressed: _xBusy ? null : _addExpense,
              icon: const Icon(Icons.add),
            ),
          ]);
          return c.maxWidth >= 640
              ? Row(children: [label, const SizedBox(width: 14), Expanded(child: fields)])
              : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [label, const SizedBox(height: 10), fields]);
        }),
        if (_xError != null)
          Padding(padding: const EdgeInsets.only(top: 6), child: Text(_xError!, style: TextStyle(color: AppColors.danger))),
        const SizedBox(height: 10),
        InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => setState(() => _showExpenses = !_showExpenses),
          child: _TotalBar(
            icon: null,
            label: s.t('adb_day_expenses_total'),
            value: money(p.spent),
            color: AppColors.danger,
            valueKey: 'adb-spent-total',
            trailing: Icon(_showExpenses ? Icons.expand_less : Icons.chevron_right, color: AppColors.textSoft),
          ),
        ),
        if (_showExpenses)
          for (var i = 0; i < expenses.length; i++)
            _Row(
              key: ValueKey('adb-exp-${expenses[i].id}'),
              n: i + 1,
              title: expenses[i].title,
              time: hhmm(expenses[i].createdAt),
              amount: money(expenses[i].amount),
              amountColor: AppColors.danger,
              onEdit: _canFix ? () => _editExpense(expenses[i]) : null,
              onDelete: _canFix ? () => _deleteExpense(expenses[i]) : null,
            ),
      ]),
    );

    // 6. Günü bağla (or the owner's / Baş admin's re-open).
    final actions = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (day.isOpen && _canAdd)
        SizedBox(
          height: 54,
          child: OutlinedButton.icon(
            key: const ValueKey('adb-close-day'),
            onPressed: _busy ? null : () => _close(p),
            icon: const Icon(Icons.check),
            label: Text(s.t('adb_close_day'), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w500)),
          ),
        ),
      if (!day.isOpen && widget.manager)
        SizedBox(
          height: 50,
          child: OutlinedButton.icon(
            key: const ValueKey('adb-reopen-day'),
            onPressed: _busy ? null : _reopen,
            icon: const Icon(Icons.lock_open),
            label: Text(s.t('adb_reopen')),
          ),
        ),
      if (!day.isOpen && !widget.manager)
        Text(s.t('adb_closed_note'), textAlign: TextAlign.center, style: TextStyle(color: AppColors.textSoft)),
    ]);

    final summary = AdbizCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(s.t('adb_day_summary'), style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.text)),
        const SizedBox(height: 8),
        _Line(s.t('adb_target'), money(p.target), AppColors.text),
        _Line(s.t('adb_income_day'), money(p.collected), AppColors.online),
        _Line(s.t('adb_spent'), money(p.spent), AppColors.danger),
        _Line(s.t('adb_left_money'), money(p.net), AppColors.blue),
        _Line(s.t('adb_to_target'), adbizTargetLine(p), AppColors.accent),
      ]),
    );

    return LayoutBuilder(builder: (context, c) {
      final wide = c.maxWidth >= 900;
      final main = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        header,
        const SizedBox(height: 10),
        numbers,
        const SizedBox(height: 10),
        if (form != null) ...[form, const SizedBox(height: 10)],
        list,
        const SizedBox(height: 10),
        expenseCard,
        const SizedBox(height: 12),
        actions,
      ]);
      if (!wide) return main;
      // Computer: the day's summary on the right (owner's picture).
      return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: main),
        const SizedBox(width: 14),
        SizedBox(width: 300, child: summary),
      ]);
    });
  }
}

/// Hədəf · Toplanan gəlir · Rasxod, then Qalan məbləğ with how it is worked
/// out (collected − rasxod), the bar and what is left to the target as an
/// amount (owner's picture, 10.11.2026; no percent).
class DayMoneyCard extends StatelessWidget {
  final AppStrings s;
  final DayProgress p;
  const DayMoneyCard({super.key, required this.s, required this.p});

  Widget _col(IconData icon, String label, String value, Color color, String key) => Column(children: [
        Icon(icon, color: color, size: 30),
        const SizedBox(height: 6),
        Text(label, textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 13, color: AppColors.textSoft)),
        const SizedBox(height: 2),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(value, key: ValueKey(key), style: TextStyle(fontSize: 19, fontWeight: FontWeight.w600, color: color)),
        ),
      ]);

  @override
  Widget build(BuildContext context) {
    final sep = Container(width: 1, height: 70, color: AppColors.line);
    return AdbizCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          Expanded(child: _col(Icons.track_changes, s.t('adb_target'), money(p.target), AppColors.text, 'adb-target')),
          sep,
          Expanded(child: _col(Icons.savings_outlined, s.t('adb_income_day'), money(p.collected), AppColors.online, 'adb-collected')),
          sep,
          Expanded(child: _col(Icons.payments_outlined, s.t('adb_spent'), money(p.spent), AppColors.danger, 'adb-spent')),
        ]),
        Divider(height: 22, color: AppColors.line),
        LayoutBuilder(builder: (context, c) {
          final left = Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.account_balance_wallet_outlined, color: AppColors.blue, size: 30),
            const SizedBox(width: 10),
            Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(s.t('adb_left_money'), style: TextStyle(fontSize: 13, color: AppColors.textSoft)),
              Text(money(p.net), key: const ValueKey('adb-left'),
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: AppColors.blue)),
            ]),
          ]);
          final calc = Container(
            key: const ValueKey('adb-calc'),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.line.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.line),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.info_outline, size: 18, color: AppColors.blue),
              const SizedBox(width: 8),
              Flexible(
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${s.t('adb_calc')}:', style: TextStyle(fontSize: 12, color: AppColors.textSoft)),
                  Text(adbizCalcLine(p), style: TextStyle(fontSize: 12.5, color: AppColors.text)),
                ]),
              ),
            ]),
          );
          return c.maxWidth >= 360
              ? Row(children: [left, const SizedBox(width: 10), const Spacer(), Flexible(child: calc)])
              : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [left, const SizedBox(height: 8), calc]);
        }),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                key: const ValueKey('adb-progress'),
                value: p.bar,
                minHeight: 14,
                backgroundColor: AppColors.line,
                color: AppColors.online,
              ),
            ),
          ),
          const SizedBox(width: 12),
          // What is left to the target, as an amount — no percent (owner, 10.11.2026).
          Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: [
            Text(s.t('adb_to_target'), style: TextStyle(fontSize: 12, color: AppColors.textSoft)),
            Text(adbizTargetLine(p), key: const ValueKey('adb-to-target'),
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: AppColors.accent)),
          ]),
        ]),
        if (p.reached)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(s.t('adb_target_reached'), style: TextStyle(color: AppColors.online, fontWeight: FontWeight.w500)),
          ),
      ]),
    );
  }
}

/// A plain amount: 235 → "235", 12.5 → "12.50" (the formula lines).
String adbizNum(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(2);

/// "120 − 30 = 90 AZN" (owner, 10.11.2026: the formula, in numbers).
String adbizCalcLine(DayProgress p) => '${adbizNum(p.collected)} − ${adbizNum(p.spent)} = ${adbizNum(p.net)} AZN';

/// What is left to the target, as a formula: "235 − 90 = 145 AZN" (owner,
/// 10.11.2026; no percent). Money left below 0 shows in brackets; the target
/// reached or passed: "0 AZN".
String adbizTargetLine(DayProgress p) {
  if (p.remaining <= 0) return '0 AZN';
  final left = p.net < 0 ? '(${adbizNum(p.net)})' : adbizNum(p.net);
  return '${adbizNum(p.target)} − $left = ${adbizNum(p.remaining)} AZN';
}

/// A numbered row: n · name (time) · amount (· edit / delete for managers).
class _Row extends StatelessWidget {
  final int n;
  final String title, time, amount;
  final Color? amountColor;
  final VoidCallback? onEdit, onDelete;
  const _Row({super.key, required this.n, required this.title, required this.time, required this.amount, this.amountColor, this.onEdit, this.onDelete});

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), border: Border.all(color: AppColors.line)),
        child: Row(children: [
          Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: AppColors.line.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(8)),
            child: Text('$n', style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.text)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: TextStyle(fontSize: 15.5, color: AppColors.text)),
              if (time.isNotEmpty) Text(time, style: TextStyle(fontSize: 11.5, color: AppColors.textSoft)),
            ]),
          ),
          Text(amount, style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600, color: amountColor ?? AppColors.text)),
          if (onEdit != null)
            IconButton(
                visualDensity: VisualDensity.compact,
                icon: Icon(Icons.edit_outlined, size: 20, color: AppColors.blue),
                onPressed: onEdit),
          if (onDelete != null)
            IconButton(
                visualDensity: VisualDensity.compact,
                icon: Icon(Icons.delete_outline, size: 20, color: AppColors.danger),
                onPressed: onDelete),
        ]),
      );
}

class _TotalBar extends StatelessWidget {
  final IconData? icon;
  final String label, value, valueKey;
  final Color color;
  final Widget? trailing;
  const _TotalBar({required this.icon, required this.label, required this.value, required this.color, required this.valueKey, this.trailing});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.13), borderRadius: BorderRadius.circular(10)),
        child: Row(children: [
          if (icon != null) ...[Icon(icon, color: color), const SizedBox(width: 10)],
          Expanded(child: Text(label, style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600, color: AppColors.text))),
          Text(value, key: ValueKey(valueKey), style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: color)),
          if (trailing != null) ...[const SizedBox(width: 6), trailing!],
        ]),
      );
}

class _Line extends StatelessWidget {
  final String label, value;
  final Color color;
  const _Line(this.label, this.value, this.color);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(children: [
          Expanded(child: Text(label, style: TextStyle(color: AppColors.textSoft))),
          Text(value, style: TextStyle(fontWeight: FontWeight.w600, color: color)),
        ]),
      );
}

class _StatusChip extends StatelessWidget {
  final AppStrings s;
  final bool open;
  const _StatusChip({required this.s, required this.open});

  @override
  Widget build(BuildContext context) {
    final c = open ? AppColors.online : AppColors.textSoft;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(color: c.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(20)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.circle, size: 9, color: c),
        const SizedBox(width: 6),
        Text(s.t(open ? 'adb_day_open' : 'adb_day_closed'), style: TextStyle(color: c, fontWeight: FontWeight.w500, fontSize: 13)),
      ]),
    );
  }
}
