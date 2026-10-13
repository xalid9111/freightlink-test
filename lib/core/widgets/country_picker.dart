import 'package:flutter/material.dart';

import '../constants/countries.dart';
import '../localization/app_strings.dart';

/// Sentinel returned by [CountryPickerSheet] for "any country".
const Country anyCountry = Country('**', 'Any', 'Hamısı', 'Tümü', 'Все');

/// Searchable, flagged country list in a bottom sheet (search matches the
/// name in any of the four UI languages). Used by the cargo-create form
/// and the home-screen route filter.
class CountryPickerSheet extends StatefulWidget {
  final String languageCode;
  final AppStrings strings;
  /// When set, a first row lets the user pick "any country" (returns
  /// [anyCountry]); used by the route filter.
  final String? anyLabel;
  const CountryPickerSheet({super.key, required this.languageCode, required this.strings, this.anyLabel});

  @override
  State<CountryPickerSheet> createState() => CountryPickerSheetState();
}

class CountryPickerSheetState extends State<CountryPickerSheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final q = Countries.normalize(_query);
    // Search matches the name in ANY of the four languages.
    final items = Countries.all.where((c) {
      if (q.isEmpty) return true;
      return [c.en, c.az, c.tr, c.ru].any((n) => Countries.normalize(n).contains(q));
    }).toList();

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.75,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: TextField(
                autofocus: false,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search),
                  hintText: widget.strings.t('country_picker_search'),
                  border: const OutlineInputBorder(),
                ),
                onChanged: (v) => setState(() => _query = v),
              ),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: items.length + (widget.anyLabel != null ? 1 : 0),
                itemBuilder: (context, i) {
                  if (widget.anyLabel != null) {
                    if (i == 0) {
                      return ListTile(
                        leading: const Icon(Icons.public, size: 26),
                        title: Text(widget.anyLabel!),
                        onTap: () => Navigator.of(context).pop(anyCountry),
                      );
                    }
                    i -= 1;
                  }
                  final c = items[i];
                  return ListTile(
                    leading: Text(c.flag, style: const TextStyle(fontSize: 26)),
                    title: Text(c.name(widget.languageCode)),
                    onTap: () => Navigator.of(context).pop(c),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

