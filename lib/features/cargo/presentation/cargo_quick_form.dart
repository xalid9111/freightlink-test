import 'package:flutter/material.dart';
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
  final _volumeCtrl = TextEditingController();

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
    for (final c in [_priceCtrl, _noteCtrl, _customTonsCtrl, _cargoTypeCtrl, _volumeCtrl]) {
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
    _volumeCtrl.text = c.volumeM3 == null ? '' : c.volumeM3!.toStringAsFixed(0);
    final t = c.weightKg / 1000;
    if (_tonOptions.contains(t)) {
      _tons = t;
    } else {
      _customTons = true;
      _customTonsCtrl.text = t == t.roundToDouble() ? t.toStringAsFixed(0) : t.toStringAsFixed(1);
    }
    _truck = _truckOptions.contains(c.truckType) ? c.truckType : null;
    _pickupDate = c.pickupDate;
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
        volumeM3: double.tryParse(_volumeCtrl.text.trim().replaceAll(',', '.')),
        palletCount: o?.palletCount,
        truckType: _truck ?? o?.truckType,
        pickupDate: _pickupDate!,
        deliveryDeadline: o?.deliveryDeadline,
        offeredPrice: double.parse(_priceCtrl.text.trim().replaceAll(',', '.')),
        currency: _currency, // chosen next to the price (USD by default)
        description: _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
        distanceKm: (pickupChanged || destChanged) ? null : o?.distanceKm,
        status: o?.status ?? 'new',
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
              _Label(strings.t('create_price_cur')),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _priceCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
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
                      controller: _volumeCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(labelText: strings.t('create_volume_m3')),
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),

              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(_error!, style: const TextStyle(color: AppColors.danger)),
                ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _submitting ? null : _submit,
                child: _submitting
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
        child: Text(text, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: AppColors.textSoft)),
      );
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
            Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textSoft)),
            const SizedBox(height: 4),
            if (p == null)
              Text(strings.t('city_pick'),
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.accent))
            else ...[
              Text(
                '${p.flag.isEmpty ? '' : '${p.flag} '}${p.cityLabel(lang)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: alignEnd ? TextAlign.end : TextAlign.start,
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppColors.text),
              ),
              Text(
                p.countryLabel(lang),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: alignEnd ? TextAlign.end : TextAlign.start,
                style: const TextStyle(fontSize: 12, color: AppColors.textSoft),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
