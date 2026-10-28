import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/countries.dart';
import '../../../core/localization/app_strings.dart';
import '../../../core/localization/locale_controller.dart';
import '../../../core/router/safe_navigation.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/country_picker.dart';
import '../../auth/presentation/providers/auth_providers.dart';
import '../data/jobs_repository.dart';
import '../domain/job_applications.dart';
import '../domain/job_feed.dart';
import '../domain/job_models.dart';
import 'job_feed_widgets.dart';
import 'job_widgets.dart';
import 'jobs_providers.dart';

/// İş Mərkəzi home (owner, 28.10.2026, picture 1): the orange "Sürücü" and
/// blue "Sahibkar" cards, "Uyğun təkliflər" (SmartMatch), my own ads
/// (edit, on / off, delete — kept from 26.10.2026) and "Aktiv elanlar":
/// vacancies and drivers in one list with a filter.
class JobCenterScreen extends ConsumerStatefulWidget {
  const JobCenterScreen({super.key});

  @override
  ConsumerState<JobCenterScreen> createState() => _JobCenterScreenState();
}

class _JobCenterScreenState extends ConsumerState<JobCenterScreen> {
  JobFeedFilter _filter = const JobFeedFilter();

  Future<void> _openFilter() async {
    final s = ref.read(stringsProvider);
    final f = await showModalBottomSheet<JobFeedFilter>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _FilterSheet(initial: _filter, s: s),
    );
    if (f != null) setState(() => _filter = f);
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: Text(s.t('job_center'), style: const TextStyle(fontWeight: FontWeight.w600)),
        actions: [
          _NoticeBell(s: s),
          IconButton(
            key: const ValueKey('job-filter-top'),
            tooltip: s.t('job_filter'),
            onPressed: _openFilter,
            icon: Badge(isLabelVisible: _filter.count > 0, label: Text('${_filter.count}'), child: const Icon(Icons.tune)),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(myJobProfileProvider);
          ref.invalidate(myVacanciesProvider);
          ref.invalidate(jobVacanciesProvider);
          ref.invalidate(jobSeekersProvider);
          ref.invalidate(myApplicationsProvider);
          ref.invalidate(jobNoticesProvider);
        },
        child: LayoutBuilder(builder: (context, c) {
          final side = c.maxWidth > 820 ? (c.maxWidth - 780) / 2 : 16.0;
          return ListView(
            padding: EdgeInsets.fromLTRB(side, 12, side, 32),
            children: [
              IntrinsicHeight(
                  child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Expanded(
                  child: _RoleCard(
                    cardKey: 'job-home-driver',
                    color: jobDriverColor,
                    icon: Icons.local_shipping,
                    title: s.t('job_home_driver'),
                    subtitle: s.t('job_home_driver_sub'),
                    onTap: () => context.pushOnce('/jobs/profile'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _RoleCard(
                    cardKey: 'job-home-employer',
                    color: jobEmployerColor,
                    icon: Icons.work,
                    title: s.t('job_home_employer'),
                    subtitle: s.t('job_home_employer_sub'),
                    onTap: () => context.pushOnce('/jobs/vacancy/new'),
                  ),
                ),
              ])),
              const SizedBox(height: 14),
              _Suggestions(s: s),
              _MyAds(s: s),
              const SizedBox(height: 18),
              Row(children: [
                Expanded(
                  child: Text(s.t('job_active_ads'),
                      style: TextStyle(fontSize: 21, fontWeight: FontWeight.w600, color: AppColors.text)),
                ),
                TextButton.icon(
                  key: const ValueKey('job-filter'),
                  style: TextButton.styleFrom(foregroundColor: AppColors.blue),
                  onPressed: _openFilter,
                  iconAlignment: IconAlignment.end,
                  icon: const Icon(Icons.tune),
                  label: Text(_filter.count > 0 ? '${s.t('job_filter')} (${_filter.count})' : s.t('job_filter'),
                      style: const TextStyle(fontSize: 15.5)),
                ),
              ]),
              const SizedBox(height: 8),
              _Feed(s: s, filter: _filter, onReset: () => setState(() => _filter = const JobFeedFilter())),
            ],
          );
        }),
      ),
    );
  }
}

/// "Sürücü — Profil / Elan ver" (orange) · "Sahibkar — Vakansiya yerləşdir"
/// (blue), as in the picture.
class _RoleCard extends StatelessWidget {
  final String cardKey, title, subtitle;
  final Color color;
  final IconData icon;
  final VoidCallback onTap;
  const _RoleCard(
      {required this.cardKey, required this.color, required this.icon, required this.title, required this.subtitle, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final light = Color.lerp(color, Colors.white, 0.18)!;
    return Material(
      color: Colors.transparent,
      child: Ink(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [light, color]),
        ),
        child: InkWell(
          key: ValueKey(cardKey),
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 16, 12, 16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Icon(icon, color: Colors.white, size: 30),
              const SizedBox(height: 8),
              Text(title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w600, color: Colors.white)),
              const SizedBox(height: 2),
              Row(children: [
                Expanded(
                  child: Text(subtitle,
                      maxLines: 2, style: TextStyle(fontSize: 13.5, color: Colors.white.withValues(alpha: 0.92))),
                ),
                const SizedBox(width: 6),
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.28), shape: BoxShape.circle),
                  child: const Icon(Icons.chevron_right, color: Colors.white),
                ),
              ]),
            ]),
          ),
        ),
      ),
    );
  }
}

/// "Uyğun təkliflər" — SmartMatch over my driver profile and my vacancies.
class _Suggestions extends ConsumerWidget {
  final AppStrings s;
  const _Suggestions({required this.s});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lang = ref.watch(currentLocaleProvider).languageCode;
    final specs = ref.watch(jobSpecialtiesProvider).valueOrNull ?? kJobSpecialties;
    final skills = ref.watch(jobSkillsProvider).valueOrNull ?? kJobSkills;
    final list = jobSuggestions(
      me: ref.watch(currentUserIdProvider),
      myProfile: ref.watch(myJobProfileProvider).valueOrNull,
      myVacancies: ref.watch(myVacanciesProvider).valueOrNull ?? const [],
      vacancies: ref.watch(jobVacanciesProvider).valueOrNull ?? const [],
      seekers: ref.watch(jobSeekersProvider).valueOrNull ?? const [],
    );
    return Container(
      key: const ValueKey('job-suggestions'),
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 6),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Icon(Icons.auto_awesome, color: AppColors.blue, size: 26),
          const SizedBox(width: 10),
          Expanded(
            child: Text(s.t('job_suggest_title'),
                style: TextStyle(fontSize: 19, fontWeight: FontWeight.w600, color: AppColors.text)),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.blue.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.blue.withValues(alpha: 0.35)),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.track_changes, size: 16, color: AppColors.blue),
              const SizedBox(width: 5),
              Text('SmartMatch', style: TextStyle(fontSize: 13, color: AppColors.blue, fontWeight: FontWeight.w500)),
            ]),
          ),
        ]),
        const SizedBox(height: 10),
        if (list.isEmpty)
          Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 8),
              child: Text(s.t('job_suggest_empty'), style: TextStyle(fontSize: 15, color: AppColors.textSoft)))
        else
          for (final m in list)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: JobFeedCard(item: m.item, match: m.match, s: s, lang: lang, specs: specs, skills: skills),
            ),
      ]),
    );
  }
}

/// My own ads — kept from 26.10.2026: my driver profile (on / off, edit,
/// jobs for me) and my vacancies (on / off, edit, drivers, delete).
class _MyAds extends ConsumerWidget {
  final AppStrings s;
  const _MyAds({required this.s});

  Future<void> _seeking(BuildContext context, WidgetRef ref, bool on) async {
    try {
      await ref.read(jobsRepositoryProvider).setSeeking(on);
    } catch (_) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.t('job_save_failed'))));
    }
    ref.invalidate(myJobProfileProvider);
    ref.invalidate(jobSeekersProvider);
  }

  Future<void> _vacancyActive(BuildContext context, WidgetRef ref, JobVacancy v, bool on) async {
    try {
      await ref.read(jobsRepositoryProvider).setVacancyActive(v.id, on);
    } catch (_) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.t('job_save_failed'))));
    }
    ref.invalidate(myVacanciesProvider);
    ref.invalidate(jobVacanciesProvider);
  }

  Future<void> _delete(BuildContext context, WidgetRef ref, JobVacancy v) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.t('job_vacancy_delete_q')),
        content: Text(s.t('job_vacancy_delete_body')),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: Text(s.t('common_cancel'))),
          TextButton(
            key: const ValueKey('job-vacancy-delete-ok'),
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(s.t('job_vacancy_delete')),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(jobsRepositoryProvider).deleteVacancy(v.id);
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.t('job_vacancy_deleted'))));
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e is JobsNotReady ? s.t('job_not_ready') : s.t('job_save_failed'))));
      }
    }
    ref.invalidate(myVacanciesProvider);
    ref.invalidate(jobVacanciesProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(myJobProfileProvider);
    final vacancies = ref.watch(myVacanciesProvider);
    final specs = ref.watch(jobSpecialtiesProvider).valueOrNull ?? kJobSpecialties;
    final p = profile.valueOrNull;
    final vs = vacancies.valueOrNull ?? const <JobVacancy>[];
    final notReady = profile.error is JobsNotReady || vacancies.error is JobsNotReady;
    if (notReady) {
      return Padding(
        padding: const EdgeInsets.only(top: 14),
        child: Text(s.t('job_not_ready'), textAlign: TextAlign.center, style: TextStyle(color: AppColors.textSoft)),
      );
    }
    final apps = ref.watch(myApplicationsProvider).valueOrNull ?? const <JobApplication>[];
    if (p == null && vs.isEmpty && apps.isEmpty) return const SizedBox.shrink();
    final me = ref.watch(currentUserIdProvider) ?? '';
    final openApps = apps.where((a) => a.isOpen).length;
    final newApps = apps.where((a) => a.status == 'sent' && a.incomingFor(me)).length;
    final dc = jobDriverColor, ec = jobEmployerColor;
    TextButton action(String key, Color c, IconData icon, String label, VoidCallback onTap) => TextButton.icon(
          key: ValueKey(key),
          style: TextButton.styleFrom(foregroundColor: c, visualDensity: VisualDensity.compact),
          onPressed: onTap,
          icon: Icon(icon, size: 18),
          label: Text(label),
        );
    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: Column(key: const ValueKey('job-my-ads'), crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(s.t('job_my_ads'), style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: AppColors.text)),
        const SizedBox(height: 8),
        // PR 2: applications and job offers, with the new ones counted.
        Material(
          color: AppColors.card,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: AppColors.line)),
          child: ListTile(
            key: const ValueKey('job-apps-open'),
            leading: Icon(Icons.assignment_ind_outlined, color: AppColors.blue),
            title: Text(s.t('job_apps_title'), style: TextStyle(color: AppColors.text)),
            subtitle: Text(s.t('job_apps_count', {'n': '$openApps'}), style: TextStyle(fontSize: 12.5, color: AppColors.textSoft)),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              if (newApps > 0)
                Badge(key: const ValueKey('job-apps-new'), label: Text('$newApps'), backgroundColor: AppColors.danger),
              Icon(Icons.chevron_right, color: AppColors.textSoft),
            ]),
            onTap: () => context.pushOnce('/jobs/applications'),
          ),
        ),
        const SizedBox(height: 8),
        if (p != null)
          _MyRow(
            rowKey: 'my-profile',
            color: dc,
            icon: Icons.local_shipping,
            title: p.fullName,
            subtitle: [for (final c in p.specialties) jobCodeLabel(s, 'job_spec_', c, specs)].join(' · '),
            status: p.isActive ? s.t('job_seeking_on') : s.t('job_seeking_off'),
            active: p.isActive,
            hidden: p.isHidden,
            s: s,
            toggle: Switch(
              key: const ValueKey('job-seeking-switch'),
              value: p.isActive,
              activeThumbColor: dc,
              onChanged: (on) => _seeking(context, ref, on),
            ),
            actions: [
              action('job-profile-open', dc, Icons.edit_outlined, s.t('job_profile_edit'), () => context.pushOnce('/jobs/profile')),
              action('job-see-jobs', dc, Icons.work_outline, s.t('job_see_jobs'), () => context.pushOnce('/jobs/work')),
            ],
          ),
        for (final v in vs)
          _MyRow(
            rowKey: 'my-vacancy-${v.id}',
            color: ec,
            icon: Icons.work,
            title: v.companyName,
            subtitle: [for (final c in v.specialties) jobCodeLabel(s, 'job_spec_', c, specs)].join(' · '),
            status: v.isActive ? s.t('job_vacancy_active') : s.t('job_vacancy_closed'),
            active: v.isActive,
            hidden: v.isHidden,
            s: s,
            toggle: Switch(
              key: ValueKey('job-vacancy-switch-${v.id}'),
              value: v.isActive,
              activeThumbColor: ec,
              onChanged: (on) => _vacancyActive(context, ref, v, on),
            ),
            actions: [
              action('job-vacancy-edit-${v.id}', ec, Icons.edit_outlined, s.t('job_vacancy_edit'),
                  () => context.pushOnce('/jobs/vacancy/${v.id}')),
              action('job-vacancy-match-${v.id}', ec, Icons.people_alt_outlined, s.t('job_see_drivers'),
                  () => context.pushOnce('/jobs/drivers?vacancy=${v.id}')),
              action('job-vacancy-delete-${v.id}', AppColors.danger, Icons.delete_outline, s.t('job_vacancy_delete'),
                  () => _delete(context, ref, v)),
            ],
          ),
      ]),
    );
  }
}

class _MyRow extends StatelessWidget {
  final String rowKey, title, subtitle, status;
  final Color color;
  final IconData icon;
  final bool active, hidden;
  final Widget toggle;
  final List<Widget> actions;
  final AppStrings s;
  const _MyRow({
    required this.rowKey,
    required this.color,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.status,
    required this.active,
    required this.hidden,
    required this.toggle,
    required this.actions,
    required this.s,
  });

  @override
  Widget build(BuildContext context) => Container(
        key: ValueKey(rowKey),
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.fromLTRB(12, 10, 6, 4),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.45)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title,
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w500, color: AppColors.text)),
                if (subtitle.isNotEmpty)
                  Text(subtitle,
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, color: AppColors.textSoft)),
                Text(status, style: TextStyle(fontSize: 12.5, color: active ? AppColors.online : AppColors.textSoft)),
                if (hidden) Text(s.t('job_hidden_badge'), style: TextStyle(fontSize: 12.5, color: AppColors.danger)),
              ]),
            ),
            toggle,
          ]),
          Wrap(spacing: 2, children: actions),
        ]),
      );
}

/// "Aktiv elanlar": vacancies and drivers together, newest first.
class _Feed extends ConsumerWidget {
  final AppStrings s;
  final JobFeedFilter filter;
  final VoidCallback onReset;
  const _Feed({required this.s, required this.filter, required this.onReset});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lang = ref.watch(currentLocaleProvider).languageCode;
    final specs = ref.watch(jobSpecialtiesProvider).valueOrNull ?? kJobSpecialties;
    final skills = ref.watch(jobSkillsProvider).valueOrNull ?? kJobSkills;
    final vs = ref.watch(jobVacanciesProvider);
    final ps = ref.watch(jobSeekersProvider);
    final err = vs.error ?? ps.error;
    if (err != null) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Text(err is JobsNotReady ? s.t('job_not_ready') : s.t('home_error_loading'),
            textAlign: TextAlign.center, style: TextStyle(color: AppColors.textSoft)),
      );
    }
    if (vs.isLoading || ps.isLoading) {
      return const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()));
    }
    final items = buildJobFeed(vs.value ?? const [], ps.value ?? const [], filter: filter);
    if (items.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Column(children: [
          Text(filter.count > 0 ? s.t('job_feed_none') : s.t('job_feed_empty'),
              textAlign: TextAlign.center, style: TextStyle(color: AppColors.textSoft)),
          if (filter.count > 0) TextButton(onPressed: onReset, child: Text(s.t('job_filter_reset'))),
        ]),
      );
    }
    return Column(key: const ValueKey('job-feed'), children: [
      for (final it in items)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: JobFeedCard(item: it, s: s, lang: lang, specs: specs, skills: skills),
        ),
    ]);
  }
}

/// Filter: what (all / vacancies / drivers), transport, licence, country.
class _FilterSheet extends ConsumerStatefulWidget {
  final JobFeedFilter initial;
  final AppStrings s;
  const _FilterSheet({required this.initial, required this.s});

  @override
  ConsumerState<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends ConsumerState<_FilterSheet> {
  late JobFeedKind _kind = widget.initial.kind;
  late String? _spec = widget.initial.specialty;
  late String? _lic = widget.initial.licence;
  late String? _country = widget.initial.country;

  @override
  Widget build(BuildContext context) {
    final s = widget.s;
    final lang = ref.watch(currentLocaleProvider).languageCode;
    final specs = ref.watch(jobSpecialtiesProvider).valueOrNull ?? kJobSpecialties;
    final skills = ref.watch(jobSkillsProvider).valueOrNull ?? kJobSkills;
    final lics = [for (final k in skills) if (k.kind == 'license') k];
    Widget chip(String key, String label, bool on, VoidCallback tap) => ChoiceChip(
          key: ValueKey(key),
          label: Text(label),
          selected: on,
          selectedColor: AppColors.blue.withValues(alpha: 0.18),
          side: BorderSide(color: on ? AppColors.blue : AppColors.line),
          onSelected: (_) => tap(),
        );
    Widget title(String t) => Padding(
          padding: const EdgeInsets.only(top: 14, bottom: 8),
          child: Text(t, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.text)),
        );
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
            Text(s.t('job_filter'), style: TextStyle(fontSize: 19, fontWeight: FontWeight.w600, color: AppColors.text)),
            title(s.t('job_filter_what')),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final (k, label) in [
                (JobFeedKind.all, s.t('job_filter_all')),
                (JobFeedKind.vacancies, s.t('job_filter_vacancies')),
                (JobFeedKind.drivers, s.t('job_filter_drivers')),
              ])
                chip('job-f-kind-${k.name}', label, _kind == k, () => setState(() => _kind = k)),
            ]),
            title(s.t('job_detail_transport')),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final it in specs)
                chip('job-f-spec-${it.code}', jobLabel(s, 'job_spec_', it), _spec == it.code,
                    () => setState(() => _spec = _spec == it.code ? null : it.code)),
            ]),
            title(s.t('job_detail_licence')),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final it in lics)
                chip('job-f-lic-${it.code}', it.name, _lic == it.code, () => setState(() => _lic = _lic == it.code ? null : it.code)),
            ]),
            title(s.t('job_filter_country')),
            Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
              ActionChip(
                key: const ValueKey('job-f-country'),
                avatar: const Icon(Icons.public, size: 18),
                label: Text(_country == null ? s.t('job_filter_any_country') : Countries.label(_country!, lang)),
                onPressed: () async {
                  final picked = await showModalBottomSheet<Country>(
                    context: context,
                    isScrollControlled: true,
                    useSafeArea: true,
                    builder: (_) => CountryPickerSheet(languageCode: lang, strings: s),
                  );
                  if (picked != null) setState(() => _country = picked.en);
                },
              ),
              if (_country != null) IconButton(onPressed: () => setState(() => _country = null), icon: const Icon(Icons.close)),
            ]),
            const SizedBox(height: 20),
            Row(children: [
              Expanded(
                child: OutlinedButton(
                  key: const ValueKey('job-f-reset'),
                  onPressed: () => Navigator.of(context).pop(const JobFeedFilter()),
                  child: Text(s.t('job_filter_reset')),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: FilledButton(
                  key: const ValueKey('job-f-apply'),
                  style: FilledButton.styleFrom(backgroundColor: AppColors.blue),
                  onPressed: () => Navigator.of(context)
                      .pop(JobFeedFilter(kind: _kind, specialty: _spec, licence: _lic, country: _country)),
                  child: Text(s.t('job_filter_apply')),
                ),
              ),
            ]),
          ]),
        ),
      ),
    );
  }
}

/// The bell: İş Mərkəzi notices, the unread ones counted.
class _NoticeBell extends ConsumerWidget {
  final AppStrings s;
  const _NoticeBell({required this.s});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unread = (ref.watch(jobNoticesProvider).valueOrNull ?? const <JobNotice>[]).where((n) => !n.isRead).length;
    return IconButton(
      key: const ValueKey('job-bell'),
      tooltip: s.t('job_ntf_title'),
      onPressed: () async {
        await context.pushOnce('/jobs/notifications');
        ref.invalidate(jobNoticesProvider);
      },
      icon: Badge(
        isLabelVisible: unread > 0,
        label: Text(unread > 99 ? '99+' : '$unread'),
        backgroundColor: AppColors.danger,
        child: const Icon(Icons.notifications_none),
      ),
    );
  }
}
