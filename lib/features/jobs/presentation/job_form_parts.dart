import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/constants/cities.dart';
import '../../../core/constants/countries.dart';
import '../../../core/localization/app_strings.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/city_picker.dart';
import '../../../core/widgets/country_picker.dart';
import '../domain/job_models.dart';

/// Pieces shared by the driver form and the vacancy form.

class JobSection extends StatelessWidget {
  final String title;
  final String? hint;
  final List<Widget> children;
  const JobSection({super.key, required this.title, this.hint, required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
          color: AppColors.card, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.line)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.text)),
        if (hint != null) ...[
          const SizedBox(height: 4),
          Text(hint!, style: TextStyle(fontSize: 12.5, color: AppColors.textSoft)),
        ],
        const SizedBox(height: 10),
        ...children,
      ]),
    );
  }
}

/// Country + city from the existing city picker.
class JobPlaceField extends StatelessWidget {
  final String? country, city;
  final String languageCode;
  final AppStrings s;
  final void Function(String? country, String? city) onChanged;
  const JobPlaceField(
      {super.key, required this.country, required this.city, required this.languageCode, required this.s, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final text = [
      if (city != null) Cities.label(city!, languageCode),
      if (country != null) Countries.label(country!, languageCode),
    ].join(', ');
    return InkWell(
      key: const ValueKey('job-place'),
      borderRadius: BorderRadius.circular(12),
      onTap: () async {
        final p = await showModalBottomSheet<PickedPlace>(
          context: context,
          isScrollControlled: true,
          useSafeArea: true,
          builder: (_) => CityPickerSheet(languageCode: languageCode, strings: s, title: s.t('job_f_place')),
        );
        if (p != null) onChanged(p.country.isEmpty ? null : p.country, p.city.isEmpty ? null : p.city);
      },
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: s.t('job_f_place'),
          prefixIcon: const Icon(Icons.place_outlined),
          suffixIcon: text.isEmpty
              ? null
              : IconButton(icon: const Icon(Icons.close), onPressed: () => onChanged(null, null)),
        ),
        child: Text(text, style: TextStyle(color: AppColors.text)),
      ),
    );
  }
}

/// Several countries (work countries / routes).
class JobCountriesField extends StatelessWidget {
  final List<String> countries;
  final String languageCode;
  final AppStrings s;
  final ValueChanged<List<String>> onChanged;
  const JobCountriesField(
      {super.key, required this.countries, required this.languageCode, required this.s, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Wrap(spacing: 8, runSpacing: 8, children: [
      for (final c in countries)
        InputChip(
          label: Text('${Countries.find(c)?.flag ?? ''} ${Countries.label(c, languageCode)}'.trim()),
          onDeleted: () => onChanged([...countries]..remove(c)),
        ),
      if (countries.length < 30)
        ActionChip(
          key: const ValueKey('job-add-country'),
          avatar: const Icon(Icons.add, size: 18),
          label: Text(s.t('job_f_add_country')),
          onPressed: () async {
            final picked = await showModalBottomSheet<Country>(
              context: context,
              isScrollControlled: true,
              useSafeArea: true,
              builder: (_) => CountryPickerSheet(languageCode: languageCode, strings: s),
            );
            if (picked != null && !countries.contains(picked.en)) onChanged([...countries, picked.en]);
          },
        ),
    ]);
  }
}

final _digits = [FilteringTextInputFormatter.allow(RegExp(r'[0-9]'))];

/// Whole numbers (years, salary).
class JobNumberField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String fieldKey;
  final int maxLength;
  const JobNumberField({super.key, required this.controller, required this.label, required this.fieldKey, this.maxLength = 3});

  @override
  Widget build(BuildContext context) => TextField(
        key: ValueKey(fieldKey),
        controller: controller,
        keyboardType: TextInputType.number,
        inputFormatters: [..._digits, LengthLimitingTextInputFormatter(maxLength)],
        decoration: InputDecoration(labelText: label),
      );
}

int? jobInt(TextEditingController c) => int.tryParse(c.text.trim());
double? jobMoney(TextEditingController c) => double.tryParse(c.text.trim());
String? jobText(TextEditingController c) {
  final t = c.text.trim();
  return t.isEmpty ? null : t;
}

/// Currency picker.
class JobCurrencyField extends StatelessWidget {
  final String? value;
  final AppStrings s;
  final ValueChanged<String?> onChanged;
  const JobCurrencyField({super.key, required this.value, required this.s, required this.onChanged});

  @override
  Widget build(BuildContext context) => DropdownButtonFormField<String>(
        key: const ValueKey('job-currency'),
        initialValue: value ?? 'AZN',
        decoration: InputDecoration(labelText: s.t('job_f_currency')),
        items: [for (final c in kJobCurrencies) DropdownMenuItem(value: c, child: Text(c))],
        onChanged: onChanged,
      );
}

/// Work schedule ("—" = not given).
class JobScheduleField extends StatelessWidget {
  final String? value;
  final AppStrings s;
  final ValueChanged<String?> onChanged;
  const JobScheduleField({super.key, required this.value, required this.s, required this.onChanged});

  @override
  Widget build(BuildContext context) => DropdownButtonFormField<String?>(
        key: const ValueKey('job-schedule'),
        initialValue: value,
        decoration: InputDecoration(labelText: s.t('job_f_schedule')),
        items: [
          const DropdownMenuItem<String?>(value: null, child: Text('—')),
          for (final k in kJobSchedules) DropdownMenuItem<String?>(value: k, child: Text(s.t('job_sch_$k'))),
        ],
        onChanged: onChanged,
      );
}

/// Phone: hidden by default; shown only when its owner turns it on (the
/// server enforces it).
class JobPhoneBlock extends StatelessWidget {
  final TextEditingController phone;
  final bool showPhone, whatsapp;
  final ValueChanged<bool> onShow, onWhatsapp;
  final AppStrings s;
  const JobPhoneBlock(
      {super.key,
      required this.phone,
      required this.showPhone,
      required this.whatsapp,
      required this.onShow,
      required this.onWhatsapp,
      required this.s});

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        TextField(
          key: const ValueKey('job-phone'),
          controller: phone,
          keyboardType: TextInputType.phone,
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9+ ()-]')), LengthLimitingTextInputFormatter(30)],
          decoration: InputDecoration(labelText: s.t('job_f_phone'), prefixIcon: const Icon(Icons.phone_outlined)),
        ),
        SwitchListTile(
          key: const ValueKey('job-show-phone'),
          contentPadding: EdgeInsets.zero,
          title: Text(s.t('job_f_show_phone')),
          subtitle: Text(s.t('job_f_show_phone_hint'), style: TextStyle(fontSize: 12.5, color: AppColors.textSoft)),
          value: showPhone,
          onChanged: onShow,
        ),
        if (showPhone)
          SwitchListTile(
            key: const ValueKey('job-whatsapp'),
            contentPadding: EdgeInsets.zero,
            title: Text(s.t('job_f_whatsapp')),
            value: whatsapp,
            onChanged: onWhatsapp,
          ),
      ]);
}
