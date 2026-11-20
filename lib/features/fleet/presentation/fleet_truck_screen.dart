import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/localization/app_strings.dart';
import '../../../core/localization/locale_controller.dart';
import '../../../core/theme/app_theme.dart';
import '../../auth/presentation/providers/auth_providers.dart';
import '../domain/fleet.dart';
import 'fleet_forms.dart';
import 'fleet_providers.dart';

/// One truck (owner's picture 3, 20.11.2026). The owner: the profit (agreed
/// prices − approved expenses, per currency), "Danışılan qiymət", the jobs,
/// the expenses (a driver's waiting one: Təsdiqlə / Rədd et; a tap edits —
/// name, amount, currency, Yadda saxla, Sil) and the driver's account link.
/// The linked driver: his jobs (no prices) and his own expenses with their
/// state ("Təsdiq gözləyir").
class FleetTruckScreen extends ConsumerWidget {
  final String id;
  const FleetTruckScreen({super.key, required this.id});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final lang = ref.watch(currentLocaleProvider).languageCode;
    final uid = ref.watch(currentUserIdProvider);
    final async = ref.watch(fleetProvider);
    final d = async.valueOrNull;
    final t = d?.truck(id);
    if (t == null) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(
          child: async.isLoading
              ? const CircularProgressIndicator()
              : Text(s.t('fl_truck_missing'), key: const ValueKey('fl-truck-missing'), style: TextStyle(color: AppColors.textSoft)),
        ),
      );
    }
    final owner = t.isOwner(uid);
    final jobs = d!.jobsOf(t.id)..sort((a, b) => b.startAt.compareTo(a.startAt));
    final expenses = d.expensesOf(t.id);
    final pending = [
      for (final e in expenses)
        if (e.pending) e
    ];
    return Scaffold(
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(t.name, maxLines: 1, overflow: TextOverflow.ellipsis),
          if ((t.plate ?? '').isNotEmpty) Text(t.plate!, style: TextStyle(fontSize: 13, color: AppColors.textSoft)),
        ]),
        actions: [
          if (owner)
            PopupMenuButton<String>(
              key: const ValueKey('fl-truck-menu'),
              onSelected: (v) async {
                if (v == 'edit') await showFleetTruckForm(context, truck: t);
                if (v == 'remove' && context.mounted) await _removeTruck(context, ref, s, t);
              },
              itemBuilder: (_) => [
                PopupMenuItem(value: 'edit', child: Text(s.t('fl_edit_truck'))),
                PopupMenuItem(value: 'remove', child: Text(s.t('fl_remove_truck'))),
              ],
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(fleetProvider.future),
        child: ListView(
          key: const ValueKey('fl-truck-page'),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
          children: [
            if (owner) ...[
              _ProfitCard(s: s, jobs: jobs, expenses: expenses),
              const SizedBox(height: 10),
              _AgreedRow(s: s, jobs: jobs),
              const SizedBox(height: 18),
            ],
            // Jobs.
            _Head(
              title: s.t('fl_jobs'),
              action: owner
                  ? TextButton.icon(
                      key: const ValueKey('fl-page-addjob'),
                      onPressed: () => showFleetJobForm(context, truckId: t.id),
                      icon: const Icon(Icons.add, size: 18),
                      label: Text(s.t('fl_add_job')),
                    )
                  : null,
            ),
            if (jobs.isEmpty)
              Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(s.t('fl_no_jobs'), style: TextStyle(color: AppColors.textSoft)))
            else
              for (final j in jobs) _JobTile(job: j, s: s, lang: lang, owner: owner, truckId: t.id),
            const SizedBox(height: 14),
            // Expenses.
            _Head(
              title: s.t('fl_expenses'),
              action: TextButton.icon(
                key: const ValueKey('fl-page-addexp'),
                onPressed: () => showFleetExpenseForm(context, truckId: t.id),
                icon: const Icon(Icons.add, size: 18),
                label: Text(s.t('fl_add_expense')),
              ),
            ),
            if (owner && pending.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(s.t('fl_pending_n', {'n': '${pending.length}'}), style: TextStyle(color: AppColors.accent)),
              ),
            if (expenses.isEmpty)
              Text(s.t('fl_no_expenses'), style: TextStyle(color: AppColors.textSoft))
            else
              for (final e in expenses) _ExpenseTile(expense: e, s: s, owner: owner, truckId: t.id, me: uid),
            if (owner) ...[
              const SizedBox(height: 22),
              _DriverCard(truck: t, s: s),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _removeTruck(BuildContext context, WidgetRef ref, AppStrings s, FleetTruck t) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(s.t('fl_remove_truck_q', {'name': t.name})),
        content: Text(s.t('fl_remove_truck_hint')),
        actions: [
          TextButton(onPressed: () => Navigator.of(d).pop(false), child: Text(s.t('common_cancel'))),
          FilledButton(onPressed: () => Navigator.of(d).pop(true), child: Text(s.t('fl_remove'))),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(fleetRepositoryProvider).removeTruck(t.id);
      ref.invalidate(fleetProvider);
      if (context.mounted) context.go('/fleet');
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.t(fleetErrorKey(e)))));
    }
  }
}

class _Head extends StatelessWidget {
  final String title;
  final Widget? action;
  const _Head({required this.title, this.action});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(children: [
          Expanded(
              child: Text(title,
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: AppColors.text))),
          // A long language / big text: the button gets smaller, never cut.
          if (action != null) Flexible(child: FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerRight, child: action!)),
        ]),
      );
}

/// "Mənfi qazanc" / "Qazanc": per currency, agreed prices − approved expenses.
class _ProfitCard extends StatelessWidget {
  final AppStrings s;
  final List<FleetJob> jobs;
  final List<FleetExpense> expenses;
  const _ProfitCard({required this.s, required this.jobs, required this.expenses});

  @override
  Widget build(BuildContext context) {
    final p = fleetProfit(jobs, expenses);
    final negative = p.values.any((v) => v < 0);
    final c = negative ? AppColors.accent : AppColors.online;
    return Container(
      key: const ValueKey('fl-profit'),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: c.withValues(alpha: 0.7)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(s.t(negative ? 'fl_profit_negative' : 'fl_profit'), style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500, color: AppColors.text)),
        const SizedBox(height: 6),
        if (p.isEmpty)
          Text('0', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w600, color: AppColors.textSoft))
        else
          Wrap(spacing: 18, runSpacing: 4, children: [
            for (final e in p.entries)
              Text('${fleetAmount(e.value)} ${e.key}',
                  key: ValueKey('fl-profit-${e.key}'),
                  style: TextStyle(fontSize: 26, fontWeight: FontWeight.w600, color: e.value < 0 ? AppColors.accent : AppColors.online)),
          ]),
      ]),
    );
  }
}

/// "Danışılan qiymət": the jobs' agreed prices per currency.
class _AgreedRow extends StatelessWidget {
  final AppStrings s;
  final List<FleetJob> jobs;
  const _AgreedRow({required this.s, required this.jobs});

  @override
  Widget build(BuildContext context) {
    final income = fleetIncome(jobs);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.line)),
      child: Row(children: [
        Expanded(child: Text(s.t('fl_agreed'), style: TextStyle(fontSize: 16, color: AppColors.text))),
        Flexible(
          child: Text(
            income.isEmpty ? '—' : [for (final e in income.entries) '${fleetAmount(e.value)} ${e.key}'].join(' · '),
            key: const ValueKey('fl-agreed'),
            textAlign: TextAlign.right,
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.text),
          ),
        ),
      ]),
    );
  }
}

class _JobTile extends ConsumerWidget {
  final FleetJob job;
  final AppStrings s;
  final String lang, truckId;
  final bool owner;
  const _JobTile({required this.job, required this.s, required this.lang, required this.owner, required this.truckId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statusKey = switch (job.status) {
      'active' => 'fl_job_active',
      'done' => 'fl_job_done',
      'cancelled' => 'fl_job_cancelled',
      _ => 'fl_job_planned',
    };
    final statusColor = switch (job.status) {
      'active' => AppColors.accent,
      'done' => AppColors.online,
      _ => AppColors.textSoft,
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        key: ValueKey('fl-jobtile-${job.id}'),
        padding: const EdgeInsets.fromLTRB(14, 10, 4, 10),
        decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.line)),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${fleetDayLabel(s, job.startAt, lang)} • ${fleetTime(job.startAt)}', style: TextStyle(fontSize: 13, color: AppColors.textSoft)),
              const SizedBox(height: 2),
              Text(job.route.isEmpty ? '—' : job.route,
                  maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: AppColors.text)),
              const SizedBox(height: 2),
              Text(s.t(statusKey), style: TextStyle(fontSize: 12.5, color: statusColor)),
            ]),
          ),
          if (owner && job.price != null)
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text('${fleetAmount(job.price!)} ${job.currency}', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.text)),
              ),
            ),
          if (owner)
            PopupMenuButton<String>(
              key: ValueKey('fl-job-menu-${job.id}'),
              onSelected: (v) async {
                final repo = ref.read(fleetRepositoryProvider);
                try {
                  if (v == 'edit') {
                    await showFleetJobForm(context, truckId: truckId, job: job);
                    return;
                  }
                  if (v == 'remove') {
                    await repo.removeJob(job.id);
                  } else {
                    await repo.setJobStatus(job.id, v);
                  }
                  ref.invalidate(fleetProvider);
                } catch (e) {
                  if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.t(fleetErrorKey(e)))));
                }
              },
              itemBuilder: (_) => [
                if (job.status == 'planned') PopupMenuItem(value: 'active', child: Text(s.t('fl_job_start'))),
                if (job.open) PopupMenuItem(value: 'done', child: Text(s.t('fl_job_finish'))),
                if (job.open) PopupMenuItem(value: 'cancelled', child: Text(s.t('fl_job_cancel'))),
                PopupMenuItem(value: 'edit', child: Text(s.t('fl_edit_job'))),
                PopupMenuItem(value: 'remove', child: Text(s.t('fl_remove'))),
              ],
            )
          else
            const SizedBox(width: 10),
        ]),
      ),
    );
  }
}

class _ExpenseTile extends ConsumerWidget {
  final FleetExpense expense;
  final AppStrings s;
  final bool owner;
  final String truckId;
  final String? me;
  const _ExpenseTile({required this.expense, required this.s, required this.owner, required this.truckId, required this.me});

  Future<void> _decide(BuildContext context, WidgetRef ref, bool approve) async {
    try {
      await ref.read(fleetRepositoryProvider).decideExpense(expense.id, approve);
      ref.invalidate(fleetProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.t(approve ? 'fl_approved' : 'fl_rejected'))));
      }
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.t(fleetErrorKey(e)))));
    }
  }

  /// The driver takes back his own waiting expense (a mistake).
  Future<void> _removeOwn(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(s.t('fl_remove_expense_q')),
        actions: [
          TextButton(onPressed: () => Navigator.of(d).pop(false), child: Text(s.t('common_cancel'))),
          FilledButton(onPressed: () => Navigator.of(d).pop(true), child: Text(s.t('fl_remove'))),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(fleetRepositoryProvider).removeExpense(expense.id);
      ref.invalidate(fleetProvider);
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.t(fleetErrorKey(e)))));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final e = expense;
    final hi = e.pending;
    final mine = e.createdBy == me;
    // The owner edits any; the driver only removes his own waiting one.
    final canOpen = owner || (mine && e.pending);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: hi ? AppColors.accent.withValues(alpha: 0.10) : AppColors.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: hi ? AppColors.accent : AppColors.line),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: ValueKey('fl-exp-${e.id}'),
          onTap: !canOpen
              ? null
              : owner
                  ? () => showFleetExpenseForm(context, truckId: truckId, expense: e, canRemove: true)
                  : () => _removeOwn(context, ref),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                Expanded(
                  child: Text(e.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 16, color: e.status == 'rejected' ? AppColors.textSoft : AppColors.text)),
                ),
                Text('${fleetAmount(e.amount)} ${e.currency}',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: e.status == 'rejected' ? AppColors.textSoft : AppColors.text,
                      decoration: e.status == 'rejected' ? TextDecoration.lineThrough : null,
                    )),
              ]),
              if (e.pending || e.status == 'rejected') ...[
                const SizedBox(height: 4),
                Text(s.t(e.pending ? 'fl_waiting' : 'fl_rejected_state'),
                    key: ValueKey('fl-exp-state-${e.id}'), style: TextStyle(fontSize: 13, color: e.pending ? AppColors.accent : AppColors.danger)),
              ],
              if (owner && e.pending) ...[
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(
                    child: OutlinedButton(
                      key: ValueKey('fl-exp-reject-${e.id}'),
                      onPressed: () => _decide(context, ref, false),
                      child: Text(s.t('fl_reject')),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      key: ValueKey('fl-exp-approve-${e.id}'),
                      onPressed: () => _decide(context, ref, true),
                      child: Text(s.t('fl_approve')),
                    ),
                  ),
                ]),
              ],
            ]),
          ),
        ),
      ),
    );
  }
}

/// The driver: his name, and his own account linked by a code.
class _DriverCard extends ConsumerWidget {
  final FleetTruck truck;
  final AppStrings s;
  const _DriverCard({required this.truck, required this.s});

  @override
  Widget build(BuildContext context, WidgetRef ref) => Container(
        key: const ValueKey('fl-driver-card'),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.line)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Icon(Icons.person_outline, color: AppColors.text),
            const SizedBox(width: 8),
            Expanded(
              child:
                  Text(truck.driverName?.isNotEmpty == true ? truck.driverName! : s.t('fl_no_driver'), style: TextStyle(fontSize: 16, color: AppColors.text)),
            ),
          ]),
          const SizedBox(height: 6),
          Text(s.t(truck.driverId != null ? 'fl_driver_linked' : 'fl_driver_not_linked'), style: TextStyle(color: AppColors.textSoft)),
          const SizedBox(height: 10),
          if (truck.driverId == null)
            OutlinedButton.icon(
              key: const ValueKey('fl-link-driver'),
              onPressed: () => showFleetInviteSheet(context, truckId: truck.id),
              icon: const Icon(Icons.link, size: 18),
              label: Text(s.t('fl_link_driver')),
            )
          else
            TextButton(
              key: const ValueKey('fl-unlink-driver'),
              onPressed: () async {
                try {
                  await ref.read(fleetRepositoryProvider).unlinkDriver(truck.id);
                  ref.invalidate(fleetProvider);
                } catch (e) {
                  if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.t(fleetErrorKey(e)))));
                }
              },
              child: Text(s.t('fl_unlink_driver')),
            ),
        ]),
      );
}
