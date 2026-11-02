import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/localization/app_strings.dart';
import '../../../core/localization/locale_controller.dart';
import '../../../core/router/safe_navigation.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/map_tiles.dart';
import '../../finance/domain/finance_models.dart';
import '../../services/presentation/services_providers.dart';
import '../data/tir_park_repository.dart';
import '../domain/tir_park.dart';
import 'tir_park_booking.dart';
import 'tir_park_widgets.dart';

/// Profil → "TIR parkı idarə edirəm" (owner, 01.11.2026, 0079): my park
/// applications and, once an admin approved them, the park's management —
/// free places and price, the payout status, entry codes and exits.
class TirParkManageScreen extends ConsumerWidget {
  const TirParkManageScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    ref.watch(currentLocaleProvider);
    final async = ref.watch(myManagedParksProvider);
    final list = async.valueOrNull ?? const <TirPark>[];
    return Scaffold(
      appBar: AppBar(title: Text(s.t('tpm_title'))),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(myManagedParksProvider),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
          children: [
            FilledButton.icon(
              key: const ValueKey('tpm-new'),
              onPressed: () => context.pushOnce('/tirpark/manage/new'),
              icon: const Icon(Icons.add),
              label: Text(s.t('tpm_new')),
            ),
            const SizedBox(height: 14),
            if (async.isLoading && !async.hasValue) const Padding(padding: EdgeInsets.all(30), child: Center(child: CircularProgressIndicator())),
            if (async.error is TirParkNotReady) Text(s.t('tp_not_ready'), style: TextStyle(color: AppColors.danger)),
            if (async.hasValue && list.isEmpty) Text(s.t('tpm_none'), style: TextStyle(color: AppColors.textSoft)),
            for (final p in list) _ManagedPark(park: p, s: s),
          ],
        ),
      ),
    );
  }
}

class _ManagedPark extends ConsumerStatefulWidget {
  final TirPark park;
  final AppStrings s;
  const _ManagedPark({required this.park, required this.s});

  @override
  ConsumerState<_ManagedPark> createState() => _ManagedParkState();
}

class _ManagedParkState extends ConsumerState<_ManagedPark> {
  late final _capacity = TextEditingController(text: '${widget.park.capacity ?? ''}');
  late final _bookable = TextEditingController(text: '${widget.park.bookable ?? ''}');
  late final _price = TextEditingController(text: widget.park.price?.toStringAsFixed(2) ?? '');
  late final _hours = TextEditingController(text: widget.park.hours ?? '');
  late final _phone = TextEditingController(text: widget.park.phone ?? '');
  final _code = TextEditingController();
  late String _unit = widget.park.priceUnit ?? 'hour';
  late bool _open = widget.park.bookingOpen;
  bool _busy = false;

  AppStrings get s => widget.s;
  TirPark get park => widget.park;

  @override
  void dispose() {
    for (final c in [_capacity, _bookable, _price, _hours, _phone, _code]) {
      c.dispose();
    }
    super.dispose();
  }

  // The newest message replaces the previous one.
  void _snack(String t) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(t)));

  Future<void> _save() async {
    final cap = int.tryParse(_capacity.text.trim());
    final free = int.tryParse(_bookable.text.trim());
    final price = double.tryParse(_price.text.trim().replaceAll(',', '.'));
    if (cap == null || free == null || price == null || free > cap || _phone.text.trim().length < 5) {
      _snack(s.t('tpm_err_invalid'));
      return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(tirParkRepositoryProvider).managerUpdate(park.id,
          capacity: cap,
          bookable: free,
          price: price,
          unit: _unit,
          hours: _hours.text.trim().isEmpty ? null : _hours.text.trim(),
          phone: _phone.text.trim(),
          open: _open);
      ref.invalidate(myManagedParksProvider);
      ref.invalidate(tirParksProvider);
      _snack(s.t('tpm_saved'));
    } catch (_) {
      _snack(s.t('tpm_err_invalid'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _checkIn() async {
    final code = _code.text.trim();
    if (code.isEmpty) return;
    setState(() => _busy = true);
    try {
      final b = await ref.read(tirParkRepositoryProvider).checkIn(park.id, code);
      _code.clear();
      _snack('${s.t('tpm_checked', {'no': b.bookingNo, 'trucks': '${b.trucks}'})}'
          '${(b.plate ?? '').isEmpty ? '' : ' · ${b.plate}'}');
      ref.invalidate(managerBookingsProvider(park.id));
    } on TirParkRefused catch (e) {
      _snack(s.t(switch (e.reason) {
        'already_used' => 'tpm_err_used',
        'not_in_time' => 'tpm_err_time',
        'not_valid' => 'tpm_err_notvalid',
        'too_many_attempts' => 'tpm_err_attempts',
        _ => 'tpm_err_code',
      }));
    } catch (_) {
      _snack(s.t('tpb_err_generic'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _checkOut(TirParkBooking b) async {
    try {
      await ref.read(tirParkRepositoryProvider).checkOut(b.id);
    } catch (_) {
      _snack(s.t('tpb_err_generic'));
    }
    ref.invalidate(managerBookingsProvider(park.id));
  }

  @override
  Widget build(BuildContext context) {
    final st = park.managerStatus ?? 'pending';
    final approved = st == 'approved';
    return Card(
      key: ValueKey('tpm-park-${park.id}'),
      margin: const EdgeInsets.only(bottom: 14),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(child: Text(park.name, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: AppColors.text))),
            Text(s.t('tpm_st_$st'),
                key: ValueKey('tpm-st-${park.id}'),
                style: TextStyle(color: approved ? AppColors.online : (st == 'rejected' ? AppColors.danger : AppColors.promoVip))),
          ]),
          Text([if ((park.city ?? '').isNotEmpty) park.city!, if ((park.address ?? '').isNotEmpty) park.address!].join(' · '),
              style: TextStyle(color: AppColors.textSoft)),
          if (!approved) ...[
            const SizedBox(height: 6),
            Text(
              '${s.t('tpb_capacity', {'n': '${park.capacity ?? '—'}'})} · '
              '${s.t('tpb_price', {'price': money(park.price ?? 0, park.currency), 'unit': tirParkUnitLabel(s, park.priceUnit ?? 'hour')})}',
              style: TextStyle(color: AppColors.text),
            ),
          ],
          if (approved) ...[
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: _num(_capacity, s.t('tpm_capacity'), 'tpm-cap-${park.id}')),
              const SizedBox(width: 8),
              Expanded(child: _num(_bookable, s.t('tpm_bookable'), 'tpm-free-${park.id}')),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: TextField(
                  key: ValueKey('tpm-price-${park.id}'),
                  controller: _price,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(labelText: s.t('tpm_price')),
                ),
              ),
              const SizedBox(width: 8),
              DropdownButton<String>(
                value: _unit,
                items: [
                  for (final u in ['hour', 'day']) DropdownMenuItem(value: u, child: Text(tirParkUnitLabel(s, u))),
                ],
                onChanged: (v) => setState(() => _unit = v ?? _unit),
              ),
            ]),
            const SizedBox(height: 8),
            TextField(controller: _hours, decoration: InputDecoration(labelText: s.t('tpm_hours'))),
            const SizedBox(height: 8),
            TextField(controller: _phone, keyboardType: TextInputType.phone, decoration: InputDecoration(labelText: s.t('tpm_phone'))),
            SwitchListTile(
              key: ValueKey('tpm-open-${park.id}'),
              contentPadding: EdgeInsets.zero,
              title: Text(s.t('tpm_open')),
              value: _open,
              onChanged: (v) => setState(() => _open = v),
            ),
            FilledButton(key: ValueKey('tpm-save-${park.id}'), onPressed: _busy ? null : _save, child: Text(s.t('tpm_save'))),
            const SizedBox(height: 14),
            // The park's own payment details (owner, 01.11.2026, 0080):
            // drivers transfer to them directly; FreightLink takes no money.
            _PayDetailsForm(parkId: park.id, s: s),
            const SizedBox(height: 14),
            Text(s.t('tpm_check'), style: TextStyle(fontWeight: FontWeight.w500, color: AppColors.text)),
            const SizedBox(height: 6),
            Row(children: [
              Expanded(
                child: TextField(
                  key: ValueKey('tpm-code-${park.id}'),
                  controller: _code,
                  textCapitalization: TextCapitalization.characters,
                  inputFormatters: [LengthLimitingTextInputFormatter(12)],
                  style: const TextStyle(letterSpacing: 3),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(key: ValueKey('tpm-checkin-${park.id}'), onPressed: _busy ? null : _checkIn, child: Text(s.t('tpm_check_btn'))),
            ]),
            const SizedBox(height: 14),
            Text(s.t('tpm_bookings'), style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.text)),
            _Bookings(parkId: park.id, s: s, onCheckOut: _checkOut),
          ],
        ]),
      ),
    );
  }

  Widget _num(TextEditingController c, String label, String key) => TextField(
        key: ValueKey(key),
        controller: c,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(4)],
        decoration: InputDecoration(labelText: label),
      );
}

class _Bookings extends ConsumerWidget {
  final String parkId;
  final AppStrings s;
  final void Function(TirParkBooking) onCheckOut;
  const _Bookings({required this.parkId, required this.s, required this.onCheckOut});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(managerBookingsProvider(parkId));
    final list = async.valueOrNull ?? const <TirParkBooking>[];
    if (async.isLoading && !async.hasValue) return const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()));
    if (list.isEmpty) return Padding(padding: const EdgeInsets.only(top: 6), child: Text(s.t('tpb_none'), style: TextStyle(color: AppColors.textSoft)));
    return Column(children: [
      for (final b in list)
        ListTile(
          key: ValueKey('tpm-b-${b.id}'),
          contentPadding: EdgeInsets.zero,
          title: Text('${b.bookingNo} · ${b.trucks} TIR${(b.plate ?? '').isEmpty ? '' : ' · ${b.plate}'}'
              '${(b.driver ?? '').isEmpty ? '' : ' · ${b.driver}'}'),
          subtitle: Text('${tirParkTime(b.startAt)} → ${tirParkTime(b.endAt)} · ${s.t('tpb_st_${b.shownStatus}')}'
              '${b.paidMode == 'test' ? ' · TEST' : ''}'),
          trailing: b.status == 'checked_in'
              ? TextButton(key: ValueKey('tpm-out-${b.id}'), onPressed: () => onCheckOut(b), child: Text(s.t('tpm_checkout')))
              : null,
        ),
      for (final b in list)
        if (b.status == 'payment_review') _ReviewRow(booking: b, parkId: parkId, s: s),
    ]);
  }
}

/// A receipt to check: look at it, then "Ödənişi təsdiqlə" (the money is on
/// the park's account → the driver gets the code) or "Rədd et".
class _ReviewRow extends ConsumerStatefulWidget {
  final TirParkBooking booking;
  final String parkId;
  final AppStrings s;
  const _ReviewRow({required this.booking, required this.parkId, required this.s});

  @override
  ConsumerState<_ReviewRow> createState() => _ReviewRowState();
}

class _ReviewRowState extends ConsumerState<_ReviewRow> {
  bool _busy = false;
  AppStrings get s => widget.s;
  TirParkBooking get b => widget.booking;

  // The newest message replaces the previous one.
  void _snack(String t) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(t)));

  Future<void> _showReceipt() async {
    final path = b.receiptPath;
    if (path == null) return;
    try {
      final url = await ref.read(tirParkRepositoryProvider).receiptUrl(path);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => Dialog(
          child: InteractiveViewer(child: Image.network(url, key: const ValueKey('tpm-receipt-img'), fit: BoxFit.contain)),
        ),
      );
    } catch (_) {
      _snack(s.t('tpb_err_generic'));
    }
  }

  Future<void> _confirm() async {
    setState(() => _busy = true);
    try {
      await ref.read(tirParkRepositoryProvider).confirmPayment(b.id);
      _snack(s.t('tpm_confirmed', {'no': b.bookingNo}));
    } catch (_) {
      _snack(s.t('tpb_err_generic'));
    } finally {
      ref.invalidate(managerBookingsProvider(widget.parkId));
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reject() async {
    final note = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(s.t('tpm_reject_q')),
          TextField(key: const ValueKey('tpm-reject-note'), controller: note, maxLength: 200),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(s.t('common_cancel'))),
          TextButton(key: const ValueKey('tpm-reject-ok'), onPressed: () => Navigator.pop(ctx, true), child: Text(s.t('tpm_reject'))),
        ],
      ),
    );
    final text = note.text.trim();
    note.dispose();
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      await ref.read(tirParkRepositoryProvider).rejectPayment(b.id, text.isEmpty ? null : text);
    } catch (_) {
      _snack(s.t('tpb_err_generic'));
    } finally {
      ref.invalidate(managerBookingsProvider(widget.parkId));
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Container(
        key: ValueKey('tpm-review-${b.id}'),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppColors.promoVip.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.promoVip.withValues(alpha: 0.4)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('${b.bookingNo} · ${money(b.amount, b.currency)} · ${s.t('tpb_st_payment_review')}',
              style: TextStyle(fontWeight: FontWeight.w500, color: AppColors.text)),
          if ((b.plate ?? '').isNotEmpty)
            Text('${s.t('tpb_plate')}: ${b.plate}', key: ValueKey('tpm-plate-${b.id}'),
                style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.text)),
          const SizedBox(height: 6),
          Wrap(spacing: 8, runSpacing: 6, children: [
            OutlinedButton.icon(
              key: ValueKey('tpm-receipt-${b.id}'),
              onPressed: b.receiptPath == null ? null : _showReceipt,
              icon: const Icon(Icons.receipt_long_outlined, size: 18),
              label: Text(s.t('tpm_receipt')),
            ),
            FilledButton(key: ValueKey('tpm-confirm-${b.id}'), onPressed: _busy ? null : _confirm, child: Text(s.t('tpm_confirm'))),
            TextButton(key: ValueKey('tpm-reject-${b.id}'), onPressed: _busy ? null : _reject, child: Text(s.t('tpm_reject'))),
          ]),
        ]),
      );
}

/// The park's own payment details: holder, bank, IBAN / account, card
/// number for transfers, note. Kept on the server, shown to a driver only
/// after he books. Never CVV / PIN / SMS codes.
class _PayDetailsForm extends ConsumerStatefulWidget {
  final String parkId;
  final AppStrings s;
  const _PayDetailsForm({required this.parkId, required this.s});

  @override
  ConsumerState<_PayDetailsForm> createState() => _PayDetailsFormState();
}

class _PayDetailsFormState extends ConsumerState<_PayDetailsForm> {
  final _holder = TextEditingController();
  final _bank = TextEditingController();
  final _account = TextEditingController();
  final _card = TextEditingController();
  final _note = TextEditingController();
  bool _filled = false;
  bool _busy = false;

  AppStrings get s => widget.s;

  @override
  void dispose() {
    for (final c in [_holder, _bank, _account, _card, _note]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final card = _card.text.replaceAll(RegExp(r'\D'), '');
    final acc = _account.text.replaceAll(RegExp(r'\s'), '');
    if (_holder.text.trim().length < 2 || (card.isEmpty && acc.isEmpty) || (card.isNotEmpty && (card.length < 12 || card.length > 19))) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.t('tpm_paydet_invalid'))));
      return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(tirParkRepositoryProvider).setPayDetails(widget.parkId,
          holder: _holder.text.trim(),
          bank: _bank.text.trim().isEmpty ? null : _bank.text.trim(),
          account: acc.isEmpty ? null : acc,
          card: card.isEmpty ? null : card,
          note: _note.text.trim().isEmpty ? null : _note.text.trim());
      ref.invalidate(parkPayDetailsProvider(widget.parkId));
      ref.invalidate(tirParksProvider);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.t('tpm_saved'))));
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.t('tpm_paydet_invalid'))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(parkPayDetailsProvider(widget.parkId));
    final d = async.valueOrNull;
    if (async.hasValue && !_filled) {
      _filled = true;
      _holder.text = d?.holder ?? '';
      _bank.text = d?.bank ?? '';
      _account.text = d?.account ?? '';
      _card.text = d?.card ?? '';
      _note.text = d?.note ?? '';
    }
    Widget f(TextEditingController c, String label, String key, {TextInputType? type, int max = 120}) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: TextField(
            key: ValueKey('$key-${widget.parkId}'),
            controller: c,
            keyboardType: type,
            maxLength: max,
            decoration: InputDecoration(labelText: label, counterText: ''),
          ),
        );
    return Container(
      key: ValueKey('tpm-paydet-${widget.parkId}'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.cardAlt,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Icon(Icons.account_balance_outlined, color: AppColors.accent, size: 20),
          const SizedBox(width: 6),
          Expanded(child: Text(s.t('tpm_paydet_title'), style: TextStyle(fontWeight: FontWeight.w500, color: AppColors.text))),
        ]),
        const SizedBox(height: 4),
        Text(s.t('tpm_paydet_hint'), style: TextStyle(fontSize: 12.5, color: AppColors.textSoft, height: 1.35)),
        if (async.hasValue && d == null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(s.t('tpm_paydet_need'), key: ValueKey('tpm-paydet-need-${widget.parkId}'), style: TextStyle(color: AppColors.promoVip)),
          ),
        const SizedBox(height: 8),
        f(_holder, s.t('tpm_holder'), 'tpm-holder'),
        f(_bank, s.t('tpm_bank'), 'tpm-bank'),
        f(_account, s.t('tpm_account'), 'tpm-account', max: 64),
        f(_card, s.t('tpm_card'), 'tpm-card', type: TextInputType.number, max: 23),
        f(_note, s.t('tpm_paynote'), 'tpm-paynote', max: 300),
        FilledButton(
          key: ValueKey('tpm-paydet-save-${widget.parkId}'),
          onPressed: _busy ? null : _save,
          child: Text(s.t('tpm_save')),
        ),
      ]),
    );
  }
}

/// "Yeni park müraciəti": contact, address, the place on the map, capacity,
/// free places now, price per hour / day, hours, services.
class TirParkManageFormScreen extends ConsumerStatefulWidget {
  const TirParkManageFormScreen({super.key});

  @override
  ConsumerState<TirParkManageFormScreen> createState() => _TirParkManageFormScreenState();
}

class _TirParkManageFormScreenState extends ConsumerState<TirParkManageFormScreen> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _city = TextEditingController();
  final _address = TextEditingController();
  final _capacity = TextEditingController();
  final _bookable = TextEditingController();
  final _price = TextEditingController();
  final _hours = TextEditingController();
  final _note = TextEditingController();
  final _amenities = <String>{};
  final _map = MapController();
  String _unit = 'hour';
  LatLng _center = kDefaultServiceCenter;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final me = ref.read(userLocationProvider).point;
    if (me != null) _center = me;
  }

  @override
  void dispose() {
    for (final c in [_name, _phone, _city, _address, _capacity, _bookable, _price, _hours, _note]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _send(AppStrings s) async {
    final cap = int.tryParse(_capacity.text.trim());
    final free = int.tryParse(_bookable.text.trim());
    final price = double.tryParse(_price.text.trim().replaceAll(',', '.'));
    if (_name.text.trim().length < 2 || _phone.text.trim().length < 5 || cap == null || cap < 1 || free == null || free > cap ||
        price == null || price <= 0) {
      setState(() => _error = 'tpm_err_invalid');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(tirParkRepositoryProvider).manageApply(
            name: _name.text.trim(),
            lat: _center.latitude,
            lng: _center.longitude,
            city: _city.text.trim().isEmpty ? null : _city.text.trim(),
            address: _address.text.trim().isEmpty ? null : _address.text.trim(),
            phone: _phone.text.trim(),
            amenities: [for (final a in kTirParkAmenities) if (_amenities.contains(a)) a],
            capacity: cap,
            bookable: free,
            price: price,
            unit: _unit,
            hours: _hours.text.trim().isEmpty ? null : _hours.text.trim(),
            note: _note.text.trim().isEmpty ? null : _note.text.trim(),
          );
      ref.invalidate(myManagedParksProvider);
      ref.invalidate(tirParksProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.t('tpm_sent'))));
      Navigator.of(context).maybePop();
    } on TirParkRefused catch (e) {
      setState(() => _error = switch (e.reason) {
            'duplicate_nearby' => 'tpm_err_dup',
            'too_many' => 'tpm_err_too_many',
            _ => 'tpm_err_invalid',
          });
    } on TirParkNotReady {
      setState(() => _error = 'tp_not_ready');
    } catch (_) {
      setState(() => _error = 'tpb_err_generic');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    ref.watch(currentLocaleProvider);
    Widget field(TextEditingController c, String label, String key, {TextInputType? type, int? max}) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: TextField(
            key: ValueKey(key),
            controller: c,
            keyboardType: type,
            maxLength: max,
            decoration: InputDecoration(labelText: label, counterText: ''),
          ),
        );
    return Scaffold(
      appBar: AppBar(title: Text(s.t('tpm_new'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
        children: [
          field(_name, s.t('tpm_name'), 'tpm-f-name', max: 80),
          field(_phone, s.t('tpm_phone'), 'tpm-f-phone', type: TextInputType.phone, max: 40),
          field(_city, s.t('tpm_city'), 'tpm-f-city', max: 80),
          field(_address, s.t('tpm_address'), 'tpm-f-address', max: 160),
          Text(s.t('tpm_place'), style: TextStyle(fontSize: 13, color: AppColors.textSoft)),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: SizedBox(
              height: 220,
              child: Stack(children: [
                FlutterMap(
                  mapController: _map,
                  options: MapOptions(
                    initialCenter: _center,
                    initialZoom: 14,
                    interactionOptions: const InteractionOptions(flags: InteractiveFlag.all & ~InteractiveFlag.rotate),
                    onPositionChanged: (camera, _) => _center = camera.center,
                  ),
                  children: const [AppTileLayer(), AppMapAttribution()],
                ),
                IgnorePointer(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 40),
                      child: Icon(Icons.location_on, size: 40, color: AppColors.accentFill),
                    ),
                  ),
                ),
              ]),
            ),
          ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: field(_capacity, s.t('tpm_capacity'), 'tpm-f-cap', type: TextInputType.number, max: 4)),
            const SizedBox(width: 8),
            Expanded(child: field(_bookable, s.t('tpm_bookable'), 'tpm-f-free', type: TextInputType.number, max: 4)),
          ]),
          Row(children: [
            Expanded(child: field(_price, s.t('tpm_price'), 'tpm-f-price', type: const TextInputType.numberWithOptions(decimal: true), max: 9)),
            const SizedBox(width: 8),
            DropdownButton<String>(
              key: const ValueKey('tpm-f-unit'),
              value: _unit,
              items: [for (final u in ['hour', 'day']) DropdownMenuItem(value: u, child: Text(tirParkUnitLabel(s, u)))],
              onChanged: (v) => setState(() => _unit = v ?? _unit),
            ),
          ]),
          field(_hours, s.t('tpm_hours'), 'tpm-f-hours', max: 40),
          Text(s.t('tpm_amenities'), style: TextStyle(fontWeight: FontWeight.w500, color: AppColors.text)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final a in kTirParkAmenities)
              FilterChip(
                key: ValueKey('tpm-f-am-$a'),
                avatar: Icon(tirParkAmenityIcon(a), size: 16),
                label: Text(s.t('tp_am_$a')),
                selected: _amenities.contains(a),
                onSelected: (on) => setState(() => on ? _amenities.add(a) : _amenities.remove(a)),
              ),
          ]),
          const SizedBox(height: 12),
          field(_note, s.t('tp_note'), 'tpm-f-note', max: 500),
          if (_error != null) Text(s.t(_error!), key: const ValueKey('tpm-f-error'), style: TextStyle(color: AppColors.danger)),
          const SizedBox(height: 10),
          FilledButton(
            key: const ValueKey('tpm-f-send'),
            onPressed: _busy ? null : () => _send(s),
            child: _busy ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : Text(s.t('tpm_send')),
          ),
        ],
      ),
    );
  }
}
