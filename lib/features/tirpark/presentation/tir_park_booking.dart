import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

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

/// "03.11" (local date) — bookings are by days (owner, 03.11.2026).
String tirParkDay(DateTime t) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(t.day)}.${two(t.month)}';
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
  // Days only (owner, 03.11.2026): the driver picks the arrival DAY, no hour.
  DateTime _day = _today();
  // "Qalma müddəti" in the park's own price unit (days or hours).
  int _len = 1;
  int _trucks = 1;
  // The truck's state number (0082), e.g. 99-ZB-911; filled in from the
  // driver's last booking.
  final _plate = TextEditingController();
  // One plate per further truck (0092): TIR 2 … TIR n.
  final _more = <TextEditingController>[];
  int? _free;
  bool _closed = false; // the server says the park takes no bookings now (e.g. no payment details)
  bool _busy = false;
  String? _error;

  static DateTime _today() {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  /// The stay counts from the chosen day's 00:00 (owner, 03.11.2026), today
  /// too; the server checks the places of every chosen day.
  DateTime get _from => _day;

  AppStrings get s => widget.s;
  TirPark get park => widget.park;
  String get _unit => 'day';
  int get _maxLen => 30;
  DateTime get _to => _from.add(Duration(days: _len));
  DateTime get _leaveDay => _day.add(Duration(days: _len));

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
    for (final c in _more) {
      c.dispose();
    }
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
    final today = _today();
    final d = await showDatePicker(
      context: context,
      initialDate: _day.isBefore(today) ? today : _day,
      firstDate: today,
      lastDate: today.add(const Duration(days: 60)),
    );
    if (d == null || !mounted) return;
    setState(() {
      _day = DateTime(d.year, d.month, d.day);
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
        TirParkRefused(reason: 'duplicate_plate') => 'tpb_err_plate_dup',
        TirParkRefused(reason: 'plates_count') => 'tpb_err_plate',
        _ => 'tpb_err_generic',
      };

  /// As many plate fields as TIRs (the first one is [_plate]).
  void _setTrucks(int v) {
    setState(() {
      _trucks = v;
      while (_more.length < v - 1) {
        _more.add(TextEditingController());
      }
      while (_more.length > v - 1) {
        _more.removeLast().dispose();
      }
      if (_error == 'tpb_err_plate' || _error == 'tpb_err_plate_dup') _error = null;
    });
  }

  /// Every truck's plate, tidied; null when one is wrong ([_error] set).
  List<String>? _platesOrError() {
    final out = <String>[];
    final fields = [_plate, ..._more];
    for (final c in fields) {
      final p = tidyTruckPlate(c.text);
      if (p == null) {
        setState(() => _error = 'tpb_err_plate');
        return null;
      }
      if (out.contains(p)) {
        setState(() => _error = 'tpb_err_plate_dup');
        return null;
      }
      out.add(p);
    }
    for (var i = 0; i < fields.length; i++) {
      fields[i].text = out[i];
    }
    return out;
  }

  /// "3,00 AZN / gün × 2 gün × 2 TIR = 12,00 AZN".
  String _calc(int units) => s.t('tpb_calc', {
        'price': money(park.price ?? 0, park.currency),
        'unit': tirParkUnitLabel(s, _unit),
        'units': '$units',
        'trucks': '$_trucks',
        'amount': money((park.price ?? 0) * units * _trucks, park.currency),
      });

  Future<void> _book() async {
    final plates = _platesOrError();
    if (plates == null) return;
    final plate = plates.first;
    final units = tirParkUnits(_from, _to, _unit);
    if (units <= 0 || _day.isBefore(_today())) {
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
            Text('${s.t('tpb_arrive_day')}: ${tirParkDay(_day)}', style: TextStyle(color: AppColors.text)),
            Text('${s.t('tpb_stay')}: $units ${tirParkUnitLabel(s, _unit)}', style: TextStyle(color: AppColors.text)),
            Text('${s.t('tpb_leave_day')}: ${tirParkDay(_leaveDay)}', style: TextStyle(color: AppColors.text)),
            Text('${s.t('tpb_trucks')}: $_trucks', style: TextStyle(color: AppColors.text)),
            Text('${s.t(plates.length > 1 ? 'tpb_plates' : 'tpb_plate')}: ${plates.join(', ')}',
                key: const ValueKey('tpb-plate-confirm'), style: TextStyle(color: AppColors.text)),
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
      final b = await ref.read(tirParkRepositoryProvider).book(park.id, _from, _to, _trucks, plate, plates: plates);
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
    // A park still priced per hour takes no bookings until its manager sets a day price.
    final closed = _closed || !park.bookingOpen || (park.price ?? 0) <= 0 || park.priceUnit != 'day';
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
            child: Text('${s.t('tpb_arrive_day')}\n${tirParkDay(_day)}', textAlign: TextAlign.center),
          ),
          const SizedBox(height: 6),
          _stepper(s.t('tpb_stay'), _len, '$_len ${tirParkUnitLabel(s, _unit)}', 'tpb-len', 1, _maxLen, _setLen),
          Text('${s.t('tpb_leave_day')}: ${tirParkDay(_leaveDay)}', key: const ValueKey('tpb-to'), style: TextStyle(color: AppColors.textSoft)),
          _stepper(s.t('tpb_trucks'), _trucks, '$_trucks', 'tpb-trucks', 1, 50, _setTrucks),
          TextField(
            key: const ValueKey('tpb-plate'),
            controller: _plate,
            // Scrolled up enough that the field and the button under it
            // stay above the keyboard.
            scrollPadding: const EdgeInsets.fromLTRB(20, 20, 20, 140),
            enabled: !_busy,
            textCapitalization: TextCapitalization.characters,
            maxLength: 15,
            onChanged: (_) {
              if (_error == 'tpb_err_plate') setState(() => _error = null);
            },
            decoration: InputDecoration(
              labelText: _trucks > 1 ? s.t('tpb_plate_n', {'n': '1'}) : s.t('tpb_plate'),
              hintText: s.t('tpb_plate_hint'),
              counterText: '',
              prefixIcon: const Icon(Icons.local_shipping_outlined),
            ),
          ),
          // TIR 2 … n: one plate each (0092), so every truck comes in on the booking.
          for (var i = 0; i < _more.length; i++)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: TextField(
                key: ValueKey('tpb-plate-${i + 2}'),
                controller: _more[i],
                scrollPadding: const EdgeInsets.fromLTRB(20, 20, 20, 140),
                enabled: !_busy,
                textCapitalization: TextCapitalization.characters,
                maxLength: 15,
                onChanged: (_) {
                  if (_error == 'tpb_err_plate' || _error == 'tpb_err_plate_dup') setState(() => _error = null);
                },
                decoration: InputDecoration(
                  labelText: s.t('tpb_plate_n', {'n': '${i + 2}'}),
                  hintText: s.t('tpb_plate_hint'),
                  counterText: '',
                  prefixIcon: const Icon(Icons.local_shipping_outlined),
                ),
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
      builder: (ctx) {
        // The keyboard (owner, 02.11.2026): the sheet stands above it, so
        // the plate field and what is typed there stay in view.
        final keyboard = MediaQuery.viewInsetsOf(ctx).bottom;
        final room = MediaQuery.sizeOf(ctx).height * 0.88 - keyboard;
        return Padding(
          padding: EdgeInsets.only(bottom: keyboard),
          child: SafeArea(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: room < 220 ? 220 : room),
              child: SingleChildScrollView(
                key: const ValueKey('tpb-sheet-scroll'),
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
      },
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
    final open = (now?.open ?? park.canBook) && park.priceUnit == 'day';
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
            if (b.allPlates.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text('${s.t(b.allPlates.length > 1 ? 'tpb_plates' : 'tpb_plate')}: ${b.platesLabel}', key: const ValueKey('tpb-pay-plate'), style: TextStyle(color: AppColors.text)),
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
                    Text('${b.bookingNo} · ${b.unit == 'day' ? tirParkDay(b.startAt) : tirParkTime(b.startAt)} → '
                        '${b.unit == 'day' ? tirParkDay(b.endAt) : tirParkTime(b.endAt)} · ${b.trucks} TIR',
                        style: TextStyle(color: AppColors.textSoft)),
                    if (b.allPlates.isNotEmpty)
                      Text('${s.t(b.allPlates.length > 1 ? 'tpb_plates' : 'tpb_plate')}: ${b.platesLabel}', key: ValueKey('tpb-plate-${b.id}'), style: TextStyle(color: AppColors.text)),
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
                    // No entry code or QR (owner, 03.11.2026): at the park the
                    // truck is found by its plate.
                    if (b.status == 'confirmed')
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(s.t('tpb_confirmed_hint', {'plate': b.platesLabel}),
                            key: ValueKey('tpb-confirmed-${b.id}'), style: TextStyle(color: AppColors.online)),
                      ),
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
