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

/// "Reklam iş dəftəri" (owner, 10.11.2026): the worker opens the day, adds
/// jobs (name + amount), sees target / collected / remaining, closes the
/// day. The owner and the Baş admin open the same page for a worker
/// ([userId]) and may fix any of his days (the server checks who may).
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
    final async = ref.watch(adbizDaysProvider(uid));
    final days = async.valueOrNull ?? const <AdbizDay>[];
    final today = bakuToday();
    AdbizDay? find(String? id) => id == null ? null : days.where((d) => d.id == id).firstOrNull;
    final todayDay = days.where((d) => d.workDate == today).firstOrNull;
    final day = find(_selected) ?? todayDay;
    final history = [for (final d in days) if (d.id != day?.id) d];

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
      appBar: AppBar(title: UtepTitle(widget.userName ?? s.t('adb_notebook'))),
      body: SafeArea(top: false, child: body),
    );
  }
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

/// One day: numbers, the quick form (Enter saves), the jobs, close / re-open.
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
  final _titleFocus = FocusNode();
  final _amountFocus = FocusNode();
  bool _busy = false;
  String? _error;

  /// The key of the job being added: the same for a repeated tap, a new one
  /// after it was saved (the server gives back the same job for the same key).
  String _key = adbizClientKey();

  AppStrings get s => widget.s;
  AdbizDay get day => widget.day;

  /// The worker writes only into his own open day; the owner / Baş admin into
  /// any day of his workers (checked again on the server).
  bool get _canEdit => widget.manager || day.isOpen;

  @override
  void dispose() {
    _title.dispose();
    _amount.dispose();
    _titleFocus.dispose();
    _amountFocus.dispose();
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

  Future<void> _close(DayProgress p) async {
    if (_busy) return;
    final body = s.t('adb_close_body', {'sum': money(p.collected), 'target': money(p.target)});
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

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(adbizEntriesProvider(day.id));
    final entries = async.valueOrNull ?? const <AdbizEntry>[];
    final p = DayProgress.of(entries, day.target);

    final header = AdbizCard(
      child: Row(children: [
        Icon(Icons.calendar_month_outlined, color: AppColors.accent, size: 28),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(s.t(widget.isToday ? 'adb_today' : 'adb_work_day'),
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.text)),
            Text(dmy(day.workDate), style: TextStyle(color: AppColors.textSoft)),
          ]),
        ),
        _StatusChip(s: s, open: day.isOpen),
      ]),
    );

    final form = !_canEdit
        ? null
        : AdbizCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              LayoutBuilder(builder: (context, c) {
                final title = TextField(
                  key: const ValueKey('adb-job-title'),
                  controller: _title,
                  focusNode: _titleFocus,
                  maxLength: 120,
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(labelText: s.t('adb_job_name'), counterText: '', hintText: s.t('adb_job_hint')),
                  onSubmitted: (_) => _amountFocus.requestFocus(),
                );
                final amount = TextField(
                  key: const ValueKey('adb-job-amount'),
                  controller: _amount,
                  focusNode: _amountFocus,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  textInputAction: TextInputAction.done,
                  decoration: InputDecoration(labelText: s.t('adb_amount'), suffixText: 'AZN'),
                  // Enter saves the job (owner, 10.11.2026).
                  onSubmitted: (_) => _add(),
                );
                return c.maxWidth >= 520
                    ? Row(children: [Expanded(flex: 3, child: title), const SizedBox(width: 10), Expanded(flex: 2, child: amount)])
                    : Column(children: [title, const SizedBox(height: 8), amount]);
              }),
              if (_error != null)
                Padding(padding: const EdgeInsets.only(top: 6), child: Text(_error!, style: TextStyle(color: AppColors.danger))),
              const SizedBox(height: 10),
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

    final list = AdbizCard(
      padding: const EdgeInsets.fromLTRB(4, 10, 4, 4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text('${s.t('adb_jobs_today')} (${entries.length})',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.text)),
        ),
        const SizedBox(height: 6),
        if (entries.isEmpty)
          Padding(
            padding: const EdgeInsets.all(14),
            child: Text(s.t('adb_no_jobs'), style: TextStyle(color: AppColors.textSoft)),
          ),
        for (var i = 0; i < entries.length; i++)
          ListTile(
            key: ValueKey('adb-job-${entries[i].id}'),
            dense: true,
            leading: Text('${i + 1}', style: TextStyle(color: AppColors.textSoft)),
            minLeadingWidth: 18,
            title: Text(entries[i].title, style: TextStyle(color: AppColors.text, fontSize: 15)),
            subtitle: Text(hhmm(entries[i].createdAt), style: TextStyle(color: AppColors.textSoft, fontSize: 12)),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              Text(money(entries[i].amount), style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.text)),
              if (_canEdit) ...[
                IconButton(
                    tooltip: s.t('adb_edit_job'),
                    visualDensity: VisualDensity.compact,
                    icon: Icon(Icons.edit_outlined, size: 20, color: AppColors.blue),
                    onPressed: () => _edit(entries[i])),
                IconButton(
                    tooltip: s.t('adb_delete'),
                    visualDensity: VisualDensity.compact,
                    icon: Icon(Icons.delete_outline, size: 20, color: AppColors.danger),
                    onPressed: () => _delete(entries[i])),
              ],
            ]),
          ),
        Container(
          margin: const EdgeInsets.fromLTRB(8, 6, 8, 6),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(color: AppColors.online.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
          child: Row(children: [
            Expanded(child: Text(s.t('adb_total'), style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.text))),
            Text(money(p.collected), key: const ValueKey('adb-total'), style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.online)),
          ]),
        ),
      ]),
    );

    final actions = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (day.isOpen && _canEdit)
        SizedBox(
          height: 48,
          child: OutlinedButton.icon(
            key: const ValueKey('adb-close-day'),
            onPressed: _busy ? null : () => _close(p),
            icon: const Icon(Icons.check),
            label: Text(s.t('adb_close_day')),
          ),
        ),
      if (!day.isOpen && widget.manager)
        SizedBox(
          height: 48,
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
        _Line(s.t('adb_collected'), money(p.collected), AppColors.online),
        _Line(s.t('adb_remaining'), money(p.remaining), AppColors.accent),
        _Line(s.t('adb_percent'), '${p.percent}%', AppColors.blue),
      ]),
    );

    return LayoutBuilder(builder: (context, c) {
      final wide = c.maxWidth >= 900;
      final main = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        header,
        const SizedBox(height: 10),
        DayProgressCard(s: s, p: p),
        const SizedBox(height: 10),
        if (form != null) ...[form, const SizedBox(height: 10)],
        list,
        const SizedBox(height: 10),
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: c.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(20)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.circle, size: 9, color: c),
        const SizedBox(width: 6),
        Text(s.t(open ? 'adb_day_open' : 'adb_day_closed'), style: TextStyle(color: c, fontWeight: FontWeight.w500, fontSize: 13)),
      ]),
    );
  }
}
