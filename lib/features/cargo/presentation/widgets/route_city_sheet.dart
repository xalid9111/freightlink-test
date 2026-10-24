import 'package:flutter/material.dart';

import '../../../../core/constants/cities.dart';
import '../../../../core/constants/countries.dart';
import '../../../../core/localization/app_strings.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/city_picker.dart';
import '../../../../models/cargo_model.dart';
import '../providers/route_filter.dart';

/// Returned by [RouteCitySheet] for "the whole country".
const kWholeCountry = '';

/// One city / district row of the route search.
class RouteCity {
  /// Value kept in the filter (English catalogue name, or the name as
  /// stored on loads).
  final String value;
  final String label;
  /// Open loads from / to this place (real count of the loaded list).
  final int loads;
  const RouteCity(this.value, this.label, this.loads);
}

/// Cities and districts of [countryCode] for the route search (owner,
/// 24.10.2026): every catalogue place of the country plus any other place
/// a listed load names, A–Z, each with its number of open loads.
List<RouteCity> routeCitiesOf(String countryCode, List<CargoModel> loads, {required bool isFrom, required String lang}) {
  final counts = <String, int>{};
  final names = <String, String>{};
  for (final c in loads) {
    final country = isFrom ? c.pickupCountry : c.destinationCountry;
    if ((Countries.find(country)?.code ?? '') != countryCode) continue;
    final city = (isFrom ? c.pickupCity : c.destinationCity).trim();
    if (city.isEmpty) continue;
    final k = RouteFilter.cityKey(city);
    counts[k] = (counts[k] ?? 0) + 1;
    names.putIfAbsent(k, () => Cities.find(city)?.en ?? city);
  }
  final rows = <String, RouteCity>{};
  for (final c in Cities.all.where((c) => c.country == countryCode)) {
    final k = RouteFilter.cityKey(c.en);
    rows[k] = RouteCity(c.en, c.name(lang), counts[k] ?? 0);
  }
  names.forEach((k, v) => rows.putIfAbsent(k, () => RouteCity(v, Cities.label(v, lang), counts[k] ?? 0)));
  final list = rows.values.toList()..sort((a, b) => alphaKey(a.label, lang).compareTo(alphaKey(b.label, lang)));
  return list;
}

/// Sort key in the reader's alphabet: Azerbaijani a b c ç d e ə f g ğ h x
/// ı i j k q l …, Turkish a b c ç d e f g ğ h ı i j k l … (plain code
/// order put "Ağcabədi" after "Astara").
String alphaKey(String s, String lang) {
  const az = 'abcçdeəfgğhxıijkqlmnoöprsştuüvyz';
  const tr = 'abcçdefgğhıijklmnoöprsştuüvyz';
  final alphabet = lang == 'az' ? az : (lang == 'tr' ? tr : null);
  final lower = s.replaceAll('I', 'ı').replaceAll('İ', 'i').toLowerCase();
  if (alphabet == null) return lower;
  return String.fromCharCodes(lower.runes.map((r) {
    final i = alphabet.indexOf(String.fromCharCode(r));
    return i < 0 ? 0x100 + r : 0x41 + i; // letters first, in alphabet order
  }));
}

/// Second step of "Haradan / Haraya": after the country, "Bütün ölkə" or
/// one of its cities / districts (searchable). Returns [kWholeCountry],
/// a city value, or null when closed (the whole country stays).
class RouteCitySheet extends StatefulWidget {
  final Country country;
  final List<RouteCity> cities;
  final String languageCode;
  final AppStrings strings;
  const RouteCitySheet(
      {super.key, required this.country, required this.cities, required this.languageCode, required this.strings});

  @override
  State<RouteCitySheet> createState() => _RouteCitySheetState();
}

class _RouteCitySheetState extends State<RouteCitySheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final s = widget.strings;
    final q = Countries.normalize(_query);
    final items = widget.cities.where((c) {
      if (q.isEmpty) return true;
      final cat = Cities.find(c.value);
      final names = cat == null ? [c.label, c.value] : [cat.en, cat.az, cat.tr, cat.ru];
      return names.any((n) => Countries.normalize(n).contains(q));
    }).toList();

    Widget count(int n) => n == 0
        ? const SizedBox.shrink()
        : Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(color: AppColors.accent.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(10)),
            child: Text('$n', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: AppColors.accent)),
          );

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.75,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 8, 4),
            child: Row(children: [
              Text(widget.country.flag, style: const TextStyle(fontSize: 22)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(widget.country.name(widget.languageCode),
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.text)),
              ),
              IconButton(onPressed: () => Navigator.of(context).pop(), icon: const Icon(Icons.close)),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              key: const ValueKey('route-city-search'),
              autofocus: false,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: s.t('route_city_search'),
                border: const OutlineInputBorder(),
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: items.length + 1,
              itemBuilder: (context, i) {
                if (i == 0) {
                  return ListTile(
                    key: const ValueKey('route-city-all'),
                    leading: Icon(Icons.public, color: AppColors.accent),
                    title: Text(s.t('route_whole_country'), style: const TextStyle(fontWeight: FontWeight.w700)),
                    onTap: () => Navigator.of(context).pop(kWholeCountry),
                  );
                }
                final c = items[i - 1];
                return ListTile(
                  key: ValueKey('route-city-${c.value}'),
                  leading: Text(flagOf(widget.country.code), style: const TextStyle(fontSize: 20)),
                  title: Text(c.label),
                  trailing: count(c.loads),
                  onTap: () => Navigator.of(context).pop(c.value),
                );
              },
            ),
          ),
        ]),
      ),
    );
  }
}
