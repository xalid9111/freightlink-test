import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/localization/app_strings.dart';
import '../../../core/localization/locale_controller.dart';
import '../../../core/router/safe_navigation.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/user_avatar.dart';
import '../../auth/presentation/providers/auth_providers.dart';
import '../data/jobs_repository.dart';
import '../domain/job_applications.dart';
import '../domain/job_feed.dart';
import '../domain/job_models.dart';
import 'job_feed_widgets.dart';
import 'job_widgets.dart';
import 'jobs_providers.dart';

/// "Müraciətlər və təkliflər" (owner, 28.10.2026, PR 2): every
/// application I sent or got and every job offer, with its status. Hired
/// only when both sides confirm (the server decides). Opening the page
/// marks what came to me as "Baxıldı".
class JobApplicationsScreen extends ConsumerStatefulWidget {
  const JobApplicationsScreen({super.key});

  @override
  ConsumerState<JobApplicationsScreen> createState() => _JobApplicationsScreenState();
}

class _JobApplicationsScreenState extends ConsumerState<JobApplicationsScreen> {
  bool _markedSeen = false;

  Future<void> _markSeen(List<JobApplication> list, String uid) async {
    if (_markedSeen) return;
    _markedSeen = true;
    final repo = ref.read(jobsRepositoryProvider);
    var changed = false;
    for (final a in list.where((a) => a.status == 'sent' && a.incomingFor(uid))) {
      try {
        await repo.setApplicationStatus(a.id, 'seen');
        changed = true;
      } catch (_) {}
    }
    if (changed && mounted) ref.invalidate(myApplicationsProvider);
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    final uid = ref.watch(currentUserIdProvider) ?? '';
    final apps = ref.watch(myApplicationsProvider);
    return Scaffold(
      appBar: AppBar(title: Text(s.t('job_apps_title'))),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(myApplicationsProvider),
        child: apps.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ListView(children: [
            Padding(
              padding: const EdgeInsets.all(24),
              child: Text(e is JobsNotReady ? s.t('job_not_ready') : s.t('home_error_loading'), textAlign: TextAlign.center),
            ),
          ]),
          data: (list) {
            WidgetsBinding.instance.addPostFrameCallback((_) => _markSeen(list, uid));
            final sorted = sortApplications(list);
            final ids = {for (final a in sorted) a.otherOf(uid)}.toList()..sort();
            return LayoutBuilder(builder: (context, c) {
              final side = c.maxWidth > 820 ? (c.maxWidth - 780) / 2 : 16.0;
              return ListView(padding: EdgeInsets.fromLTRB(side, 12, side, 32), children: [
                if (sorted.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(s.t('job_apps_empty'), textAlign: TextAlign.center, style: TextStyle(color: AppColors.textSoft)),
                  ),
                for (final a in sorted)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _AppCard(a: a, uid: uid, s: s, peopleKey: ids.join(',')),
                  ),
              ]);
            });
          },
        ),
      ),
    );
  }
}

Color _statusColor(String status) => switch (status) {
      'accepted' => AppColors.online,
      'rejected' => AppColors.danger,
      'closed' => AppColors.textSoft,
      'talking' => AppColors.blue,
      _ => AppColors.accent,
    };

/// One application / offer.
class _AppCard extends ConsumerStatefulWidget {
  final JobApplication a;
  final String uid;
  final AppStrings s;
  final String peopleKey;
  const _AppCard({required this.a, required this.uid, required this.s, required this.peopleKey});

  @override
  ConsumerState<_AppCard> createState() => _AppCardState();
}

class _AppCardState extends ConsumerState<_AppCard> {
  bool _busy = false;

  Future<void> _act(JobAppAction action) async {
    final s = widget.s;
    if (action == JobAppAction.reject || action == JobAppAction.withdraw || action == JobAppAction.close) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(s.t('job_app_act_${action.name}')),
          content: Text(s.t('job_app_confirm_end')),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: Text(s.t('common_cancel'))),
            TextButton(
              key: const ValueKey('job-app-confirm-ok'),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(s.t('job_app_act_${action.name}')),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(jobsRepositoryProvider).setApplicationStatus(widget.a.id, JobApplication.statusFor(action));
      ref.invalidate(myApplicationsProvider);
      ref.invalidate(jobNoticesProvider);
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.t('job_save_failed'))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.a, s = widget.s, uid = widget.uid;
    final specs = ref.watch(jobSpecialtiesProvider).valueOrNull ?? kJobSpecialties;
    final people = ref.watch(jobPeopleProvider(widget.peopleKey)).valueOrNull ?? const {};
    final mine = ref.watch(myVacanciesProvider).valueOrNull ?? const <JobVacancy>[];
    final open = ref.watch(jobVacanciesProvider).valueOrNull ?? const <JobVacancy>[];
    final seekers = ref.watch(jobSeekersProvider).valueOrNull ?? const <JobSeeker>[];
    final side = a.sideOf(uid);
    final vacancy = [...mine, ...open].where((v) => v.id == a.vacancyId).firstOrNull;
    final seeker = seekers.where((p) => p.userId == a.seekerId).firstOrNull;
    final other = a.otherOf(uid);
    final who = people[other];
    final name = (who?.name ?? '').trim();
    final title = vacancy == null ? s.t('job_app_vacancy') : jobFeedTitle(s, JobFeedItem.vacancy(vacancy), specs);
    final dir = switch ((side, a.initiatedBy)) {
      ('seeker', 'seeker') => 'job_app_dir_my_app',
      ('seeker', _) => 'job_app_dir_offer_in',
      ('employer', 'seeker') => 'job_app_dir_app_in',
      _ => 'job_app_dir_my_offer',
    };
    final note = a.waitingNoteFor(uid);
    final color = _statusColor(a.status);
    final actions = a.actionsFor(uid);
    // Contacts: the phone only when its owner shows it (the server lists).
    final phone = side == 'employer' ? seeker?.phone : vacancy?.phone;
    final whatsapp = side == 'employer' ? (seeker?.whatsapp ?? false) : (vacancy?.whatsapp ?? false);
    return Container(
      key: ValueKey('job-app-${a.id}'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: a.isFinal ? AppColors.line : color.withValues(alpha: 0.5)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: InkWell(
              onTap: () => context.pushOnce(side == 'employer' ? '/jobs/d/${a.seekerId}' : '/jobs/v/${a.vacancyId}'),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(s.t(dir), style: TextStyle(fontSize: 12.5, color: AppColors.textSoft)),
                const SizedBox(height: 2),
                Text(title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.text)),
                if (vacancy != null && side == 'seeker')
                  Text(vacancy.companyName, style: TextStyle(fontSize: 13.5, color: AppColors.textSoft)),
              ]),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            key: ValueKey('job-app-status-${a.id}'),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(10)),
            child: Text(s.t('job_app_st_${a.status}'), style: TextStyle(fontSize: 12.5, color: color, fontWeight: FontWeight.w500)),
          ),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          UserAvatar(
              imageUrl: who?.avatar,
              initials: name.isEmpty ? '?' : name.characters.first.toUpperCase(),
              radius: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(name.isEmpty ? '—' : name,
                maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: AppColors.text)),
          ),
        ]),
        if (a.message != null) ...[
          const SizedBox(height: 8),
          Text('“${a.message}”', style: TextStyle(fontSize: 13.5, color: AppColors.textSoft)),
        ],
        if (note != null) ...[
          const SizedBox(height: 8),
          Text(s.t(note), key: ValueKey('job-app-note-${a.id}'), style: TextStyle(fontSize: 13, color: AppColors.blue)),
        ],
        if (a.isOpen) ...[
          const SizedBox(height: 10),
          JobContactActions(userId: other, phone: phone, whatsapp: whatsapp, s: s, color: AppColors.blue),
        ],
        if (actions.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final act in actions)
              act == JobAppAction.accept || act == JobAppAction.talk
                  ? FilledButton(
                      key: ValueKey('job-app-${act.name}-${a.id}'),
                      style: FilledButton.styleFrom(
                          backgroundColor: act == JobAppAction.accept ? AppColors.online : AppColors.blue, foregroundColor: Colors.white),
                      onPressed: _busy ? null : () => _act(act),
                      child: Text(s.t('job_app_act_${act.name}')),
                    )
                  : OutlinedButton(
                      key: ValueKey('job-app-${act.name}-${a.id}'),
                      style: OutlinedButton.styleFrom(foregroundColor: AppColors.danger, side: BorderSide(color: AppColors.line)),
                      onPressed: _busy ? null : () => _act(act),
                      child: Text(s.t('job_app_act_${act.name}')),
                    ),
          ]),
        ],
      ]),
    );
  }
}

/// İş Mərkəzi notices: new applications / offers, status changes, new
/// matching vacancies or drivers. Opening the page marks them as read.
class JobNoticesScreen extends ConsumerStatefulWidget {
  const JobNoticesScreen({super.key});

  @override
  ConsumerState<JobNoticesScreen> createState() => _JobNoticesScreenState();
}

class _JobNoticesScreenState extends ConsumerState<JobNoticesScreen> {
  bool _marked = false;

  Future<void> _markRead(List<JobNotice> list) async {
    if (_marked) return;
    _marked = true;
    final ids = [for (final n in list) if (!n.isRead) n.id];
    if (ids.isEmpty) return;
    try {
      await ref.read(jobsRepositoryProvider).markNoticesRead(ids);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    final lang = ref.watch(currentLocaleProvider).languageCode;
    final notices = ref.watch(jobNoticesProvider);
    return PopScope(
      onPopInvokedWithResult: (_, __) => ref.invalidate(jobNoticesProvider),
      child: Scaffold(
        appBar: AppBar(title: Text(s.t('job_ntf_title'))),
        body: notices.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(e is JobsNotReady ? s.t('job_not_ready') : s.t('home_error_loading'), textAlign: TextAlign.center),
            ),
          ),
          data: (list) {
            WidgetsBinding.instance.addPostFrameCallback((_) => _markRead(list));
            if (list.isEmpty) {
              return Center(child: Text(s.t('job_ntf_empty'), style: TextStyle(color: AppColors.textSoft)));
            }
            return ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: list.length,
              separatorBuilder: (_, __) => Divider(height: 1, color: AppColors.line),
              itemBuilder: (context, i) {
                final n = list[i];
                final icon = switch (n.type) {
                  'job_match_vacancy' => Icons.work_outline,
                  'job_match_seeker' => Icons.local_shipping_outlined,
                  _ => Icons.assignment_ind_outlined,
                };
                return ListTile(
                  key: ValueKey('job-ntf-${n.id}'),
                  leading: CircleAvatar(
                    backgroundColor: AppColors.blue.withValues(alpha: 0.14),
                    child: Icon(icon, color: AppColors.blue),
                  ),
                  title: Text(s.t(n.textKey),
                      style: TextStyle(color: AppColors.text, fontWeight: n.isRead ? FontWeight.w400 : FontWeight.w600)),
                  subtitle: n.createdAt == null
                      ? null
                      : Text(jobNoticeTime(n.createdAt!.toLocal(), lang), style: TextStyle(color: AppColors.textSoft, fontSize: 12.5)),
                  trailing: n.isRead ? null : Icon(Icons.circle, size: 10, color: AppColors.accent),
                  onTap: () => context.pushOnce(n.route),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

/// "28.10.2026 15:42".
String jobNoticeTime(DateTime t, String lang) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(t.day)}.${two(t.month)}.${t.year} ${two(t.hour)}:${two(t.minute)}';
}
