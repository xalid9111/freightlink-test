import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../core/localization/app_strings.dart';
import '../../../core/localization/locale_controller.dart';
import '../../../core/theme/app_theme.dart';
import '../../finance/domain/finance_models.dart';
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
      'pending_payment' || 'payment_review' => AppColors.promoVip,
      'payment_rejected' => AppColors.danger,
      _ => AppColors.textSoft,
    };

/// The booking part of a park's page (owner, 01.11.2026; 0079 + 0080):
/// price, capacity, free places for the chosen time, arrival / departure,
/// TIRs → "Yeri rezerv et" → summary with the conditions → the space is
/// held and the park's own payment details are shown (direct transfer,
/// receipt). FreightLink takes no money and asks no card data.
class TirParkBookingSection extends ConsumerStatefulWidget {
  final TirPark park;
  final AppStrings s;
  const TirParkBookingSection({super.key, required this.park, required this.s});

  @override
  ConsumerState<TirParkBookingSection> createState() => _TirParkBookingSectionState();
}

class _TirParkBookingSectionState extends ConsumerState<TirParkBookingSection> {
  late DateTime _from = _roundUp(DateTime.now().add(const Duration(hours: 1)));
  // "Qalma müddəti" in the park's own price unit (days or hours).
  int _len = 1;
  int _trucks = 1;
  // The truck's state number (0082), e.g. 99-ZB-911; filled in from the
  // driver's last booking.
  final _plate = TextEditingController();
  int? _free;
  bool _closed = false; // the server says the park takes no bookings now (e.g. no payment details)
  bool _busy = false;
  String? _error;

  static DateTime _roundUp(DateTime t) => DateTime(t.year, t.month, t.day, t.hour).add(Duration(minutes: t.minute > 0 ? 60 : 0));

  AppStrings get s => widget.s;
  TirPark get park => widget.park;
  String get _unit => park.priceUnit ?? 'hour';
  int get _maxLen => _unit == 'day' ? 30 : 72;
  DateTime get _to => _from.add(_unit == 'day' ? Duration(days: _len) : Duration(hours: _len));

  @override
  void initState() {
    super.initState();
    _loadFree();
    _lastPlate();
  }

  Future<void> _lastPlate() async {
    try {
      final mine = await ref.read(tirParkRepositoryProvider).myBookings();
      final last = mine.map((b) => b.plate).whereType<String>().firstOrNull;
      if (last != null && mounted && _plate.text.isEmpty) setState(() => _plate.text = last);
    } catch (_) {}
  }

  @override
  void dispose() {
    _plate.dispose();
    super.dispose();
  }

  Future<void> _loadFree() async {
    setState(() => _free = null);
    if (!park.bookingOpen) return;
    try {
      final n = await ref.read(tirParkRepositoryProvider).freePlaces(park.id, _from, _to);
      if (mounted) setState(() => _free = n);
    } on TirParkRefused catch (e) {
      if (mounted) setState(() => _closed = e.reason == 'not_bookable');
    } catch (_) {
      if (mounted) setState(() => _free = null);
    }
  }

  Future<void> _pickArrival() async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: _from.isBefore(now) ? now : _from,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 60)),
    );
    if (d == null || !mounted) return;
    final t = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(_from));
    if (t == null || !mounted) return;
    setState(() {
      _from = DateTime(d.year, d.month, d.day, t.hour, t.minute);
      _error = null;
    });
    _loadFree();
  }

  void _setLen(int v) {
    setState(() {
      _len = v.clamp(1, _maxLen);
      _error = null;
    });
    _loadFree();
  }

  String _errorKey(Object e) => switch (e) {
        TirParkRefused(reason: 'no_space') => 'tpb_err_no_space',
        TirParkRefused(reason: 'invalid_time') => 'tpb_err_time',
        TirParkRefused(reason: 'own_park') => 'tpb_err_own',
        TirParkRefused(reason: 'not_bookable') => 'tpb_closed',
        TirParkRefused(reason: 'invalid_plate') => 'tpb_err_plate',
        _ => 'tpb_err_generic',
      };

  /// "3,00 AZN / gün × 2 gün × 2 TIR = 12,00 AZN".
  String _calc(int units) => s.t('tpb_calc', {
        'price': money(park.price ?? 0, park.currency),
        'unit': tirParkUnitLabel(s, _unit),
        'units': '$units',
        'trucks': '$_trucks',
        'amount': money((park.price ?? 0) * units * _trucks, park.currency),
      });

  Future<void> _book() async {
    final plate = tidyTruckPlate(_plate.text);
    if (plate == null) {
      setState(() => _error = 'tpb_err_plate');
      return;
    }
    _plate.text = plate;
    final units = tirParkUnits(_from, _to, _unit);
    if (units <= 0 || _from.isBefore(DateTime.now().subtract(const Duration(minutes: 15)))) {
      setState(() => _error = 'tpb_err_time');
      return;
    }
    final amount = (park.price ?? 0) * units * _trucks;
    // 1) Everything shown before anything is held.
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
            Text('${s.t('tpb_stay')}: $units ${tirParkUnitLabel(s, _unit)}', style: TextStyle(color: AppColors.text)),
            Text('${s.t('tpb_leave')}: ${tirParkTime(_to)}', style: TextStyle(color: AppColors.text)),
            Text('${s.t('tpb_trucks')}: $_trucks', style: TextStyle(color: AppColors.text)),
            Text('${s.t('tpb_plate')}: $plate', key: const ValueKey('tpb-plate-confirm'), style: TextStyle(color: AppColors.text)),
            const SizedBox(height: 8),
            Text(_calc(units), key: const ValueKey('tpb-calc-confirm'), style: TextStyle(color: AppColors.text)),
            Text(
              s.t('tpb_total', {
                'amount': money(amount, park.currency),
                'units': '$units',
                'unit': tirParkUnitLabel(s, _unit),
                'trucks': '$_trucks',
              }),
              key: const ValueKey('tpb-total'),
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: AppColors.text),
            ),
            const SizedBox(height: 10),
            Text(s.t('tpb_terms'), key: const ValueKey('tpb-terms'), style: TextStyle(fontSize: 13, color: AppColors.textSoft, height: 1.35)),
            const SizedBox(height: 14),
            FilledButton(key: const ValueKey('tpb-go'), onPressed: () => Navigator.of(ctx).pop(true), child: Text(s.t('tpb_book'))),
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
      final b = await ref.read(tirParkRepositoryProvider).book(park.id, _from, _to, _trucks, plate);
      if (!mounted) return;
      final container = ProviderScope.containerOf(context, listen: false);
      container.invalidate(tirParkBookingNowProvider);
      // 3) The park's own details; the driver transfers and sends the receipt.
      await showTirParkPaySheet(context, s, b);
      container.invalidate(myParkBookingsProvider);
      container.invalidate(tirParkBookingNowProvider);
      _loadFree();
    } catch (e) {
      if (mounted) setState(() => _error = _errorKey(e));
      if (e is TirParkRefused && e.reason == 'no_space') _loadFree();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _stepper(String label, int value, String text, String key, int min, int max, ValueChanged<int> onChanged) => Row(children: [
        Expanded(child: Text(label, style: TextStyle(color: AppColors.text))),
        IconButton(
          key: ValueKey('$key-minus'),
          onPressed: value > min && !_busy ? () => onChanged(value - 1) : null,
          icon: const Icon(Icons.remove_circle_outline),
        ),
        Text(text, key: ValueKey(key), style: TextStyle(fontSize: 17, color: AppColors.text)),
        IconButton(
          key: ValueKey('$key-plus'),
          onPressed: value < max && !_busy ? () => onChanged(value + 1) : null,
          icon: const Icon(Icons.add_circle_outline),
        ),
      ]);

  @override
  Widget build(BuildContext context) {
    final units = tirParkUnits(_from, _to, _unit);
    final closed = _closed || !park.bookingOpen || (park.price ?? 0) <= 0 || park.priceUnit == null;
    final full = _free == 0;
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
        if ((park.price ?? 0) > 0)
          Text(s.t('tpb_price', {'price': money(park.price ?? 0, park.currency), 'unit': tirParkUnitLabel(s, _unit)}),
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.accent)),
        if (park.capacity != null) Text(s.t('tpb_capacity', {'n': '${park.capacity}'}), style: TextStyle(color: AppColors.text)),
        if ((park.hours ?? '').isNotEmpty) Text(s.t('tpb_hours', {'h': park.hours!}), style: TextStyle(color: AppColors.textSoft)),
        if ((park.phone ?? '').isNotEmpty) Text(s.t('tpb_phone', {'p': park.phone!}), style: TextStyle(color: AppColors.textSoft)),
        if ((park.address ?? '').isNotEmpty) Text(park.address!, style: TextStyle(color: AppColors.textSoft)),
        const SizedBox(height: 12),
        if (closed)
          Text(s.t('tpb_closed'), key: const ValueKey('tpb-closed'), style: TextStyle(fontWeight: FontWeight.w500, color: AppColors.textSoft))
        else ...[
          OutlinedButton(
            key: const ValueKey('tpb-from'),
            onPressed: _busy ? null : _pickArrival,
            child: Text('${s.t('tpb_arrive')}\n${tirParkTime(_from)}', textAlign: TextAlign.center),
          ),
          const SizedBox(height: 6),
          _stepper(s.t('tpb_stay'), _len, '$_len ${tirParkUnitLabel(s, _unit)}', 'tpb-len', 1, _maxLen, _setLen),
          Text('${s.t('tpb_leave')}: ${tirParkTime(_to)}', key: const ValueKey('tpb-to'), style: TextStyle(color: AppColors.textSoft)),
          _stepper(s.t('tpb_trucks'), _trucks, '$_trucks', 'tpb-trucks', 1, 50, (v) => setState(() => _trucks = v)),
          TextField(
            key: const ValueKey('tpb-plate'),
            controller: _plate,
            enabled: !_busy,
            textCapitalization: TextCapitalization.characters,
            maxLength: 15,
            onChanged: (_) {
              if (_error == 'tpb_err_plate') setState(() => _error = null);
            },
            decoration: InputDecoration(
              labelText: s.t('tpb_plate'),
              hintText: s.t('tpb_plate_hint'),
              counterText: '',
              prefixIcon: const Icon(Icons.local_shipping_outlined),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _free == null ? '…' : s.t('tpb_free', {'n': '$_free'}),
            key: const ValueKey('tpb-free'),
            style: TextStyle(color: enough ? AppColors.online : AppColors.danger),
          ),
          if (units > 0) ...[
            const SizedBox(height: 4),
            Text(_calc(units), key: const ValueKey('tpb-calc'), style: TextStyle(fontWeight: FontWeight.w500, color: AppColors.text)),
          ],
          if (_error != null) ...[
            const SizedBox(height: 6),
            Text(s.t(_error!), key: const ValueKey('tpb-error'), style: TextStyle(color: AppColors.danger)),
          ],
          const SizedBox(height: 10),
          if (full)
            Text(s.t('tpb_full'), key: const ValueKey('tpb-full'), textAlign: TextAlign.center,
                style: TextStyle(fontWeight: FontWeight.w500, color: AppColors.danger))
          else
            FilledButton(
              key: const ValueKey('tpb-book'),
              onPressed: _busy || !enough || units <= 0 ? null : _book,
              child: _busy ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : Text(s.t('tpb_book')),
            ),
          const SizedBox(height: 6),
          Text(s.t('tpb_no_money'), style: TextStyle(fontSize: 12.5, color: AppColors.textSoft)),
        ],
      ]),
    );
  }
}

/// "Yeri rezerv et" from a park card on the TIRPark list: the same booking
/// part as on the park's page, in a sheet (closed by swiping down).
Future<void> showTirParkBookSheet(BuildContext context, AppStrings s, TirPark park) => showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.88),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
              Text(park.name, style: TextStyle(fontSize: 19, fontWeight: FontWeight.w600, color: AppColors.text)),
              const SizedBox(height: 10),
              TirParkBookingSection(park: park, s: s),
            ]),
          ),
        ),
      ),
    );

/// The booking line of a park card (owner, 02.11.2026, 0081): "Boş
/// yerlər: 6" + "Yeri rezerv et", or "Rezervasiya bağlıdır" / "Boş yer
/// yoxdur". Only for parks with an approved manager.
class TirParkCardBooking extends ConsumerWidget {
  final TirPark park;
  final AppStrings s;
  const TirParkCardBooking({super.key, required this.park, required this.s});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!park.isManaged) return const SizedBox.shrink();
    final now = ref.watch(tirParkBookingNowProvider).valueOrNull?[park.id];
    // Before 0081 runs: the park's own fields.
    final open = now?.open ?? park.canBook;
    final free = now?.free;
    final unit = park.priceUnit ?? 'hour';
    Widget line(String text, Color color, String key) =>
        Text(text, key: ValueKey('$key-${park.id}'), style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: color));
    if (!open) return line(s.t('tpb_closed'), AppColors.textSoft, 'tpc-closed');
    if (free == 0) return line(s.t('tpb_full'), AppColors.danger, 'tpc-full');
    return Row(children: [
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (free != null) line(s.t('tpb_free_now', {'n': '$free'}), AppColors.online, 'tpc-free'),
          if ((park.price ?? 0) > 0)
            Text('${money(park.price!, park.currency)} / ${tirParkUnitLabel(s, unit)}',
                style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: AppColors.accent)),
        ]),
      ),
      FilledButton(
        key: ValueKey('tpc-book-${park.id}'),
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 36),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          visualDensity: VisualDensity.compact,
        ),
        onPressed: () async {
          await showTirParkBookSheet(context, s, park);
          ref.invalidate(tirParkBookingNowProvider);
        },
        child: Text(s.t('tpb_book'), style: const TextStyle(fontSize: 13.5)),
      ),
    ]);
  }
}

/// The park's payment details for one booking (only its driver gets them)
/// and "Qəbzin şəklini yüklə" → "Ödəniş yoxlanılır".
Future<void> showTirParkPaySheet(BuildContext context, AppStrings s, TirParkBooking b) => showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => TirParkPaySheet(booking: b, s: s),
    );

class TirParkPaySheet extends ConsumerStatefulWidget {
  final TirParkBooking booking;
  final AppStrings s;
  const TirParkPaySheet({super.key, required this.booking, required this.s});

  @override
  ConsumerState<TirParkPaySheet> createState() => _TirParkPaySheetState();
}

class _TirParkPaySheetState extends ConsumerState<TirParkPaySheet> {
  TirParkPayDetails? _d;
  bool _loading = true;
  bool _busy = false;
  String? _error;

  AppStrings get s => widget.s;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final d = await ref.read(tirParkRepositoryProvider).bookingPayDetails(widget.booking.id);
      if (mounted) setState(() => _d = d);
    } catch (_) {
      if (mounted) setState(() => _error = 'tpb_err_generic');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _upload() async {
    final x = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 2200, imageQuality: 85);
    if (x == null || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final bytes = await x.readAsBytes();
      await ref.read(tirParkRepositoryProvider).uploadReceipt(widget.booking.id, bytes, contentType: x.mimeType);
      ref.invalidate(myParkBookingsProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.t('tpb_uploaded'))));
      Navigator.of(context).maybePop();
    } catch (_) {
      if (mounted) setState(() => _error = 'tpb_upload_fail');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _row(String label, String? value, String key) {
    if ((value ?? '').isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: TextStyle(fontSize: 12.5, color: AppColors.textSoft)),
            SelectableText(value!, key: ValueKey(key), style: TextStyle(fontSize: 16, color: AppColors.text)),
          ]),
        ),
        IconButton(
          tooltip: s.t('tpb_copied'),
          icon: const Icon(Icons.copy, size: 18),
          onPressed: () {
            Clipboard.setData(ClipboardData(text: value));
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.t('tpb_copied'))));
          },
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final d = _d;
    final b = widget.booking;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          Text(s.t('tpb_paysheet_title'), style: TextStyle(fontSize: 19, fontWeight: FontWeight.w600, color: AppColors.text)),
          const SizedBox(height: 6),
          Text(s.t('tpb_pay_to'), style: TextStyle(color: AppColors.textSoft)),
          const SizedBox(height: 12),
          if (_loading) const Center(child: CircularProgressIndicator()),
          if (d != null) ...[
            Text(money(d.amount ?? b.amount, d.currency),
                key: const ValueKey('tpb-pay-amount'), style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600, color: AppColors.text)),
            const SizedBox(height: 10),
            _row(s.t('tpb_holder'), d.holder, 'tpb-pay-holder'),
            _row(s.t('tpb_bank'), d.bank, 'tpb-pay-bank'),
            _row(s.t('tpb_account'), d.account, 'tpb-pay-account'),
            _row(s.t('tpb_card'), d.card, 'tpb-pay-card'),
            _row(s.t('tpb_purpose_label'), d.bookingNo ?? b.bookingNo, 'tpb-pay-no'),
            if ((b.plate ?? '').isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text('${s.t('tpb_plate')}: ${b.plate}', key: const ValueKey('tpb-pay-plate'), style: TextStyle(color: AppColors.text)),
              ),
            if ((d.note ?? '').isNotEmpty) Text(d.note!, style: TextStyle(color: AppColors.text)),
            if (d.holdUntil != null) ...[
              const SizedBox(height: 6),
              Text(s.t('tpb_hold_till', {'t': tirParkTime(d.holdUntil!)}), style: TextStyle(color: AppColors.promoVip)),
            ],
          ],
          if ((b.rejectNote ?? '').isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(s.t('tpb_rejected', {'note': b.rejectNote!}), style: TextStyle(color: AppColors.danger)),
          ],
          const SizedBox(height: 10),
          Text(s.t('tpb_no_money'), style: TextStyle(fontSize: 12.5, color: AppColors.textSoft)),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(s.t(_error!), key: const ValueKey('tpb-pay-error'), style: TextStyle(color: AppColors.danger)),
          ],
          const SizedBox(height: 12),
          FilledButton.icon(
            key: const ValueKey('tpb-upload'),
            onPressed: _busy || d == null ? null : _upload,
            icon: _busy
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.receipt_long_outlined),
            label: Text(s.t('tpb_upload')),
          ),
        ]),
      ),
    );
  }
}

/// Profil → "Park rezervasiyalarım": status, "Rekvizitlər və qəbz" while
/// unpaid, "Ödəniş yoxlanılır", and after the park's confirmation the
/// booking number, the entry code and its QR.
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
                    if ((b.plate ?? '').isNotEmpty)
                      Text('${s.t('tpb_plate')}: ${b.plate}', key: ValueKey('tpb-plate-${b.id}'), style: TextStyle(color: AppColors.text)),
                    Text(money(b.amount, b.currency), style: TextStyle(color: AppColors.text)),
                    if (b.shownStatus == 'payment_rejected')
                      Text(
                        (b.rejectNote ?? '').isEmpty ? s.t('tpb_rejected_plain') : s.t('tpb_rejected_end', {'note': b.rejectNote!}),
                        key: ValueKey('tpb-rejected-${b.id}'),
                        style: TextStyle(fontSize: 13, color: AppColors.danger),
                      ),
                    if (b.shownStatus == 'pending_payment') ...[
                      if ((b.rejectNote ?? '').isNotEmpty)
                        Text(s.t('tpb_rejected', {'note': b.rejectNote!}), style: TextStyle(fontSize: 13, color: AppColors.danger)),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        key: ValueKey('tpb-pay-${b.id}'),
                        onPressed: () => showTirParkPaySheet(context, s, b),
                        icon: const Icon(Icons.receipt_long_outlined, size: 18),
                        label: Text(s.t('tpb_pay_open')),
                      ),
                    ],
                    if ((b.code ?? '').isNotEmpty && b.status == 'confirmed') ...[
                      const SizedBox(height: 10),
                      Text(s.t('tpb_code'), style: TextStyle(fontSize: 12.5, color: AppColors.textSoft)),
                      Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                        // The QR on a white plate so it reads in day and night.
                        Container(
                          key: ValueKey('tpb-qr-${b.id}'),
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(color: AppColors.logoPlate, borderRadius: BorderRadius.circular(8)),
                          child: QrImageView(data: b.code!, size: 112, padding: EdgeInsets.zero),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            SelectableText(b.code!,
                                key: ValueKey('tpb-code-${b.id}'),
                                style: TextStyle(fontSize: 26, letterSpacing: 3, fontWeight: FontWeight.w600, color: AppColors.text)),
                            IconButton(
                              tooltip: s.t('tpb_copied'),
                              onPressed: () => Clipboard.setData(ClipboardData(text: b.code!)),
                              icon: const Icon(Icons.copy, size: 18),
                            ),
                          ]),
                        ),
                      ]),
                      Text(s.t('tpb_code_hint'), style: TextStyle(fontSize: 12.5, color: AppColors.textSoft)),
                    ],
                    if ((b.shownStatus == 'pending_payment' || b.status == 'payment_review' || b.status == 'confirmed') &&
                        b.startAt.isAfter(DateTime.now())) ...[
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
