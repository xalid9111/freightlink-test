import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/constants/countries.dart';
import '../../../core/localization/app_strings.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/country_picker.dart';
import '../../../core/widgets/mouse_drag_scroll.dart';
import '../domain/job_models.dart';
import 'job_widgets.dart';

// Pieces of the two one-page forms (owner, 28.10.2026, pictures 2 and 3):
// the banner, "icon + label" rows, country tiles with flags, transport
// tiles with FreightLink's own truck pictures, licence boxes, tick boxes,
// pills, the contact choice. Selection colour: blue, as in the pictures.

Color get _sel => AppColors.blue;

/// The picture banner: the owner's photo on the right, our text on the
/// left (so it is in every language).
class JobFormBanner extends StatelessWidget {
  final String asset, line1, line2, subtitle;
  const JobFormBanner({super.key, required this.asset, required this.line1, required this.line2, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    const bg = AppColors.jobBannerBg;
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: SizedBox(
        height: 150,
        child: Stack(fit: StackFit.expand, children: [
          const ColoredBox(color: bg),
          Align(
            alignment: Alignment.centerRight,
            child: FractionallySizedBox(
              widthFactor: 0.66,
              heightFactor: 1,
              child: ShaderMask(
                shaderCallback: (r) => const LinearGradient(
                  colors: [Colors.transparent, Colors.black, Colors.black],
                  stops: [0, 0.35, 1],
                ).createShader(r),
                blendMode: BlendMode.dstIn,
                child: Image.asset(asset, fit: BoxFit.cover, alignment: Alignment.centerRight),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
              Text(line1, maxLines: 1, style: const TextStyle(fontSize: 26, height: 1.05, fontWeight: FontWeight.w600, color: Colors.white)),
              Text(line2,
                  maxLines: 1, style: const TextStyle(fontSize: 26, height: 1.1, fontWeight: FontWeight.w600, color: AppColors.jobBannerAccent)),
              const SizedBox(height: 8),
              SizedBox(
                width: 210,
                child: Text(subtitle, maxLines: 2, style: const TextStyle(fontSize: 14.5, color: Colors.white)),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}

/// A label with its icon (picture: "🏢 Şirkət adı").
class JobLabel extends StatelessWidget {
  final IconData icon;
  final String text;
  final String? hint;
  const JobLabel({super.key, required this.icon, required this.text, this.hint});

  @override
  Widget build(BuildContext context) => Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 24, color: AppColors.text),
        const SizedBox(width: 10),
        Flexible(
          child: Text.rich(TextSpan(children: [
            TextSpan(text: text, style: TextStyle(fontSize: 15.5, color: AppColors.text)),
            if (hint != null) TextSpan(text: '\n$hint', style: TextStyle(fontSize: 13, color: AppColors.textSoft)),
          ])),
        ),
      ]);
}

/// "icon + label" on the left, the control on the right; stacked on a
/// narrow phone so nothing is squeezed.
class JobFieldRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final Widget child;
  const JobFieldRow({super.key, required this.icon, required this.label, required this.child});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 14),
        child: LayoutBuilder(builder: (context, c) {
          if (c.maxWidth < 330) {
            return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              JobLabel(icon: icon, text: label),
              const SizedBox(height: 8),
              child,
            ]);
          }
          return Row(children: [
            SizedBox(width: c.maxWidth * 0.36, child: JobLabel(icon: icon, text: label)),
            const SizedBox(width: 8),
            Expanded(child: child),
          ]);
        }),
      );
}

/// A label on its own line with the choices under it.
class JobBlock extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? hint;
  final Widget child;
  const JobBlock({super.key, required this.icon, required this.label, this.hint, required this.child});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          JobLabel(icon: icon, text: label, hint: hint),
          const SizedBox(height: 10),
          child,
        ]),
      );
}

BoxDecoration _box(bool on) => BoxDecoration(
      color: on ? _sel.withValues(alpha: 0.14) : AppColors.card,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: on ? _sel : AppColors.line, width: on ? 1.6 : 1),
    );

/// Work countries: AZ · TR · GE · RU · Avropa İttifaqı · Başqa (picker);
/// several can be chosen.
class JobCountryTiles extends StatelessWidget {
  final List<String> selected;
  final ValueChanged<List<String>> onChanged;
  final String lang;
  final AppStrings s;
  const JobCountryTiles({super.key, required this.selected, required this.onChanged, required this.lang, required this.s});

  static const quick = ['AZ', 'TR', 'GE', 'RU'];

  bool _has(String value) => selected.any((x) => x == value || (Countries.find(x) != null && Countries.find(x)?.en == value));

  @override
  Widget build(BuildContext context) {
    final quickEn = [for (final c in quick) Countries.all.firstWhere((x) => x.code == c).en];
    final extra = [for (final c in selected) if (!quickEn.contains(Countries.find(c)?.en) && c != kJobEu) c];
    return LayoutBuilder(builder: (context, box) {
    // Four in a row on a phone, six on a wide screen (picture: one row).
    final n = box.maxWidth >= 560 ? 6 : 4;
    final w = (box.maxWidth - 8 * (n - 1)) / n;
    Widget tile(String key, String flag, String label, bool on, VoidCallback tap) => SizedBox(
          width: w,
          height: 76,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              key: ValueKey(key),
              borderRadius: BorderRadius.circular(12),
              onTap: tap,
              child: Ink(
                decoration: _box(on),
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Text(flag, style: const TextStyle(fontSize: 26)),
                  const SizedBox(height: 4),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Text(label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11.5, color: on ? _sel : AppColors.text)),
                  ),
                ]),
              ),
            ),
          ),
        );
    void toggle(String value) => onChanged(_has(value)
        ? [for (final x in selected) if (x != value && Countries.find(x)?.en != value) x]
        : [...selected, value]);
    return Wrap(spacing: 8, runSpacing: 8, children: [
      for (final c in quick)
        () {
          final country = Countries.all.firstWhere((x) => x.code == c);
          return tile('job-country-$c', country.flag, country.name(lang), _has(country.en), () => toggle(country.en));
        }(),
      tile('job-country-EU', '🇪🇺', s.t('job_eu'), selected.contains(kJobEu), () => toggle(kJobEu)),
      for (final c in extra)
        tile('job-country-x-$c', Countries.find(c)?.flag ?? '🌍', Countries.find(c)?.name(lang) ?? c, true, () => toggle(c)),
      if (selected.length < 30)
        tile('job-country-other', '＋', s.t('job_other_country'), false, () async {
          final picked = await showModalBottomSheet<Country>(
            context: context,
            isScrollControlled: true,
            useSafeArea: true,
            builder: (_) => CountryPickerSheet(languageCode: lang, strings: s),
          );
          if (picked != null && !_has(picked.en)) onChanged([...selected, picked.en]);
        }),
    ]);
    });
  }
}

/// FreightLink's own truck pictures (the Loads page) for job transport codes.
String? jobTransportAsset(String code) {
  final name = switch (code) {
    'tent' => 'type_tent',
    'ref' => 'type_ref',
    'container' => 'type_container',
    'dump' => 'type_dump',
    'open' => 'type_open',
    'tanker' => 'type_tanker',
    'tow' => 'type_tow_truck',
    'car_carrier' => 'type_car_carrier',
    _ => null,
  };
  if (name == null) return null;
  return AppColors.isDay ? 'assets/images/cargo/$name.png' : 'assets/images/cargo/${name}_night.png';
}

IconData _transportIcon(String code) => switch (code) {
      'bus' => Icons.directions_bus_outlined,
      'excavator' => Icons.construction_outlined,
      _ => Icons.more_horiz,
    };

/// Transport: one row of truck pictures that scrolls sideways; several
/// can be chosen (blue line under the chosen ones).
class JobTransportRow extends StatelessWidget {
  final List<JobCatalogItem> items;
  final Set<String> selected;
  final ValueChanged<Set<String>> onChanged;
  final AppStrings s;
  final String lang;
  const JobTransportRow(
      {super.key, required this.items, required this.selected, required this.onChanged, required this.s, required this.lang});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 96,
      child: MouseDragScroll(child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (context, i) {
          final it = items[i];
          final on = selected.contains(it.code);
          final asset = jobTransportAsset(it.code);
          return InkWell(
            key: ValueKey('job-transport-${it.code}'),
            borderRadius: BorderRadius.circular(10),
            onTap: () => onChanged(on ? ({...selected}..remove(it.code)) : {...selected, it.code}),
            child: SizedBox(
              width: 96,
              child: Column(children: [
                SizedBox(
                  height: 50,
                  child: asset != null
                      ? Image.asset(asset, fit: BoxFit.contain)
                      : Icon(_transportIcon(it.code), size: 36, color: AppColors.text),
                ),
                const SizedBox(height: 6),
                Text(jobUpper(jobLabel(s, 'job_spec_', it), lang),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12.5, color: on ? _sel : AppColors.text, fontWeight: on ? FontWeight.w500 : FontWeight.w400)),
                const SizedBox(height: 6),
                Container(height: 3, width: 70, color: on ? _sel : Colors.transparent),
              ]),
            ),
          );
        },
      )),
    );
  }
}

/// Licence categories as equal boxes (B · C1 · C · CE · D1 · D · C1E ·
/// D1E · DE); several can be chosen.
class JobLicenceBoxes extends StatelessWidget {
  final List<JobCatalogItem> items;
  final Set<String> selected;
  final ValueChanged<String> onTap;
  const JobLicenceBoxes({super.key, required this.items, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, c) {
        final perRow = c.maxWidth < 330 ? 4 : 5;
        final w = (c.maxWidth - 8 * (perRow - 1)) / perRow;
        return Wrap(spacing: 8, runSpacing: 8, children: [
          for (final it in items)
            SizedBox(
              width: w,
              height: 46,
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  key: ValueKey('job-lic-${it.code}'),
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => onTap(it.code),
                  child: Ink(
                    decoration: selected.contains(it.code)
                        ? BoxDecoration(color: _sel, borderRadius: BorderRadius.circular(12))
                        : _box(false),
                    child: Center(
                      child: Text(it.name,
                          style: TextStyle(
                              fontSize: 16,
                              color: selected.contains(it.code) ? Colors.white : AppColors.text,
                              fontWeight: selected.contains(it.code) ? FontWeight.w500 : FontWeight.w400)),
                    ),
                  ),
                ),
              ),
            ),
        ]);
      });
}

/// Tick boxes (documents, skills) in two columns.
class JobTickGrid extends StatelessWidget {
  final List<(String code, String label)> items;
  final bool Function(String code) checked;
  final ValueChanged<String> onTap;
  final String keyPrefix;
  const JobTickGrid({super.key, required this.items, required this.checked, required this.onTap, this.keyPrefix = 'job-doc'});

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, c) {
        final w = c.maxWidth < 330 ? c.maxWidth : (c.maxWidth - 8) / 2;
        return Wrap(spacing: 8, runSpacing: 4, children: [
          for (final (code, label) in items)
            SizedBox(
              width: w,
              child: InkWell(
                key: ValueKey('$keyPrefix-$code'),
                borderRadius: BorderRadius.circular(8),
                onTap: () => onTap(code),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: checked(code) ? _sel : Colors.transparent,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: checked(code) ? _sel : AppColors.textSoft, width: 1.6),
                      ),
                      child: checked(code) ? const Icon(Icons.check, size: 18, color: Colors.white) : null,
                    ),
                    const SizedBox(width: 8),
                    Expanded(child: Text(label, style: TextStyle(fontSize: 14.5, color: AppColors.text))),
                  ]),
                ),
              ),
            ),
        ]);
      });
}

/// One choice out of a few (İş rejimi); a second tap clears it.
class JobPills extends StatelessWidget {
  final List<(String value, String label)> items;
  final String? value;
  final ValueChanged<String?> onChanged;
  final String keyPrefix;
  const JobPills({super.key, required this.items, required this.value, required this.onChanged, this.keyPrefix = 'job-sch'});

  @override
  Widget build(BuildContext context) => Wrap(spacing: 8, runSpacing: 8, children: [
        for (final (v, label) in items)
          Material(
            color: Colors.transparent,
            child: InkWell(
              key: ValueKey('$keyPrefix-$v'),
              borderRadius: BorderRadius.circular(12),
              onTap: () => onChanged(value == v ? null : v),
              child: Ink(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                decoration: value == v ? BoxDecoration(color: _sel, borderRadius: BorderRadius.circular(12)) : _box(false),
                child: Text(label,
                    style: TextStyle(
                        fontSize: 14.5,
                        color: value == v ? Colors.white : AppColors.text,
                        fontWeight: value == v ? FontWeight.w500 : FontWeight.w400)),
              ),
            ),
          ),
      ]);
}

/// A compact drop-down box.
class JobDropdown<T> extends StatelessWidget {
  final String fieldKey;
  final T? value;
  final List<(T? value, String label)> items;
  final ValueChanged<T?> onChanged;
  const JobDropdown({super.key, required this.fieldKey, required this.value, required this.items, required this.onChanged});

  @override
  Widget build(BuildContext context) => DropdownButtonFormField<T?>(
        key: ValueKey(fieldKey),
        initialValue: value,
        isExpanded: true,
        decoration: const InputDecoration(isDense: true),
        dropdownColor: AppColors.card,
        items: [for (final (v, label) in items) DropdownMenuItem<T?>(value: v, child: Text(label, overflow: TextOverflow.ellipsis))],
        onChanged: onChanged,
      );
}

/// Salary: Min (· Maks) · currency · "Danışılacaq".
class JobSalaryRow extends StatelessWidget {
  final TextEditingController min;
  final TextEditingController? max;
  final String? currency;
  final bool negotiable;
  final ValueChanged<String?> onCurrency;
  final ValueChanged<bool> onNegotiable;
  final AppStrings s;
  const JobSalaryRow(
      {super.key,
      required this.min,
      this.max,
      required this.currency,
      required this.negotiable,
      required this.onCurrency,
      required this.onNegotiable,
      required this.s});

  @override
  Widget build(BuildContext context) {
    final digits = [FilteringTextInputFormatter.allow(RegExp(r'[0-9]')), LengthLimitingTextInputFormatter(7)];
    Widget field(String key, TextEditingController c, String hint) => TextField(
          key: ValueKey(key),
          controller: c,
          keyboardType: TextInputType.number,
          inputFormatters: digits,
          decoration: InputDecoration(hintText: hint, isDense: true),
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Expanded(child: field('job-salary-min', min, max == null ? s.t('job_salary_hint') : s.t('job_salary_min_hint'))),
        if (max != null) ...[const SizedBox(width: 8), Expanded(child: field('job-salary-max', max!, s.t('job_salary_max_hint')))],
        const SizedBox(width: 8),
        SizedBox(
          width: 96,
          child: JobDropdown<String>(
            fieldKey: 'job-currency',
            value: currency ?? 'AZN',
            items: [for (final c in kJobCurrencies) (c, c)],
            onChanged: onCurrency,
          ),
        ),
      ]),
      InkWell(
        key: const ValueKey('job-negotiable'),
        onTap: () => onNegotiable(!negotiable),
        child: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Row(children: [
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: negotiable ? _sel : Colors.transparent,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: negotiable ? _sel : AppColors.textSoft, width: 1.6),
              ),
              child: negotiable ? const Icon(Icons.check, size: 18, color: Colors.white) : null,
            ),
            const SizedBox(width: 8),
            Text(s.t('job_negotiable'), style: TextStyle(fontSize: 14.5, color: AppColors.text)),
          ]),
        ),
      ),
    ]);
  }
}

/// How to be contacted (phone hidden by default — the server decides):
/// only by message · my profile number and message · another number.
enum JobContactWay { message, profile, other }

class JobContactField extends StatelessWidget {
  final JobContactWay way;
  final TextEditingController phone;
  final bool whatsapp;
  final String? profilePhone;
  final ValueChanged<JobContactWay> onWay;
  final ValueChanged<bool> onWhatsapp;
  final AppStrings s;
  const JobContactField(
      {super.key,
      required this.way,
      required this.phone,
      required this.whatsapp,
      required this.profilePhone,
      required this.onWay,
      required this.onWhatsapp,
      required this.s});

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        JobDropdown<JobContactWay>(
          fieldKey: 'job-contact',
          value: way,
          items: [
            (JobContactWay.message, s.t('job_contact_message')),
            if ((profilePhone ?? '').isNotEmpty) (JobContactWay.profile, s.t('job_contact_profile')),
            (JobContactWay.other, s.t('job_contact_other')),
          ],
          onChanged: (v) => onWay(v ?? JobContactWay.message),
        ),
        if (way == JobContactWay.other) ...[
          const SizedBox(height: 8),
          TextField(
            key: const ValueKey('job-phone'),
            controller: phone,
            keyboardType: TextInputType.phone,
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9+ ()-]')), LengthLimitingTextInputFormatter(30)],
            decoration: InputDecoration(hintText: s.t('job_f_phone'), isDense: true, prefixIcon: const Icon(Icons.phone_outlined)),
          ),
        ],
        if (way != JobContactWay.message)
          SwitchListTile(
            key: const ValueKey('job-whatsapp'),
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: Text(s.t('job_f_whatsapp')),
            value: whatsapp,
            onChanged: onWhatsapp,
          ),
      ]);
}

/// The big blue button at the end ("Tələblərimi yerləşdir" / "Profilimi
/// dərc et").
class JobSubmitButton extends StatelessWidget {
  final String buttonKey, label;
  final bool busy;
  final VoidCallback? onPressed;
  const JobSubmitButton({super.key, required this.buttonKey, required this.label, required this.busy, required this.onPressed});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 24),
        child: FilledButton.icon(
          key: ValueKey(buttonKey),
          style: FilledButton.styleFrom(
            backgroundColor: _sel,
            foregroundColor: Colors.white,
            minimumSize: const Size.fromHeight(56),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
          onPressed: busy ? null : onPressed,
          icon: busy
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.send_rounded),
          label: Text(label, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w500)),
        ),
      );
}

/// Contact choice from what is stored.
JobContactWay jobContactWayOf({required bool showPhone, required String? phone, required String? profilePhone}) {
  if (!showPhone) return JobContactWay.message;
  if (phone != null && profilePhone != null && phone == profilePhone) return JobContactWay.profile;
  return JobContactWay.other;
}

/// The short label of a document / skill in the forms ("Taxo kart",
/// "Beynəlxalq daşıma" …); the catalogue label otherwise.
String jobShortLabel(AppStrings s, JobCatalogItem it) {
  for (final key in ['job_short_${it.code}', 'job_chip_${it.code}']) {
    final t = s.t(key);
    if (t != key) return t;
  }
  return jobLabel(s, 'job_skill_', it);
}

/// Capitals that keep the dotted İ in Azerbaijani / Turkish ("SİSTERN").
String jobUpper(String text, String lang) =>
    (lang == 'az' || lang == 'tr' ? text.replaceAll('i', 'İ') : text).toUpperCase();
