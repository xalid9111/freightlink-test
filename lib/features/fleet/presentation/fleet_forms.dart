import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/localization/app_strings.dart';
import '../../../core/localization/locale_controller.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/birth_date_field.dart' show monthName;
import '../data/fleet_repository.dart';
import '../domain/fleet.dart';
import 'fleet_providers.dart';

/// The text key for a failed write.
String fleetErrorKey(Object e) => switch (e) {
      FleetNotReady() => 'fl_not_ready',
      FleetRefused(reason: 'name_required') => 'fl_err_name',
      FleetRefused(reason: 'invalid_amount') => 'fl_err_amount',
      FleetRefused(reason: 'invalid_code') => 'fl_err_code',
      FleetRefused(reason: 'own_truck') => 'fl_err_own_truck',
      FleetRefused(reason: 'already_decided') => 'fl_err_decided',
      FleetRefused(reason: 'too_many') => 'fl_err_too_many',
      _ => 'tp_err_generic',
    };

/// "450" / "450,5" / "1 200" → 450.0 …; null when empty or not a number > 0.
double? parseFleetAmount(String text) {
  final t = text.replaceAll(RegExp(r'\s'), '').replaceAll(',', '.');
  if (t.isEmpty) return null;
  final v = double.tryParse(t);
  if (v == null || v <= 0 || v > 100000000) return null;
  return v;
}

/// AZN · USD · EUR · RUB · TRY as chips (one chosen).
class FleetCurrencyPicker extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;
  const FleetCurrencyPicker({super.key, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) => Wrap(spacing: 8, runSpacing: 8, children: [
        for (final c in kFleetCurrencies)
          ChoiceChip(
            key: ValueKey('fl-cur-$c'),
            label: Text(c),
            selected: value == c,
            showCheckmark: false,
            selectedColor: AppColors.accentFill,
            labelStyle: TextStyle(color: value == c ? Colors.white : AppColors.text, fontWeight: value == c ? FontWeight.w500 : FontWeight.w400),
            onSelected: (_) => onChanged(c),
          ),
      ]);
}

/// A sheet's frame: title + ✕, the fields, the main button; the keyboard
/// never covers the button.
class _SheetFrame extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const _SheetFrame({required this.title, required this.children});

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.fromLTRB(18, 4, 18, 18 + MediaQuery.viewInsetsOf(context).bottom),
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(child: Text(title, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: AppColors.text))),
              IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.of(context).pop()),
            ]),
            const SizedBox(height: 8),
            ...children,
          ]),
        ),
      );
}

Future<T?> _sheet<T>(BuildContext context, Widget child) => showModalBottomSheet<T>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => child,
    );

Widget _label(String t) => Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 6),
      child: Text(t, style: TextStyle(fontSize: 13.5, color: AppColors.textSoft)),
    );

Widget _error(String? e) => e == null
    ? const SizedBox.shrink()
    : Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Text(e, key: const ValueKey('fl-error'), style: TextStyle(color: AppColors.danger)),
      );

// ---------------------------------------------------------------- truck

/// "Maşın əlavə et" / "Redaktə et": name, plate, driver.
Future<bool?> showFleetTruckForm(BuildContext context, {FleetTruck? truck}) => _sheet<bool>(context, _TruckForm(truck: truck));

class _TruckForm extends ConsumerStatefulWidget {
  final FleetTruck? truck;
  const _TruckForm({this.truck});
  @override
  ConsumerState<_TruckForm> createState() => _TruckFormState();
}

class _TruckFormState extends ConsumerState<_TruckForm> {
  late final _name = TextEditingController(text: widget.truck?.name ?? '');
  late final _plate = TextEditingController(text: widget.truck?.plate ?? '');
  late final _driver = TextEditingController(text: widget.truck?.driverName ?? '');
  bool _busy = false;
  String? _err;

  @override
  void dispose() {
    _name.dispose();
    _plate.dispose();
    _driver.dispose();
    super.dispose();
  }

  Future<void> _save(AppStrings s) async {
    if (_busy) return;
    if (_name.text.trim().isEmpty) {
      setState(() => _err = s.t('fl_err_name'));
      return;
    }
    setState(() {
      _busy = true;
      _err = null;
    });
    try {
      await ref.read(fleetRepositoryProvider).saveTruck(
            id: widget.truck?.id,
            name: _name.text.trim(),
            plate: _plate.text.trim().isEmpty ? null : _plate.text.trim(),
            driverName: _driver.text.trim().isEmpty ? null : _driver.text.trim(),
          );
      ref.invalidate(fleetProvider);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) setState(() => _err = s.t(fleetErrorKey(e)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    return _SheetFrame(title: s.t(widget.truck == null ? 'fl_add_truck' : 'fl_edit_truck'), children: [
      _label(s.t('fl_truck_name')),
      TextField(
        key: const ValueKey('fl-truck-name'),
        controller: _name,
        maxLength: 60,
        textCapitalization: TextCapitalization.words,
        decoration: InputDecoration(hintText: s.t('fl_truck_name_hint'), counterText: ''),
      ),
      _label(s.t('fl_plate')),
      TextField(
        key: const ValueKey('fl-truck-plate'),
        controller: _plate,
        maxLength: 20,
        textCapitalization: TextCapitalization.characters,
        decoration: const InputDecoration(hintText: '99-AC-981', counterText: ''),
      ),
      _label(s.t('fl_driver')),
      TextField(
        key: const ValueKey('fl-truck-driver'),
        controller: _driver,
        maxLength: 60,
        textCapitalization: TextCapitalization.words,
        decoration: InputDecoration(hintText: s.t('fl_driver_hint'), counterText: ''),
      ),
      _error(_err),
      const SizedBox(height: 16),
      FilledButton(
        key: const ValueKey('fl-truck-save'),
        onPressed: _busy ? null : () => _save(s),
        child: _busy ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : Text(s.t('fl_save')),
      ),
    ]);
  }
}

// ---------------------------------------------------------------- job

/// "İş əlavə et": the day and time, from → to, the agreed price + currency.
Future<bool?> showFleetJobForm(BuildContext context, {required String truckId, FleetJob? job}) => _sheet<bool>(context, _JobForm(truckId: truckId, job: job));

class _JobForm extends ConsumerStatefulWidget {
  final String truckId;
  final FleetJob? job;
  const _JobForm({required this.truckId, this.job});
  @override
  ConsumerState<_JobForm> createState() => _JobFormState();
}

class _JobFormState extends ConsumerState<_JobForm> {
  late DateTime _at = widget.job?.startAt ?? _roundedNow();
  late final _from = TextEditingController(text: widget.job?.from ?? '');
  late final _to = TextEditingController(text: widget.job?.to ?? '');
  late final _price = TextEditingController(text: widget.job?.price == null ? '' : fleetAmount(widget.job!.price!).replaceAll(' ', ''));
  late final _note = TextEditingController(text: widget.job?.note ?? '');
  late String _cur = widget.job?.currency ?? 'AZN';
  bool _busy = false;
  String? _err;

  static DateTime _roundedNow() {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day, n.hour, (n.minute ~/ 15) * 15);
  }

  @override
  void dispose() {
    _from.dispose();
    _to.dispose();
    _price.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _pickDay() async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: _at,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 2),
    );
    if (d != null) setState(() => _at = DateTime(d.year, d.month, d.day, _at.hour, _at.minute));
  }

  Future<void> _pickTime() async {
    final t = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(_at));
    if (t != null) setState(() => _at = DateTime(_at.year, _at.month, _at.day, t.hour, t.minute));
  }

  Future<void> _save(AppStrings s) async {
    if (_busy) return;
    final priceText = _price.text.trim();
    final price = priceText.isEmpty ? null : parseFleetAmount(priceText);
    if (priceText.isNotEmpty && price == null) {
      setState(() => _err = s.t('fl_err_amount'));
      return;
    }
    setState(() {
      _busy = true;
      _err = null;
    });
    try {
      await ref.read(fleetRepositoryProvider).saveJob(
            id: widget.job?.id,
            truckId: widget.truckId,
            startAt: _at,
            from: _from.text.trim().isEmpty ? null : _from.text.trim(),
            to: _to.text.trim().isEmpty ? null : _to.text.trim(),
            price: price,
            currency: _cur,
            note: _note.text.trim().isEmpty ? null : _note.text.trim(),
          );
      ref.invalidate(fleetProvider);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) setState(() => _err = s.t(fleetErrorKey(e)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    final lang = ref.watch(currentLocaleProvider).languageCode;
    return _SheetFrame(title: s.t(widget.job == null ? 'fl_add_job' : 'fl_edit_job'), children: [
      _label(s.t('fl_when')),
      Row(children: [
        Expanded(
          child: OutlinedButton.icon(
            key: const ValueKey('fl-job-day'),
            onPressed: _pickDay,
            icon: const Icon(Icons.calendar_today_outlined, size: 18),
            label: Text(fleetDayLabel(s, _at, lang)),
          ),
        ),
        const SizedBox(width: 10),
        OutlinedButton.icon(
          key: const ValueKey('fl-job-time'),
          onPressed: _pickTime,
          icon: const Icon(Icons.schedule, size: 18),
          label: Text(fleetTime(_at)),
        ),
      ]),
      _label(s.t('fl_from')),
      TextField(
          key: const ValueKey('fl-job-from'), controller: _from, maxLength: 80, decoration: InputDecoration(hintText: s.t('fl_from_hint'), counterText: '')),
      _label(s.t('fl_to')),
      TextField(key: const ValueKey('fl-job-to'), controller: _to, maxLength: 80, decoration: InputDecoration(hintText: s.t('fl_to_hint'), counterText: '')),
      _label(s.t('fl_price')),
      TextField(
        key: const ValueKey('fl-job-price'),
        controller: _price,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9., ]'))],
        decoration: const InputDecoration(hintText: '4500'),
      ),
      const SizedBox(height: 8),
      FleetCurrencyPicker(value: _cur, onChanged: (c) => setState(() => _cur = c)),
      _label(s.t('fl_note')),
      TextField(
          key: const ValueKey('fl-job-note'), controller: _note, maxLength: 300, maxLines: 2, minLines: 1, decoration: const InputDecoration(counterText: '')),
      _error(_err),
      const SizedBox(height: 16),
      FilledButton(
        key: const ValueKey('fl-job-save'),
        onPressed: _busy ? null : () => _save(s),
        child: _busy ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : Text(s.t('fl_save')),
      ),
    ]);
  }
}

// ---------------------------------------------------------------- expense

/// "Rasxod əlavə et" / "Rasxodu redaktə et" (owner's picture 3): name,
/// amount, currency; "Yadda saxla"; "Sil" for a saved one.
Future<bool?> showFleetExpenseForm(BuildContext context, {required String truckId, FleetExpense? expense, bool canRemove = false}) =>
    _sheet<bool>(context, _ExpenseForm(truckId: truckId, expense: expense, canRemove: canRemove));

class _ExpenseForm extends ConsumerStatefulWidget {
  final String truckId;
  final FleetExpense? expense;
  final bool canRemove;
  const _ExpenseForm({required this.truckId, this.expense, this.canRemove = false});
  @override
  ConsumerState<_ExpenseForm> createState() => _ExpenseFormState();
}

class _ExpenseFormState extends ConsumerState<_ExpenseForm> {
  late final _name = TextEditingController(text: widget.expense?.name ?? '');
  late final _amount = TextEditingController(text: widget.expense == null ? '' : fleetAmount(widget.expense!.amount).replaceAll(' ', ''));
  late String _cur = widget.expense?.currency ?? 'AZN';
  // One key per opened form: a double tap never adds twice (server).
  final _key = '${DateTime.now().microsecondsSinceEpoch}-${math.Random().nextInt(1 << 30)}';
  bool _busy = false;
  String? _err;

  @override
  void dispose() {
    _name.dispose();
    _amount.dispose();
    super.dispose();
  }

  Future<void> _save(AppStrings s) async {
    if (_busy) return;
    final amount = parseFleetAmount(_amount.text);
    if (_name.text.trim().isEmpty) {
      setState(() => _err = s.t('fl_err_name'));
      return;
    }
    if (amount == null) {
      setState(() => _err = s.t('fl_err_amount'));
      return;
    }
    setState(() {
      _busy = true;
      _err = null;
    });
    try {
      final repo = ref.read(fleetRepositoryProvider);
      String status = 'approved';
      if (widget.expense == null) {
        status = await repo.addExpense(truckId: widget.truckId, name: _name.text.trim(), amount: amount, currency: _cur, clientKey: _key);
      } else {
        await repo.updateExpense(widget.expense!.id, name: _name.text.trim(), amount: amount, currency: _cur);
      }
      ref.invalidate(fleetProvider);
      if (!mounted) return;
      Navigator.of(context).pop(true);
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(s.t(status == 'pending' ? 'fl_expense_sent' : 'fl_saved'))));
    } catch (e) {
      if (mounted) setState(() => _err = s.t(fleetErrorKey(e)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove(AppStrings s) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(s.t('fl_remove_expense_q')),
        actions: [
          TextButton(onPressed: () => Navigator.of(d).pop(false), child: Text(s.t('common_cancel'))),
          FilledButton(key: const ValueKey('fl-remove-yes'), onPressed: () => Navigator.of(d).pop(true), child: Text(s.t('fl_remove'))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await ref.read(fleetRepositoryProvider).removeExpense(widget.expense!.id);
      ref.invalidate(fleetProvider);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) setState(() => _err = s.t(fleetErrorKey(e)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    return _SheetFrame(title: s.t(widget.expense == null ? 'fl_add_expense' : 'fl_edit_expense'), children: [
      _label(s.t('fl_expense_name')),
      TextField(
        key: const ValueKey('fl-exp-name'),
        controller: _name,
        maxLength: 60,
        decoration: InputDecoration(hintText: s.t('fl_expense_name_hint'), counterText: ''),
      ),
      _label(s.t('fl_amount')),
      TextField(
        key: const ValueKey('fl-exp-amount'),
        controller: _amount,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9., ]'))],
        decoration: const InputDecoration(hintText: '450'),
      ),
      const SizedBox(height: 10),
      FleetCurrencyPicker(value: _cur, onChanged: (c) => setState(() => _cur = c)),
      _error(_err),
      const SizedBox(height: 18),
      FilledButton(
        key: const ValueKey('fl-exp-save'),
        onPressed: _busy ? null : () => _save(s),
        child: _busy ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : Text(s.t('fl_save')),
      ),
      if (widget.expense != null && widget.canRemove) ...[
        const SizedBox(height: 10),
        OutlinedButton(key: const ValueKey('fl-exp-remove'), onPressed: _busy ? null : () => _remove(s), child: Text(s.t('fl_remove'))),
      ],
    ]);
  }
}

// ---------------------------------------------------------------- driver

/// The driver enters the owner's code with his own account.
Future<String?> showFleetJoinSheet(BuildContext context) => _sheet<String>(context, const _JoinSheet());

class _JoinSheet extends ConsumerStatefulWidget {
  const _JoinSheet();
  @override
  ConsumerState<_JoinSheet> createState() => _JoinSheetState();
}

class _JoinSheetState extends ConsumerState<_JoinSheet> {
  final _code = TextEditingController();
  bool _busy = false;
  String? _err;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _join(AppStrings s) async {
    if (_busy || _code.text.trim().length < 6) return;
    setState(() {
      _busy = true;
      _err = null;
    });
    try {
      final name = await ref.read(fleetRepositoryProvider).join(_code.text);
      ref.invalidate(fleetProvider);
      if (mounted) Navigator.of(context).pop(name);
    } catch (e) {
      if (mounted) setState(() => _err = s.t(fleetErrorKey(e)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    return _SheetFrame(title: s.t('fl_join'), children: [
      Text(s.t('fl_join_hint'), style: TextStyle(color: AppColors.textSoft)),
      const SizedBox(height: 12),
      TextField(
        key: const ValueKey('fl-join-code'),
        controller: _code,
        maxLength: 12,
        textCapitalization: TextCapitalization.characters,
        style: const TextStyle(letterSpacing: 2, fontSize: 18),
        decoration: const InputDecoration(hintText: 'K7M2P9QX', counterText: ''),
      ),
      _error(_err),
      const SizedBox(height: 16),
      FilledButton(
        key: const ValueKey('fl-join-go'),
        onPressed: _busy ? null : () => _join(s),
        child: _busy ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : Text(s.t('fl_join_go')),
      ),
    ]);
  }
}

/// The owner's one-time code for the driver (7 days).
Future<void> showFleetInviteSheet(BuildContext context, {required String truckId}) => _sheet<void>(context, _InviteSheet(truckId: truckId));

class _InviteSheet extends ConsumerStatefulWidget {
  final String truckId;
  const _InviteSheet({required this.truckId});
  @override
  ConsumerState<_InviteSheet> createState() => _InviteSheetState();
}

class _InviteSheetState extends ConsumerState<_InviteSheet> {
  String? _code;
  String? _err;

  @override
  void initState() {
    super.initState();
    _make();
  }

  Future<void> _make() async {
    try {
      final c = await ref.read(fleetRepositoryProvider).inviteCode(widget.truckId);
      if (mounted) setState(() => _code = c);
    } catch (e) {
      if (mounted) setState(() => _err = ref.read(stringsProvider).t(fleetErrorKey(e)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    return _SheetFrame(title: s.t('fl_link_driver'), children: [
      Text(s.t('fl_invite_hint'), style: TextStyle(color: AppColors.textSoft)),
      const SizedBox(height: 16),
      if (_code == null && _err == null) const Center(child: CircularProgressIndicator()),
      if (_code != null)
        Center(
          child: SelectableText(_code!,
              key: const ValueKey('fl-invite-code'), style: TextStyle(fontSize: 30, letterSpacing: 4, fontWeight: FontWeight.w600, color: AppColors.accent)),
        ),
      _error(_err),
      const SizedBox(height: 16),
      if (_code != null)
        FilledButton.icon(
          key: const ValueKey('fl-invite-copy'),
          onPressed: () {
            Clipboard.setData(ClipboardData(text: s.t('fl_invite_share', {'code': _code!})));
            ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(s.t('fl_copied'))));
          },
          icon: const Icon(Icons.copy, size: 18),
          label: Text(s.t('fl_copy')),
        ),
    ]);
  }
}

/// "Bu gün" / "Sabah" / "20 noyabr".
String fleetDayLabel(AppStrings s, DateTime d, String lang) {
  final now = DateTime.now();
  final day = DateTime(d.year, d.month, d.day);
  final today = DateTime(now.year, now.month, now.day);
  final diff = day.difference(today).inDays;
  if (diff == 0) return s.t('fl_today');
  if (diff == 1) return s.t('fl_tomorrow');
  return '${d.day} ${monthName(d.month, lang)}${d.year != now.year ? ' ${d.year}' : ''}';
}
