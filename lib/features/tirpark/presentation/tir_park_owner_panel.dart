import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/localization/app_strings.dart';
import '../../../core/theme/app_theme.dart';
import '../../finance/domain/finance_models.dart';
import '../data/tir_park_repository.dart';
import '../domain/tir_park.dart';
import 'tir_park_booking.dart';
import 'tir_park_manage.dart' show TirParkNewPayments;

/// "1 gün 4 saat" · "5 saat" · "35 dəq".
String tirParkDuration(AppStrings s, Duration d) {
  if (d.isNegative) d = Duration.zero;
  final days = d.inDays, hours = d.inHours % 24, mins = d.inMinutes % 60;
  if (days > 0) {
    return hours > 0 ? '${s.t('tpo_dur_days', {'n': '$days'})} ${s.t('tpo_dur_hours', {'n': '$hours'})}' : s.t('tpo_dur_days', {'n': '$days'});
  }
  if (hours > 0) return s.t('tpo_dur_hours', {'n': '$hours'});
  return s.t('tpo_dur_min', {'n': '$mins'});
}

String _hm(DateTime t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

/// The owner's panel (owner, 03.11.2026; picture "Sahibkar paneli"):
/// Ümumi · Maşınlar · Ayarlar. Stage 2 adds İşçilər and Hesabat.
class TirParkOwnerPanel extends ConsumerStatefulWidget {
  final List<TirPark> parks;
  final AppStrings s;
  /// The park's settings, payment details and bookings (Ayarlar).
  final Widget Function(TirPark park) settings;
  const TirParkOwnerPanel({super.key, required this.parks, required this.s, required this.settings});

  @override
  ConsumerState<TirParkOwnerPanel> createState() => _TirParkOwnerPanelState();
}

class _TirParkOwnerPanelState extends ConsumerState<TirParkOwnerPanel> {
  int _tab = 0;
  String? _parkId;

  AppStrings get s => widget.s;
  TirPark get park => widget.parks.firstWhere((p) => p.id == _parkId, orElse: () => widget.parks.first);

  void _refresh() {
    ref.invalidate(tirParkSummaryProvider(park.id));
    ref.invalidate(tirParkParkedProvider(park.id));
    ref.invalidate(tirParkFeedProvider(park.id));
    ref.invalidate(managerBookingsProvider(park.id));
    ref.invalidate(tirParkManagerPendingProvider);
    ref.invalidate(tirParkWorkersProvider(park.id));
    ref.invalidate(tirParkActivityProvider(park.id));
    ref.invalidate(tirParkReportProvider(park.id));
  }

  /// Ayarlar opens from the gear (the four tabs follow the owner's picture).
  void _openSettings(TirPark p) => Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          appBar: AppBar(title: Text(s.t('tpo_tab_settings'))),
          body: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 40), children: [widget.settings(p)]),
        ),
      ));

  Future<void> _pickPark() async {
    final id = await showModalBottomSheet<String>(
      context: context,
      useRootNavigator: true,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: ListView(shrinkWrap: true, children: [
          for (final p in widget.parks)
            ListTile(
              key: ValueKey('tpo-park-${p.id}'),
              leading: const Icon(Icons.local_parking),
              title: Text(p.name),
              selected: p.id == park.id,
              onTap: () => Navigator.of(ctx).pop(p.id),
            ),
        ]),
      ),
    );
    if (id != null && mounted) setState(() => _parkId = id);
  }

  @override
  Widget build(BuildContext context) {
    final p = park;
    final summary = ref.watch(tirParkSummaryProvider(p.id)).valueOrNull;
    final open = summary?.open ?? p.bookingOpen;
    final header = Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Material(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          key: const ValueKey('tpo-park'),
          borderRadius: BorderRadius.circular(14),
          onTap: widget.parks.length > 1 ? _pickPark : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(children: [
              Icon(Icons.location_on, color: AppColors.accent),
              const SizedBox(width: 10),
              Expanded(
                child: Text(p.name.toUpperCase(),
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.text)),
              ),
              Container(
                key: const ValueKey('tpo-state'),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: (open ? AppColors.online : AppColors.textSoft).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.circle, size: 9, color: open ? AppColors.online : AppColors.textSoft),
                  const SizedBox(width: 5),
                  Text(s.t(open ? 'tpo_working' : 'tpo_closed'),
                      style: TextStyle(fontSize: 13, color: open ? AppColors.online : AppColors.textSoft)),
                ]),
              ),
              if (widget.parks.length > 1) Icon(Icons.chevron_right, color: AppColors.textSoft),
              IconButton(
                key: const ValueKey('tpo-settings'),
                tooltip: s.t('tpo_tab_settings'),
                visualDensity: VisualDensity.compact,
                onPressed: () => _openSettings(p),
                icon: Icon(Icons.settings_outlined, color: AppColors.textSoft),
              ),
            ]),
          ),
        ),
      ),
    );
    final body = switch (_tab) {
      0 => _Overview(park: p, s: s, onRefresh: _refresh, onOpenWorkers: () => setState(() => _tab = 2)),
      1 => TirParkCars(park: p, s: s, onChanged: _refresh),
      2 => TirParkWorkersTab(park: p, s: s),
      _ => _Report(park: p, s: s),
    };
    return Column(children: [
      header,
      Expanded(child: body),
      NavigationBar(
        key: const ValueKey('tpo-nav'),
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: [
          NavigationDestination(icon: const Icon(Icons.home_outlined), selectedIcon: const Icon(Icons.home), label: s.t('tpo_tab_overview')),
          NavigationDestination(
              icon: const Icon(Icons.local_shipping_outlined), selectedIcon: const Icon(Icons.local_shipping), label: s.t('tpo_tab_cars')),
          NavigationDestination(icon: const Icon(Icons.groups_outlined), selectedIcon: const Icon(Icons.groups), label: s.t('tpo_tab_workers')),
          NavigationDestination(icon: const Icon(Icons.bar_chart), label: s.t('tpo_tab_report')),
        ],
      ),
    ]);
  }
}

class _Stat extends StatelessWidget {
  final IconData icon;
  final String label, value, keyName;
  final Color? color;
  const _Stat({required this.icon, required this.label, required this.value, required this.keyName, this.color});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.line),
        ),
        child: Column(children: [
          Icon(icon, size: 22, color: color ?? AppColors.text),
          const SizedBox(height: 4),
          Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: AppColors.textSoft)),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(value, key: ValueKey(keyName), style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: color ?? AppColors.text)),
          ),
        ]),
      );
}

/// Tutum · Parkda · Boş (+ Bu gün on the overview).
class _Stats extends StatelessWidget {
  final TirParkSummary? sum;
  final AppStrings s;
  final bool withToday;
  const _Stats({required this.sum, required this.s, this.withToday = false});

  @override
  Widget build(BuildContext context) {
    final v = sum;
    String n(int? x) => v == null ? '…' : '$x';
    final cells = [
      _Stat(icon: Icons.layers_outlined, label: s.t('tpo_capacity'), value: n(v?.capacity), keyName: 'tpo-cap'),
      _Stat(icon: Icons.local_shipping_outlined, label: s.t('tpo_in'), value: n(v?.inPark), keyName: 'tpo-in'),
      _Stat(icon: Icons.check_circle_outline, label: s.t('tpo_free'), value: n(v?.free), keyName: 'tpo-free', color: AppColors.online),
      if (withToday)
        _Stat(
          icon: Icons.payments_outlined,
          label: s.t('tpo_today'),
          value: v == null ? '…' : money(v.todayPaid, v.currency),
          keyName: 'tpo-today',
          color: AppColors.accent,
        ),
    ];
    return Row(children: [
      for (var i = 0; i < cells.length; i++) ...[
        if (i > 0) const SizedBox(width: 6),
        Expanded(child: cells[i]),
      ],
    ]);
  }
}

/// Ümumi: the numbers, money run up in the park (not taken yet), new
/// receipts and "Parkın gedişatı".
class _Overview extends ConsumerWidget {
  final TirPark park;
  final AppStrings s;
  final VoidCallback onRefresh;
  final VoidCallback onOpenWorkers;
  const _Overview({required this.park, required this.s, required this.onRefresh, required this.onOpenWorkers});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sum = ref.watch(tirParkSummaryProvider(park.id)).valueOrNull;
    final feedAsync = ref.watch(tirParkFeedProvider(park.id));
    final feed = feedAsync.valueOrNull ?? const <TirParkFeedItem>[];
    return RefreshIndicator(
      onRefresh: () async => onRefresh(),
      child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 40), children: [
        _Stats(sum: sum, s: s, withToday: true),
        if (sum != null) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.line)),
            child: Row(children: [
              Icon(Icons.hourglass_bottom, size: 20, color: AppColors.promoVip),
              const SizedBox(width: 8),
              Expanded(
                child: Text(s.t('tpo_accruing', {'amount': money(sum.accruing, sum.currency)}),
                    key: const ValueKey('tpo-accruing'), style: TextStyle(color: AppColors.text)),
              ),
            ]),
          ),
        ],
        // Workers waiting for approval (0088) → İşçilər.
        _WorkersWaiting(park: park, s: s, onOpen: onOpenWorkers),
        // Receipts waiting for "Ödənişi təsdiqlə".
        TirParkNewPayments(parkId: park.id, s: s),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
          decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.line)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Icon(Icons.swap_horiz, color: AppColors.text),
              const SizedBox(width: 8),
              Expanded(child: Text(s.t('tpo_feed'), style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: AppColors.text))),
              Text(s.t('tpo_feed_sub'), style: TextStyle(fontSize: 13, color: AppColors.textSoft)),
            ]),
            const SizedBox(height: 6),
            if (feedAsync.isLoading && !feedAsync.hasValue) const Padding(padding: EdgeInsets.all(12), child: Center(child: CircularProgressIndicator())),
            if (feedAsync.hasValue && feed.isEmpty)
              Padding(padding: const EdgeInsets.symmetric(vertical: 10), child: Text(s.t('tpo_feed_none'), style: TextStyle(color: AppColors.textSoft))),
            for (final e in feed.take(20)) _FeedRow(e: e, s: s),
          ]),
        ),
        const SizedBox(height: 14),
        _Activity(park: park, s: s),
      ]),
    );
  }
}

/// "n işçi təsdiq gözləyir" on Ümumi (0088): a tap opens İşçilər.
class _WorkersWaiting extends ConsumerWidget {
  final TirPark park;
  final AppStrings s;
  final VoidCallback onOpen;
  const _WorkersWaiting({required this.park, required this.s, required this.onOpen});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final n = [
      for (final w in ref.watch(tirParkWorkersProvider(park.id)).valueOrNull?.workers ?? const <TirParkWorker>[])
        if (w.isPending) w,
    ].length;
    if (n == 0) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Material(
        color: AppColors.promoVip.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          key: const ValueKey('tpo-workers-waiting'),
          borderRadius: BorderRadius.circular(12),
          onTap: onOpen,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(children: [
              Icon(Icons.person_add_alt_1, color: AppColors.promoVip),
              const SizedBox(width: 10),
              Expanded(child: Text(s.t('tpo_workers_pending', {'n': '$n'}), style: TextStyle(fontWeight: FontWeight.w500, color: AppColors.text))),
              Icon(Icons.chevron_right, color: AppColors.textSoft),
            ]),
          ),
        ),
      ),
    );
  }
}

/// "İşçi fəaliyyəti": who added / let out which truck (0087).
class _Activity extends ConsumerWidget {
  final TirPark park;
  final AppStrings s;
  const _Activity({required this.park, required this.s});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(tirParkActivityProvider(park.id));
    final list = async.valueOrNull ?? const <TirParkFeedItem>[];
    return Container(
      key: const ValueKey('tpo-activity'),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
      decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.line)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Icon(Icons.groups_outlined, color: AppColors.text),
          const SizedBox(width: 8),
          Text(s.t('tpo_activity'), style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: AppColors.text)),
        ]),
        const SizedBox(height: 6),
        if (async.hasValue && list.isEmpty)
          Padding(padding: const EdgeInsets.symmetric(vertical: 10), child: Text(s.t('tpo_activity_none'), style: TextStyle(color: AppColors.textSoft))),
        for (final e in list.take(20))
          Container(
            decoration: BoxDecoration(border: Border(top: BorderSide(color: AppColors.line))),
            padding: const EdgeInsets.symmetric(vertical: 9),
            child: Row(children: [
              Icon(Icons.person_outline, size: 20, color: AppColors.text),
              const SizedBox(width: 10),
              Expanded(
                child: Text.rich(
                  TextSpan(children: [
                    TextSpan(text: e.by ?? '', style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.text)),
                    TextSpan(
                      text: ' · ${s.t(e.kind == 'out' ? 'tpo_act_out' : 'tpo_act_in', {'plate': e.plate})}',
                      style: TextStyle(color: AppColors.text),
                    ),
                  ]),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(_hm(e.at), style: TextStyle(fontSize: 13, color: AppColors.textSoft)),
            ]),
          ),
      ]),
    );
  }
}

class _FeedRow extends StatelessWidget {
  final TirParkFeedItem e;
  final AppStrings s;
  const _FeedRow({required this.e, required this.s});

  @override
  Widget build(BuildContext context) {
    final (icon, color, label) = switch (e.kind) {
      'out' => (Icons.logout, AppColors.danger, s.t('tpo_ev_out')),
      'booking' => (Icons.event_outlined, AppColors.promoVip, s.t('tpo_ev_booking')),
      'paid' => (Icons.verified_outlined, AppColors.online, s.t('tpo_ev_paid')),
      _ => (Icons.login, AppColors.online, s.t('tpo_ev_in')),
    };
    final today = DateTime.now();
    final when = e.at.year == today.year && e.at.month == today.month && e.at.day == today.day ? _hm(e.at) : tirParkTime(e.at);
    return Container(
      decoration: BoxDecoration(border: Border(top: BorderSide(color: AppColors.line))),
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(width: 10),
        Expanded(
          child: Text.rich(
            TextSpan(children: [
              TextSpan(text: e.plate, style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.text)),
              TextSpan(text: ' · $label', style: TextStyle(color: AppColors.text)),
              if (e.amount != null && e.amount! > 0) TextSpan(text: ' · ${money(e.amount!, 'AZN')}', style: TextStyle(color: AppColors.textSoft)),
            ]),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        Text(when, style: TextStyle(fontSize: 13, color: AppColors.textSoft)),
      ]),
    );
  }
}

/// Maşınlar (owner) and the İşçi profili (worker): "+ Maşın əlavə et", search by plate, the cars in the park (time,
/// money so far, "Çıxış") and today's paid bookings not come yet.
class TirParkCars extends ConsumerStatefulWidget {
  final TirPark park;
  final AppStrings s;
  final VoidCallback onChanged;
  const TirParkCars({super.key, required this.park, required this.s, required this.onChanged});

  @override
  ConsumerState<TirParkCars> createState() => _CarsState();
}

class _CarsState extends ConsumerState<TirParkCars> {
  final _search = TextEditingController();
  Timer? _tick;
  bool _busy = false;

  AppStrings get s => widget.s;

  @override
  void initState() {
    super.initState();
    // Time and money in the list move on every minute.
    _tick = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _snack(String text) {
    final m = ScaffoldMessenger.of(context);
    m.hideCurrentSnackBar();
    m.showSnackBar(SnackBar(content: Text(text)));
  }

  String _err(Object e) => s.t(switch (e) {
        TirParkRefused(reason: 'already_in') => 'tpo_err_already_in',
        TirParkRefused(reason: 'no_space') => 'tpo_err_no_space',
        TirParkRefused(reason: 'payment_in_review') => 'tpo_err_review',
        TirParkRefused(reason: 'invalid_plate') => 'tpb_err_plate',
        TirParkRefused(reason: 'already_out') => 'tpo_err_already_out',
        _ => 'tpb_err_generic',
      });

  Future<void> _add() async {
    final plate = await showDialog<String>(context: context, builder: (_) => _PlateDialog(s: s));
    if (plate == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final st = await ref.read(tirParkRepositoryProvider).stayEnter(widget.park.id, plate);
      _snack(st.bookingNo == null
          ? s.t('tpo_enter_ok', {'plate': st.plate})
          : '${s.t('tpo_enter_ok', {'plate': st.plate})} · ${s.t('tpo_enter_booked')}');
      widget.onChanged();
    } catch (e) {
      _snack(_err(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _exit(TirParkStay st) async {
    final now = DateTime.now();
    final amount = st.amountAt(now);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(st.plate),
        content: Text(
          s.t('tpo_exit_q', {'dur': tirParkDuration(s, now.difference(st.enteredAt)), 'amount': money(amount, st.currency)}),
          key: const ValueKey('tpo-exit-text'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(s.t('common_cancel'))),
          FilledButton(key: const ValueKey('tpo-exit-go'), onPressed: () => Navigator.pop(ctx, true), child: Text(s.t('tpo_exit_btn'))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    try {
      final taken = await ref.read(tirParkRepositoryProvider).stayExit(st.id);
      _snack(s.t('tpo_exit_ok', {'plate': st.plate, 'amount': money(taken, st.currency)}));
      widget.onChanged();
    } catch (e) {
      _snack(_err(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final park = widget.park;
    final sum = ref.watch(tirParkSummaryProvider(park.id)).valueOrNull;
    final async = ref.watch(tirParkParkedProvider(park.id));
    final data = async.valueOrNull ?? const TirParkParked();
    final q = _search.text.trim().toUpperCase().replaceAll(RegExp(r'[^\p{L}\p{N}]', unicode: true), '');
    bool hit(String plate) => q.isEmpty || plate.toUpperCase().replaceAll(RegExp(r'[^\p{L}\p{N}]', unicode: true), '').contains(q);
    final list = [for (final st in data.inPark) if (hit(st.plate)) st];
    final expected = [for (final b in data.expected) if (hit(b.plate)) b];
    final now = DateTime.now();
    return RefreshIndicator(
      onRefresh: () async => widget.onChanged(),
      child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 40), children: [
        _Stats(sum: sum, s: s),
        const SizedBox(height: 12),
        FilledButton.icon(
          key: const ValueKey('tpo-add'),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(54), textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w500)),
          onPressed: _busy ? null : _add,
          icon: const Icon(Icons.add, size: 26),
          label: Text(s.t('tpo_add_car')),
        ),
        const SizedBox(height: 10),
        TextField(
          key: const ValueKey('tpo-search'),
          controller: _search,
          textCapitalization: TextCapitalization.characters,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(prefixIcon: const Icon(Icons.search), hintText: s.t('tpo_search')),
        ),
        const SizedBox(height: 14),
        Row(children: [
          Icon(Icons.local_shipping_outlined, color: AppColors.text),
          const SizedBox(width: 8),
          Expanded(child: Text(s.t('tpo_in_list'), style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: AppColors.text))),
          Text('(${data.inPark.length})', key: const ValueKey('tpo-in-count'), style: TextStyle(color: AppColors.textSoft)),
        ]),
        Padding(
          padding: const EdgeInsets.only(top: 2, bottom: 8),
          child: Text(s.t('tpo_in_hint'), style: TextStyle(fontSize: 13, color: AppColors.textSoft)),
        ),
        if (async.isLoading && !async.hasValue) const Padding(padding: EdgeInsets.all(20), child: Center(child: CircularProgressIndicator())),
        if (async.hasError) Text(s.t('tpb_err_generic'), style: TextStyle(color: AppColors.danger)),
        for (final st in list)
          Container(
            key: ValueKey('tpo-car-${st.id}'),
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
            decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.line)),
            child: Row(children: [
              Icon(Icons.local_shipping_outlined, color: AppColors.text),
              const SizedBox(width: 8),
              Expanded(
                flex: 5,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(st.plate, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.text)),
                  if (st.bookingNo != null)
                    Text(s.t('tpo_booked'), style: TextStyle(fontSize: 12, color: AppColors.online)),
                ]),
              ),
              Expanded(
                flex: 5,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Icon(Icons.schedule, size: 15, color: AppColors.textSoft),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(tirParkDuration(s, now.difference(st.enteredAt)),
                          key: ValueKey('tpo-dur-${st.id}'), style: TextStyle(fontSize: 13, color: AppColors.text)),
                    ),
                  ]),
                  Text(money(st.amountAt(now), st.currency),
                      key: ValueKey('tpo-amount-${st.id}'), style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.text)),
                ]),
              ),
              OutlinedButton.icon(
                key: ValueKey('tpo-exit-${st.id}'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.accent,
                  side: BorderSide(color: AppColors.accent),
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                ),
                onPressed: _busy ? null : () => _exit(st),
                icon: const Icon(Icons.logout, size: 18),
                label: Text(s.t('tpo_exit')),
              ),
            ]),
          ),
        if (async.hasValue && list.isEmpty)
          Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Text(s.t('tpo_none_in'), style: TextStyle(color: AppColors.textSoft))),
        if (expected.isNotEmpty) ...[
          const SizedBox(height: 14),
          Text(s.t('tpo_expected'), style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.text)),
          const SizedBox(height: 6),
          for (final b in expected)
            ListTile(
              key: ValueKey('tpo-exp-${b.id}'),
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.event_available_outlined, color: AppColors.promoVip),
              title: Text(b.plate, style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.text)),
              subtitle: Text('${tirParkDay(b.startAt)} → ${tirParkDay(b.endAt)} · ${s.t('tpb_st_${b.status}')}'),
            ),
        ],
      ]),
    );
  }
}

/// "Maşın əlavə et": the truck's plate (tidied like the server does).
class _PlateDialog extends StatefulWidget {
  final AppStrings s;
  const _PlateDialog({required this.s});

  @override
  State<_PlateDialog> createState() => _PlateDialogState();
}

class _PlateDialogState extends State<_PlateDialog> {
  final _c = TextEditingController();
  bool _bad = false;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _go() {
    final p = tidyTruckPlate(_c.text);
    if (p == null) {
      setState(() => _bad = true);
      return;
    }
    Navigator.of(context).pop(p);
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.s;
    return AlertDialog(
      title: Text(s.t('tpo_add_car')),
      content: TextField(
        key: const ValueKey('tpo-plate'),
        controller: _c,
        autofocus: true,
        textCapitalization: TextCapitalization.characters,
        maxLength: 15,
        onSubmitted: (_) => _go(),
        decoration: InputDecoration(
          labelText: s.t('tpb_plate'),
          hintText: s.t('tpb_plate_hint'),
          counterText: '',
          errorText: _bad ? s.t('tpb_err_plate') : null,
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(s.t('common_cancel'))),
        FilledButton(key: const ValueKey('tpo-plate-go'), onPressed: _go, child: Text(s.t('tpo_enter_btn'))),
      ],
    );
  }
}

/// İşçilər (0087): invite by a one-time code (the worker accepts it with his
/// own account — never automatically), open invitations, the workers and
/// what each did today, take one off.
/// İşçilər: invitations, requests, workers. The owner sees everything and
/// names the park's admin; the park's admin (0089, [owner] false) invites,
/// approves and takes off ordinary workers only.
class TirParkWorkersTab extends ConsumerStatefulWidget {
  final TirPark park;
  final AppStrings s;
  final bool owner;
  const TirParkWorkersTab({super.key, required this.park, required this.s, this.owner = true});

  @override
  ConsumerState<TirParkWorkersTab> createState() => _WorkersState();
}

class _WorkersState extends ConsumerState<TirParkWorkersTab> {
  bool _busy = false;
  AppStrings get s => widget.s;

  void _snack(String t) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(t)));

  Future<void> _invite() async {
    setState(() => _busy = true);
    try {
      final inv = await ref.read(tirParkRepositoryProvider).inviteCreate(widget.park.id);
      ref.invalidate(tirParkWorkersProvider(widget.park.id));
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(s.t('tpo_invite_title')),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SelectableText(inv.code,
                key: const ValueKey('tpo-invite-code'),
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 30, letterSpacing: 4, fontWeight: FontWeight.w600, color: AppColors.text)),
            const SizedBox(height: 10),
            Text(s.t('tpo_invite_how', {'park': widget.park.name}), style: TextStyle(color: AppColors.textSoft, height: 1.35)),
          ]),
          actions: [
            TextButton(
              onPressed: () {
                // Only the code (owner, 03.11.2026): it is pasted as it is.
                Clipboard.setData(ClipboardData(text: inv.code));
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.t('tpb_copied'))));
              },
              child: Text(s.t('tpo_invite_copy')),
            ),
            FilledButton(onPressed: () => Navigator.pop(ctx), child: Text(s.t('tpo_close'))),
          ],
        ),
      );
    } on TirParkRefused catch (e) {
      _snack(s.t(e.reason == 'too_many' ? 'tpo_err_invites' : 'tpb_err_generic'));
    } catch (_) {
      _snack(s.t('tpb_err_generic'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cancel(TirParkInvite i) async {
    try {
      await ref.read(tirParkRepositoryProvider).inviteCancel(i.id);
    } catch (_) {
      _snack(s.t('tpb_err_generic'));
    }
    ref.invalidate(tirParkWorkersProvider(widget.park.id));
  }

  // A worker's request (0088): let him in or not.
  Future<void> _decide(TirParkWorker w, bool approve) async {
    setState(() => _busy = true);
    try {
      final repo = ref.read(tirParkRepositoryProvider);
      if (approve) {
        await repo.workerApprove(widget.park.id, w.userId);
      } else {
        await repo.workerReject(widget.park.id, w.userId);
      }
      _snack(s.t(approve ? 'tpo_worker_approved' : 'tpo_worker_rejected', {'name': w.name}));
    } catch (_) {
      _snack(s.t('tpb_err_generic'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    ref.invalidate(tirParkWorkersProvider(widget.park.id));
    ref.invalidate(tirParkPendingWorkersProvider);
    ref.invalidate(myWorkParksProvider);
  }

  // The owner names / un-names the park's admin (0089); one per park.
  Future<void> _setAdmin(TirParkWorker w, bool on) async {
    setState(() => _busy = true);
    try {
      await ref.read(tirParkRepositoryProvider).workerSetAdmin(widget.park.id, w.userId, on);
      _snack(s.t(on ? 'tpo_admin_set' : 'tpo_admin_unset', {'name': w.name}));
    } catch (_) {
      _snack(s.t('tpb_err_generic'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    ref.invalidate(tirParkWorkersProvider(widget.park.id));
  }

  Future<void> _remove(TirParkWorker w) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: Text(s.t('tpo_worker_remove_q', {'name': w.name})),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(s.t('common_cancel'))),
          FilledButton(
            key: const ValueKey('tpo-remove-go'),
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(s.t('tpo_worker_remove')),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(tirParkRepositoryProvider).workerRemove(widget.park.id, w.userId);
    } catch (_) {
      _snack(s.t('tpb_err_generic'));
    }
    ref.invalidate(tirParkWorkersProvider(widget.park.id));
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(tirParkWorkersProvider(widget.park.id));
    final data = async.valueOrNull ?? const TirParkWorkers();
    final active = [for (final w in data.workers) if (w.active) w];
    final pending = [for (final w in data.workers) if (w.isPending) w];
    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(tirParkWorkersProvider(widget.park.id)),
      child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 40), children: [
        Text(s.t(widget.owner ? 'tpo_workers_hint' : 'tpo_admin_hint'), style: TextStyle(color: AppColors.textSoft, height: 1.35)),
        const SizedBox(height: 10),
        FilledButton.icon(
          key: const ValueKey('tpo-invite'),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
          onPressed: _busy ? null : _invite,
          icon: const Icon(Icons.person_add_alt_1),
          label: Text(s.t('tpo_invite')),
        ),
        if (async.hasError) Padding(padding: const EdgeInsets.only(top: 10), child: Text(s.t('tpb_err_generic'), style: TextStyle(color: AppColors.danger))),
        // Requests waiting for the owner (0088).
        if (pending.isNotEmpty) ...[
          const SizedBox(height: 14),
          Text(s.t('tpo_workers_pending', {'n': '${pending.length}'}),
              key: const ValueKey('tpo-workers-pending'),
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.promoVip)),
          for (final w in pending)
            Container(
              key: ValueKey('tpo-wreq-${w.userId}'),
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.promoVip.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.promoVip.withValues(alpha: 0.4)),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text(w.name, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.text)),
                Text(
                  [
                    if ((w.accountName ?? '').isNotEmpty && w.accountName != w.name) s.t('tpo_worker_account', {'name': w.accountName!}),
                    if ((w.phone ?? '').isNotEmpty) w.phone!,
                  ].join(' · '),
                  style: TextStyle(fontSize: 13, color: AppColors.textSoft),
                ),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(
                    child: FilledButton(
                      key: ValueKey('tpo-wreq-ok-${w.userId}'),
                      onPressed: _busy ? null : () => _decide(w, true),
                      child: Text(s.t('tpo_worker_approve')),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton(
                      key: ValueKey('tpo-wreq-no-${w.userId}'),
                      onPressed: _busy ? null : () => _decide(w, false),
                      child: Text(s.t('tpm_reject')),
                    ),
                  ),
                ]),
              ]),
            ),
        ],
        if (data.invites.isNotEmpty) ...[
          const SizedBox(height: 14),
          Text(s.t('tpo_invites_open'), style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.text)),
          for (final i in data.invites)
            ListTile(
              key: ValueKey('tpo-inv-${i.id}'),
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.mail_outline, color: AppColors.promoVip),
              title: Text(i.code, style: TextStyle(letterSpacing: 2, fontWeight: FontWeight.w600, color: AppColors.text)),
              subtitle: i.expiresAt == null ? null : Text(s.t('tpo_invite_until', {'t': tirParkTime(i.expiresAt!)})),
              trailing: TextButton(key: ValueKey('tpo-inv-cancel-${i.id}'), onPressed: () => _cancel(i), child: Text(s.t('tpb_cancel'))),
            ),
        ],
        const SizedBox(height: 14),
        Text(s.t('tpo_workers_n', {'n': '${active.length}'}), style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.text)),
        if (async.hasValue && active.isEmpty)
          Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Text(s.t('tpo_workers_none'), style: TextStyle(color: AppColors.textSoft))),
        for (final w in active)
          ListTile(
            key: ValueKey('tpo-worker-${w.userId}'),
            contentPadding: EdgeInsets.zero,
            leading: Icon(w.isAdmin ? Icons.admin_panel_settings : Icons.person_outline,
                color: w.isAdmin ? AppColors.accent : AppColors.text),
            title: Text(w.name, style: TextStyle(fontWeight: FontWeight.w500, color: AppColors.text)),
            subtitle: Text([
              if (w.isAdmin) s.t('tpo_admin'),
              if ((w.phone ?? '').isNotEmpty) w.phone!,
              s.t('tpo_worker_today', {'in': '${w.todayIn}', 'out': '${w.todayOut}'}),
            ].join(' · ')),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              // Only the owner names the admin (0089).
              if (widget.owner)
                IconButton(
                  key: ValueKey('tpo-worker-admin-${w.userId}'),
                  tooltip: s.t(w.isAdmin ? 'tpo_admin_take' : 'tpo_admin_make'),
                  icon: Icon(w.isAdmin ? Icons.admin_panel_settings : Icons.admin_panel_settings_outlined,
                      color: w.isAdmin ? AppColors.accent : AppColors.textSoft),
                  onPressed: _busy ? null : () => _setAdmin(w, !w.isAdmin),
                ),
              // The park's admin takes off ordinary workers only.
              if (widget.owner || !w.isAdmin)
                IconButton(
                  key: ValueKey('tpo-worker-remove-${w.userId}'),
                  tooltip: s.t('tpo_worker_remove'),
                  icon: Icon(Icons.person_remove_outlined, color: AppColors.danger),
                  onPressed: () => _remove(w),
                ),
            ]),
          ),
      ]),
    );
  }
}

/// Hesabat (0087): the last 30 days — trucks in / out and the money taken.
class _Report extends ConsumerWidget {
  final TirPark park;
  final AppStrings s;
  const _Report({required this.park, required this.s});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(tirParkReportProvider(park.id));
    final days = async.valueOrNull ?? const <TirParkReportDay>[];
    final total = days.fold<double>(0, (a, d) => a + d.total);
    final ins = days.fold<int>(0, (a, d) => a + d.entries);
    final outs = days.fold<int>(0, (a, d) => a + d.exits);
    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(tirParkReportProvider(park.id)),
      child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 40), children: [
        Text(s.t('tpo_report_title'), style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: AppColors.text)),
        const SizedBox(height: 8),
        if (async.isLoading && !async.hasValue) const Padding(padding: EdgeInsets.all(20), child: Center(child: CircularProgressIndicator())),
        if (async.hasError) Text(s.t('tpb_err_generic'), style: TextStyle(color: AppColors.danger)),
        if (async.hasValue) ...[
          Row(children: [
            Expanded(child: _Stat(icon: Icons.login, label: s.t('tpo_report_in'), value: '$ins', keyName: 'tpo-rep-in')),
            const SizedBox(width: 6),
            Expanded(child: _Stat(icon: Icons.logout, label: s.t('tpo_report_out'), value: '$outs', keyName: 'tpo-rep-out')),
            const SizedBox(width: 6),
            Expanded(
                child: _Stat(
                    icon: Icons.payments_outlined,
                    label: s.t('tpo_report_paid'),
                    value: money(total, park.currency),
                    keyName: 'tpo-rep-total',
                    color: AppColors.accent)),
          ]),
          const SizedBox(height: 12),
          for (final d in days)
            if (d.entries > 0 || d.exits > 0 || d.total > 0)
              Container(
                key: ValueKey('tpo-rep-${d.day.toIso8601String().substring(0, 10)}'),
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.line))),
                child: Row(children: [
                  SizedBox(width: 60, child: Text(tirParkDay(d.day), style: TextStyle(fontWeight: FontWeight.w500, color: AppColors.text))),
                  Expanded(
                    child: Text(s.t('tpo_report_row', {'in': '${d.entries}', 'out': '${d.exits}'}), style: TextStyle(color: AppColors.textSoft)),
                  ),
                  Text(money(d.total, park.currency), style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.text)),
                ]),
              ),
          if (days.every((d) => d.entries == 0 && d.exits == 0 && d.total == 0))
            Text(s.t('tpo_report_none'), style: TextStyle(color: AppColors.textSoft)),
        ],
      ]),
    );
  }
}
