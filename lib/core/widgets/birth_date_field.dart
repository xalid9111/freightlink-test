import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../localization/app_strings.dart';
import '../theme/app_theme.dart';
import '../utils/age.dart';

/// Birth date as Gün · Ay · İl (owner, 28.10.2026: "23 yanvar 1978").
/// Reports a full date only when all three are chosen (null otherwise);
/// the years offered keep the user 16–100 years old (the server checks
/// the same, migration 0074).
class BirthDateField extends StatefulWidget {
  final DateTime? initial;
  final ValueChanged<DateTime?> onChanged;
  final AppStrings strings;
  final String languageCode;
  final String? errorText;
  const BirthDateField(
      {super.key, required this.initial, required this.onChanged, required this.strings, required this.languageCode, this.errorText});

  @override
  State<BirthDateField> createState() => _BirthDateFieldState();
}

/// "23 yanvar 1978" in the user's language (numbers if the month names
/// are not available).
String birthDateLabel(DateTime d, String languageCode) => '${d.day} ${monthName(d.month, languageCode)} ${d.year}';

String monthName(int month, String languageCode) {
  try {
    return DateFormat.MMMM(languageCode).format(DateTime(2000, month));
  } catch (_) {
    return month.toString().padLeft(2, '0');
  }
}

int daysIn(int year, int month) => DateTime(year, month + 1, 0).day;

/// The date once Gün, Ay and İl are all chosen (null before); a day past
/// the month's end (31 → February) becomes its last day.
DateTime? composeBirthDate(int? day, int? month, int? year) {
  if (day == null || month == null || year == null) return null;
  final max = daysIn(year, month);
  return DateTime(year, month, day > max ? max : day);
}

class _BirthDateFieldState extends State<BirthDateField> {
  int? _day, _month, _year;

  @override
  void initState() {
    super.initState();
    _day = widget.initial?.day;
    _month = widget.initial?.month;
    _year = widget.initial?.year;
  }

  void _emit() {
    final d = composeBirthDate(_day, _month, _year);
    if (d != null) _day = d.day;
    widget.onChanged(d);
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.strings;
    final now = DateTime.now();
    final years = [for (var y = now.year - kAgeMin; y >= now.year - 100; y--) y];
    final maxDay = (_year != null && _month != null) ? daysIn(_year!, _month!) : 31;
    InputDecoration deco(String label) => InputDecoration(
        hintText: label,
        isDense: true,
        border: const OutlineInputBorder(),
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12));
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      Row(children: [
        Expanded(
          flex: 4,
          child: DropdownButtonFormField<int>(
            key: const ValueKey('birth-day'),
            initialValue: _day == null ? null : (_day! > maxDay ? maxDay : _day),
            isExpanded: true,
            menuMaxHeight: 360,
            decoration: deco(s.t('birth_day')),
            items: [for (var d = 1; d <= maxDay; d++) DropdownMenuItem(value: d, child: Text('$d'))],
            onChanged: (v) {
              setState(() => _day = v);
              _emit();
            },
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 6,
          child: DropdownButtonFormField<int>(
            key: const ValueKey('birth-month'),
            initialValue: _month,
            isExpanded: true,
            menuMaxHeight: 360,
            decoration: deco(s.t('birth_month')),
            items: [
              for (var m = 1; m <= 12; m++)
                DropdownMenuItem(value: m, child: Text(monthName(m, widget.languageCode), overflow: TextOverflow.ellipsis)),
            ],
            onChanged: (v) {
              setState(() => _month = v);
              _emit();
            },
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 5,
          child: DropdownButtonFormField<int>(
            key: const ValueKey('birth-year'),
            initialValue: _year,
            isExpanded: true,
            menuMaxHeight: 360,
            decoration: deco(s.t('birth_year')),
            items: [for (final y in years) DropdownMenuItem(value: y, child: Text('$y'))],
            onChanged: (v) {
              setState(() => _year = v);
              _emit();
            },
          ),
        ),
      ]),
      if (widget.errorText != null)
        Padding(
          padding: const EdgeInsets.only(top: 6, left: 4),
          child: Text(widget.errorText!, style: TextStyle(fontSize: 12.5, color: AppColors.danger)),
        ),
    ]);
  }
}

/// True when [birth] makes the user at least 16 (and at most 100).
bool birthDateAllowed(DateTime birth, DateTime now) {
  final age = ageFromBirthDate(birth, now);
  return age >= kAgeMin && age <= 100;
}
