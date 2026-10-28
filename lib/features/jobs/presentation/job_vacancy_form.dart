import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/localization/locale_controller.dart';
import '../../../core/theme/app_theme.dart';
import '../../auth/presentation/providers/auth_providers.dart';
import '../data/jobs_repository.dart';
import '../domain/job_models.dart';
import 'job_form_kit.dart';
import 'job_form_parts.dart';
import 'jobs_providers.dart';

/// "Sahibkar — Sürücü axtarıram" (owner, 28.10.2026, picture 2): one page,
/// scrolled down, no Sürücü | Sahibkar switch (chosen on the home page).
/// A new vacancy ([id] null) or one of mine. A ticked licence category or
/// document is "Mütləq", a ticked skill "Arzuolunan" (an existing level is
/// kept). Fields the picture does not show (place, route, İş növü, "I can
/// help") keep what was saved.
class JobVacancyFormScreen extends ConsumerWidget {
  final String? id;
  const JobVacancyFormScreen({super.key, this.id});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final mine = ref.watch(myVacanciesProvider);
    return Scaffold(
      appBar: AppBar(centerTitle: true, title: Text(s.t('job_center'), style: const TextStyle(fontWeight: FontWeight.w600))),
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

const _experienceYears = [1, 2, 3, 5, 7, 10];
const _documentOrder = ['tachograph', 'cpc', 'adr', 'idp'];
const _licenceOrder = ['lic_b', 'lic_c1', 'lic_c', 'lic_ce', 'lic_d1', 'lic_d', 'lic_c1e', 'lic_d1e', 'lic_de'];
const _transportOrder = ['tent', 'ref', 'container', 'dump', 'open', 'tanker'];

class _VacancyForm extends ConsumerStatefulWidget {
  final JobVacancy? initial;
  const _VacancyForm({required this.initial});

  @override
  ConsumerState<_VacancyForm> createState() => _VacancyFormState();
}

class _VacancyFormState extends ConsumerState<_VacancyForm> {
  late final TextEditingController _company, _salaryMin, _salaryMax, _conditions, _phone;
  String? _currency;
  late List<String> _schedules;
  int? _minExp, _ageMin, _ageMax;
  late Set<String> _specialties;
  late Map<String, ReqLevel> _req;
  late Set<String> _help;
  late List<String> _countries;
  late bool _negotiable, _whatsapp;
  late JobContactWay _way;
  String? _profilePhone;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final v = widget.initial;
    final user = ref.read(currentUserProvider);
    _profilePhone = user?.phone;
    _company = TextEditingController(text: v?.companyName ?? user?.fullName ?? '');
    _salaryMin = TextEditingController(text: v?.salaryMin == null ? '' : v!.salaryMin!.round().toString());
    _salaryMax = TextEditingController(text: v?.salaryMax == null ? '' : v!.salaryMax!.round().toString());
    _conditions = TextEditingController(text: v?.conditions ?? '');
    _phone = TextEditingController(text: v?.phone ?? '');
    _currency = v?.currency;
    _schedules = [...?v?.allSchedules];
    _minExp = v?.minExperience;
    _ageMin = v?.ageMin;
    _ageMax = v?.ageMax;
    _specialties = {...?v?.specialties};
    _req = {...?v?.requirements};
    _help = {...?v?.canHelp};
    _countries = [...?v?.countries];
    _negotiable = v?.salaryNegotiable ?? false;
    _showPhone = v?.showPhone ?? false;
    _whatsapp = v?.whatsapp ?? false;
    _way = jobContactWayOf(showPhone: _showPhone, phone: v?.phone, profilePhone: _profilePhone);
  }

  // Phone hidden by default (owner, 26.10.2026); kept for the tests' guard.
  late bool _showPhone;

  @override
  void dispose() {
    for (final c in [_company, _salaryMin, _salaryMax, _conditions, _phone]) {
      c.dispose();
    }
    super.dispose();
  }

  void _toggle(String code, ReqLevel level) {
    final r = toggleRequirement(_req, _help, code, !_req.containsKey(code), level);
    setState(() {
      _req = r.req;
      _help = r.help;
    });
  }

  Future<void> _save() async {
    final s = ref.read(stringsProvider);
    final uid = ref.read(currentUserIdProvider);
    if (uid == null) return;
    if (_company.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.t('job_name_required'))));
      return;
    }
    var lo = jobMoney(_salaryMin), hi = jobMoney(_salaryMax);
    if (lo != null && hi != null && hi < lo) (lo, hi) = (hi, lo);
    var aMin = _ageMin, aMax = _ageMax;
    if (aMin != null && aMax != null && aMax < aMin) (aMin, aMax) = (aMax, aMin);
    final phone = switch (_way) {
      JobContactWay.message => widget.initial?.phone,
      JobContactWay.profile => _profilePhone,
      JobContactWay.other => jobText(_phone),
    };
    final show = _way != JobContactWay.message && (phone ?? '').isNotEmpty;
    final old = widget.initial;
    setState(() => _saving = true);
    final v = JobVacancy(
      id: old?.id ?? '',
      ownerId: uid,
      companyName: _company.text.trim(),
      country: old?.country,
      city: old?.city,
      jobType: old == null ? 'tir' : old.jobType,
      specialties: [..._specialties],
      requirements: _req,
      canHelp: _help,
      minExperience: _minExp,
      countries: _countries,
      routes: old?.routes,
      salaryMin: lo,
      salaryMax: hi,
      currency: _currency,
      salaryNegotiable: _negotiable,
      ageMin: aMin,
      ageMax: aMax,
      schedule: _schedules.firstOrNull,
      schedules: _schedules,
      conditions: jobText(_conditions),
      phone: phone,
      showPhone: show,
      whatsapp: show && _whatsapp,
      status: old?.status ?? 'active',
    );
    try {
      await ref.read(jobsRepositoryProvider).saveVacancy(v);
      ref.invalidate(myVacanciesProvider);
      ref.invalidate(jobVacanciesProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.t('job_saved'))));
      Navigator.of(context).maybePop();
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.t('job_save_failed'))));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    final lang = ref.watch(currentLocaleProvider).languageCode;
    final specs = orderedCatalog(ref.watch(jobSpecialtiesProvider).valueOrNull ?? kJobSpecialties, _transportOrder);
    final skills = ref.watch(jobSkillsProvider).valueOrNull ?? kJobSkills;
    final lics = orderedCatalog(skills.where((k) => k.kind == 'license').toList(), _licenceOrder);
    final docs = orderedCatalog(skills.where((k) => k.kind == 'document').toList(), _documentOrder);
    final soft = skills.where((k) => k.kind == 'skill').toList();
    final years = {..._experienceYears, if (_minExp != null && _minExp! > 0) _minExp!}.toList()..sort();
    final ages = [for (var a = 18; a <= 70; a++) a];
    final schedules = [...kJobFormSchedules, for (final k in _schedules) if (!kJobFormSchedules.contains(k)) k];
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 40), children: [
          JobFormBanner(
            asset: 'assets/images/jobs/banner_employer.jpg',
            line1: s.t('job_emp_banner_1'),
            line2: s.t('job_emp_banner_2'),
            subtitle: s.t('job_emp_banner_sub'),
          ),
          JobFieldRow(
            icon: Icons.apartment,
            label: s.t('job_company'),
            child: TextField(
              key: const ValueKey('job-company'),
              controller: _company,
              maxLength: 120,
              decoration: const InputDecoration(isDense: true, counterText: ''),
            ),
          ),
          JobBlock(
            icon: Icons.place,
            label: s.t('job_work_countries'),
            hint: s.t('job_pick_one_or_more'),
            child: JobCountryTiles(selected: _countries, lang: lang, s: s, onChanged: (v) => setState(() => _countries = v)),
          ),
          JobBlock(
            icon: Icons.local_shipping_outlined,
            label: s.t('job_need_transport'),
            child: JobTransportRow(items: specs, selected: _specialties, s: s, lang: lang, onChanged: (v) => setState(() => _specialties = v)),
          ),
          JobBlock(
            icon: Icons.badge_outlined,
            label: s.t('job_licence_category'),
            child: JobLicenceBoxes(
              items: lics,
              selected: {for (final k in lics) if (_req.containsKey(k.code)) k.code},
              onTap: (code) => _toggle(code, ReqLevel.must),
            ),
          ),
          JobFieldRow(
            icon: Icons.bar_chart_rounded,
            label: s.t('job_exp_required'),
            child: JobDropdown<int>(
              fieldKey: 'job-min-experience',
              value: (_minExp ?? 0) > 0 ? _minExp : null,
              items: [(null, s.t('job_wz_no_exp')), for (final y in years) (y, s.t('job_at_least_years', {'n': '$y'}))],
              onChanged: (v) => setState(() => _minExp = v),
            ),
          ),
          JobFieldRow(
            icon: Icons.calendar_month_outlined,
            label: s.t('job_age_range'),
            child: Row(children: [
              Expanded(
                child: JobDropdown<int>(
                  fieldKey: 'job-age-min',
                  value: _ageMin,
                  items: [(null, '—'), for (final a in ages) (a, '$a')],
                  onChanged: (v) => setState(() => _ageMin = v),
                ),
              ),
              Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: Text('–', style: TextStyle(color: AppColors.text))),
              Expanded(
                child: JobDropdown<int>(
                  fieldKey: 'job-age-max',
                  value: _ageMax,
                  items: [(null, '—'), for (final a in ages) (a, '$a')],
                  onChanged: (v) => setState(() => _ageMax = v),
                ),
              ),
            ]),
          ),
          JobBlock(
            icon: Icons.description_outlined,
            label: s.t('job_doc_requirements'),
            child: JobTickGrid(
              items: [for (final d in docs) (d.code, jobShortLabel(s, d))],
              checked: (c) => _req.containsKey(c),
              onTap: (c) => _toggle(c, ReqLevel.must),
            ),
          ),
          JobBlock(
            icon: Icons.star_outline,
            label: s.t('job_skills_wanted'),
            child: JobTickGrid(
              keyPrefix: 'job-skill',
              items: [for (final k in soft) (k.code, jobShortLabel(s, k))],
              checked: (c) => _req.containsKey(c),
              onTap: (c) => _toggle(c, ReqLevel.nice),
            ),
          ),
          JobFieldRow(
            icon: Icons.sticky_note_2_outlined,
            label: s.t('job_extra_requirements'),
            child: TextField(
              key: const ValueKey('job-conditions'),
              controller: _conditions,
              maxLength: math.max(1000, _conditions.text.length),
              minLines: 2,
              maxLines: 5,
              decoration: InputDecoration(hintText: s.t('job_extra_requirements_hint'), isDense: true, counterText: ''),
            ),
          ),
          JobBlock(
            icon: Icons.schedule,
            label: s.t('job_work_mode'),
            child: JobMultiPills(
              items: [for (final k in schedules) (k, s.t('job_sch_$k'))],
              values: _schedules,
              onChanged: (v) => setState(() => _schedules = v),
            ),
          ),
          JobBlock(
            icon: Icons.attach_money,
            label: s.t('job_salary_offer'),
            child: JobSalaryRow(
              min: _salaryMin,
              max: _salaryMax,
              currency: _currency,
              negotiable: _negotiable,
              s: s,
              onCurrency: (v) => setState(() => _currency = v),
              onNegotiable: (v) => setState(() => _negotiable = v),
            ),
          ),
          JobFieldRow(
            icon: Icons.chat_outlined,
            label: s.t('job_contact_info'),
            child: JobContactField(
              way: _way,
              phone: _phone,
              whatsapp: _whatsapp,
              profilePhone: _profilePhone,
              s: s,
              onWay: (w) => setState(() => _way = w),
              onWhatsapp: (v) => setState(() => _whatsapp = v),
            ),
          ),
          JobSubmitButton(
            buttonKey: 'job-save',
            label: s.t('job_post_requirements'),
            busy: _saving,
            onPressed: _save,
          ),
        ]),
      ),
    );
  }
}
