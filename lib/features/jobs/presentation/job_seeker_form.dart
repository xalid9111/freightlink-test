import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/localization/locale_controller.dart';
import '../../auth/presentation/providers/auth_providers.dart';
import '../data/jobs_repository.dart';
import '../domain/job_models.dart';
import 'job_form_kit.dart';
import 'job_form_parts.dart';
import 'jobs_providers.dart';

/// "Sürücü — İş axtarıram" (owner, 28.10.2026, picture 3): my work profile
/// on one page, no Sürücü | Sahibkar switch. A ticked document / category /
/// skill = "has it" (✓); not ticked = not given (never "no"). An answer the
/// form does not show ("no", "ready to obtain") is kept until it is ticked.
/// Fields the picture does not show (place, route, other documents) keep
/// what was saved. "Profilimi dərc et" publishes it (İş axtarıram on).
class JobSeekerFormScreen extends ConsumerWidget {
  const JobSeekerFormScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final me = ref.watch(myJobProfileProvider);
    return Scaffold(
      appBar: AppBar(centerTitle: true, title: Text(s.t('job_center'), style: const TextStyle(fontWeight: FontWeight.w600))),
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

const _documentOrder = ['tachograph', 'cpc', 'adr', 'idp'];
const _licenceOrder = ['lic_b', 'lic_c1', 'lic_c', 'lic_ce', 'lic_d1', 'lic_d', 'lic_c1e', 'lic_d1e', 'lic_de'];
const _transportOrder = ['tent', 'ref', 'container', 'dump', 'open', 'tanker'];

/// The birth date stored for an age picked in the list: 1 January of
/// (this year − age), so the age shown is the one picked and grows by
/// itself every year.
DateTime birthForAge(int age, DateTime now) => DateTime(now.year - age, 1, 1);

class _SeekerForm extends ConsumerStatefulWidget {
  final JobSeeker? initial;
  const _SeekerForm({required this.initial});

  @override
  ConsumerState<_SeekerForm> createState() => _SeekerFormState();
}

class _SeekerFormState extends ConsumerState<_SeekerForm> {
  late final TextEditingController _name, _salary, _note, _phone;
  int? _age, _experience;
  String? _currency;
  late List<String> _schedules;
  late Set<String> _specialties;
  late Map<String, SkillState> _skills;
  late List<String> _countries;
  late bool _negotiable, _whatsapp;
  late JobContactWay _way;
  String? _profilePhone;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final p = widget.initial;
    final user = ref.read(currentUserProvider);
    _profilePhone = user?.phone;
    _name = TextEditingController(text: p?.fullName ?? user?.fullName ?? '');
    _salary = TextEditingController(text: p?.salaryMin == null ? '' : p!.salaryMin!.round().toString());
    _note = TextEditingController(text: p?.note ?? '');
    _phone = TextEditingController(text: p?.phone ?? '');
    _age = p?.birthDate == null ? null : ageOn(p!.birthDate!, DateTime.now());
    _experience = p?.experienceYears;
    _currency = p?.currency;
    _schedules = [...?p?.allSchedules];
    _specialties = {...?p?.specialties};
    _skills = {...?p?.skills};
    _countries = [...?p?.countries];
    _negotiable = p?.salaryNegotiable ?? false;
    _showPhone = p?.showPhone ?? false;
    _whatsapp = p?.whatsapp ?? false;
    _way = jobContactWayOf(showPhone: _showPhone, phone: p?.phone, profilePhone: _profilePhone);
  }

  // Phone hidden by default (owner, 26.10.2026); kept for the tests' guard.
  late bool _showPhone;

  @override
  void dispose() {
    for (final c in [_name, _salary, _note, _phone]) {
      c.dispose();
    }
    super.dispose();
  }

  bool _has(String code) => _skills[code] == SkillState.yes;

  void _tick(String code) => setState(() {
        if (_has(code)) {
          _skills = {..._skills}..remove(code);
        } else {
          _skills = {..._skills, code: SkillState.yes};
        }
      });

  Future<void> _save() async {
    final s = ref.read(stringsProvider);
    final uid = ref.read(currentUserIdProvider);
    if (uid == null) return;
    if (_name.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.t('job_name_required'))));
      return;
    }
    final old = widget.initial;
    final now = DateTime.now();
    final oldAge = old?.birthDate == null ? null : ageOn(old!.birthDate!, now);
    final birth = _age == null ? null : (_age == oldAge ? old!.birthDate : birthForAge(_age!, now));
    final phone = switch (_way) {
      JobContactWay.message => old?.phone,
      JobContactWay.profile => _profilePhone,
      JobContactWay.other => jobText(_phone),
    };
    final show = _way != JobContactWay.message && (phone ?? '').isNotEmpty;
    setState(() => _saving = true);
    final p = JobSeeker(
      userId: uid,
      fullName: _name.text.trim(),
      birthDate: birth,
      country: old?.country,
      city: old?.city,
      experienceYears: _experience,
      specialties: [..._specialties],
      skills: _skills,
      otherDocs: old?.otherDocs,
      countries: _countries,
      routes: old?.routes,
      salaryMin: jobMoney(_salary),
      currency: _currency,
      salaryNegotiable: _negotiable,
      schedule: _schedules.firstOrNull,
      schedules: _schedules,
      note: jobText(_note),
      phone: phone,
      showPhone: show,
      whatsapp: show && _whatsapp,
      isActive: true,
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
    final specs = orderedCatalog(ref.watch(jobSpecialtiesProvider).valueOrNull ?? kJobSpecialties, _transportOrder);
    final skills = ref.watch(jobSkillsProvider).valueOrNull ?? kJobSkills;
    final lics = orderedCatalog(skills.where((k) => k.kind == 'license').toList(), _licenceOrder);
    final docs = orderedCatalog(skills.where((k) => k.kind == 'document').toList(), _documentOrder);
    final soft = skills.where((k) => k.kind == 'skill').toList();
    final ages = {for (var a = 18; a <= 70; a++) a, if (_age != null) _age!}.toList()..sort();
    final years = {for (var y = 0; y <= 40; y++) y, if (_experience != null) _experience!}.toList()..sort();
    final schedules = [...kJobFormSchedules, for (final k in _schedules) if (!kJobFormSchedules.contains(k)) k];
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 40), children: [
          JobFormBanner(
            asset: 'assets/images/jobs/banner_driver.jpg',
            line1: s.t('job_drv_banner_1'),
            line2: s.t('job_drv_banner_2'),
            subtitle: s.t('job_drv_banner_sub'),
          ),
          JobFieldRow(
            icon: Icons.person,
            label: s.t('job_full_name'),
            child: TextField(
              key: const ValueKey('job-name'),
              controller: _name,
              maxLength: 120,
              decoration: const InputDecoration(isDense: true, counterText: ''),
            ),
          ),
          JobFieldRow(
            icon: Icons.calendar_month_outlined,
            label: s.t('job_detail_age'),
            child: JobDropdown<int>(
              fieldKey: 'job-age',
              value: _age,
              items: [(null, '—'), for (final a in ages) (a, '$a')],
              onChanged: (v) => setState(() => _age = v),
            ),
          ),
          JobFieldRow(
            icon: Icons.bar_chart_rounded,
            label: s.t('job_chk_experience'),
            child: JobDropdown<int>(
              fieldKey: 'job-experience',
              value: _experience,
              items: [(null, '—'), for (final y in years) (y, s.t('job_years', {'n': '$y'}))],
              onChanged: (v) => setState(() => _experience = v),
            ),
          ),
          JobBlock(
            icon: Icons.local_shipping_outlined,
            label: s.t('job_detail_transport'),
            child: JobTransportRow(items: specs, selected: _specialties, s: s, lang: lang, onChanged: (v) => setState(() => _specialties = v)),
          ),
          JobBlock(
            icon: Icons.badge_outlined,
            label: s.t('job_detail_licence'),
            child: JobLicenceBoxes(
              items: lics,
              selected: {for (final k in lics) if (_has(k.code)) k.code},
              onTap: _tick,
            ),
          ),
          JobBlock(
            icon: Icons.description_outlined,
            label: s.t('job_my_documents'),
            child: JobTickGrid(items: [for (final d in docs) (d.code, jobShortLabel(s, d))], checked: _has, onTap: _tick),
          ),
          JobBlock(
            icon: Icons.star_outline,
            label: s.t('job_my_skills'),
            child: JobTickGrid(
              keyPrefix: 'job-skill',
              items: [for (final k in soft) (k.code, jobShortLabel(s, k))],
              checked: _has,
              onTap: _tick,
            ),
          ),
          JobBlock(
            icon: Icons.public,
            label: s.t('job_work_countries'),
            hint: s.t('job_pick_one_or_more'),
            child: JobCountryTiles(selected: _countries, lang: lang, s: s, onChanged: (v) => setState(() => _countries = v)),
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
            label: s.t('job_salary_wish'),
            child: JobSalaryRow(
              min: _salary,
              currency: _currency,
              negotiable: _negotiable,
              s: s,
              onCurrency: (v) => setState(() => _currency = v),
              onNegotiable: (v) => setState(() => _negotiable = v),
            ),
          ),
          JobFieldRow(
            icon: Icons.sticky_note_2_outlined,
            label: s.t('job_detail_extra'),
            child: TextField(
              key: const ValueKey('job-note'),
              controller: _note,
              maxLength: math.max(1000, _note.text.length),
              minLines: 2,
              maxLines: 5,
              decoration: InputDecoration(hintText: s.t('job_note_hint'), isDense: true, counterText: ''),
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
          JobSubmitButton(buttonKey: 'job-save', label: s.t('job_publish_profile'), busy: _saving, onPressed: _save),
        ]),
      ),
    );
  }
}
