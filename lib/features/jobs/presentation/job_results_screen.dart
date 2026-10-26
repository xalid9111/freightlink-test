import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/cities.dart';
import '../../../core/constants/countries.dart';
import '../../../core/localization/app_strings.dart';
import '../../../core/localization/locale_controller.dart';
import '../../../core/router/safe_navigation.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/user_avatar.dart';
import '../../auth/presentation/providers/auth_providers.dart';
import '../data/jobs_repository.dart';
import '../domain/job_match.dart';
import '../domain/job_models.dart';
import 'job_widgets.dart';
import 'jobs_providers.dart';

/// SmartMatch results (owner, 26.10.2026). The driver sees vacancies
/// ("Mənə uyğun işlər" / "Bütün işlər"); the employer sees drivers for one
/// of his vacancies ("Uyğun sürücülər" / "Bütün sürücülər"). The
/// percentage only informs — "Bütün …" always lists everybody.
class JobResultsScreen extends ConsumerStatefulWidget {
  /// true = the employer looks for drivers, false = the driver looks for work.
  final bool employer;
  final String? vacancyId;
  const JobResultsScreen({super.key, required this.employer, this.vacancyId});

  @override
  ConsumerState<JobResultsScreen> createState() => _JobResultsScreenState();
}

class _JobResultsScreenState extends ConsumerState<JobResultsScreen> {
  String? _vacancyId;

  @override
  void initState() {
    super.initState();
    _vacancyId = widget.vacancyId;
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    final c = widget.employer ? jobEmployerColor : jobDriverColor;
    final tabs = widget.employer
        ? [s.t('job_tab_match_drivers'), s.t('job_tab_all_drivers')]
        : [s.t('job_tab_match_jobs'), s.t('job_tab_all_jobs')];
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.employer ? s.t('job_see_drivers') : s.t('job_see_jobs')),
          bottom: TabBar(
            labelColor: c,
            indicatorColor: c,
            tabs: [for (final (i, t) in tabs.indexed) Tab(key: ValueKey('job-tab-$i'), text: t)],
          ),
        ),
        body: widget.employer ? _employerBody(s) : _driverBody(s),
      ),
    );
  }

  Widget _error(AppStrings s, Object e) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(e is JobsNotReady ? s.t('job_not_ready') : s.t('home_error_loading'), textAlign: TextAlign.center),
        ),
      );

  Widget _driverBody(AppStrings s) {
    final me = ref.watch(myJobProfileProvider);
    final all = ref.watch(jobVacanciesProvider);
    final uid = ref.watch(currentUserIdProvider);
    return all.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => _error(s, e),
      data: (list) {
        final vs = list.where((v) => v.ownerId != uid).toList();
        final profile = me.valueOrNull;
        Widget tab(bool only) {
          if (profile == null) {
            return _List(
              header: _Hint(text: s.t('job_need_profile'), button: s.t('job_profile_fill'), route: '/jobs/profile', color: jobDriverColor),
              empty: s.t('job_empty'),
              children: only ? const [] : [for (final v in vs) _VacancyCard(v: v, match: null, s: s)],
            );
          }
          final ranked = rankMatches(vs, (v) => matchJob(profile, v), only: only, updated: (v) => v.updatedAt);
          return _List(
            empty: s.t('job_empty'),
            children: [for (final v in ranked) _VacancyCard(v: v, match: matchJob(profile, v), s: s)],
          );
        }

        return TabBarView(children: [tab(true), tab(false)]);
      },
    );
  }

  Widget _employerBody(AppStrings s) {
    final mine = ref.watch(myVacanciesProvider);
    final all = ref.watch(jobSeekersProvider);
    final uid = ref.watch(currentUserIdProvider);
    return all.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => _error(s, e),
      data: (list) {
        final people = list.where((p) => p.userId != uid).toList();
        final vacancies = (mine.valueOrNull ?? const <JobVacancy>[]).where((v) => v.isActive).toList();
        final vacancy = vacancies.where((v) => v.id == _vacancyId).firstOrNull ?? vacancies.firstOrNull;
        final picker = vacancies.length < 2
            ? null
            : Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: DropdownButtonFormField<String>(
                  key: const ValueKey('job-vacancy-pick'),
                  initialValue: vacancy?.id,
                  decoration: InputDecoration(labelText: s.t('job_for_vacancy')),
                  items: [for (final v in vacancies) DropdownMenuItem(value: v.id, child: Text(v.companyName, overflow: TextOverflow.ellipsis))],
                  onChanged: (id) => setState(() => _vacancyId = id),
                ),
              );
        Widget tab(bool only) {
          if (vacancy == null) {
            return _List(
              header: _Hint(text: s.t('job_need_vacancy'), button: s.t('job_vacancy_new'), route: '/jobs/vacancy/new', color: jobEmployerColor),
              empty: s.t('job_empty'),
              children: only ? const [] : [for (final p in people) _SeekerCard(p: p, match: null, vacancy: null, s: s)],
            );
          }
          final ranked = rankMatches(people, (p) => matchJob(p, vacancy), only: only, updated: (p) => p.updatedAt);
          return _List(
            header: picker,
            empty: s.t('job_empty'),
            children: [for (final p in ranked) _SeekerCard(p: p, match: matchJob(p, vacancy), vacancy: vacancy, s: s)],
          );
        }

        return TabBarView(children: [tab(true), tab(false)]);
      },
    );
  }
}

class _List extends StatelessWidget {
  final Widget? header;
  final List<Widget> children;
  final String empty;
  const _List({this.header, required this.children, required this.empty});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final side = c.maxWidth > 820 ? (c.maxWidth - 780) / 2 : 12.0;
      return ListView(
        padding: EdgeInsets.fromLTRB(side, 12, side, 32),
        children: [
          if (header != null) header!,
          if (children.isEmpty)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Text(empty, textAlign: TextAlign.center, style: TextStyle(color: AppColors.textSoft)),
            ),
          for (final w in children) Padding(padding: const EdgeInsets.only(bottom: 10), child: w),
        ],
      );
    });
  }
}

class _Hint extends StatelessWidget {
  final String text, button, route;
  final Color color;
  const _Hint({required this.text, required this.button, required this.route, required this.color});

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(14)),
        child: Row(children: [
          Expanded(child: Text(text, style: TextStyle(color: AppColors.text))),
          const SizedBox(width: 8),
          FilledButton(
            key: ValueKey('job-hint-$route'),
            style: FilledButton.styleFrom(backgroundColor: color),
            onPressed: () => context.pushOnce(route),
            child: Text(button),
          ),
        ]),
      );
}

String _initials(String name) {
  final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).take(2);
  return parts.isEmpty ? '?' : parts.map((p) => p.characters.first.toUpperCase()).join();
}

String _place(String? city, String? country, String lang) => [
      if (city != null) Cities.label(city, lang),
      if (country != null) Countries.label(country, lang),
    ].join(', ');

String _money(double v) {
  final t = v.round().toString();
  return t.replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ' ');
}

/// A comparison line's text.
String checkLabel(AppStrings s, MatchCheck c, List<JobCatalogItem> specs, List<JobCatalogItem> skills, JobVacancy v, String lang) {
  return switch (c.kind) {
    CheckKind.specialty => '${s.t('job_chk_specialty')}: ${jobCodeLabel(s, 'job_spec_', c.code ?? '', specs)}',
    CheckKind.skill => jobCodeLabel(s, 'job_skill_', c.code ?? '', skills),
    CheckKind.experience => '${s.t('job_chk_experience')}: ${s.t('job_years', {'n': '${v.minExperience}+'})}',
    CheckKind.place => '${s.t('job_chk_place')}: ${Countries.label(v.country ?? '', lang)}',
    CheckKind.city => '${s.t('job_chk_city')}: ${Cities.label(v.city ?? '', lang)}',
    CheckKind.countries => s.t('job_chk_countries'),
    CheckKind.salary => s.t('job_chk_salary'),
    CheckKind.schedule => '${s.t('job_chk_schedule')}: ${s.t('job_sch_${v.schedule}')}',
  };
}

/// Shared frame of a result card: head, facts, the ✓ / ✗ lines (first
/// few, "Ətraflı" for the rest), contacts and the admin's hide / show.
class _ResultCard extends ConsumerStatefulWidget {
  final String cardKey, userId, title;
  final String? subtitle, avatarUrl, phone, adminKind, adminId;
  final bool whatsapp, hidden;
  final List<String> chips;
  final List<String> facts;
  final JobMatch? match;
  final List<Widget> Function(List<MatchCheck>) lines;
  final List<Widget> extra;
  final Color color;
  final AppStrings s;
  const _ResultCard({
    required this.cardKey,
    required this.userId,
    required this.title,
    required this.subtitle,
    required this.avatarUrl,
    required this.phone,
    required this.whatsapp,
    required this.hidden,
    required this.chips,
    required this.facts,
    required this.match,
    required this.lines,
    required this.color,
    required this.s,
    required this.adminKind,
    required this.adminId,
    this.extra = const [],
  });

  @override
  ConsumerState<_ResultCard> createState() => _ResultCardState();
}

class _ResultCardState extends ConsumerState<_ResultCard> {
  bool _open = false;

  Future<void> _setHidden(bool hidden) async {
    try {
      await ref.read(jobsRepositoryProvider).adminSetHidden(widget.adminKind!, widget.adminId!, hidden);
      ref.invalidate(jobSeekersProvider);
      ref.invalidate(jobVacanciesProvider);
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(widget.s.t('job_save_failed'))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.s;
    final checks = widget.match?.checks ?? const <MatchCheck>[];
    final shown = _open ? checks : checks.take(4).toList();
    final isAdmin = ref.watch(currentUserProvider)?.role == 'admin';
    return Container(
      key: ValueKey(widget.cardKey),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: widget.hidden ? AppColors.danger : AppColors.line),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          UserAvatar(imageUrl: widget.avatarUrl, initials: _initials(widget.title), radius: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(widget.title,
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.text)),
              if (widget.subtitle != null && widget.subtitle!.isNotEmpty)
                Text(widget.subtitle!, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: AppColors.textSoft)),
            ]),
          ),
          if (widget.match != null) MatchBadge(percent: widget.match!.percent, s: s),
        ]),
        if (widget.hidden)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(s.t('job_hidden_badge'), style: TextStyle(color: AppColors.danger, fontSize: 12.5)),
          ),
        if (widget.chips.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final c in widget.chips)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: widget.color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
                child: Text(c, style: TextStyle(fontSize: 12.5, color: widget.color)),
              ),
          ]),
        ],
        if (widget.facts.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(widget.facts.join(' · '), style: TextStyle(fontSize: 13.5, color: AppColors.text)),
        ],
        ...widget.extra,
        if (checks.isNotEmpty) ...[
          const SizedBox(height: 8),
          ...widget.lines(shown),
          if (checks.length > 4)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                key: ValueKey('${widget.cardKey}-more'),
                onPressed: () => setState(() => _open = !_open),
                child: Text(_open ? s.t('job_less') : s.t('job_more', {'n': '${checks.length - 4}'})),
              ),
            ),
          Text(s.t('job_declared'), style: TextStyle(fontSize: 11.5, color: AppColors.textSoft)),
        ],
        const SizedBox(height: 8),
        JobContactActions(userId: widget.userId, phone: widget.phone, whatsapp: widget.whatsapp, s: s, color: widget.color),
        if (isAdmin && widget.adminKind != null)
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              key: ValueKey('${widget.cardKey}-admin'),
              onPressed: () => _setHidden(!widget.hidden),
              icon: Icon(widget.hidden ? Icons.visibility_outlined : Icons.visibility_off_outlined, size: 18),
              label: Text(widget.hidden ? s.t('job_show') : s.t('job_hide')),
            ),
          ),
      ]),
    );
  }
}

/// A driver, seen by an employer.
class _SeekerCard extends ConsumerWidget {
  final JobSeeker p;
  final JobMatch? match;
  final JobVacancy? vacancy;
  final AppStrings s;
  const _SeekerCard({required this.p, required this.match, required this.vacancy, required this.s});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lang = ref.watch(currentLocaleProvider).languageCode;
    final specs = ref.watch(jobSpecialtiesProvider).valueOrNull ?? kJobSpecialties;
    final skills = ref.watch(jobSkillsProvider).valueOrNull ?? kJobSkills;
    final has = [for (final k in skills) if (p.skills[k.code] == SkillState.yes) jobLabel(s, 'job_skill_', k)];
    return _ResultCard(
      cardKey: 'job-seeker-${p.userId}',
      userId: p.userId,
      title: p.fullName,
      subtitle: [if (p.age != null) s.t('job_age', {'n': '${p.age}'}), _place(p.city, p.country, lang)].where((x) => x.isNotEmpty).join(' · '),
      avatarUrl: p.avatarUrl,
      phone: p.phone,
      whatsapp: p.whatsapp,
      hidden: p.isHidden,
      chips: [for (final c in p.specialties) jobCodeLabel(s, 'job_spec_', c, specs)],
      facts: [
        if (p.experienceYears != null) '${s.t('job_chk_experience')}: ${s.t('job_years', {'n': '${p.experienceYears}'})}',
        if (p.salaryMin != null) '${s.t('job_chk_salary')}: ${_money(p.salaryMin!)} ${p.currency ?? 'AZN'}',
        if (p.schedule != null) s.t('job_sch_${p.schedule}'),
      ],
      extra: [
        if (match == null && has.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text('✓ ${has.join(' · ')}', style: TextStyle(fontSize: 13, color: AppColors.online)),
          ),
        if (p.note != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(p.note!, maxLines: 3, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: AppColors.textSoft)),
          ),
      ],
      match: match,
      lines: (checks) => [
        for (final c in checks)
          CheckLine(check: c, s: s, label: vacancy == null ? '' : checkLabel(s, c, specs, skills, vacancy!, lang)),
      ],
      color: jobEmployerColor,
      s: s,
      adminKind: 'seeker',
      adminId: p.userId,
    );
  }
}

/// A vacancy, seen by a driver.
class _VacancyCard extends ConsumerWidget {
  final JobVacancy v;
  final JobMatch? match;
  final AppStrings s;
  const _VacancyCard({required this.v, required this.match, required this.s});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lang = ref.watch(currentLocaleProvider).languageCode;
    final specs = ref.watch(jobSpecialtiesProvider).valueOrNull ?? kJobSpecialties;
    final skills = ref.watch(jobSkillsProvider).valueOrNull ?? kJobSkills;
    final cur = v.currency ?? 'AZN';
    final salary = v.salaryMin != null && v.salaryMax != null
        ? '${_money(v.salaryMin!)}–${_money(v.salaryMax!)} $cur'
        : (v.salaryMax ?? v.salaryMin) != null
            ? '${_money((v.salaryMax ?? v.salaryMin)!)} $cur'
            : null;
    final musts = [for (final e in v.requirements.entries) if (e.value == ReqLevel.must) jobCodeLabel(s, 'job_skill_', e.key, skills)];
    return _ResultCard(
      cardKey: 'job-vacancy-${v.id}',
      userId: v.ownerId,
      title: v.companyName,
      subtitle: _place(v.city, v.country, lang),
      avatarUrl: v.avatarUrl,
      phone: v.phone,
      whatsapp: v.whatsapp,
      hidden: v.isHidden,
      chips: [for (final c in v.specialties) jobCodeLabel(s, 'job_spec_', c, specs)],
      facts: [
        if (salary != null) '${s.t('job_chk_salary')}: $salary',
        if (v.schedule != null) s.t('job_sch_${v.schedule}'),
        if (v.minExperience != null && v.minExperience! > 0)
          '${s.t('job_chk_experience')}: ${s.t('job_years', {'n': '${v.minExperience}+'})}',
      ],
      extra: [
        if (match == null && musts.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text('${s.t('job_req_must')}: ${musts.join(' · ')}', style: TextStyle(fontSize: 13, color: AppColors.textSoft)),
          ),
        if (v.conditions != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(v.conditions!, maxLines: 3, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: AppColors.textSoft)),
          ),
      ],
      match: match,
      lines: (checks) => [for (final c in checks) CheckLine(check: c, s: s, label: checkLabel(s, c, specs, skills, v, lang))],
      color: jobDriverColor,
      s: s,
      adminKind: 'vacancy',
      adminId: v.id,
    );
  }
}
