import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/localization/app_strings.dart';
import '../../../core/localization/locale_controller.dart';
import '../../../core/router/guest_access.dart';
import '../../../core/router/safe_navigation.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/birth_date_field.dart' show monthName;
import '../../auth/presentation/providers/auth_providers.dart';
import '../../tirpark/presentation/map_page_header.dart';
import '../data/fleet_repository.dart';
import '../domain/fleet.dart';
import 'fleet_forms.dart';
import 'fleet_providers.dart';

/// "Maşınlarım" (owner's picture 2, 20.11.2026): the counters and "+ Maşın
/// əlavə et", the totals (income · expenses · profit per currency), Maşınlar
/// | İş cədvəli, the truck cards (Boşdur / İşdədir), "Yaxın işlər"; a
/// driver's trucks apart; "Sürücü kodu ilə qoşul".
class FleetScreen extends ConsumerStatefulWidget {
  /// 'plan' opens "İş cədvəli" (from "Bugünkü plan" on the map).
  final String? tab;
  const FleetScreen({super.key, this.tab});

  @override
  ConsumerState<FleetScreen> createState() => _FleetScreenState();
}

enum FleetFilter { all, free, busy }

class _FleetScreenState extends ConsumerState<FleetScreen> {
  late bool _plan = widget.tab == 'plan';
  FleetFilter _filter = FleetFilter.all;

  @override
  void didUpdateWidget(covariant FleetScreen old) {
    super.didUpdateWidget(old);
    if (widget.tab != old.tab && widget.tab == 'plan') _plan = true;
  }

  Future<void> _addTruck() async {
    final ok = await showFleetTruckForm(context);
    if (ok == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ref.read(stringsProvider).t('fl_truck_added'))));
    }
  }

  Future<void> _join(AppStrings s) async {
    final name = await showFleetJoinSheet(context);
    if (name != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.t('fl_joined', {'name': name}))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    final lang = ref.watch(currentLocaleProvider).languageCode;
    final uid = ref.watch(currentUserIdProvider);
    final async = ref.watch(fleetProvider);
    final now = DateTime.now();
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(children: [
          MapPageHeader(s: s, titleKey: 'fl_title'),
          MapFleetSwitch(s: s, fleet: true, onMap: () => context.go('/tirpark'), onFleet: () {}),
          Expanded(
            child: async.when(
              skipLoadingOnReload: true,
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) =>
                  _Message(text: s.t(e is FleetNotReady ? 'fl_not_ready' : 'home_error_loading'), onRetry: () => ref.invalidate(fleetProvider), s: s),
              data: (d) {
                final owned = d.owned(uid);
                final driven = d.driven(uid);
                final busy = [
                  for (final t in owned)
                    if (fleetTruckBusy(t.id, d.jobs, now)) t
                ];
                final shown = switch (_filter) {
                  FleetFilter.all => owned,
                  FleetFilter.free => [
                      for (final t in owned)
                        if (!busy.contains(t)) t
                    ],
                  FleetFilter.busy => busy,
                };
                final ownedIds = {for (final t in owned) t.id};
                final ownJobs = [
                  for (final j in d.jobs)
                    if (ownedIds.contains(j.truckId)) j
                ];
                final ownExpenses = [
                  for (final e in d.expenses)
                    if (ownedIds.contains(e.truckId)) e
                ];
                final upcoming = fleetUpcoming(d.jobs, now);
                return RefreshIndicator(
                  onRefresh: () => ref.refresh(fleetProvider.future),
                  child: ListView(
                    key: const ValueKey('fl-list'),
                    padding: const EdgeInsets.fromLTRB(14, 6, 14, 120),
                    children: [
                      // Counters + "Maşın əlavə et".
                      Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                        _Pill(key: const ValueKey('fl-count-all'), icon: Icons.local_shipping_outlined, text: s.t('fl_n_trucks', {'n': '${owned.length}'})),
                        _Pill(dot: AppColors.online, text: s.t('fl_n_free', {'n': '${owned.length - busy.length}'})),
                        _Pill(dot: AppColors.accent, text: s.t('fl_n_busy', {'n': '${busy.length}'})),
                        FilledButton.icon(
                          key: const ValueKey('fl-add-truck'),
                          onPressed: _addTruck,
                          icon: const Icon(Icons.add, size: 20),
                          label: Text(s.t('fl_add_truck')),
                        ),
                      ]),
                      if (owned.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        FleetTotalsCard(s: s, jobs: ownJobs, expenses: ownExpenses),
                      ],
                      const SizedBox(height: 12),
                      _Tabs(s: s, plan: _plan, onChange: (v) => setState(() => _plan = v)),
                      const SizedBox(height: 12),
                      if (!_plan) ...[
                        Row(children: [
                          Icon(Icons.calendar_today_outlined, size: 20, color: AppColors.text),
                          const SizedBox(width: 8),
                          Expanded(
                            child:
                                Text('${s.t('fl_today')} • ${now.day} ${fleetMonth(now.month, lang)}', style: TextStyle(fontSize: 16, color: AppColors.text)),
                          ),
                          _FilterButton(s: s, value: _filter, onChanged: (f) => setState(() => _filter = f)),
                        ]),
                        const SizedBox(height: 10),
                        if (owned.isEmpty)
                          _Empty(s: s, text: s.t('fl_empty'))
                        else
                          for (final t in shown)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: FleetTruckCard(
                                truck: t,
                                s: s,
                                busy: fleetTruckBusy(t.id, d.jobs, now),
                                job: fleetCurrentJob(t.id, d.jobs, now),
                                pending: d.expensesOf(t.id).where((e) => e.pending).length,
                              ),
                            ),
                        if (driven.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text(s.t('fl_my_driving'), style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: AppColors.text)),
                          const SizedBox(height: 10),
                          for (final t in driven)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: FleetTruckCard(
                                truck: t,
                                s: s,
                                busy: fleetTruckBusy(t.id, d.jobs, now),
                                job: fleetCurrentJob(t.id, d.jobs, now),
                                driver: true,
                              ),
                            ),
                        ],
                        if (upcoming.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          Text(s.t('fl_upcoming'), style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: AppColors.text)),
                          const SizedBox(height: 10),
                          for (final j in upcoming.take(5)) FleetJobRow(job: j, truck: d.truck(j.truckId), s: s, lang: lang),
                        ],
                      ] else
                        FleetPlan(s: s, lang: lang, data: d, uid: uid),
                      const SizedBox(height: 18),
                      OutlinedButton.icon(
                        key: const ValueKey('fl-join'),
                        onPressed: () => _join(s),
                        icon: const Icon(Icons.vpn_key_outlined, size: 18),
                        label: Text(s.t('fl_join')),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ]),
      ),
    );
  }
}

/// "18 noyabr": the month in the user's language.
String fleetMonth(int m, String lang) => monthName(m, lang);

class _Message extends StatelessWidget {
  final String text;
  final VoidCallback onRetry;
  final AppStrings s;
  const _Message({required this.text, required this.onRetry, required this.s});

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(text, key: const ValueKey('fl-message'), textAlign: TextAlign.center, style: TextStyle(color: AppColors.textSoft)),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: onRetry, child: Text(s.t('home_retry'))),
          ]),
        ),
      );
}

class _Empty extends StatelessWidget {
  final AppStrings s;
  final String text;
  const _Empty({required this.s, required this.text});

  @override
  Widget build(BuildContext context) => Container(
        key: const ValueKey('fl-empty'),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(18), border: Border.all(color: AppColors.line)),
        child: Column(children: [
          Icon(Icons.local_shipping_outlined, size: 40, color: AppColors.textSoft),
          const SizedBox(height: 8),
          Text(text, textAlign: TextAlign.center, style: TextStyle(color: AppColors.textSoft)),
        ]),
      );
}

class _Pill extends StatelessWidget {
  final IconData? icon;
  final Color? dot;
  final String text;
  const _Pill({super.key, this.icon, this.dot, required this.text});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(22), border: Border.all(color: AppColors.line)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) Icon(icon, size: 18, color: AppColors.text),
          if (dot != null) Container(width: 9, height: 9, decoration: BoxDecoration(color: dot, shape: BoxShape.circle)),
          const SizedBox(width: 7),
          Text(text, style: TextStyle(fontSize: 14, color: AppColors.text)),
        ]),
      );
}

class _Tabs extends StatelessWidget {
  final AppStrings s;
  final bool plan;
  final ValueChanged<bool> onChange;
  const _Tabs({required this.s, required this.plan, required this.onChange});

  @override
  Widget build(BuildContext context) {
    Widget half(String key, IconData icon, String label, bool on, bool value) => Expanded(
          child: Material(
            color: on ? AppColors.accentFill : Colors.transparent,
            borderRadius: BorderRadius.circular(16),
            child: InkWell(
              key: ValueKey(key),
              borderRadius: BorderRadius.circular(16),
              onTap: () => onChange(value),
              child: SizedBox(
                height: 44,
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(icon, size: 20, color: on ? Colors.white : AppColors.text),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 15, fontWeight: on ? FontWeight.w500 : FontWeight.w400, color: on ? Colors.white : AppColors.text)),
                  ),
                ]),
              ),
            ),
          ),
        );
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(19), border: Border.all(color: AppColors.line)),
      child: Row(children: [
        half('fl-tab-trucks', Icons.local_shipping_outlined, s.t('fl_tab_trucks'), !plan, false),
        const SizedBox(width: 4),
        half('fl-tab-plan', Icons.calendar_month_outlined, s.t('fl_tab_plan'), plan, true),
      ]),
    );
  }
}

class _FilterButton extends StatelessWidget {
  final AppStrings s;
  final FleetFilter value;
  final ValueChanged<FleetFilter> onChanged;
  const _FilterButton({required this.s, required this.value, required this.onChanged});

  String _label(FleetFilter f) => s.t(switch (f) { FleetFilter.all => 'fl_f_all', FleetFilter.free => 'fl_f_free', FleetFilter.busy => 'fl_f_busy' });

  @override
  Widget build(BuildContext context) => PopupMenuButton<FleetFilter>(
        key: const ValueKey('fl-filter'),
        initialValue: value,
        onSelected: onChanged,
        itemBuilder: (_) => [for (final f in FleetFilter.values) PopupMenuItem(value: f, child: Text(_label(f)))],
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.line)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.filter_alt_outlined, size: 18, color: AppColors.text),
            const SizedBox(width: 6),
            Text(_label(value), style: TextStyle(color: AppColors.text)),
            Icon(Icons.expand_more, size: 20, color: AppColors.text),
          ]),
        ),
      );
}

/// "Ümumi": income · expenses · profit per currency (owner, 20.11.2026: "nəticə
/// Maşınlarım bölməsində ümumi rasxod və qazanc görünsün"). The look is the
/// owner's own, approved in the design editor (21.11.2026): the card glows
/// blue, Gəlir and Qazanc are glowing tiles, the expenses stand in orange —
/// so the three never blur into one another. One row of tiles per currency.
class FleetTotalsCard extends StatelessWidget {
  final AppStrings s;
  final List<FleetJob> jobs;
  final List<FleetExpense> expenses;
  const FleetTotalsCard({super.key, required this.s, required this.jobs, required this.expenses});

  @override
  Widget build(BuildContext context) {
    final income = fleetIncome(jobs);
    final spent = fleetSpent(expenses);
    final profit = fleetProfit(jobs, expenses);
    final currencies = [
      for (final c in kFleetCurrencies)
        if (income.containsKey(c) || spent.containsKey(c)) c
    ];
    final glow = AppColors.blue;
    return Container(
      key: const ValueKey('fl-totals'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: glow.withValues(alpha: 0.53)),
        boxShadow: [BoxShadow(color: glow.withValues(alpha: 0.4), blurRadius: 26)],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(s.t('fl_totals'), style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: AppColors.text)),
        const SizedBox(height: 10),
        if (currencies.isEmpty)
          Text(s.t('fl_totals_empty'), style: TextStyle(color: AppColors.textSoft))
        else
          for (final c in currencies) ...[
            if (c != currencies.first) const SizedBox(height: 10),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: _tile(ValueKey('fl-tot-income-$c'), s.t('fl_income'), income[c] ?? 0, c, AppColors.text, glow: glow)),
              const SizedBox(width: 8),
              Expanded(child: _tile(ValueKey('fl-tot-spent-$c'), s.t('fl_expenses'), -(spent[c] ?? 0), c, AppColors.accentFill)),
              const SizedBox(width: 8),
              Expanded(
                  child: _tile(ValueKey('fl-tot-profit-$c'), s.t('fl_profit_short'), profit[c] ?? 0, c,
                      (profit[c] ?? 0) < 0 ? AppColors.danger : AppColors.online,
                      bold: true, glow: glow)),
            ]),
          ],
      ]),
    );
  }

  Widget _tile(Key key, String label, double v, String cur, Color color, {bool bold = false, Color? glow}) => Container(
        key: key,
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: glow == null ? null : Border.all(color: glow.withValues(alpha: 0.53)),
          boxShadow: glow == null ? null : [BoxShadow(color: glow.withValues(alpha: 0.4), blurRadius: 26)],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, color: AppColors.textSoft)),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text('${fleetAmount(v)} $cur',
                style: TextStyle(fontSize: 16, color: color, fontWeight: bold ? FontWeight.w600 : FontWeight.w400)),
          ),
        ]),
      );
}

/// A truck card (owner's picture 2).
class FleetTruckCard extends StatelessWidget {
  final FleetTruck truck;
  final AppStrings s;
  final bool busy, driver;
  final FleetJob? job;
  final int pending;
  const FleetTruckCard({super.key, required this.truck, required this.s, required this.busy, this.job, this.driver = false, this.pending = 0});

  @override
  Widget build(BuildContext context) {
    final status = busy ? AppColors.accent : AppColors.online;
    return Material(
      color: AppColors.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide(color: AppColors.line)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: ValueKey('fl-truck-${truck.id}'),
        onTap: () => context.pushOnce('/fleet/t/${truck.id}'),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                width: 74,
                height: 74,
                decoration: BoxDecoration(color: AppColors.accent.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(16)),
                child: Icon(Icons.local_shipping, size: 40, color: AppColors.accent),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(
                      flex: 3,
                      child: Text(truck.name,
                          maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: AppColors.text)),
                    ),
                    const SizedBox(width: 6),
                    // Shrinks in a long language on a narrow phone, never cut.
                    Flexible(
                      flex: 2,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.topRight,
                        child: Container(
                          key: ValueKey('fl-status-${truck.id}'),
                          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                          decoration: BoxDecoration(
                            color: status.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: status.withValues(alpha: 0.6)),
                          ),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            Container(width: 7, height: 7, decoration: BoxDecoration(color: status, shape: BoxShape.circle)),
                            const SizedBox(width: 5),
                            Text(s.t(busy ? 'fl_busy' : 'fl_free'), style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500, color: status)),
                          ]),
                        ),
                      ),
                    ),
                  ]),
                  if ((truck.plate ?? '').isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(8), border: Border.all(color: AppColors.line)),
                      child: Text(truck.plate!, style: TextStyle(fontSize: 14, color: AppColors.text, letterSpacing: 0.5)),
                    ),
                  ],
                  if ((truck.driverName ?? '').isNotEmpty || truck.driverId != null) ...[
                    const SizedBox(height: 6),
                    Row(children: [
                      Icon(Icons.person_outline, size: 18, color: AppColors.textSoft),
                      const SizedBox(width: 5),
                      Flexible(
                        child: Text(truck.driverName ?? s.t('fl_driver_linked'),
                            maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: AppColors.textSoft)),
                      ),
                    ]),
                  ],
                  // The chosen registered driver has not said yes yet (0131).
                  if (!driver && truck.driverWaiting) ...[
                    const SizedBox(height: 6),
                    FleetDriverWaitingPill(s: s, key: ValueKey('fl-driver-wait-${truck.id}')),
                  ],
                ]),
              ),
            ]),
            if (pending > 0) ...[
              const SizedBox(height: 8),
              Row(children: [
                Icon(Icons.hourglass_top, size: 16, color: AppColors.accent),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(s.t('fl_pending_n', {'n': '$pending'}),
                      key: ValueKey('fl-pending-${truck.id}'), maxLines: 2, style: TextStyle(color: AppColors.accent)),
                ),
              ]),
            ],
            Divider(height: 18, color: AppColors.line),
            if (busy && job != null)
              Row(children: [
                Icon(Icons.route_outlined, size: 20, color: AppColors.text),
                const SizedBox(width: 8),
                Expanded(
                  child: Text([fleetTime(job!.startAt), if (job!.route.isNotEmpty) job!.route].join(' • '),
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 15, color: AppColors.text)),
                ),
                Icon(Icons.chevron_right, color: AppColors.textSoft),
              ])
            else if (!driver)
              Wrap(alignment: WrapAlignment.end, spacing: 8, runSpacing: 8, children: [
                // Boşdur → an empty truck ad on Daşıyıcılar (owner, 20.11.2026: "əlaqələnsin").
                TextButton.icon(
                  key: ValueKey('fl-ad-${truck.id}'),
                  onPressed: () => context.pushOnce('/trucks/new'),
                  icon: const Icon(Icons.campaign_outlined, size: 18),
                  label: Text(s.t('fl_empty_ad')),
                ),
                OutlinedButton.icon(
                  key: ValueKey('fl-addjob-${truck.id}'),
                  style: OutlinedButton.styleFrom(foregroundColor: AppColors.accent, side: BorderSide(color: AppColors.accent)),
                  onPressed: () => showFleetJobForm(context, truckId: truck.id),
                  icon: const Icon(Icons.work_outline, size: 18),
                  label: Text(s.t('fl_add_job')),
                ),
              ])
            else
              Text(s.t('fl_free_now'), style: TextStyle(color: AppColors.textSoft)),
          ]),
        ),
      ),
    );
  }
}

/// One job in a list: "16:00 • Bakı → Gəncə", the truck under it.
class FleetJobRow extends StatelessWidget {
  final FleetJob job;
  final FleetTruck? truck;
  final AppStrings s;
  final String lang;
  const FleetJobRow({super.key, required this.job, required this.truck, required this.s, required this.lang});

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final sameDay = job.startAt.year == today.year && job.startAt.month == today.month && job.startAt.day == today.day;
    final when = sameDay ? fleetTime(job.startAt) : '${fleetDayLabel(s, job.startAt, lang)} ${fleetTime(job.startAt)}';
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: AppColors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: AppColors.line)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: ValueKey('fl-job-${job.id}'),
          onTap: truck == null ? null : () => context.pushOnce('/fleet/t/${truck!.id}'),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(color: AppColors.accent.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(12)),
                child: Icon(Icons.local_shipping_outlined, color: AppColors.accent),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text([when, if (job.route.isNotEmpty) job.route].join(' • '),
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w500, color: AppColors.text)),
                  if (truck != null)
                    Text([truck!.name, if ((truck!.plate ?? '').isNotEmpty) truck!.plate!].join(' · '),
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: AppColors.textSoft)),
                ]),
              ),
              Icon(Icons.chevron_right, color: AppColors.textSoft),
            ]),
          ),
        ),
      ),
    );
  }
}

/// "İş cədvəli": the open jobs from today on, by day.
class FleetPlan extends StatelessWidget {
  final AppStrings s;
  final String lang;
  final FleetData data;
  final String? uid;
  const FleetPlan({super.key, required this.s, required this.lang, required this.data, required this.uid});

  @override
  Widget build(BuildContext context) {
    final list = fleetUpcoming(data.jobs, DateTime.now());
    if (list.isEmpty) return _Empty(s: s, text: s.t('fl_plan_empty'));
    final out = <Widget>[];
    DateTime? day;
    for (final j in list) {
      final d = DateTime(j.startAt.year, j.startAt.month, j.startAt.day);
      if (day != d) {
        day = d;
        out.add(Padding(
          padding: const EdgeInsets.only(top: 6, bottom: 8),
          child: Text(fleetDayLabel(s, d, lang), style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.text)),
        ));
      }
      out.add(FleetJobRow(job: j, truck: data.truck(j.truckId), s: s, lang: lang));
    }
    return Column(key: const ValueKey('fl-plan'), crossAxisAlignment: CrossAxisAlignment.stretch, children: out);
  }
}

/// "Bugünkü plan" on the map (owner's picture 1): the next job of today with
/// "Cədvələ bax"; nothing for a visitor, before 0130 or with no job today.
class FleetTodayCard extends ConsumerWidget {
  final AppStrings s;
  const FleetTodayCard({super.key, required this.s});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (isSignedOut() || ref.watch(currentUserIdProvider) == null) return const SizedBox.shrink();
    final d = ref.watch(fleetProvider).valueOrNull;
    if (d == null) return const SizedBox.shrink();
    final today = fleetToday(d.jobs, DateTime.now());
    if (today.isEmpty) return const SizedBox.shrink();
    final j = today.first;
    final t = d.truck(j.truckId);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(key: const ValueKey('fl-today'), crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(s.t('fl_today_plan'), style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: AppColors.text)),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.line)),
          child: Row(children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(color: AppColors.accent.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(12)),
              child: Icon(Icons.local_shipping_outlined, color: AppColors.accent),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text([fleetTime(j.startAt), if (j.route.isNotEmpty) j.route].join(' • '),
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600, color: AppColors.text)),
                if (t != null) Text(t.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: AppColors.textSoft)),
              ]),
            ),
            const SizedBox(width: 8),
            OutlinedButton(
              key: const ValueKey('fl-today-open'),
              style: OutlinedButton.styleFrom(foregroundColor: AppColors.accent, side: BorderSide(color: AppColors.accent)),
              onPressed: () => context.go('/fleet?tab=plan'),
              child: Text(s.t('fl_see_plan')),
            ),
          ]),
        ),
      ]),
    );
  }
}

/// "⏳ Sürücü təsdiqi gözləyir" (0131).
class FleetDriverWaitingPill extends StatelessWidget {
  final AppStrings s;
  const FleetDriverWaitingPill({super.key, required this.s});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(color: AppColors.urgentBg, borderRadius: BorderRadius.circular(20)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.hourglass_top, size: 14, color: AppColors.urgentFg),
          const SizedBox(width: 5),
          Flexible(
            child: Text(s.t('fl_driver_waiting'),
                maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, color: AppColors.urgentFg)),
          ),
        ]),
      );
}
