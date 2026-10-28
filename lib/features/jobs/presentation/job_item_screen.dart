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
import '../domain/job_feed.dart';
import '../domain/job_match.dart';
import '../domain/job_models.dart';
import 'job_feed_widgets.dart';
import 'job_results_screen.dart' show checkLabel;
import 'job_widgets.dart';
import 'jobs_providers.dart';

/// The page of one ad from "Aktiv elanlar" (owner, 28.10.2026): everything
/// the ad says, the contacts its owner allowed (the phone only when shown —
/// the server decides) and the SmartMatch lines against my own profile /
/// vacancy. /jobs/v/:id (vacancy) · /jobs/d/:id (driver).
class JobItemScreen extends ConsumerWidget {
  final bool vacancy;
  final String id;
  const JobItemScreen({super.key, required this.vacancy, required this.id});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final list = vacancy ? ref.watch(jobVacanciesProvider) : ref.watch(jobSeekersProvider);
    return Scaffold(
      appBar: AppBar(title: Text(s.t('job_detail_title'))),
      body: list.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(e is JobsNotReady ? s.t('job_not_ready') : s.t('home_error_loading'), textAlign: TextAlign.center),
          ),
        ),
        data: (rows) {
          final JobFeedItem? item = vacancy
              ? (rows as List<JobVacancy>).where((v) => v.id == id).map(JobFeedItem.vacancy).firstOrNull
              : (rows as List<JobSeeker>).where((p) => p.userId == id).map(JobFeedItem.seeker).firstOrNull;
          if (item == null) return Center(child: Text(s.t('job_empty')));
          return _Body(item: item, s: s);
        },
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  final JobFeedItem item;
  final AppStrings s;
  const _Body({required this.item, required this.s});

  Future<void> _setHidden(BuildContext context, WidgetRef ref, bool hidden) async {
    try {
      await ref.read(jobsRepositoryProvider).adminSetHidden(item.isVacancy ? 'vacancy' : 'seeker', item.id, hidden);
      ref.invalidate(jobSeekersProvider);
      ref.invalidate(jobVacanciesProvider);
    } catch (_) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.t('job_save_failed'))));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lang = ref.watch(currentLocaleProvider).languageCode;
    final specs = ref.watch(jobSpecialtiesProvider).valueOrNull ?? kJobSpecialties;
    final skills = ref.watch(jobSkillsProvider).valueOrNull ?? kJobSkills;
    final me = ref.watch(currentUserIdProvider);
    final isAdmin = ref.watch(currentUserProvider)?.role == 'admin';
    final own = item.ownerId == me;
    final c = item.isVacancy ? AppColors.accent : AppColors.blue;
    final kind = {for (final k in skills) k.code: k.kind};
    String names(Iterable<String> codes, String prefix, List<JobCatalogItem> cat) =>
        [for (final x in codes) jobCodeLabel(s, prefix, x, cat)].join(', ');

    // What the ad says.
    final v = item.vacancy, p = item.seeker;
    final skillCodes = v != null
        ? v.requirements.keys.toList()
        : [for (final e in p!.skills.entries) if (e.value == SkillState.yes) e.key];
    final docs = [for (final x in skillCodes) if (kind[x] == 'document') x];
    final soft = [for (final x in skillCodes) if (kind[x] == 'skill') x];
    final place = [
      if ((v?.city ?? p?.city) != null) Cities.label((v?.city ?? p?.city)!, lang),
      if ((v?.country ?? p?.country) != null) Countries.label((v?.country ?? p?.country)!, lang),
    ].join(', ');
    final schedule = v?.schedule ?? p?.schedule;
    final note = v?.conditions ?? p?.note;
    final rows = <(IconData, String, String?)>[
      (Icons.local_shipping_outlined, s.t('job_detail_transport'),
          item.specialties.isEmpty ? null : names(item.specialties, 'job_spec_', specs)),
      (Icons.badge_outlined, s.t('job_detail_licence'), item.licences.isEmpty ? null : names(item.licences, 'job_lic_', skills)),
      (Icons.description_outlined, s.t('job_detail_docs'), docs.isEmpty ? null : names(docs, 'job_skill_', skills)),
      (Icons.star_outline, s.t('job_detail_skills'), soft.isEmpty ? null : names(soft, 'job_skill_', skills)),
      (Icons.bar_chart_rounded, s.t('job_chk_experience'),
          (item.experience ?? 0) > 0 ? s.t('job_exp_years', {'n': '${item.experience}'}) : null),
      (Icons.cake_outlined, s.t('job_detail_age'), p?.age == null ? null : s.t('job_age', {'n': '${p!.age}'})),
      (Icons.public, s.t('job_detail_countries'),
          item.countries.isEmpty ? null : [for (final x in item.countries) Countries.label(x, lang)].join(', ')),
      (Icons.alt_route, s.t('job_detail_route'), v?.routes ?? p?.routes),
      (Icons.place_outlined, s.t('job_detail_place'), place.isEmpty ? null : place),
      (Icons.payments_outlined, s.t('job_detail_salary'), jobFeedSalary(item)),
      (Icons.schedule, s.t('job_detail_schedule'), schedule == null ? null : s.t('job_sch_$schedule')),
      (Icons.notes, s.t('job_detail_extra'), note),
    ];

    // SmartMatch against my side.
    JobMatch? match;
    JobVacancy? against;
    if (!own) {
      if (v != null) {
        final mine = ref.watch(myJobProfileProvider).valueOrNull;
        if (mine != null) {
          match = matchJob(mine, v);
          against = v;
        }
      } else {
        for (final mv in (ref.watch(myVacanciesProvider).valueOrNull ?? const <JobVacancy>[]).where((x) => x.isActive)) {
          final m = matchJob(p!, mv);
          if (match == null || (m.percent ?? -1) > (match.percent ?? -1)) {
            match = m;
            against = mv;
          }
        }
      }
    }

    final name = v?.companyName ?? p!.fullName;
    final avatar = v?.avatarUrl ?? p?.avatarUrl;
    final initials = name.trim().isEmpty ? '?' : name.trim().characters.first.toUpperCase();
    Widget section(String title, List<Widget> children, {Key? key}) => Container(
          key: key,
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.line),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.text)),
            const SizedBox(height: 8),
            ...children,
          ]),
        );

    return LayoutBuilder(builder: (context, box) {
      final side = box.maxWidth > 820 ? (box.maxWidth - 780) / 2 : 16.0;
      return ListView(padding: EdgeInsets.fromLTRB(side, 14, side, 32), children: [
        Row(children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(color: c.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(15)),
            child: Icon(item.isVacancy ? Icons.work : Icons.local_shipping, color: c, size: 28),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(jobFeedTitle(s, item, specs),
                key: const ValueKey('job-item-title'),
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: AppColors.text)),
          ),
          if (match != null) MatchBadge(percent: match.percent, s: s),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          UserAvatar(imageUrl: avatar, initials: initials, radius: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(name,
                maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 16, color: AppColors.text)),
          ),
        ]),
        if ((v?.isHidden ?? p!.isHidden))
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(s.t('job_hidden_badge'), style: TextStyle(color: AppColors.danger)),
          ),
        const SizedBox(height: 14),
        section(s.t('job_detail_info'), key: const ValueKey('job-item-info'), [
          for (final r in rows)
            if (r.$3 != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(r.$1, size: 19, color: AppColors.textSoft),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text.rich(TextSpan(children: [
                      TextSpan(text: '${r.$2}: ', style: TextStyle(color: AppColors.textSoft)),
                      TextSpan(text: r.$3, style: TextStyle(color: AppColors.text)),
                    ])),
                  ),
                ]),
              ),
        ]),
        if (own)
          section(s.t('job_detail_own'), [
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.icon(
                key: const ValueKey('job-item-edit'),
                style: FilledButton.styleFrom(backgroundColor: c),
                onPressed: () => context.pushOnce(item.isVacancy ? '/jobs/vacancy/${item.id}' : '/jobs/profile'),
                icon: const Icon(Icons.edit_outlined),
                label: Text(item.isVacancy ? s.t('job_vacancy_edit') : s.t('job_profile_edit')),
              ),
            ),
          ])
        else
          section(s.t('job_detail_contact'), key: const ValueKey('job-item-contact'), [
            JobContactActions(
                userId: item.ownerId, phone: v?.phone ?? p?.phone, whatsapp: v?.whatsapp ?? p!.whatsapp, s: s, color: c),
            const SizedBox(height: 6),
            Text(s.t('job_detail_contact_hint'), style: TextStyle(fontSize: 12, color: AppColors.textSoft)),
          ]),
        if (match != null && match.checks.isNotEmpty && against != null)
          section('SmartMatch', key: const ValueKey('job-item-match'), [
            for (final ch in match.checks) CheckLine(check: ch, s: s, label: checkLabel(s, ch, specs, skills, against, lang)),
            const SizedBox(height: 4),
            Text(s.t('job_declared'), style: TextStyle(fontSize: 11.5, color: AppColors.textSoft)),
          ]),
        if (isAdmin)
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              key: const ValueKey('job-item-admin'),
              onPressed: () => _setHidden(context, ref, !(v?.isHidden ?? p!.isHidden)),
              icon: Icon((v?.isHidden ?? p!.isHidden) ? Icons.visibility_outlined : Icons.visibility_off_outlined, size: 18),
              label: Text((v?.isHidden ?? p!.isHidden) ? s.t('job_show') : s.t('job_hide')),
            ),
          ),
      ]);
    });
  }
}
