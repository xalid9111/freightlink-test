import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/localization/app_strings.dart';
import '../../../core/localization/locale_controller.dart';
import '../../../core/theme/app_theme.dart';
import '../../finance/domain/finance_models.dart';
import '../../finance/presentation/card_checkout.dart';
import '../../finance/presentation/finance_providers.dart';
import '../data/tir_park_repository.dart';
import '../domain/tir_park.dart';

/// "12.11 18:30" (local time).
String tirParkTime(DateTime t) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(t.day)}.${two(t.month)} ${two(t.hour)}:${two(t.minute)}';
}

String tirParkUnitLabel(AppStrings s, String unit) => s.t(unit == 'day' ? 'tpb_unit_day' : 'tpb_unit_hour');

Color tirParkStatusColor(String status) => switch (status) {
      'confirmed' || 'checked_in' => AppColors.online,
      'completed' => AppColors.blue,
      'pending_payment' => AppColors.promoVip,
      _ => AppColors.textSoft,
    };

/// The booking part of a park's page (owner, 01.11.2026, 0079): price,
/// capacity, free places for the chosen time, arrival / departure, TIRs,
/// "Yeri rezerv et" → summary with the conditions → the existing card
/// checkout. Everything is decided on the server.
class TirParkBookingSection extends ConsumerStatefulWidget {
  final TirPark park;
  final AppStrings s;
  const TirParkBookingSection({super.key, required this.park, required this.s});

  @override
  ConsumerState<TirParkBookingSection> createState() => _TirParkBookingSectionState();
}

class _TirParkBookingSectionState extends ConsumerState<TirParkBookingSection> {
  late DateTime _from = _roundUp(DateTime.now().add(const Duration(hours: 1)));
  late DateTime _to = _from.add(Duration(hours: widget.park.priceUnit == 'day' ? 24 : 4));
  int _trucks = 1;
  int? _free;
  bool _busy = false;
  String? _error;

  static DateTime _roundUp(DateTime t) => DateTime(t.year, t.month, t.day, t.hour).add(Duration(minutes: t.minute > 0 ? 60 : 0));

  AppStrings get s => widget.s;
  TirPark get park => widget.park;

  @override
  void initState() {
    super.initState();
    _loadFree();
  }

  Future<void> _loadFree() async {
    setState(() => _free = null);
    if (!_to.isAfter(_from)) return;
    try {
      final n = await ref.read(tirParkRepositoryProvider).freePlaces(park.id, _from, _to);
      if (mounted) setState(() => _free = n);
    } catch (_) {
      if (mounted) setState(() => _free = null);
    }
  }

  Future<void> _pick(bool start) async {
    final cur = start ? _from : _to;
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: cur,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 60)),
    );
    if (d == null || !mounted) return;
    final t = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(cur));
    if (t == null || !mounted) return;
    final v = DateTime(d.year, d.month, d.day, t.hour, t.minute);
    setState(() {
      if (start) {
        final len = _to.difference(_from);
        _from = v;
        if (!_to.isAfter(_from)) _to = _from.add(len.isNegative || len == Duration.zero ? const Duration(hours: 1) : len);
      } else {
        _to = v;
      }
      _error = null;
    });
    _loadFree();
  }

  String _errorKey(Object e) => switch (e) {
        TirParkRefused(reason: 'no_space') => 'tpb_err_no_space',
        TirParkRefused(reason: 'invalid_time') => 'tpb_err_time',
        TirParkRefused(reason: 'own_park') => 'tpb_err_own',
        _ => 'tpb_err_generic',
      };

  Future<void> _book(CheckoutAvailability av, List<PayMethod> methods) async {
    final units = tirParkUnits(_from, _to, park.priceUnit ?? 'hour');
    if (units <= 0 || _to.difference(_from) > const Duration(days: 30)) {
      setState(() => _error = 'tpb_err_time');
      return;
    }
    final amount = (park.price ?? 0) * units * _trucks;
    // 1) Everything shown before the payment starts.
    final go = await showModalBottomSheet<bool>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
            Text(s.t('tpb_confirm_title'), style: TextStyle(fontSize: 19, fontWeight: FontWeight.w600, color: AppColors.text)),
            const SizedBox(height: 12),
            Text(park.name, style: TextStyle(fontWeight: FontWeight.w500, color: AppColors.text)),
            const SizedBox(height: 4),
            Text('${s.t('tpb_arrive')}: ${tirParkTime(_from)}', style: TextStyle(color: AppColors.text)),
            Text('${s.t('tpb_leave')}: ${tirParkTime(_to)}', style: TextStyle(color: AppColors.text)),
            Text('${s.t('tpb_trucks')}: $_trucks', style: TextStyle(color: AppColors.text)),
            const SizedBox(height: 8),
            Text(
              s.t('tpb_total', {
                'amount': money(amount, park.currency),
                'units': '$units',
                'unit': tirParkUnitLabel(s, park.priceUnit ?? 'hour'),
                'trucks': '$_trucks',
              }),
              key: const ValueKey('tpb-total'),
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: AppColors.text),
            ),
            const SizedBox(height: 10),
            Text(s.t('tpb_terms'), key: const ValueKey('tpb-terms'), style: TextStyle(fontSize: 13, color: AppColors.textSoft, height: 1.35)),
            if (av.mode == 'test') ...[
              const SizedBox(height: 8),
              Text(s.t('pay_test_banner_vip'), style: TextStyle(fontSize: 12.5, color: AppColors.blue)),
            ],
            const SizedBox(height: 14),
            FilledButton(key: const ValueKey('tpb-go'), onPressed: () => Navigator.of(ctx).pop(true), child: Text(s.t('tpb_pay'))),
          ]),
        ),
      ),
    );
    if (go != true || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      // 2) The server holds the space (atomic) and prices the booking.
      final b = await ref.read(tirParkRepositoryProvider).book(park.id, _from, _to, _trucks);
      if (!mounted) return;
      final container = ProviderScope.containerOf(context, listen: false);
      // 3) The existing secure checkout; only the provider's verified
      //    event confirms the booking (payments-webhook).
      await showModalBottomSheet<void>(
        context: context,
        useRootNavigator: true,
        isScrollControlled: true,
        isDismissible: false,
        builder: (_) => CheckoutSheet(
          vip: VipCheckoutTarget(vipOrderId: b.id, amount: b.amount, currency: b.currency, tirParkBooking: true),
          s: s,
          availability: av,
          methods: methods,
        ),
      );
      container.invalidate(myParkBookingsProvider);
      _loadFree();
    } catch (e) {
      if (mounted) setState(() => _error = _errorKey(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final av = ref.watch(checkoutAvailabilityProvider).valueOrNull;
    final methods = av == null ? const <PayMethod>[] : methodsForDevice(currentDeviceKind(), av.methods);
    final canPay = av != null && av.available && methods.isNotEmpty;
    final unit = park.priceUnit ?? 'hour';
    final units = tirParkUnits(_from, _to, unit);
    final enough = _free != null && _free! >= _trucks;
    return Container(
      key: const ValueKey('tpb-section'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(s.t('tpb_title'), style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: AppColors.text)),
        const SizedBox(height: 6),
        Text(s.t('tpb_price', {'price': money(park.price ?? 0, park.currency), 'unit': tirParkUnitLabel(s, unit)}),
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.accent)),
        if (park.capacity != null) Text(s.t('tpb_capacity', {'n': '${park.capacity}'}), style: TextStyle(color: AppColors.text)),
        if ((park.hours ?? '').isNotEmpty) Text(s.t('tpb_hours', {'h': park.hours!}), style: TextStyle(color: AppColors.textSoft)),
        if ((park.phone ?? '').isNotEmpty) Text(s.t('tpb_phone', {'p': park.phone!}), style: TextStyle(color: AppColors.textSoft)),
        if ((park.address ?? '').isNotEmpty) Text(park.address!, style: TextStyle(color: AppColors.textSoft)),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: OutlinedButton(
              key: const ValueKey('tpb-from'),
              onPressed: _busy ? null : () => _pick(true),
              child: Text('${s.t('tpb_arrive')}\n${tirParkTime(_from)}', textAlign: TextAlign.center),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton(
              key: const ValueKey('tpb-to'),
              onPressed: _busy ? null : () => _pick(false),
              child: Text('${s.t('tpb_leave')}\n${tirParkTime(_to)}', textAlign: TextAlign.center),
            ),
          ),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: Text(s.t('tpb_trucks'), style: TextStyle(color: AppColors.text))),
          IconButton(
            key: const ValueKey('tpb-minus'),
            onPressed: _trucks > 1 && !_busy ? () => setState(() => _trucks--) : null,
            icon: const Icon(Icons.remove_circle_outline),
          ),
          Text('$_trucks', key: const ValueKey('tpb-trucks'), style: TextStyle(fontSize: 17, color: AppColors.text)),
          IconButton(
            key: const ValueKey('tpb-plus'),
            onPressed: _trucks < 50 && !_busy ? () => setState(() => _trucks++) : null,
            icon: const Icon(Icons.add_circle_outline),
          ),
        ]),
        Text(
          _free == null ? '…' : s.t('tpb_free', {'n': '$_free'}),
          key: const ValueKey('tpb-free'),
          style: TextStyle(color: enough ? AppColors.online : AppColors.danger),
        ),
        if (units > 0) ...[
          const SizedBox(height: 4),
          Text(
            s.t('tpb_total', {
              'amount': money((park.price ?? 0) * units * _trucks, park.currency),
              'units': '$units',
              'unit': tirParkUnitLabel(s, unit),
              'trucks': '$_trucks',
            }),
            style: TextStyle(fontWeight: FontWeight.w500, color: AppColors.text),
          ),
        ],
        if (_error != null) ...[
          const SizedBox(height: 6),
          Text(s.t(_error!), key: const ValueKey('tpb-error'), style: TextStyle(color: AppColors.danger)),
        ],
        const SizedBox(height: 10),
        if (!canPay)
          Text(s.t('tpb_pay_off'), key: const ValueKey('tpb-pay-off'), style: TextStyle(fontSize: 13, color: AppColors.textSoft))
        else
          FilledButton(
            key: const ValueKey('tpb-book'),
            onPressed: _busy || !enough || units <= 0 ? null : () => _book(av, methods),
            child: _busy
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : Text(s.t('tpb_book')),
          ),
      ]),
    );
  }
}

/// Profil → "Park rezervasiyalarım": status, the entry code (confirmed
/// bookings), TEST mark, cancel before arrival.
class MyParkBookingsScreen extends ConsumerWidget {
  const MyParkBookingsScreen({super.key});

  Future<void> _cancel(BuildContext context, WidgetRef ref, TirParkBooking b, AppStrings s) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: Text(s.t('tpb_cancel_q')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(s.t('common_cancel'))),
          TextButton(key: const ValueKey('tpb-cancel-ok'), onPressed: () => Navigator.pop(ctx, true), child: Text(s.t('tpb_cancel'))),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(tirParkRepositoryProvider).cancelBooking(b.id);
    } catch (_) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.t('tpb_err_generic'))));
    }
    ref.invalidate(myParkBookingsProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    ref.watch(currentLocaleProvider);
    final async = ref.watch(myParkBookingsProvider);
    final parks = {for (final p in ref.watch(tirParksProvider).valueOrNull ?? const <TirPark>[]) p.id: p};
    final list = async.valueOrNull ?? const <TirParkBooking>[];
    return Scaffold(
      appBar: AppBar(title: Text(s.t('tpb_my'))),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(myParkBookingsProvider),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
          children: [
            if (async.isLoading && !async.hasValue) const Padding(padding: EdgeInsets.all(30), child: Center(child: CircularProgressIndicator())),
            if (async.hasValue && list.isEmpty) Text(s.t('tpb_none'), style: TextStyle(color: AppColors.textSoft)),
            if (async.hasError) Text(s.t('tpb_err_generic'), style: TextStyle(color: AppColors.danger)),
            for (final b in list)
              Card(
                key: ValueKey('tpb-my-${b.id}'),
                margin: const EdgeInsets.only(bottom: 10),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Expanded(
                        child: Text(parks[b.parkId]?.name ?? b.bookingNo,
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.text)),
                      ),
                      Text(s.t('tpb_st_${b.shownStatus}'), style: TextStyle(color: tirParkStatusColor(b.shownStatus))),
                    ]),
                    const SizedBox(height: 4),
                    Text('${b.bookingNo} · ${tirParkTime(b.startAt)} → ${tirParkTime(b.endAt)} · ${b.trucks} TIR',
                        style: TextStyle(color: AppColors.textSoft)),
                    Text(money(b.amount, b.currency), style: TextStyle(color: AppColors.text)),
                    if (b.paidMode == 'test')
                      Text(s.t('tpb_test_paid'), key: ValueKey('tpb-test-${b.id}'), style: TextStyle(fontSize: 12.5, color: AppColors.blue)),
                    if ((b.code ?? '').isNotEmpty && (b.status == 'confirmed')) ...[
                      const SizedBox(height: 10),
                      Text(s.t('tpb_code'), style: TextStyle(fontSize: 12.5, color: AppColors.textSoft)),
                      Row(children: [
                        SelectableText(b.code!,
                            key: ValueKey('tpb-code-${b.id}'),
                            style: TextStyle(fontSize: 28, letterSpacing: 4, fontWeight: FontWeight.w600, color: AppColors.text)),
                        IconButton(
                          tooltip: 'Copy',
                          onPressed: () => Clipboard.setData(ClipboardData(text: b.code!)),
                          icon: const Icon(Icons.copy, size: 18),
                        ),
                      ]),
                      Text(s.t('tpb_code_hint'), style: TextStyle(fontSize: 12.5, color: AppColors.textSoft)),
                    ],
                    if ((b.shownStatus == 'pending_payment' || b.status == 'confirmed') && b.startAt.isAfter(DateTime.now())) ...[
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          key: ValueKey('tpb-cancel-${b.id}'),
                          onPressed: () => _cancel(context, ref, b, s),
                          child: Text(s.t('tpb_cancel')),
                        ),
                      ),
                    ],
                  ]),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
