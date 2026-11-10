import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/localization/app_strings.dart';
import '../../../core/localization/locale_controller.dart';
import '../../../core/router/safe_navigation.dart';
import '../../../core/theme/app_theme.dart';
import '../../finance/domain/finance_models.dart';
import '../data/adbiz_repository.dart';
import '../domain/adbiz_models.dart';
import 'adbiz_providers.dart';
import 'adbiz_widgets.dart';

/// "Reklam idarəetməsi" of one company (owner, 10.11.2026): income for the
/// day / month / year, expenses, net profit, the workers with their results
/// (a tap opens the worker's notebook), open / closed days and the archive.
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

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    ref.watch(currentLocaleProvider);
    final me = ref.watch(adbizMeProvider).valueOrNull;
    final chief = me?.chief == true;
    final company = (ref.watch(adbizCompaniesProvider).valueOrNull ?? const <AdbizCompany>[])
        .where((c) => c.id == widget.companyId)
        .firstOrNull;
    final canStaff = chief || (me?.isOwner == true && me?.managesStaff == true && me?.companyId == widget.companyId);
    final rep = ref.watch(adbizReportProvider(_key));
    final exps = ref.watch(adbizExpensesProvider(_key)).valueOrNull ?? const <AdbizExpense>[];
    final r = rep.valueOrNull;

    final periodBar = AdbizCard(
      padding: const EdgeInsets.all(10),
      child: Column(children: [
        SegmentedButton<AdbizPeriod>(
          key: const ValueKey('adb-period'),
          segments: [
            ButtonSegment(value: AdbizPeriod.day, label: Text(s.t('adb_period_day'))),
            ButtonSegment(value: AdbizPeriod.month, label: Text(s.t('adb_period_month'))),
            ButtonSegment(value: AdbizPeriod.year, label: Text(s.t('adb_period_year'))),
          ],
          selected: {_period},
          showSelectedIcon: false,
          onSelectionChanged: (v) => setState(() => _period = v.first),
        ),
        Row(children: [
          IconButton(onPressed: () => _shift(-1), icon: const Icon(Icons.chevron_left)),
          Expanded(child: Text(_periodLabel(s), textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.text))),
          IconButton(onPressed: () => _shift(1), icon: const Icon(Icons.chevron_right)),
        ]),
      ]),
    );

    final totals = AdbizCard(
      child: Column(children: [
        LayoutBuilder(builder: (context, c) {
          final items = [
            AdbizStat(icon: Icons.trending_up, label: s.t('adb_income'), value: money(r?.income ?? 0), color: AppColors.online, valueKey: 'adb-income'),
            AdbizStat(icon: Icons.receipt_long_outlined, label: s.t('adb_expenses'), value: money(r?.expenses ?? 0), color: AppColors.danger),
            AdbizStat(icon: Icons.account_balance_wallet_outlined, label: s.t('adb_net'), value: money(r?.net ?? 0), color: AppColors.blue, valueKey: 'adb-net'),
          ];
          return c.maxWidth >= 420
              ? Row(children: [for (final w in items) Expanded(child: w)])
              : Column(children: [for (final w in items) Padding(padding: const EdgeInsets.only(bottom: 8), child: w)]);
        }),
        const SizedBox(height: 8),
        Row(children: [
          Icon(Icons.lock_open, size: 16, color: AppColors.online),
          const SizedBox(width: 4),
          Text('${s.t('adb_days_open')}: ${r?.daysOpen ?? 0}', style: TextStyle(color: AppColors.textSoft)),
          const SizedBox(width: 16),
          Icon(Icons.lock_outline, size: 16, color: AppColors.textSoft),
          const SizedBox(width: 4),
          Text('${s.t('adb_days_closed')}: ${r?.daysClosed ?? 0}', style: TextStyle(color: AppColors.textSoft)),
        ]),
      ]),
    );

    final workers = AdbizCard(
      padding: const EdgeInsets.fromLTRB(4, 10, 4, 6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(children: [
            Expanded(child: Text(s.t('adb_workers'), style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.text))),
            if (canStaff)
              TextButton.icon(
                key: const ValueKey('adb-add-member'),
                onPressed: _busy ? null : () => _addMember(s, chief: chief),
                icon: const Icon(Icons.person_add_alt_1_outlined),
                label: Text(s.t(chief ? 'adb_add_member' : 'adb_add_worker')),
              ),
          ]),
        ),
        if (r != null && r.workers.isEmpty)
          Padding(padding: const EdgeInsets.all(12), child: Text(s.t('adb_no_workers'), style: TextStyle(color: AppColors.textSoft))),
        for (final w in r?.workers ?? const <AdbizWorkerSum>[])
          ListTile(
            key: ValueKey('adb-worker-${w.userId}'),
            leading: CircleAvatar(
              backgroundColor: (w.role == 'owner' ? AppColors.accent : AppColors.blue).withValues(alpha: 0.15),
              child: Icon(w.role == 'owner' ? Icons.workspace_premium : Icons.person_outline,
                  color: w.role == 'owner' ? AppColors.accent : AppColors.blue),
            ),
            title: Text(w.name, style: TextStyle(color: w.isActive ? AppColors.text : AppColors.textSoft)),
            subtitle: Text([
              s.t(w.role == 'owner' ? 'adb_role_owner' : 'adb_role_worker'),
              if (!w.isActive) s.t('adb_inactive'),
              if (w.personalTarget != null) '${s.t('adb_target')}: ${money(w.personalTarget!)}',
            ].join(' · ')),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              Text(money(w.total), style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.online)),
              if (canStaff && (chief || w.role == 'worker'))
                PopupMenuButton<String>(
                  key: ValueKey('adb-member-menu-${w.userId}'),
                  onSelected: (v) => switch (v) {
                    'active' => _run(s, () => ref.read(adbizRepositoryProvider).memberSetActive(w.userId, !w.isActive), done: s.t('adb_saved')),
                    'target' => _memberTarget(s, w),
                    'owner' => _run(s, () => ref.read(adbizRepositoryProvider).memberSet(w.userId, widget.companyId, 'owner'), done: s.t('adb_saved')),
                    'worker' => _run(s, () => ref.read(adbizRepositoryProvider).memberSet(w.userId, widget.companyId, 'worker'), done: s.t('adb_saved')),
                    _ => null,
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem(value: 'active', child: Text(s.t(w.isActive ? 'adb_deactivate' : 'adb_activate'))),
                    if (chief) PopupMenuItem(value: 'target', child: Text(s.t('adb_personal_target'))),
                    if (chief && w.role == 'worker') PopupMenuItem(value: 'owner', child: Text(s.t('adb_make_owner'))),
                    if (chief && w.role == 'owner') PopupMenuItem(value: 'worker', child: Text(s.t('adb_make_worker'))),
                  ],
                ),
            ]),
            onTap: () => context.pushOnce(Uri(path: '/profile/adbiz/worker/${w.userId}', queryParameters: {'name': w.name}).toString()),
          ),
      ]),
    );

    final expenses = AdbizCard(
      padding: const EdgeInsets.fromLTRB(4, 10, 4, 6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(children: [
            Expanded(child: Text(s.t('adb_expenses'), style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.text))),
            TextButton.icon(
              key: const ValueKey('adb-add-expense'),
              onPressed: _busy ? null : () => _addExpense(s),
              icon: const Icon(Icons.add),
              label: Text(s.t('adb_add_expense')),
            ),
          ]),
        ),
        if (exps.isEmpty) Padding(padding: const EdgeInsets.all(12), child: Text(s.t('adb_no_expenses'), style: TextStyle(color: AppColors.textSoft))),
        for (final x in exps)
          ListTile(
            dense: true,
            title: Text(x.title, style: TextStyle(color: AppColors.text)),
            subtitle: Text(dmy(x.spentOn)),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              Text(money(x.amount), style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.danger)),
              IconButton(visualDensity: VisualDensity.compact, icon: Icon(Icons.edit_outlined, size: 20, color: AppColors.blue), onPressed: () => _editExpense(s, x)),
              IconButton(visualDensity: VisualDensity.compact, icon: Icon(Icons.delete_outline, size: 20, color: AppColors.danger), onPressed: () => _deleteExpense(s, x)),
            ]),
          ),
      ]),
    );

    final archive = AdbizCard(
      padding: const EdgeInsets.fromLTRB(4, 10, 4, 6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(s.t('adb_archive'), style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.text)),
        ),
        if ((r?.byDay ?? const []).isEmpty)
          Padding(padding: const EdgeInsets.all(12), child: Text(s.t('adb_no_days'), style: TextStyle(color: AppColors.textSoft))),
        for (final (d, v) in r?.byDay ?? const <(DateTime, double)>[])
          ListTile(
            dense: true,
            leading: Icon(Icons.event_note_outlined, color: AppColors.textSoft),
            title: Text(dmy(d), style: TextStyle(color: AppColors.text)),
            trailing: Text(money(v), style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.online)),
            onTap: () => setState(() {
              _period = AdbizPeriod.day;
              _date = d;
            }),
          ),
      ]),
    );

    final settings = !chief || company == null
        ? null
        : AdbizCard(
            child: Row(children: [
              Icon(Icons.track_changes, color: AppColors.accent),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${s.t('adb_company_target')}: ${money(company.dailyTarget)}',
                      style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.text)),
                  Text(s.t(company.isActive ? 'adb_company_active' : 'adb_company_off'),
                      style: TextStyle(color: company.isActive ? AppColors.online : AppColors.danger, fontSize: 13)),
                ]),
              ),
              IconButton(key: const ValueKey('adb-company-edit'), icon: const Icon(Icons.edit_outlined), onPressed: () => _editCompany(s, company)),
              Switch(
                key: const ValueKey('adb-company-active'),
                value: company.isActive,
                onChanged: _busy ? null : (v) => _run(s, () => ref.read(adbizRepositoryProvider).companySetActive(company.id, v)),
              ),
            ]),
          );

    Widget body;
    if (rep.hasError && r == null) {
      body = Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(adbizError(s, rep.error!), textAlign: TextAlign.center)));
    } else {
      body = LayoutBuilder(builder: (context, c) {
        final wide = c.maxWidth >= 900;
        final left = [periodBar, const SizedBox(height: 10), totals, const SizedBox(height: 10), workers];
        final right = [if (settings != null) ...[settings, const SizedBox(height: 10)], expenses, const SizedBox(height: 10), archive];
        return RefreshIndicator(
          onRefresh: () async => _refresh(),
          child: ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 32), children: [
            if (wide)
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(flex: 3, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: left)),
                const SizedBox(width: 14),
                Expanded(flex: 2, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: right)),
              ])
            else ...[
              ...left,
              const SizedBox(height: 10),
              ...right,
            ],
          ]),
        );
      });
    }
    return Scaffold(
      appBar: AppBar(title: UtepTitle(company?.name ?? me?.companyName ?? s.t('adb_business'))),
      body: SafeArea(top: false, child: body),
    );
  }
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
