import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/localization/locale_controller.dart';
import '../../auth/presentation/providers/auth_providers.dart';
import '../data/jobs_repository.dart';
import '../domain/job_models.dart';
import 'job_form_parts.dart';
import 'job_widgets.dart';
import 'jobs_providers.dart';

/// "İşçi axtarıram — Sahibkar": a new vacancy ([id] null) or one of mine.
/// Requirements are optional: each one "Mütləq" or "Arzuolunan", and for a
/// required document "I can help to obtain it".
class JobVacancyFormScreen extends ConsumerWidget {
  final String? id;
  const JobVacancyFormScreen({super.key, this.id});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final mine = ref.watch(myVacanciesProvider);
    return Scaffold(
      appBar: AppBar(title: Text(id == null ? s.t('job_vacancy_new') : s.t('job_vacancy_edit'))),
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

class _VacancyForm extends ConsumerStatefulWidget {
  final JobVacancy? initial;
  const _VacancyForm({required this.initial});

  @override
  ConsumerState<_VacancyForm> createState() => _VacancyFormState();
}

class _VacancyFormState extends ConsumerState<_VacancyForm> {
  late final TextEditingController _company, _minExp, _routes, _salaryMin, _salaryMax, _conditions, _phone;
  String? _country, _city, _currency, _schedule;
  late Set<String> _specialties;
  late Map<String, ReqLevel> _req;
  late Set<String> _help;
  late List<String> _countries;
  late bool _showPhone, _whatsapp, _active;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final v = widget.initial;
    final user = ref.read(currentUserProvider);
    _company = TextEditingController(text: v?.companyName ?? user?.fullName ?? '');
    _minExp = TextEditingController(text: v?.minExperience?.toString() ?? '');
    _routes = TextEditingController(text: v?.routes ?? '');
    _salaryMin = TextEditingController(text: v?.salaryMin == null ? '' : v!.salaryMin!.round().toString());
    _salaryMax = TextEditingController(text: v?.salaryMax == null ? '' : v!.salaryMax!.round().toString());
    _conditions = TextEditingController(text: v?.conditions ?? '');
    _phone = TextEditingController(text: v?.phone ?? user?.phone ?? '');
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
    for (final c in [_company, _minExp, _routes, _salaryMin, _salaryMax, _conditions, _phone]) {
      c.dispose();
    }
    super.dispose();
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
    setState(() => _saving = true);
    final v = JobVacancy(
      id: widget.initial?.id ?? '',
      ownerId: uid,
      companyName: _company.text.trim(),
      country: _country,
      city: _city,
      specialties: [..._specialties],
      requirements: _req,
      canHelp: _help,
      minExperience: jobInt(_minExp),
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
    final specs = ref.watch(jobSpecialtiesProvider).valueOrNull ?? kJobSpecialties;
    final skills = ref.watch(jobSkillsProvider).valueOrNull ?? kJobSkills;
    final c = jobEmployerColor;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 40), children: [
          JobSection(title: s.t('job_sec_company'), children: [
            TextField(
                key: const ValueKey('job-company'),
                controller: _company,
                maxLength: 120,
                decoration: InputDecoration(labelText: s.t('job_f_company'))),
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
          ]),
          JobSection(title: s.t('job_f_specialties_need'), children: [
            JobChoiceChips(items: specs, selected: _specialties, s: s, color: c, onChanged: (v) => setState(() => _specialties = v)),
          ]),
          JobSection(title: s.t('job_f_requirements'), hint: s.t('job_f_requirements_hint'), children: [
            JobNumberField(controller: _minExp, label: s.t('job_f_min_experience'), fieldKey: 'job-min-experience', maxLength: 2),
            for (final kind in kJobSkillKinds) ...[
              Padding(
                padding: const EdgeInsets.only(top: 10, bottom: 2),
                child: Text(s.t('job_kind_$kind'), style: TextStyle(color: c, fontWeight: FontWeight.w500)),
              ),
              for (final it in skills.where((k) => k.kind == kind))
                RequirementRow(
                  label: jobLabel(s, 'job_skill_', it),
                  code: it.code,
                  helpable: kind != 'skill',
                  value: _req[it.code],
                  canHelp: _help.contains(it.code),
                  s: s,
                  onChanged: (v) => setState(() {
                    if (v == null) {
                      _req.remove(it.code);
                      _help.remove(it.code);
                    } else {
                      _req[it.code] = v;
                    }
                  }),
                  onHelp: (on) => setState(() => on ? _help.add(it.code) : _help.remove(it.code)),
                ),
            ],
          ]),
          JobSection(title: s.t('job_f_countries_v'), children: [
            JobCountriesField(countries: _countries, languageCode: lang, s: s, onChanged: (v) => setState(() => _countries = v)),
            const SizedBox(height: 10),
            TextField(
              key: const ValueKey('job-routes'),
              controller: _routes,
              maxLength: 300,
              decoration: InputDecoration(labelText: s.t('job_f_routes')),
            ),
          ]),
          JobSection(title: s.t('job_sec_terms'), children: [
            Row(children: [
              Expanded(child: JobNumberField(controller: _salaryMin, label: s.t('job_f_salary_min'), fieldKey: 'job-salary-min', maxLength: 7)),
              const SizedBox(width: 8),
              Expanded(child: JobNumberField(controller: _salaryMax, label: s.t('job_f_salary_max'), fieldKey: 'job-salary-max', maxLength: 7)),
              const SizedBox(width: 8),
              SizedBox(width: 110, child: JobCurrencyField(value: _currency, s: s, onChanged: (v) => setState(() => _currency = v))),
            ]),
            const SizedBox(height: 10),
            JobScheduleField(value: _schedule, s: s, onChanged: (v) => setState(() => _schedule = v)),
            const SizedBox(height: 10),
            TextField(
              key: const ValueKey('job-conditions'),
              controller: _conditions,
              maxLength: 1000,
              maxLines: 4,
              minLines: 2,
              decoration: InputDecoration(labelText: s.t('job_f_conditions')),
            ),
          ]),
          JobSection(title: s.t('job_sec_contact'), children: [
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
              activeThumbColor: c,
              title: Text(_active ? s.t('job_vacancy_active') : s.t('job_vacancy_closed')),
              value: _active,
              onChanged: (v) => setState(() => _active = v),
            ),
          ]),
          FilledButton.icon(
            key: const ValueKey('job-save'),
            style: FilledButton.styleFrom(backgroundColor: c, padding: const EdgeInsets.symmetric(vertical: 14)),
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.check),
            label: Text(s.t('job_save')),
          ),
        ]),
      ),
    );
  }
}
