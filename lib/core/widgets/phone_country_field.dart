import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../constants/countries.dart';
import '../constants/phone_countries.dart';
import '../localization/locale_controller.dart';
import '../theme/app_theme.dart';

/// Phone number with a country picker.
///
/// The country button opens a searchable list (name in any app language,
/// ISO code or calling code). Picking a country puts its international
/// calling code in front of the number automatically. The result is
/// reported as one international number, e.g. "+994501234567".
///
/// This only collects the phone number (a profile field). It does not
/// change how people sign in and adds no phone login / OTP. The country
/// chosen here never limits the app language.
class PhoneCountryField extends ConsumerStatefulWidget {
  final String label;
  final String initialIso;
  /// Called with the full international number ("" while empty).
  final ValueChanged<String> onChanged;
  final bool required;

  const PhoneCountryField({
    super.key,
    required this.label,
    required this.onChanged,
    this.initialIso = PhoneCountries.defaultIso,
    this.required = true,
  });

  @override
  ConsumerState<PhoneCountryField> createState() => _PhoneCountryFieldState();
}

class _PhoneCountryFieldState extends ConsumerState<PhoneCountryField> {
  late PhoneCountry _country = PhoneCountries.byIso(widget.initialIso) ?? PhoneCountries.all.first;
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  /// National digits without the trunk "0" people often type (050 … →
  /// 50 …). Italy keeps its leading 0 — it is part of the number there.
  String _national() {
    var d = _ctrl.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (_country.iso != 'IT') d = d.replaceFirst(RegExp(r'^0+'), '');
    return d;
  }

  String _e164() {
    final n = _national();
    return n.isEmpty ? '' : '+${_country.dial}$n';
  }

  void _emit() => widget.onChanged(_e164());

  Future<void> _pickCountry() async {
    final picked = await showModalBottomSheet<PhoneCountry>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.card,
      builder: (_) => _CountrySheet(selected: _country),
    );
    if (picked != null && mounted) {
      setState(() => _country = picked);
      _emit();
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    final lang = ref.watch(currentLocaleProvider).languageCode;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 56,
          child: OutlinedButton(
            onPressed: _pickCountry,
            style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 10)),
            child: Tooltip(
              message: s.t('phone_country_label'),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_country.flag, style: const TextStyle(fontSize: 20)),
                  const SizedBox(width: 6),
                  Text('+${_country.dial}', style: const TextStyle(fontWeight: FontWeight.w600)),
                  const Icon(Icons.arrow_drop_down, size: 20),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: TextFormField(
            controller: _ctrl,
            keyboardType: TextInputType.phone,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9 ]')),
              LengthLimitingTextInputFormatter(18),
            ],
            decoration: InputDecoration(
              labelText: widget.label,
              border: const OutlineInputBorder(),
              helperText: '${_country.name(lang)} · +${_country.dial}',
            ),
            onChanged: (_) => _emit(),
            validator: (_) {
              final n = _national();
              if (n.isEmpty) return widget.required ? s.t('field_required') : null;
              // E.164: at most 15 digits in total; at least 4 national digits.
              if (n.length < 4 || _country.dial.length + n.length > 15) return s.t('profile_phone_invalid');
              return null;
            },
          ),
        ),
      ],
    );
  }
}

class _CountrySheet extends ConsumerStatefulWidget {
  final PhoneCountry selected;
  const _CountrySheet({required this.selected});

  @override
  ConsumerState<_CountrySheet> createState() => _CountrySheetState();
}

class _CountrySheetState extends ConsumerState<_CountrySheet> {
  final _search = TextEditingController();
  String _q = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  bool _matches(PhoneCountry c) {
    if (_q.isEmpty) return true;
    final q = Countries.normalize(_q).replaceAll('+', '');
    if (q.isEmpty) return true;
    for (final t in c.searchTerms) {
      if (Countries.normalize(t).replaceAll('+', '').contains(q)) return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    final lang = ref.watch(currentLocaleProvider).languageCode;
    final list = PhoneCountries.ordered.where(_matches).toList();
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.75,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Text(s.t('phone_country_title'), style: Theme.of(context).textTheme.titleMedium),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  controller: _search,
                  autofocus: true,
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search),
                    hintText: s.t('phone_country_search'),
                    border: const OutlineInputBorder(),
                  ),
                  onChanged: (v) => setState(() => _q = v.trim()),
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: list.isEmpty
                    ? Center(child: Text(s.t('phone_country_not_found'), style: TextStyle(color: AppColors.textSoft)))
                    : ListView.builder(
                        itemCount: list.length,
                        itemBuilder: (context, i) {
                          final c = list[i];
                          final sel = c.iso == widget.selected.iso;
                          return ListTile(
                            leading: Text(c.flag, style: const TextStyle(fontSize: 22)),
                            title: Text(c.name(lang)),
                            subtitle: c.name(lang) == c.en ? null : Text(c.en, style: const TextStyle(fontSize: 12)),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text('+${c.dial}', style: const TextStyle(fontWeight: FontWeight.w400)),
                                if (sel) ...[
                                  const SizedBox(width: 6),
                                  Icon(Icons.check, color: AppColors.accent, size: 18),
                                ],
                              ],
                            ),
                            onTap: () => Navigator.of(context).pop(c),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
