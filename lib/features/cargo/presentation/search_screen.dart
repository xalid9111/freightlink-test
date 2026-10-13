import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/localization/locale_controller.dart';
import '../../../core/constants/countries.dart';
import 'providers/cargo_providers.dart';
import 'widgets/cargo_card.dart';
import '../../../core/router/safe_navigation.dart';

/// Bottom-nav "Search" tab — real filters wired straight to
/// CargoRepository.fetchMarketplace(), same repository the Home tab
/// uses, just with the filter arguments actually populated.
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _fromCtrl = TextEditingController();
  final _toCtrl = TextEditingController();
  final _cargoTypeCtrl = TextEditingController();
  final _truckTypeCtrl = TextEditingController();
  final _minPriceCtrl = TextEditingController();
  final _maxPriceCtrl = TextEditingController();
  final _maxWeightCtrl = TextEditingController();

  CargoFilter _filter = const CargoFilter();

  @override
  void dispose() {
    for (final c in [_fromCtrl, _toCtrl, _cargoTypeCtrl, _truckTypeCtrl, _minPriceCtrl, _maxPriceCtrl, _maxWeightCtrl]) {
      c.dispose();
    }
    super.dispose();
  }

  void _apply() {
    setState(() {
      _filter = CargoFilter(
        // Typed country names in any language map to the canonical
        // English name new cargo is stored with (core/constants/countries.dart).
        pickupCountry: _fromCtrl.text.trim().isEmpty ? null : Countries.canonical(_fromCtrl.text),
        destinationCountry: _toCtrl.text.trim().isEmpty ? null : Countries.canonical(_toCtrl.text),
        cargoType: _cargoTypeCtrl.text.trim().isEmpty ? null : _cargoTypeCtrl.text.trim(),
        truckType: _truckTypeCtrl.text.trim().isEmpty ? null : _truckTypeCtrl.text.trim(),
        minPrice: double.tryParse(_minPriceCtrl.text.trim()),
        maxPrice: double.tryParse(_maxPriceCtrl.text.trim()),
        maxWeightKg: double.tryParse(_maxWeightCtrl.text.trim()),
      );
    });
  }

  void _clear() {
    for (final c in [_fromCtrl, _toCtrl, _cargoTypeCtrl, _truckTypeCtrl, _minPriceCtrl, _maxPriceCtrl, _maxWeightCtrl]) {
      c.clear();
    }
    setState(() => _filter = const CargoFilter());
  }

  @override
  Widget build(BuildContext context) {
    final strings = ref.watch(stringsProvider);
    final resultsAsync = ref.watch(filteredCargoProvider(_filter));

    return Scaffold(
      appBar: AppBar(title: Text(strings.t('search_placeholder_title'))),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
            child: Column(
              children: [
                Row(children: [
                  Expanded(child: _FilterField(controller: _fromCtrl, label: strings.t('search_from_label'))),
                  const SizedBox(width: 10),
                  Expanded(child: _FilterField(controller: _toCtrl, label: strings.t('search_to_label'))),
                ]),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(child: _FilterField(controller: _cargoTypeCtrl, label: strings.t('search_cargo_type_label'))),
                  const SizedBox(width: 10),
                  Expanded(child: _FilterField(controller: _truckTypeCtrl, label: strings.t('search_truck_type_label'))),
                ]),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(child: _FilterField(controller: _minPriceCtrl, label: strings.t('search_min_price'), numeric: true)),
                  const SizedBox(width: 10),
                  Expanded(child: _FilterField(controller: _maxPriceCtrl, label: strings.t('search_max_price'), numeric: true)),
                ]),
                const SizedBox(height: 10),
                _FilterField(controller: _maxWeightCtrl, label: strings.t('search_max_weight'), numeric: true),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(child: FilledButton(onPressed: _apply, child: Text(strings.t('search_apply')))),
                    const SizedBox(width: 10),
                    OutlinedButton(onPressed: _clear, child: Text(strings.t('search_clear'))),
                  ],
                ),
              ],
            ),
          ),
          const Divider(height: 24),
          Expanded(
            child: resultsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, __) => Center(child: Text(strings.t('home_error_loading'))),
              data: (results) {
                if (results.isEmpty) return Center(child: Text(strings.t('search_no_results')));
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      child: Text(strings.t('search_results_count', {'count': '${results.length}'}), style: Theme.of(context).textTheme.bodySmall),
                    ),
                    Expanded(
                      child: ListView.separated(
                        padding: const EdgeInsets.fromLTRB(14, 8, 14, 20),
                        itemCount: results.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (context, i) => CargoCard(compact: true, 
                          cargo: results[i],
                          strings: strings,
                          onTap: () => context.pushOnce('/cargo/${results[i].id}'),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final bool numeric;
  const _FilterField({required this.controller, required this.label, this.numeric = false});

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: numeric ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.text,
      decoration: InputDecoration(labelText: label, border: const OutlineInputBorder(), isDense: true),
    );
  }
}
