import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/localization/locale_controller.dart';
import '../../../core/theme/app_theme.dart';
import '../../auth/presentation/providers/auth_providers.dart';
import '../data/jobs_repository.dart';
import '../domain/job_models.dart';
import 'job_form_parts.dart';
import 'job_widgets.dart';
import 'jobs_providers.dart';

/// "İş axtarıram — Sürücü": my work profile. Name and phone come from my
/// account; everything else except the name is optional. Documents and
/// skills: ✓ has it · ✗ does not · "ready to obtain" · nothing = not given.
class JobSeekerFormScreen extends ConsumerWidget {
  const JobSeekerFormScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final me = ref.watch(myJobProfileProvider);
    return Scaffold(
      appBar: AppBar(title: Text(s.t('job_role_driver'))),
      body: me.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(e is JobsNotReady ? s.t('job_not_ready') : s.t('home_error_loading'), textAlign: TextAlign.center),
          ),
        ),
        data: (p) => _SeekerForm(initial: p),
      ),
    );
  }
}

class _SeekerForm extends ConsumerStatefulWidget {
  final JobSeeker? initial;
  const _SeekerForm({required this.initial});

  @override
  ConsumerState<_SeekerForm> createState() => _SeekerFormState();
}

class _SeekerFormState extends ConsumerState<_SeekerForm> {
  late final TextEditingController _name, _experience, _otherDocs, _routes, _salary, _note, _phone;
  DateTime? _birth;
  String? _country, _city, _currency, _schedule;
  late Set<String> _specialties;
  late Map<String, SkillState> _skills;
  late List<String> _countries;
  late bool _showPhone, _whatsapp, _active;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final p = widget.initial;
    final user = ref.read(currentUserProvider);
    _name = TextEditingController(text: p?.fullName ?? user?.fullName ?? '');
    _experience = TextEditingController(text: p?.experienceYears?.toString() ?? '');
    _otherDocs = TextEditingController(text: p?.otherDocs ?? '');
    _routes = TextEditingController(text: p?.routes ?? '');
    _salary = TextEditingController(text: p?.salaryMin == null ? '' : p!.salaryMin!.round().toString());
    _note = TextEditingController(text: p?.note ?? '');
    _phone = TextEditingController(text: p?.phone ?? user?.phone ?? '');
    _birth = p?.birthDate;
    _country = p?.country;
    _city = p?.city;
    _currency = p?.currency;
    _schedule = p?.schedule;
    _specialties = {...?p?.specialties};
    _skills = {...?p?.skills};
    _countries = [...?p?.countries];
    _showPhone = p?.showPhone ?? false;
    _whatsapp = p?.whatsapp ?? false;
    _active = p?.isActive ?? true;
  }

  @override
  void dispose() {
    for (final c in [_name, _experience, _otherDocs, _routes, _salary, _note, _phone]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickBirth() async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: _birth ?? DateTime(now.year - 30),
      firstDate: DateTime(now.year - 90),
      lastDate: DateTime(now.year - 16, now.month, now.day),
    );
    if (d != null) setState(() => _birth = d);
  }

  Future<void> _save() async {
    final s = ref.read(stringsProvider);
    final uid = ref.read(currentUserIdProvider);
    if (uid == null) return;
    if (_name.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.t('job_name_required'))));
      return;
    }
    setState(() => _saving = true);
    final p = JobSeeker(
      userId: uid,
      fullName: _name.text.trim(),
      birthDate: _birth,
      country: _country,
      city: _city,
      experienceYears: jobInt(_experience),
      specialties: [..._specialties],
      skills: _skills,
      otherDocs: jobText(_otherDocs),
      countries: _countries,
      routes: jobText(_routes),
      salaryMin: jobMoney(_salary),
      currency: _currency,
      schedule: _schedule,
      note: jobText(_note),
      phone: jobText(_phone),
      showPhone: _showPhone,
      whatsapp: _showPhone && _whatsapp,
      isActive: _active,
    );
    try {
      await ref.read(jobsRepositoryProvider).saveProfile(p);
      ref.invalidate(myJobProfileProvider);
      ref.invalidate(jobSeekersProvider);
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
    final c = jobDriverColor;
    final b = _birth;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 40), children: [
          JobSection(title: s.t('job_sec_about'), children: [
            TextField(
                key: const ValueKey('job-name'),
                controller: _name,
                maxLength: 120,
                decoration: InputDecoration(labelText: s.t('job_f_name'))),
            InkWell(
              key: const ValueKey('job-birth'),
              onTap: _pickBirth,
              child: InputDecorator(
                decoration: InputDecoration(
                  labelText: s.t('job_f_birth'),
                  prefixIcon: const Icon(Icons.cake_outlined),
                  suffixIcon: b == null ? null : IconButton(icon: const Icon(Icons.close), onPressed: () => setState(() => _birth = null)),
                ),
                child: Text(b == null
                    ? ''
                    : '${b.day.toString().padLeft(2, '0')}.${b.month.toString().padLeft(2, '0')}.${b.year} · ${s.t('job_age', {'n': '${ageOn(b, DateTime.now())}'})}'),
              ),
            ),
            const SizedBox(height: 10),
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
            const SizedBox(height: 10),
            JobNumberField(controller: _experience, label: s.t('job_f_experience'), fieldKey: 'job-experience', maxLength: 2),
          ]),
          JobSection(title: s.t('job_f_specialties'), children: [
            JobChoiceChips(items: specs, selected: _specialties, s: s, color: c, onChanged: (v) => setState(() => _specialties = v)),
          ]),
          JobSection(title: s.t('job_f_skills'), hint: s.t('job_f_skills_hint'), children: [
            for (final kind in kJobSkillKinds) ...[
              Padding(
                padding: const EdgeInsets.only(top: 6, bottom: 2),
                child: Text(s.t('job_kind_$kind'), style: TextStyle(color: c, fontWeight: FontWeight.w500)),
              ),
              for (final it in skills.where((k) => k.kind == kind))
                SkillAnswerRow(
                  label: jobLabel(s, 'job_skill_', it),
                  code: it.code,
                  value: _skills[it.code],
                  s: s,
                  onChanged: (v) => setState(() => v == null ? _skills.remove(it.code) : _skills[it.code] = v),
                ),
            ],
            const SizedBox(height: 6),
            TextField(
              key: const ValueKey('job-other-docs'),
              controller: _otherDocs,
              maxLength: 300,
              decoration: InputDecoration(labelText: s.t('job_f_other_docs')),
            ),
            Text(s.t('job_declared'), style: TextStyle(fontSize: 12, color: AppColors.textSoft)),
          ]),
          JobSection(title: s.t('job_f_countries'), children: [
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
              Expanded(child: JobNumberField(controller: _salary, label: s.t('job_f_salary'), fieldKey: 'job-salary', maxLength: 7)),
              const SizedBox(width: 10),
              SizedBox(width: 120, child: JobCurrencyField(value: _currency, s: s, onChanged: (v) => setState(() => _currency = v))),
            ]),
            const SizedBox(height: 10),
            JobScheduleField(value: _schedule, s: s, onChanged: (v) => setState(() => _schedule = v)),
            const SizedBox(height: 10),
            TextField(
              key: const ValueKey('job-note'),
              controller: _note,
              maxLength: 1000,
              maxLines: 4,
              minLines: 2,
              decoration: InputDecoration(labelText: s.t('job_f_note')),
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
              title: Text(_active ? s.t('job_seeking_on') : s.t('job_seeking_off')),
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
