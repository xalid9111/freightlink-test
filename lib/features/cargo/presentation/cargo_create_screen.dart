import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/countries.dart';
import '../../../core/widgets/country_picker.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/localization/app_strings.dart';
import '../../../core/localization/locale_controller.dart';
import '../../../models/cargo_model.dart';
import '../../auth/presentation/providers/auth_providers.dart';
import 'providers/cargo_providers.dart';

/// Real "Create cargo" form (brief §5 / §4). Submits directly to
/// Supabase via CargoRepository.create() — RLS (migration 0002)
/// requires owner_id = auth.uid(), which is set below from the
/// signed-in user, so a cargo owner can only ever publish under their
/// own account even if this code had a bug.
class CargoCreateScreen extends ConsumerStatefulWidget {
  const CargoCreateScreen({super.key});

  @override
  ConsumerState<CargoCreateScreen> createState() => _CargoCreateScreenState();
}

class _CargoCreateScreenState extends ConsumerState<CargoCreateScreen> {
  final _formKey = GlobalKey<FormState>();

  final _pickupCountryCtrl = TextEditingController();
  final _pickupCityCtrl = TextEditingController();
  final _pickupAddressCtrl = TextEditingController();
  final _destinationCountryCtrl = TextEditingController();
  final _destinationCityCtrl = TextEditingController();
  final _destinationAddressCtrl = TextEditingController();
  final _cargoTypeCtrl = TextEditingController();
  final _weightCtrl = TextEditingController();
  final _volumeCtrl = TextEditingController();
  final _palletCtrl = TextEditingController();
  final _truckTypeCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
  final _descriptionCtrl = TextEditingController();
  final _pickupLatCtrl = TextEditingController();
  final _pickupLngCtrl = TextEditingController();
  final _destLatCtrl = TextEditingController();
  final _destLngCtrl = TextEditingController();

  DateTime? _pickupDate;
  DateTime? _deliveryDeadline;
  bool _submitting = false;
  String? _errorText;

  @override
  void dispose() {
    for (final c in [
      _pickupCountryCtrl, _pickupCityCtrl, _pickupAddressCtrl,
      _destinationCountryCtrl, _destinationCityCtrl, _destinationAddressCtrl,
      _cargoTypeCtrl, _weightCtrl, _volumeCtrl, _palletCtrl, _truckTypeCtrl,
      _priceCtrl, _descriptionCtrl,
      _pickupLatCtrl, _pickupLngCtrl, _destLatCtrl, _destLngCtrl,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  double? _parseOptionalDouble(String text) {
    final t = text.trim();
    if (t.isEmpty) return null;
    return double.tryParse(t);
  }

  Future<void> _pickDate({required bool isPickup}) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: now.subtract(const Duration(days: 1)),
      lastDate: now.add(const Duration(days: 365)),
    );
    if (picked == null) return;
    setState(() {
      if (isPickup) {
        _pickupDate = picked;
      } else {
        _deliveryDeadline = picked;
      }
    });
  }

  Future<void> _submit() async {
    final strings = ref.read(stringsProvider);
    if (!_formKey.currentState!.validate()) return;
    if (_pickupDate == null) {
      setState(() => _errorText = strings.t('field_required'));
      return;
    }

    final user = ref.read(currentUserProvider);
    if (user == null) return;

    setState(() {
      _submitting = true;
      _errorText = null;
    });

    try {
      final cargo = CargoModel(
        id: '', // ignored by toInsertJson()/create()
        ownerId: user.id,
        pickupCountry: _pickupCountryCtrl.text.trim(),
        pickupCity: _pickupCityCtrl.text.trim(),
        pickupAddress: _pickupAddressCtrl.text.trim().isEmpty ? null : _pickupAddressCtrl.text.trim(),
        pickupLatitude: _parseOptionalDouble(_pickupLatCtrl.text),
        pickupLongitude: _parseOptionalDouble(_pickupLngCtrl.text),
        destinationCountry: _destinationCountryCtrl.text.trim(),
        destinationCity: _destinationCityCtrl.text.trim(),
        destinationAddress:
            _destinationAddressCtrl.text.trim().isEmpty ? null : _destinationAddressCtrl.text.trim(),
        destinationLatitude: _parseOptionalDouble(_destLatCtrl.text),
        destinationLongitude: _parseOptionalDouble(_destLngCtrl.text),
        cargoType: _cargoTypeCtrl.text.trim().isEmpty ? null : _cargoTypeCtrl.text.trim(),
        weightKg: double.parse(_weightCtrl.text.trim()),
        volumeM3: _parseOptionalDouble(_volumeCtrl.text),
        palletCount: int.tryParse(_palletCtrl.text.trim()),
        truckType: _truckTypeCtrl.text.trim().isEmpty ? null : _truckTypeCtrl.text.trim(),
        pickupDate: _pickupDate!,
        deliveryDeadline: _deliveryDeadline,
        offeredPrice: double.parse(_priceCtrl.text.trim()),
        description: _descriptionCtrl.text.trim().isEmpty ? null : _descriptionCtrl.text.trim(),
      );

      final created = await ref.read(cargoRepositoryProvider).create(cargo);

      // Force the Home/Search feeds to re-fetch so the new listing
      // appears immediately without waiting for the next pull-to-refresh.
      ref.invalidate(marketplaceProvider);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(strings.t('create_success'))));
      context.pushReplacement('/cargo/${created.id}');
    } on AppException catch (e) {
      setState(() => _errorText = strings.error(e.code));
    } catch (e) {
      setState(() => _errorText = strings.t('error_generic'));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = ref.watch(stringsProvider);
    return Scaffold(
      appBar: AppBar(title: Text(strings.t('create_title'))),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            children: [
              _SectionLabel(strings.t('create_section_pickup')),
              _CountryField(controller: _pickupCountryCtrl, label: strings.t('create_pickup_country'), strings: strings),
              _TextField(controller: _pickupCityCtrl, label: strings.t('create_pickup_city'), required: true, strings: strings),
              _TextField(controller: _pickupAddressCtrl, label: strings.t('create_pickup_address')),
              _DateField(
                label: strings.t('create_pickup_date'),
                value: _pickupDate,
                onTap: () => _pickDate(isPickup: true),
              ),
              const SizedBox(height: 8),
              Text(strings.t('create_pickup_coords_title'), style: Theme.of(context).textTheme.labelMedium),
              Row(children: [
                Expanded(child: _TextField(controller: _pickupLatCtrl, label: strings.t('create_lat'), numeric: true)),
                const SizedBox(width: 10),
                Expanded(child: _TextField(controller: _pickupLngCtrl, label: strings.t('create_lng'), numeric: true)),
              ]),

              const SizedBox(height: 20),
              _SectionLabel(strings.t('create_section_destination')),
              _CountryField(controller: _destinationCountryCtrl, label: strings.t('create_destination_country'), strings: strings),
              _TextField(controller: _destinationCityCtrl, label: strings.t('create_destination_city'), required: true, strings: strings),
              _TextField(controller: _destinationAddressCtrl, label: strings.t('create_destination_address')),
              _DateField(
                label: strings.t('create_delivery_deadline'),
                value: _deliveryDeadline,
                onTap: () => _pickDate(isPickup: false),
              ),
              const SizedBox(height: 8),
              Text(strings.t('create_destination_coords_title'), style: Theme.of(context).textTheme.labelMedium),
              Row(children: [
                Expanded(child: _TextField(controller: _destLatCtrl, label: strings.t('create_lat'), numeric: true)),
                const SizedBox(width: 10),
                Expanded(child: _TextField(controller: _destLngCtrl, label: strings.t('create_lng'), numeric: true)),
              ]),

              const SizedBox(height: 20),
              _SectionLabel(strings.t('create_section_cargo')),
              _TextField(controller: _cargoTypeCtrl, label: strings.t('create_cargo_type')),
              _TextField(controller: _weightCtrl, label: strings.t('create_weight_kg'), numeric: true, required: true, strings: strings),
              _TextField(controller: _volumeCtrl, label: strings.t('create_volume_m3'), numeric: true),
              _TextField(controller: _palletCtrl, label: strings.t('create_pallet_count'), numeric: true),
              _TextField(controller: _truckTypeCtrl, label: strings.t('create_truck_type')),

              const SizedBox(height: 20),
              _SectionLabel(strings.t('create_section_price')),
              _TextField(controller: _priceCtrl, label: strings.t('create_price'), numeric: true, required: true, strings: strings),
              _TextField(controller: _descriptionCtrl, label: strings.t('create_description'), maxLines: 3),

              if (_errorText != null) ...[
                const SizedBox(height: 12),
                Text(_errorText!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ],
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _submitting ? null : _submit,
                child: _submitting
                    ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : Text(strings.t('create_submit')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(text, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
      );
}

/// Required country picker. Shows "🇦🇿 Azərbaycan" in the UI language;
/// writes the canonical English name into [controller] (what gets
/// stored — see core/constants/countries.dart), so the submit code that
/// reads `controller.text` is unchanged.
class _CountryField extends ConsumerWidget {
  final TextEditingController controller;
  final String label;
  final AppStrings strings;
  const _CountryField({required this.controller, required this.label, required this.strings});

  Future<Country?> _pick(BuildContext context, String languageCode) {
    return showModalBottomSheet<Country>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => CountryPickerSheet(languageCode: languageCode, strings: strings),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final languageCode = ref.watch(currentLocaleProvider).languageCode;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: FormField<String>(
        initialValue: controller.text,
        validator: (v) => (v == null || v.trim().isEmpty) ? strings.t('field_required') : null,
        builder: (state) {
          final value = state.value ?? '';
          return InkWell(
            onTap: () async {
              final picked = await _pick(context, languageCode);
              if (picked != null) {
                controller.text = picked.en;
                state.didChange(picked.en);
              }
            },
            child: InputDecorator(
              isEmpty: value.isEmpty,
              decoration: InputDecoration(
                labelText: label,
                border: const OutlineInputBorder(),
                errorText: state.errorText,
                suffixIcon: const Icon(Icons.arrow_drop_down),
              ),
              child: Text(value.isEmpty ? '' : Countries.label(value, languageCode)),
            ),
          );
        },
      ),
    );
  }
}

class _TextField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final bool required;
  final bool numeric;
  final int maxLines;
  final AppStrings? strings;

  const _TextField({
    required this.controller,
    required this.label,
    this.required = false,
    this.numeric = false,
    this.maxLines = 1,
    this.strings,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: controller,
        maxLines: maxLines,
        keyboardType: numeric ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.text,
        decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
        validator: (v) {
          final s = strings;
          if (required && (v == null || v.trim().isEmpty)) return s?.t('field_required') ?? label;
          if (numeric && v != null && v.trim().isNotEmpty && double.tryParse(v.trim()) == null) {
            return s?.t('field_invalid_number') ?? label;
          }
          return null;
        },
      ),
    );
  }
}

class _DateField extends StatelessWidget {
  final String label;
  final DateTime? value;
  final VoidCallback onTap;
  const _DateField({required this.label, required this.value, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: onTap,
        child: InputDecorator(
          decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
          child: Text(value == null ? '—' : '${value!.year}-${value!.month.toString().padLeft(2, '0')}-${value!.day.toString().padLeft(2, '0')}'),
        ),
      ),
    );
  }
}
