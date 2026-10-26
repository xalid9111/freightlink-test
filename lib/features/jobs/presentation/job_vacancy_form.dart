import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/countries.dart';
import '../../../core/localization/app_strings.dart';
import '../../../core/localization/locale_controller.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/country_picker.dart';
import '../../auth/presentation/providers/auth_providers.dart';
import '../data/jobs_repository.dart';
import '../domain/job_models.dart';
import 'job_form_parts.dart';
import 'job_widgets.dart';
import 'jobs_providers.dart';

/// "Vakansiya yerləşdir" — 4 steps as in the owner's picture (26.10.2026):
/// 1 Əsas məlumat · 2 Tələblər · 3 Marşrut · 4 Dərc et. A new vacancy
/// ([id] null) or one of mine. A ticked document / licence category is
/// "Mütləq", a ticked skill "Arzuolunan" (an existing level is kept).
class JobVacancyFormScreen extends ConsumerWidget {
  final String? id;
  const JobVacancyFormScreen({super.key, this.id});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final mine = ref.watch(myVacanciesProvider);
    return Scaffold(
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text(id == null ? s.t('job_vacancy_new') : s.t('job_vacancy_edit'),
              maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
          Text(s.t('job_wz_sub'),
              maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, color: AppColors.textSoft)),
        ]),
      ),
      body: mine.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(e is JobsNotReady ? s.t('job_not_ready') : s.t('home_error_loading'), textAlign: TextAlign.center),
          ),
        ),
        data: (list) {
          final v = id == null ? null : list.where((x) => x.id == id).firstOrNull;
          if (id != null && v == null) return Center(child: Text(s.t('job_empty')));
          return _VacancyForm(initial: v);
        },
      ),
    );
  }
}

/// Picture order (owner's design).
const _licenceOrder = ['lic_b', 'lic_c', 'lic_c1', 'lic_d', 'lic_ce'];
const _documentOrder = ['cpc', 'tachograph', 'adr'];
const _skillOrder = ['intl_exp', 'responsibility', 'discipline', 'tech', 'route_mix', 'night'];
const _quickCountries = ['AZ', 'TR', 'GE', 'RU'];
const _wizardSchedules = ['full_time', 'rotation', 'project'];
const _experienceYears = [1, 2, 3, 5, 10];

class _VacancyForm extends ConsumerStatefulWidget {
  final JobVacancy? initial;
  const _VacancyForm({required this.initial});

  @override
  ConsumerState<_VacancyForm> createState() => _VacancyFormState();
}

class _VacancyFormState extends ConsumerState<_VacancyForm> {
  late final TextEditingController _company, _routes, _salaryMin, _salaryMax, _conditions, _phone;
  String? _country, _city, _currency, _schedule, _jobType;
  int? _minExp;
  late Set<String> _specialties;
  late Map<String, ReqLevel> _req;
  late Set<String> _help;
  late List<String> _countries;
  late bool _showPhone, _whatsapp, _active;
  int _step = 0;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final v = widget.initial;
    final user = ref.read(currentUserProvider);
    _company = TextEditingController(text: v?.companyName ?? user?.fullName ?? '');
    _routes = TextEditingController(text: v?.routes ?? '');
    _salaryMin = TextEditingController(text: v?.salaryMin == null ? '' : v!.salaryMin!.round().toString());
    _salaryMax = TextEditingController(text: v?.salaryMax == null ? '' : v!.salaryMax!.round().toString());
    _conditions = TextEditingController(text: v?.conditions ?? '');
    _phone = TextEditingController(text: v?.phone ?? user?.phone ?? '');
    _jobType = v == null ? 'tir' : v.jobType;
    _minExp = v?.minExperience;
    _country = v?.country;
    _city = v?.city;
    _currency = v?.currency;
    _schedule = v?.schedule;
    _specialties = {...?v?.specialties};
    _req = {...?v?.requirements};
    _help = {...?v?.canHelp};
    _countries = [...?v?.countries];
    _showPhone = v?.showPhone ?? false;
    _whatsapp = v?.whatsapp ?? false;
    _active = v?.isActive ?? true;
  }

  @override
  void dispose() {
    for (final c in [_company, _routes, _salaryMin, _salaryMax, _conditions, _phone]) {
      c.dispose();
    }
    super.dispose();
  }

  void _snack(String text) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  void _toggle(String code, bool on, ReqLevel level) {
    final r = toggleRequirement(_req, _help, code, on, level);
    setState(() {
      _req = r.req;
      _help = r.help;
    });
  }

  void _go(int step) {
    if (step > _step && _step == 0 && _jobType == null) {
      _snack(ref.read(stringsProvider).t('job_wz_need_type'));
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() => _step = step.clamp(0, 3));
  }

  Future<void> _save() async {
    final s = ref.read(stringsProvider);
    final uid = ref.read(currentUserIdProvider);
    if (uid == null) return;
    if (_company.text.trim().isEmpty) {
      _snack(s.t('job_name_required'));
      return;
    }
    var lo = jobMoney(_salaryMin), hi = jobMoney(_salaryMax);
    if (lo != null && hi != null && hi < lo) (lo, hi) = (hi, lo);
    setState(() => _saving = true);
    final v = JobVacancy(
      id: widget.initial?.id ?? '',
      ownerId: uid,
      companyName: _company.text.trim(),
      country: _country,
      city: _city,
      jobType: _jobType,
      specialties: [..._specialties],
      requirements: _req,
      canHelp: _help,
      minExperience: _minExp,
      countries: _countries,
      routes: jobText(_routes),
      salaryMin: lo,
      salaryMax: hi,
      currency: _currency,
      schedule: _schedule,
      conditions: jobText(_conditions),
      phone: jobText(_phone),
      showPhone: _showPhone,
      whatsapp: _showPhone && _whatsapp,
      status: _active ? 'active' : 'closed',
    );
    try {
      await ref.read(jobsRepositoryProvider).saveVacancy(v);
      ref.invalidate(myVacanciesProvider);
      ref.invalidate(jobVacanciesProvider);
      if (!mounted) return;
      _snack(s.t('job_saved'));
      Navigator.of(context).maybePop();
    } catch (_) {
      if (mounted) _snack(s.t('job_save_failed'));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    final lang = ref.watch(currentLocaleProvider).languageCode;
    final specs = ref.watch(jobSpecialtiesProvider).valueOrNull ?? kJobSpecialties;
    final skills = ref.watch(jobSkillsProvider).valueOrNull ?? kJobSkills;
    final steps = [
      () => _stepBasics(s, lang, skills),
      () => _stepRequirements(s, skills),
      () => _stepRoute(s, lang, specs),
      () => _stepPublish(s, lang, specs, skills),
    ];
    return PopScope(
      canPop: _step == 0 || _saving,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _step > 0) _go(_step - 1);
      },
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
              child: _WizardStepper(
                step: _step,
                labels: [s.t('job_wz_step1'), s.t('job_wz_step2'), s.t('job_wz_step3'), s.t('job_wz_step4')],
                onTap: (i) {
                  if (i < _step) _go(i);
                },
              ),
            ),
            Expanded(
              child: ListView(
                key: ValueKey('job-wz-step-$_step'),
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 32),
                children: steps[_step](),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  // ---- 1 Əsas məlumat ---------------------------------------------------------
  List<Widget> _stepBasics(AppStrings s, String lang, List<JobCatalogItem> skills) {
    final licences = orderedCatalog(skills.where((k) => k.kind == 'license').toList(), _licenceOrder);
    final schedules = [..._wizardSchedules, if (_schedule != null && !_wizardSchedules.contains(_schedule)) _schedule!];
    final extraCountries = [
      for (final c in _countries)
        if (!_quickCountries.contains(Countries.find(c)?.code)) c
    ];
    return [
      _SectionTitle(n: 1, title: s.t('job_wz_type')),
      Row(children: [
        Expanded(
          child: _TypeCard(
            cardKey: 'job-type-tir',
            label: s.t('job_wz_type_tir'),
            selected: _jobType == 'tir',
            picture: Image.asset(
              AppColors.isDay ? 'assets/images/cargo/type_tent.png' : 'assets/images/cargo/type_tent_night.png',
              height: 58,
              fit: BoxFit.contain,
            ),
            onTap: () => setState(() => _jobType = 'tir'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _TypeCard(
            cardKey: 'job-type-other',
            label: s.t('job_wz_type_other'),
            selected: _jobType == 'other',
            picture: Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(color: AppColors.cardAlt, shape: BoxShape.circle),
              child: Icon(Icons.person_outline, size: 34, color: AppColors.textSoft),
            ),
            onTap: () => setState(() => _jobType = 'other'),
          ),
        ),
      ]),
      _SectionTitle(n: 2, title: s.t('job_wz_salary')),
      LayoutBuilder(builder: (context, c) {
        // Narrow phones (320 pt): no coin box, so Min / Maks stay readable.
        final narrow = c.maxWidth < 330;
        return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (!narrow) ...[
            Container(
              width: 48,
              height: 52,
              decoration: BoxDecoration(
                color: AppColors.accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(Icons.monetization_on_outlined, color: AppColors.accent),
            ),
            const SizedBox(width: 8),
          ],
        Expanded(child: JobNumberField(controller: _salaryMin, label: s.t('job_wz_min'), fieldKey: 'job-salary-min', maxLength: 7)),
        const SizedBox(width: 8),
        Expanded(child: JobNumberField(controller: _salaryMax, label: s.t('job_wz_max'), fieldKey: 'job-salary-max', maxLength: 7)),
        const SizedBox(width: 8),
        SizedBox(width: 96, child: JobCurrencyField(value: _currency, s: s, onChanged: (v) => setState(() => _currency = v))),
      ]);
      }),
      _SectionTitle(n: 3, title: s.t('job_wz_schedule')),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final k in schedules)
          _Pill(
            pillKey: 'job-sch-$k',
            label: _scheduleLabel(s, k),
            selected: _schedule == k,
            onTap: () => setState(() => _schedule = _schedule == k ? null : k),
          ),
      ]),
      _SectionTitle(n: 4, title: s.t('job_wz_license')),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final it in licences)
          _Pill(
            pillKey: 'job-lic-${it.code}',
            label: it.name,
            minWidth: 52,
            selected: _req.containsKey(it.code),
            onTap: () => _toggle(it.code, !_req.containsKey(it.code), ReqLevel.must),
          ),
      ]),
      _SectionTitle(n: 5, title: s.t('job_wz_countries')),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final code in _quickCountries) _countryPill(code),
        for (final c in extraCountries)
          _Pill(
            pillKey: 'job-country-$c',
            label: Countries.find(c) == null ? c : '${Countries.find(c)!.flag} ${Countries.find(c)!.code}',
            selected: true,
            onTap: () => setState(() => _countries = [..._countries]..remove(c)),
          ),
        if (_countries.length < 30)
          _Pill(
            pillKey: 'job-add-country',
            label: '+',
            minWidth: 52,
            selected: false,
            onTap: () async {
              final picked = await showModalBottomSheet<Country>(
                context: context,
                isScrollControlled: true,
                useSafeArea: true,
                builder: (_) => CountryPickerSheet(languageCode: lang, strings: s),
              );
              if (picked != null && !_countries.any((c) => Countries.find(c)?.code == picked.code)) {
                setState(() => _countries = [..._countries, picked.en]);
              }
            },
          ),
      ]),
      const SizedBox(height: 12),
      Material(
        color: AppColors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: AppColors.line)),
        child: InkWell(
          key: const ValueKey('job-add-route'),
          borderRadius: BorderRadius.circular(14),
          onTap: () => _go(2),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            child: Row(children: [
              Icon(Icons.alt_route, color: AppColors.accent),
              const SizedBox(width: 10),
              Expanded(child: Text(s.t('job_wz_add_route'), style: TextStyle(color: AppColors.text))),
              Icon(Icons.chevron_right, color: AppColors.textSoft),
            ]),
          ),
        ),
      ),
      const SizedBox(height: 20),
      _NavButtons(s: s, onNext: () => _go(1)),
    ];
  }

  Widget _countryPill(String code) {
    final c = Countries.all.firstWhere((x) => x.code == code);
    final on = _countries.any((x) => Countries.find(x)?.code == code);
    return _Pill(
      pillKey: 'job-country-$code',
      label: '${c.flag} $code',
      selected: on,
      onTap: () => setState(() {
        _countries = on ? [for (final x in _countries) if (Countries.find(x)?.code != code) x] : [..._countries, c.en];
      }),
    );
  }

  String _scheduleLabel(AppStrings s, String k) {
    final short = s.t('job_sch_short_$k');
    return short == 'job_sch_short_$k' ? s.t('job_sch_$k') : short;
  }

  // ---- 2 Tələblər ---------------------------------------------------------------
  List<Widget> _stepRequirements(AppStrings s, List<JobCatalogItem> skills) {
    final docs = orderedCatalog(skills.where((k) => k.kind == 'document').toList(), _documentOrder);
    final soft = orderedCatalog(skills.where((k) => k.kind == 'skill').toList(), _skillOrder);
    final years = [..._experienceYears, if (_minExp != null && !_experienceYears.contains(_minExp)) _minExp!]..sort();
    return [
      _SectionTitle(n: 6, title: s.t('job_wz_docs')),
      Container(
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.line),
        ),
        child: Column(children: [
          for (var i = 0; i < docs.length; i++) ...[
            if (i > 0) Divider(height: 1, color: AppColors.line),
            _DocRow(
              rowKey: 'job-doc-${docs[i].code}',
              icon: switch (docs[i].code) {
                'cpc' => Icons.workspace_premium_outlined,
                'tachograph' => Icons.credit_card,
                'adr' => Icons.warning_amber_rounded,
                _ => Icons.description_outlined,
              },
              label: jobLabel(s, 'job_skill_', docs[i]),
              checked: _req.containsKey(docs[i].code),
              onTap: () => _toggle(docs[i].code, !_req.containsKey(docs[i].code), ReqLevel.must),
            ),
          ],
        ]),
      ),
      _SectionTitle(n: 7, title: s.t('job_wz_skills')),
      Row(children: [
        Expanded(child: Text(s.t('job_wz_min_exp'), style: TextStyle(fontSize: 15, color: AppColors.text))),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.line),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<int?>(
              key: const ValueKey('job-min-experience'),
              value: _minExp,
              dropdownColor: AppColors.card,
              items: [
                DropdownMenuItem<int?>(value: null, child: Text(s.t('job_wz_no_exp'))),
                for (final y in years) DropdownMenuItem<int?>(value: y, child: Text(s.t('job_wz_years', {'n': '$y'}))),
              ],
              onChanged: (v) => setState(() => _minExp = v),
            ),
          ),
        ),
      ]),
      const SizedBox(height: 12),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final it in soft)
          _Pill(
            pillKey: 'job-skill-${it.code}',
            label: _chipLabel(s, it),
            selected: _req.containsKey(it.code),
            check: true,
            onTap: () => _toggle(it.code, !_req.containsKey(it.code), ReqLevel.nice),
          ),
      ]),
      _SectionTitle(n: 8, title: s.t('job_wz_extra')),
      TextField(
        key: const ValueKey('job-conditions'),
        controller: _conditions,
        maxLength: math.max(500, _conditions.text.length),
        maxLines: 5,
        minLines: 4,
        decoration: InputDecoration(hintText: s.t('job_wz_extra_hint'), alignLabelWithHint: true),
      ),
      const SizedBox(height: 16),
      _NavButtons(s: s, onBack: () => _go(0), onNext: () => _go(2)),
    ];
  }

  String _chipLabel(AppStrings s, JobCatalogItem it) {
    final short = s.t('job_chip_${it.code}');
    return short == 'job_chip_${it.code}' ? jobLabel(s, 'job_skill_', it) : short;
  }

  // ---- 3 Marşrut -------------------------------------------------------------------
  List<Widget> _stepRoute(AppStrings s, String lang, List<JobCatalogItem> specs) => [
        _SectionTitle(n: 9, title: s.t('job_f_place')),
        JobPlaceField(
          country: _country,
          city: _city,
          languageCode: lang,
          s: s,
          onChanged: (co, ci) => setState(() {
            _country = co;
            _city = ci;
          }),
        ),
        _SectionTitle(n: 10, title: s.t('job_wz_step3')),
        TextField(
          key: const ValueKey('job-routes'),
          controller: _routes,
          maxLength: 300,
          decoration: InputDecoration(hintText: s.t('job_wz_route_hint'), prefixIcon: Icon(Icons.alt_route, color: AppColors.accent)),
        ),
        _SectionTitle(n: 11, title: s.t('job_wz_more_specs')),
        JobChoiceChips(
            items: specs, selected: _specialties, s: s, color: AppColors.accent, onChanged: (v) => setState(() => _specialties = v)),
        const SizedBox(height: 20),
        _NavButtons(s: s, onBack: () => _go(1), onNext: () => _go(3)),
      ];

  // ---- 4 Dərc et ------------------------------------------------------------------
  List<Widget> _stepPublish(AppStrings s, String lang, List<JobCatalogItem> specs, List<JobCatalogItem> skills) {
    String names(Iterable<String> codes, String prefix, List<JobCatalogItem> cat) =>
        [for (final c in codes) jobCodeLabel(s, prefix, c, cat)].join(', ');
    final lo = jobMoney(_salaryMin), hi = jobMoney(_salaryMax);
    final cur = _currency ?? 'AZN';
    final salary = lo == null && hi == null
        ? null
        : '${{if (lo != null) lo.round(), if (hi != null) hi.round()}.join(' – ')} $cur';
    final kindOf = {for (final k in skills) k.code: k.kind};
    final licences = [for (final c in _req.keys) if (kindOf[c] == 'license') c];
    final docs = [for (final c in _req.keys) if (kindOf[c] == 'document') c];
    final soft = [for (final c in _req.keys) if (kindOf[c] != 'license' && kindOf[c] != 'document') c];
    final rows = <(String, String?)>[
      (s.t('job_wz_type'), _jobType == null ? null : s.t('job_wz_type_$_jobType')),
      (s.t('job_wz_salary'), salary),
      (s.t('job_wz_schedule'), _schedule == null ? null : s.t('job_sch_$_schedule')),
      (s.t('job_wz_license'), licences.isEmpty ? null : names(licences, 'job_skill_', skills)),
      (s.t('job_wz_countries'), _countries.isEmpty ? null : [for (final c in _countries) Countries.label(c, lang)].join(', ')),
      (s.t('job_wz_docs'), docs.isEmpty ? null : names(docs, 'job_skill_', skills)),
      (s.t('job_wz_min_exp'), _minExp == null ? null : s.t('job_wz_years', {'n': '$_minExp'})),
      (s.t('job_wz_skills'), soft.isEmpty ? null : names(soft, 'job_skill_', skills)),
      (s.t('job_wz_step3'), jobText(_routes)),
      (s.t('job_wz_more_specs'), _specialties.isEmpty ? null : names(_specialties, 'job_spec_', specs)),
    ];
    return [
      _SectionTitle(n: 12, title: s.t('job_f_company')),
      TextField(key: const ValueKey('job-company'), controller: _company, maxLength: 120),
      _SectionTitle(n: 13, title: s.t('job_sec_contact')),
      JobPhoneBlock(
        phone: _phone,
        showPhone: _showPhone,
        whatsapp: _whatsapp,
        s: s,
        onShow: (v) => setState(() => _showPhone = v),
        onWhatsapp: (v) => setState(() => _whatsapp = v),
      ),
      SwitchListTile(
        key: const ValueKey('job-form-active'),
        contentPadding: EdgeInsets.zero,
        activeThumbColor: AppColors.accent,
        title: Text(_active ? s.t('job_vacancy_active') : s.t('job_vacancy_closed')),
        value: _active,
        onChanged: (v) => setState(() => _active = v),
      ),
      _SectionTitle(n: 14, title: s.t('job_wz_summary')),
      Container(
        key: const ValueKey('job-wz-summary'),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.line),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (final r in rows)
            if (r.$2 != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text.rich(TextSpan(children: [
                  TextSpan(text: '${r.$1}: ', style: TextStyle(color: AppColors.textSoft)),
                  TextSpan(text: r.$2, style: TextStyle(color: AppColors.text)),
                ])),
              ),
        ]),
      ),
      const SizedBox(height: 20),
      _NavButtons(
        s: s,
        onBack: () => _go(2),
        onNext: _saving ? null : _save,
        nextKey: 'job-save',
        nextLabel: s.t('job_wz_publish'),
        nextIcon: Icons.check,
        busy: _saving,
      ),
    ];
  }
}

/// 1 ─ 2 ─ 3 ─ 4: done = orange ✓, current = orange number, later = grey.
class _WizardStepper extends StatelessWidget {
  final int step;
  final List<String> labels;
  final ValueChanged<int> onTap;
  const _WizardStepper({required this.step, required this.labels, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final on = AppColors.accent;
    Widget line(bool visible, bool lit) => Expanded(
          child: Container(height: 2, color: !visible ? Colors.transparent : (lit ? on : AppColors.line)),
        );
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      for (var i = 0; i < labels.length; i++)
        Expanded(
          child: GestureDetector(
            key: ValueKey('job-wz-dot-$i'),
            behavior: HitTestBehavior.opaque,
            onTap: () => onTap(i),
            child: Column(children: [
              Row(children: [
                line(i > 0, i <= step),
                Container(
                  width: 32,
                  height: 32,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: i <= step ? on : Colors.transparent,
                    shape: BoxShape.circle,
                    border: Border.all(color: i <= step ? on : AppColors.line, width: 1.6),
                  ),
                  child: i < step
                      ? const Icon(Icons.check, size: 18, color: Colors.white)
                      : Text('${i + 1}',
                          style: TextStyle(
                              color: i == step ? Colors.white : AppColors.textSoft, fontWeight: FontWeight.w600)),
                ),
                line(i < labels.length - 1, i < step),
              ]),
              const SizedBox(height: 6),
              Text(labels[i],
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  style: TextStyle(
                      fontSize: 12,
                      color: i <= step ? AppColors.text : AppColors.textSoft,
                      fontWeight: i == step ? FontWeight.w500 : FontWeight.w400)),
            ]),
          ),
        ),
    ]);
  }
}

class _SectionTitle extends StatelessWidget {
  final int n;
  final String title;
  const _SectionTitle({required this.n, required this.title});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 18, bottom: 10),
        child: Row(children: [
          Container(
            width: 24,
            height: 24,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: AppColors.accent, shape: BoxShape.circle),
            child: Text('$n', style: const TextStyle(fontSize: 12.5, color: Colors.white, fontWeight: FontWeight.w600)),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.text))),
        ]),
      );
}

/// İş növü: big picture card, orange frame and ✓ when chosen.
class _TypeCard extends StatelessWidget {
  final String cardKey, label;
  final bool selected;
  final Widget picture;
  final VoidCallback onTap;
  const _TypeCard(
      {required this.cardKey, required this.label, required this.selected, required this.picture, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.accent;
    return Material(
      color: selected ? c.withValues(alpha: 0.08) : AppColors.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: selected ? c : AppColors.line, width: selected ? 1.8 : 1),
      ),
      child: InkWell(
        key: ValueKey(cardKey),
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Stack(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 16, 10, 12),
            child: Column(children: [
              SizedBox(height: 60, child: Center(child: picture)),
              const SizedBox(height: 8),
              Text(label,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  style: TextStyle(fontSize: 14, color: AppColors.text, fontWeight: selected ? FontWeight.w500 : FontWeight.w400)),
            ]),
          ),
          if (selected)
            Positioned(
              top: 8,
              right: 8,
              child: Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(color: c, shape: BoxShape.circle),
                child: const Icon(Icons.check, size: 15, color: Colors.white),
              ),
            ),
        ]),
      ),
    );
  }
}

/// A rounded choice (schedule, category, country, skill).
class _Pill extends StatelessWidget {
  final String pillKey, label;
  final bool selected;
  final bool check;
  final double minWidth;
  final VoidCallback onTap;
  const _Pill(
      {required this.pillKey,
      required this.label,
      required this.selected,
      required this.onTap,
      this.check = false,
      this.minWidth = 0});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.accent;
    return Material(
      color: selected ? c.withValues(alpha: 0.10) : AppColors.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: selected ? c : AppColors.line, width: selected ? 1.6 : 1),
      ),
      child: InkWell(
        key: ValueKey(pillKey),
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: ConstrainedBox(
          constraints: BoxConstraints(minWidth: minWidth, minHeight: 42),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children: [
              if (check && selected) ...[Icon(Icons.check, size: 17, color: c), const SizedBox(width: 6)],
              Flexible(
                child: Text(label,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 14,
                        color: selected ? c : AppColors.text,
                        fontWeight: selected ? FontWeight.w500 : FontWeight.w400)),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// A document row: icon, name, tick box.
class _DocRow extends StatelessWidget {
  final String rowKey, label;
  final IconData icon;
  final bool checked;
  final VoidCallback onTap;
  const _DocRow({required this.rowKey, required this.label, required this.icon, required this.checked, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.accent;
    return InkWell(
      key: ValueKey(rowKey),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        child: Row(children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(color: c.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, size: 21, color: c),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(label, style: TextStyle(fontSize: 15, color: AppColors.text))),
          AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: checked ? c : Colors.transparent,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: checked ? c : AppColors.textSoft, width: 1.6),
            ),
            child: checked ? const Icon(Icons.check, size: 17, color: Colors.white) : null,
          ),
        ]),
      ),
    );
  }
}

/// "← Geri" · "Davam et →" (only "Davam et" on the first step).
class _NavButtons extends StatelessWidget {
  final AppStrings s;
  final VoidCallback? onBack;
  final VoidCallback? onNext;
  final String nextKey;
  final String? nextLabel;
  final IconData nextIcon;
  final bool busy;
  const _NavButtons(
      {required this.s,
      this.onBack,
      required this.onNext,
      this.nextKey = 'job-wz-next',
      this.nextLabel,
      this.nextIcon = Icons.arrow_forward,
      this.busy = false});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.accent;
    final next = FilledButton(
      key: ValueKey(nextKey),
      style: FilledButton.styleFrom(
        backgroundColor: c,
        foregroundColor: Colors.white,
        minimumSize: const Size.fromHeight(52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      onPressed: onNext,
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Flexible(
          child: Text(nextLabel ?? s.t('job_wz_next'),
              overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
        ),
        const SizedBox(width: 8),
        busy
            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : Icon(nextIcon, size: 20),
      ]),
    );
    if (onBack == null) return next;
    return Row(children: [
      Expanded(
        child: OutlinedButton(
          key: const ValueKey('job-wz-back'),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.text,
            minimumSize: const Size.fromHeight(52),
            side: BorderSide(color: AppColors.line),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          onPressed: onBack,
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.arrow_back, size: 20),
            const SizedBox(width: 6),
            Flexible(child: Text(s.t('job_wz_back'), overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16))),
          ]),
        ),
      ),
      const SizedBox(width: 12),
      Expanded(flex: 2, child: next),
    ]);
  }
}
