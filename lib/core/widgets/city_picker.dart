import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/geo_service.dart';
import '../constants/cities.dart';
import '../constants/countries.dart';
import '../localization/app_strings.dart';
import '../theme/app_theme.dart';

/// A route end chosen in [CityPickerSheet]: the city plus the country it
/// belongs to (filled in automatically — no separate country step).
class PickedPlace {
  /// Stored in cargo.*_city (English name for catalogue cities).
  final String city;
  /// Stored in cargo.*_country (English country name).
  final String country;
  /// ISO code when known ('' otherwise) — for the flag.
  final String countryCode;
  const PickedPlace({required this.city, required this.country, required this.countryCode});

  factory PickedPlace.fromCity(City c) =>
      PickedPlace(city: c.en, country: Countries.find(c.country)?.en ?? c.country, countryCode: c.country);

  /// Rebuilds the pick from what a saved load contains (edit mode).
  factory PickedPlace.fromStored(String city, String country) {
    final known = Countries.find(country);
    final cat = Cities.find(city);
    return PickedPlace(
      city: cat?.en ?? city,
      country: known?.en ?? country,
      countryCode: known?.code ?? cat?.country ?? '',
    );
  }

  String get flag => flagOf(countryCode);

  String cityLabel(String lang) => Cities.label(city, lang);

  String countryLabel(String lang) => Countries.find(country)?.name(lang) ?? country;
}

/// Emoji flag from an ISO-3166 alpha-2 code ('' for anything else).
String flagOf(String code) {
  final c = code.toUpperCase();
  if (c.length != 2 || !RegExp(r'^[A-Z]{2}$').hasMatch(c)) return '';
  return String.fromCharCodes(c.codeUnits.map((u) => 0x1F1E6 + u - 0x41));
}

/// Bottom sheet: 🔍 search on top, popular cities as quick picks, and
/// — while typing — matching catalogue cities plus worldwide results
/// from OpenStreetMap. Returns a [PickedPlace] or null.
class CityPickerSheet extends ConsumerStatefulWidget {
  final String languageCode;
  final AppStrings strings;
  final String title;
  const CityPickerSheet({super.key, required this.languageCode, required this.strings, required this.title});

  @override
  ConsumerState<CityPickerSheet> createState() => _CityPickerSheetState();
}

class _CityPickerSheetState extends ConsumerState<CityPickerSheet> {
  final _ctrl = TextEditingController();
  String _query = '';
  Timer? _debounce;
  List<PlaceHit> _online = const [];
  bool _searching = false;
  int _seq = 0;

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  void _onChanged(String v) {
    setState(() => _query = v.trim());
    _debounce?.cancel();
    if (_query.length < 3) {
      setState(() {
        _online = const [];
        _searching = false;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 450), () async {
      final mySeq = ++_seq;
      setState(() => _searching = true);
      final hits = await ref.read(geoServiceProvider).searchCities(_query);
      if (!mounted || mySeq != _seq) return;
      setState(() {
        _online = hits;
        _searching = false;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.strings;
    final lang = widget.languageCode;
    final local = Cities.search(_query);
    final localKeys = {for (final c in local) '${Countries.normalize(c.en)}|${c.country}'};
    final online = _online
        .where((h) => !localKeys.contains('${Countries.normalize(h.city)}|${h.countryCode}'))
        .where((h) => Cities.find(h.city) == null || Cities.find(h.city)!.country != h.countryCode)
        .toList();

    Widget cityTile(PickedPlace p, {String? subtitle}) => ListTile(
          leading: Text(p.flag.isEmpty ? '📍' : p.flag, style: const TextStyle(fontSize: 24)),
          title: Text(p.cityLabel(lang), style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text(subtitle ?? p.countryLabel(lang)),
          onTap: () => Navigator.of(context).pop(p),
        );

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.85,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 8, 4),
              child: Row(
                children: [
                  Expanded(child: Text(widget.title, style: AppFonts.display(size: 22, color: AppColors.text))),
                  IconButton(onPressed: () => Navigator.of(context).pop(), icon: const Icon(Icons.close)),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: TextField(
                controller: _ctrl,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                onChanged: _onChanged,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search),
                  hintText: s.t('city_search_hint'),
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () {
                            _ctrl.clear();
                            _onChanged('');
                          },
                        ),
                ),
              ),
            ),
            Expanded(
              child: ListView(
                children: [
                  if (_query.isEmpty) ...[
                    _Header(s.t('city_popular')),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final c in Cities.popularCities)
                            ActionChip(
                              avatar: Text(flagOf(c.country)),
                              label: Text(c.name(lang)),
                              onPressed: () => Navigator.of(context).pop(PickedPlace.fromCity(c)),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    _Header(s.t('city_all')),
                    for (final c in Cities.all) cityTile(PickedPlace.fromCity(c)),
                  ] else ...[
                    for (final c in local) cityTile(PickedPlace.fromCity(c)),
                    if (_searching)
                      const Padding(
                        padding: EdgeInsets.all(16),
                        child: Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))),
                      ),
                    if (online.isNotEmpty) ...[
                      _Header(s.t('city_more_results')),
                      for (final h in online)
                        cityTile(
                          PickedPlace(city: h.city, country: Countries.find(h.countryName)?.en ?? h.countryName, countryCode: h.countryCode),
                          subtitle: Countries.find(h.countryName)?.name(lang) ?? h.countryName,
                        ),
                    ],
                    if (local.isEmpty && online.isEmpty && !_searching)
                      Padding(
                        padding: const EdgeInsets.all(20),
                        child: Text(
                          _query.length < 3 ? s.t('city_type_more') : s.t('city_not_found'),
                          style: TextStyle(color: AppColors.textSoft),
                        ),
                      ),
                  ],
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final String text;
  const _Header(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Text(text.toUpperCase(),
            style: TextStyle(color: AppColors.textSoft, fontSize: 12, letterSpacing: 1.1, fontWeight: FontWeight.w700)),
      );
}
