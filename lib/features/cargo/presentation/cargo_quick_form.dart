import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/currencies.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/localization/app_strings.dart';
import '../../../core/localization/locale_controller.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/city_picker.dart';
import '../../../models/cargo_model.dart';
import '../../auth/presentation/providers/auth_providers.dart';
import 'providers/cargo_providers.dart';

/// Quick "post a load" form, built for speed on a phone: countries and
/// weight are picked with one tap (chips), only city + price are typed.
/// Everything else is optional and folded under "More details".
/// With [editCargoId] the same form edits an existing load.
class CargoQuickForm extends ConsumerStatefulWidget {
  final String? editCargoId;
  const CargoQuickForm({super.key, this.editCargoId});

  @override
  ConsumerState<CargoQuickForm> createState() => _CargoQuickFormState();
}

class _CargoQuickFormState extends ConsumerState<CargoQuickForm> {
  static const _tonOptions = [1.0, 3.0, 5.0, 10.0, 15.0, 20.0, 22.0, 25.0, 30.0];
  static const _truckOptions = ['tent', 'ref', 'open', 'container', 'tanker'];

  final _formKey = GlobalKey<FormState>();
  final _priceCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  final _customTonsCtrl = TextEditingController();
  final _cargoTypeCtrl = TextEditingController();
  final _palletCtrl = TextEditingController();
  // Advance amount (0046); the other payment ways are only ticked (0047).
  final _advanceCtrl = TextEditingController();
  int _freeWait = kDefaultFreeWaitHours;
  // Ticked payment ways: advance (its box opens), cash, delivery, bank.
  final Set<String> _payOn = {};

  // Route ends: city + its country, chosen together in one sheet.
  PickedPlace? _from;
  PickedPlace? _to;
  // In edit mode an end the user didn't touch keeps its stored text
  // exactly (and its saved exact point / distance).
  bool _fromTouched = false;
  bool _toTouched = false;
  double? _tons;
  bool _customTons = false;
  String? _truck;
  DateTime? _pickupDate;
  String _currency = kDefaultCargoCurrency;

  CargoModel? _original;
  bool _loaded = false;
  bool _submitting = false;
  String? _error;

  bool get _isEdit => widget.editCargoId != null;

  @override
  void dispose() {
    for (final c in [
      _priceCtrl,
      _noteCtrl,
      _customTonsCtrl,
      _cargoTypeCtrl,
      _palletCtrl,
      _advanceCtrl,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  void _prefill(CargoModel c) {
    _original = c;
    _from = PickedPlace.fromStored(c.pickupCity, c.pickupCountry);
    _to = PickedPlace.fromStored(c.destinationCity, c.destinationCountry);
    _priceCtrl.text = c.offeredPrice.toStringAsFixed(0);
    _currency = cargoCurrencyOrDefault(c.currency);
    _noteCtrl.text = c.description ?? '';
    _cargoTypeCtrl.text = c.cargoType ?? '';
    _palletCtrl.text = c.palletCount?.toString() ?? '';
    final t = c.weightKg / 1000;
    if (_tonOptions.contains(t)) {
      _tons = t;
    } else {
      _customTons = true;
      _customTonsCtrl.text = t == t.roundToDouble() ? t.toStringAsFixed(0) : t.toStringAsFixed(1);
    }
    _truck = _truckOptions.contains(c.truckType) ? c.truckType : null;
    _pickupDate = c.pickupDate;
    String amount(double? v) => v == null ? '' : (v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2));
    _advanceCtrl.text = amount(c.payAdvance);
    _payOn
      ..clear()
      ..addAll([
        if (c.payAdvance != null) 'advance',
        if (c.cashTicked) 'cash',
        if (c.payOnDelivery) 'delivery',
        if (c.bankTicked) 'bank',
      ]);
    _freeWait = kFreeWaitChoices.contains(c.freeWaitHours) ? c.freeWaitHours! : kDefaultFreeWaitHours;
    _loaded = true;
  }

  Future<void> _pickCity({required bool from}) async {
    final lang = ref.read(currentLocaleProvider).languageCode;
    final strings = ref.read(stringsProvider);
    final picked = await showModalBottomSheet<PickedPlace>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => CityPickerSheet(
        languageCode: lang,
        strings: strings,
        title: strings.t(from ? 'route_from' : 'route_to'),
      ),
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (from) {
        _from = picked;
        _fromTouched = true;
      } else {
        _to = picked;
        _toTouched = true;
      }
    });
  }

  void _swap() {
    setState(() {
      final f = _from;
      _from = _to;
      _to = f;
      final t = _fromTouched;
      _fromTouched = _toTouched || _from != null;
      _toTouched = t || _to != null;
    });
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _pickupDate ?? now,
      firstDate: DateTime(now.year, now.month, now.day).subtract(const Duration(days: 1)),
      lastDate: now.add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _pickupDate = picked);
  }

  double? get _weightTons {
    if (_customTons) return double.tryParse(_customTonsCtrl.text.trim().replaceAll(',', '.'));
    return _tons;
  }

  Future<void> _submit() async {
    final strings = ref.read(stringsProvider);
    final o0 = _original;
    // Untouched ends in edit mode keep exactly what was stored.
    final fromValue = (o0 != null && !_fromTouched) ? o0.pickupCountry : (_from?.country ?? '');
    final toValue = (o0 != null && !_toTouched) ? o0.destinationCountry : (_to?.country ?? '');
    final fromCity = (o0 != null && !_fromTouched) ? o0.pickupCity : (_from?.city ?? '');
    final toCity = (o0 != null && !_toTouched) ? o0.destinationCity : (_to?.city ?? '');
    final tons = _weightTons;
    String? problem;
    if (fromValue.isEmpty || toValue.isEmpty || fromCity.trim().isEmpty || toCity.trim().isEmpty) {
      problem = strings.t('quick_err_route');
    }
    if (problem == null && (tons == null || tons <= 0)) problem = strings.t('quick_err_weight');
    if (problem == null && _pickupDate == null) problem = strings.t('quick_err_date');
    final formOk = _formKey.currentState!.validate();
    if (problem != null || !formOk) {
      setState(() => _error = problem ?? strings.t('quick_err_fields'));
      return;
    }
    final user = ref.read(currentUserProvider);
    if (user == null) return;

    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final o = _original;
      // If a route end moved, its saved exact point and distance are stale.
      final pickupChanged = o == null || o.pickupCountry != fromValue || o.pickupCity != fromCity;
      final destChanged = o == null || o.destinationCountry != toValue || o.destinationCity != toCity;
      final cargo = CargoModel(
        id: o?.id ?? '',
        ownerId: o?.ownerId ?? user.id,
        companyId: o?.companyId,
        pickupCountry: fromValue,
        pickupCity: fromCity.trim(),
        pickupAddress: o?.pickupAddress,
        pickupLatitude: pickupChanged ? null : o?.pickupLatitude,
        pickupLongitude: pickupChanged ? null : o?.pickupLongitude,
        destinationCountry: toValue,
        destinationCity: toCity.trim(),
        destinationAddress: o?.destinationAddress,
        destinationLatitude: destChanged ? null : o?.destinationLatitude,
        destinationLongitude: destChanged ? null : o?.destinationLongitude,
        cargoType: _cargoTypeCtrl.text.trim().isEmpty ? null : _cargoTypeCtrl.text.trim(),
        weightKg: tons! * 1000,
        // Volume is no longer asked (owner, 20.10.2026: pallets instead);
        // an old load keeps its saved volume.
        volumeM3: o?.volumeM3,
        palletCount: int.tryParse(_palletCtrl.text.trim()),
        truckType: _truck ?? o?.truckType,
        pickupDate: _pickupDate!,
        deliveryDeadline: o?.deliveryDeadline,
        offeredPrice: double.parse(_priceCtrl.text.trim().replaceAll(',', '.')),
        currency: _currency, // chosen next to the price (USD by default)
        description: _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
        distanceKm: (pickupChanged || destChanged) ? null : o?.distanceKm,
        status: o?.status ?? 'new',
        // Checked by the form validator above (positive or empty).
        payAdvance: _payOn.contains('advance') ? parsePaymentAmount(_advanceCtrl.text) : null,
        // Cash / bank have no amount any more (owner, 21.10.2026); an
        // amount saved earlier stays while the way stays ticked.
        payCash: _payOn.contains('cash') ? o?.payCash : null,
        payBank: _payOn.contains('bank') ? o?.payBank : null,
        payCashOn: _payOn.contains('cash'),
        payOnDelivery: _payOn.contains('delivery'),
        payBankOn: _payOn.contains('bank'),
        freeWaitHours: _freeWait,
      );

      final repo = ref.read(cargoRepositoryProvider);
      String id;
      if (o == null) {
        id = (await repo.create(cargo)).id;
      } else {
        await repo.update(cargo);
        id = o.id;
        ref.invalidate(cargoDetailProvider(id));
      }
      ref.invalidate(marketplaceProvider);
      ref.invalidate(myCargoProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(strings.t(o == null ? 'create_success' : 'quick_saved'))),
      );
      if (o == null) {
        context.pushReplacement('/cargo/$id');
      } else {
        context.pop();
      }
    } on AppException catch (e) {
      setState(() => _error = strings.error(e.code));
    } catch (_) {
      setState(() => _error = strings.t('error_generic'));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = ref.watch(stringsProvider);
    final lang = ref.watch(currentLocaleProvider).languageCode;

    if (_isEdit && !_loaded) {
      final async = ref.watch(cargoDetailProvider(widget.editCargoId!));
      return Scaffold(
        appBar: AppBar(title: Text(strings.t('quick_edit_title'))),
        body: async.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, __) => Center(child: Text(strings.t('error_generic'))),
          data: (c) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted && !_loaded) setState(() => _prefill(c));
            });
            return const Center(child: CircularProgressIndicator());
          },
        ),
      );
    }

    final dateFmt = DateFormat('d MMM yyyy', lang);
    final today = DateTime.now();
    final tomorrow = today.add(const Duration(days: 1));
    bool sameDay(DateTime? a, DateTime b) => a != null && a.year == b.year && a.month == b.month && a.day == b.day;

    return Scaffold(
      appBar: AppBar(title: Text(strings.t(_isEdit ? 'quick_edit_title' : 'create_title'))),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
            children: [
              _RouteCard(
                from: _from,
                to: _to,
                lang: lang,
                strings: strings,
                onFrom: () => _pickCity(from: true),
                onTo: () => _pickCity(from: false),
                onSwap: _swap,
              ),

              const SizedBox(height: 18),
              _Label(strings.t('quick_weight')),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final t in _tonOptions)
                    ChoiceChip(
                      label: Text('${t.toStringAsFixed(0)} t'),
                      selected: !_customTons && _tons == t,
                      onSelected: (_) => setState(() {
                        _tons = t;
                        _customTons = false;
                      }),
                    ),
                  ChoiceChip(
                    label: Text(strings.t('quick_other')),
                    selected: _customTons,
                    onSelected: (_) => setState(() => _customTons = true),
                  ),
                ],
              ),
              if (_customTons)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: TextFormField(
                    controller: _customTonsCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(labelText: strings.t('quick_weight_tons'), suffixText: 't'),
                  ),
                ),

              const SizedBox(height: 18),
              _Label(strings.t('create_pickup_date')),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ChoiceChip(
                    label: Text(strings.t('quick_today')),
                    selected: sameDay(_pickupDate, today),
                    onSelected: (_) => setState(() => _pickupDate = DateTime(today.year, today.month, today.day)),
                  ),
                  ChoiceChip(
                    label: Text(strings.t('quick_tomorrow')),
                    selected: sameDay(_pickupDate, tomorrow),
                    onSelected: (_) => setState(() => _pickupDate = DateTime(tomorrow.year, tomorrow.month, tomorrow.day)),
                  ),
                  ChoiceChip(
                    avatar: const Icon(Icons.calendar_month, size: 18),
                    label: Text(
                      (_pickupDate != null && !sameDay(_pickupDate, today) && !sameDay(_pickupDate, tomorrow))
                          ? dateFmt.format(_pickupDate!)
                          : strings.t('quick_pick_date'),
                    ),
                    selected: _pickupDate != null && !sameDay(_pickupDate, today) && !sameDay(_pickupDate, tomorrow),
                    onSelected: (_) => _pickDate(),
                  ),
                ],
              ),

              const SizedBox(height: 18),
              // Without "(USD)": the currency is picked next to the price.
              _FormCard(
                icon: Icons.sell_outlined,
                title: strings.t('create_price_cur'),
                child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _priceCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(hintText: strings.t('cargo_price_hint')),
                      validator: (v) {
                        final p = double.tryParse((v ?? '').trim().replaceAll(',', '.'));
                        return (p == null || p < 0) ? strings.t('field_required') : null;
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  // Currency of the price (USD by default).
                  SizedBox(
                    width: 104,
                    child: DropdownButtonFormField<String>(
                      // Re-created once an edited load is loaded, so its saved currency shows.
                      key: ValueKey('cargo-currency-${_original?.id}'),
                      initialValue: _currency,
                      isExpanded: true,
                      items: [
                        for (final c in cargoCurrencyChoices(_currency)) DropdownMenuItem(value: c, child: Text(c)),
                      ],
                      onChanged: (v) {
                        if (v != null) setState(() => _currency = v);
                      },
                    ),
                  ),
                ],
              ),
              ),

              const SizedBox(height: 18),
              _PaymentTerms(
                strings: strings,
                currency: _currency,
                advance: _advanceCtrl,
                on: _payOn,
                onToggle: (k, v) => setState(() {
                  if (v) {
                    _payOn.add(k);
                  } else {
                    // Unticked: not shown on the load (the advance amount is cleared).
                    _payOn.remove(k);
                    if (k == 'advance') _advanceCtrl.clear();
                  }
                }),
                freeWait: _freeWait,
                onFreeWait: (h) => setState(() => _freeWait = h),
              ),

              const SizedBox(height: 18),
              _Label(strings.t('quick_note')),
              TextFormField(
                controller: _noteCtrl,
                maxLines: 2,
                maxLength: 200,
                decoration: InputDecoration(hintText: strings.t('quick_note_hint')),
              ),

              // Optional extras, folded away so the form stays short.
              Theme(
                data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: Text(strings.t('quick_more'), style: const TextStyle(fontWeight: FontWeight.w600)),
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: _Label(strings.t('create_truck_type')),
                    ),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final t in _truckOptions)
                          ChoiceChip(
                            label: Text(strings.t('truck_$t')),
                            selected: _truck == t,
                            onSelected: (sel) => setState(() => _truck = sel ? t : null),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _cargoTypeCtrl,
                      decoration: InputDecoration(labelText: strings.t('create_cargo_type')),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      key: const ValueKey('cargo-pallets'),
                      controller: _palletCtrl,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(4)],
                      decoration: InputDecoration(
                        labelText: strings.t('detail_pallets_label'),
                        hintText: strings.t('cargo_pallet_hint'),
                        // Always visible, like the payment boxes.
                        suffixIcon: Padding(
                          padding: const EdgeInsets.only(right: 14, left: 4),
                          child: Text(strings.t('cargo_pallet_unit'),
                              style: TextStyle(color: AppColors.textSoft, fontWeight: FontWeight.w600)),
                        ),
                        suffixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
                      ),
                      validator: (v) {
                        final t = (v ?? '').trim();
                        return t.isEmpty || (int.tryParse(t) ?? 0) > 0 ? null : strings.t('cargo_pallet_invalid');
                      },
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),

              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(_error!, style: TextStyle(color: AppColors.danger)),
                ),
              const SizedBox(height: 12),
              FilledButton.icon(
                key: const ValueKey('cargo-submit'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                ),
                onPressed: _submitting ? null : _submit,
                icon: _submitting ? const SizedBox.shrink() : Icon(_isEdit ? Icons.check_circle_outline : Icons.add_circle, size: 24),
                label: _submitting
                    ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : Text(strings.t(_isEdit ? 'quick_save' : 'create_submit')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(text, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: AppColors.textSoft)),
      );
}

/// Card of the load form (owner's design, 20.10.2026): orange icon,
/// title, optional grey line under it, then the fields.
class _FormCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget child;
  const _FormCard({required this.icon, required this.title, this.subtitle, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, color: AppColors.accent, size: 24),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.text)),
              if (subtitle != null) ...[
                const SizedBox(height: 3),
                Text(subtitle!, style: TextStyle(fontSize: 12.5, color: AppColors.textSoft)),
              ],
            ]),
          ),
        ]),
        const SizedBox(height: 12),
        child,
      ]),
    );
  }
}

/// "Ödəniş şərtləri" and "Prostoy" (0046) as two cards: each way of paying
/// has a tick box on the left, its name, and the amount box opposite
/// (open only when ticked); then 24 / 36 / 48 h as three equal buttons.
class _PaymentTerms extends StatelessWidget {
  final AppStrings strings;
  final String currency;
  final TextEditingController advance;
  final Set<String> on;
  final void Function(String key, bool on) onToggle;
  final int freeWait;
  final ValueChanged<int> onFreeWait;
  const _PaymentTerms({
    required this.strings,
    required this.currency,
    required this.advance,
    required this.on,
    required this.onToggle,
    required this.freeWait,
    required this.onFreeWait,
  });

  @override
  Widget build(BuildContext context) {
    Widget row(String id, String key, TextEditingController ctrl) {
      final ticked = on.contains(id);
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        // Wide screens: name and box stay close together on the left.
        child: Align(
          alignment: Alignment.centerLeft,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: LayoutBuilder(
              builder: (context, c) => Row(children: [
                Checkbox(
                  key: ValueKey('cargo-pay-on-$id'),
                  value: ticked,
                  visualDensity: VisualDensity.compact,
                  onChanged: (v) => onToggle(id, v ?? false),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: GestureDetector(
                    onTap: () => onToggle(id, !ticked),
                    child: Text(strings.t(key),
                        style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: AppColors.text)),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  // Narrow phones: the box shrinks, the text wraps — never overlaps.
                  width: (c.maxWidth * 0.44).clamp(104.0, 200.0),
                  child: TextFormField(
                    key: ValueKey('cargo-$key'),
                    controller: ctrl,
                    enabled: ticked,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    // Digits and one separator only: no minus sign.
                    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
                    textAlign: TextAlign.end,
                    decoration: InputDecoration(
                      hintText: strings.t('cargo_pay_amount'),
                      // Always visible (suffixText hides while the box is empty).
                      suffixIcon: Padding(
                        padding: const EdgeInsets.only(right: 12, left: 4),
                        child: Text(currency, style: TextStyle(color: AppColors.textSoft, fontWeight: FontWeight.w600)),
                      ),
                      suffixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
                      isDense: true,
                    ),
                    validator: (v) {
                      if (!ticked) return null;
                      try {
                        // Ticked: an amount is needed.
                        return parsePaymentAmount(v) == null ? strings.t('cargo_pay_invalid') : null;
                      } on FormatException {
                        return strings.t('cargo_pay_invalid');
                      }
                    },
                  ),
                ),
              ]),
            ),
          ),
        ),
      );
    }

    // Cash, payment after delivery, bank transfer: just a tick, no amount
    // (the price is already given above).
    Widget choice(String id, String key) {
      final ticked = on.contains(id);
      return Align(
        alignment: Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: InkWell(
            key: ValueKey('cargo-pay-choice-$id'),
            borderRadius: BorderRadius.circular(10),
            onTap: () => onToggle(id, !ticked),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(children: [
                Checkbox(
                  key: ValueKey('cargo-pay-on-$id'),
                  value: ticked,
                  visualDensity: VisualDensity.compact,
                  onChanged: (v) => onToggle(id, v ?? false),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(strings.t(key),
                      style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: AppColors.text)),
                ),
              ]),
            ),
          ),
        ),
      );
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _FormCard(
        icon: Icons.payments_outlined,
        title: strings.t('cargo_pay_title'),
        subtitle: strings.t('cargo_pay_sub'),
        child: Column(children: [
          row('advance', 'cargo_pay_advance', advance),
          choice('cash', 'cargo_pay_cash'),
          choice('delivery', 'cargo_pay_on_delivery'),
          choice('bank', 'cargo_pay_bank'),
        ]),
      ),
      const SizedBox(height: 14),
      _FormCard(
        icon: Icons.schedule,
        title: strings.t('cargo_wait_title'),
        subtitle: strings.t('cargo_wait_sub'),
        child: Align(
          alignment: Alignment.centerLeft,
          child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Row(children: [
          for (final h in kFreeWaitChoices) ...[
            if (h != kFreeWaitChoices.first) const SizedBox(width: 8),
            Expanded(
              child: ChoiceChip(
                key: ValueKey('cargo-wait-$h'),
                label: SizedBox(
                  width: double.infinity,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(strings.t('cargo_wait_hours', {'n': '$h'})),
                  ),
                ),
                padding: const EdgeInsets.symmetric(vertical: 8),
                selected: freeWait == h,
                onSelected: (_) => onFreeWait(h),
              ),
            ),
          ],
        ]),
        ),
        ),
      ),
    ]);
  }
}

/// Compact route card:  Haradan            ⇄            Haraya
///                       🇦🇿 Bakı                       🇷🇺 Moskva
/// Tapping an end opens the city sheet; ⇄ swaps the ends.
class _RouteCard extends StatelessWidget {
  final PickedPlace? from;
  final PickedPlace? to;
  final String lang;
  final AppStrings strings;
  final VoidCallback onFrom;
  final VoidCallback onTo;
  final VoidCallback onSwap;
  const _RouteCard({
    required this.from,
    required this.to,
    required this.lang,
    required this.strings,
    required this.onFrom,
    required this.onTo,
    required this.onSwap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.line),
      ),
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(child: _RouteEndButton(label: strings.t('route_from'), place: from, lang: lang, strings: strings, onTap: onFrom, alignEnd: false)),
          Material(
            color: AppColors.accentFill,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: (from == null && to == null) ? null : onSwap,
              child: const Padding(
                padding: EdgeInsets.all(9),
                child: Icon(Icons.swap_horiz, color: Colors.white, size: 22),
              ),
            ),
          ),
          Expanded(child: _RouteEndButton(label: strings.t('route_to'), place: to, lang: lang, strings: strings, onTap: onTo, alignEnd: true)),
        ],
      ),
    );
  }
}

class _RouteEndButton extends StatelessWidget {
  final String label;
  final PickedPlace? place;
  final String lang;
  final AppStrings strings;
  final VoidCallback onTap;
  final bool alignEnd;
  const _RouteEndButton({
    required this.label,
    required this.place,
    required this.lang,
    required this.strings,
    required this.onTap,
    required this.alignEnd,
  });

  @override
  Widget build(BuildContext context) {
    final p = place;
    final cross = alignEnd ? CrossAxisAlignment.end : CrossAxisAlignment.start;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          crossAxisAlignment: cross,
          children: [
            Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textSoft)),
            const SizedBox(height: 4),
            if (p == null)
              Text(strings.t('city_pick'),
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.accent))
            else ...[
              Text(
                '${p.flag.isEmpty ? '' : '${p.flag} '}${p.cityLabel(lang)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: alignEnd ? TextAlign.end : TextAlign.start,
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppColors.text),
              ),
              Text(
                p.countryLabel(lang),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: alignEnd ? TextAlign.end : TextAlign.start,
                style: TextStyle(fontSize: 12, color: AppColors.textSoft),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
