import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/localization/app_strings.dart';
import '../../../core/router/safe_navigation.dart';
import '../../../core/theme/app_theme.dart';
import '../../chat/presentation/providers/chat_providers.dart';
import '../../chat/data/group_repository.dart';
import '../domain/job_match.dart';
import '../domain/job_models.dart';

/// Driver = orange, employer = blue (owner, 26.10.2026).
Color get jobDriverColor => AppColors.accent;
Color get jobEmployerColor => AppColors.blue;

/// The approved İş Mərkəzi icon (two people, arrows; no background).
class JobCenterIcon extends StatelessWidget {
  final double height;
  const JobCenterIcon({super.key, this.height = 26});

  @override
  Widget build(BuildContext context) => Image.asset(
        AppColors.isDay ? 'assets/images/jobs/job_center_day.png' : 'assets/images/jobs/job_center_night.png',
        key: const ValueKey('job-center-icon'),
        height: height,
        filterQuality: FilterQuality.medium,
      );
}

/// Loads page (owner, 27.10.2026): on the live map, under the "CANLI"
/// badge — the icon with "İş Mərkəzi" under it on a glass card.
class JobCenterMapButton extends StatelessWidget {
  final AppStrings strings;
  const JobCenterMapButton({super.key, required this.strings});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: strings.t('job_center'),
      child: Material(
        color: AppColors.isDay ? AppColors.tileBg.withValues(alpha: 0.92) : AppColors.card.withValues(alpha: 0.72),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: BorderSide(color: AppColors.tileLine)),
        child: InkWell(
          key: const ValueKey('map-job-center'),
          borderRadius: BorderRadius.circular(18),
          onTap: () => context.pushOnce('/jobs'),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 6, 14, 6),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const JobCenterIcon(height: 26),
              const SizedBox(height: 2),
              Text(strings.t('job_center'), style: TextStyle(fontSize: 13, color: AppColors.text)),
            ]),
          ),
        ),
      ),
    );
  }
}

/// A catalogue label in the user's language (admin-added codes: their name).
String jobLabel(AppStrings s, String prefix, JobCatalogItem item) {
  final key = '$prefix${item.code}';
  final t = s.t(key);
  return t == key ? item.name : t;
}

String jobCodeLabel(AppStrings s, String prefix, String code, List<JobCatalogItem> catalog) {
  final item = catalog.firstWhere((i) => i.code == code, orElse: () => JobCatalogItem(code, code));
  return jobLabel(s, prefix, item);
}

/// Multi-choice chips (specialties).
class JobChoiceChips extends StatelessWidget {
  final List<JobCatalogItem> items;
  final Set<String> selected;
  final ValueChanged<Set<String>> onChanged;
  final AppStrings s;
  final Color color;
  final String keyPrefix;
  const JobChoiceChips(
      {super.key,
      required this.items,
      required this.selected,
      required this.onChanged,
      required this.s,
      required this.color,
      this.keyPrefix = 'job-spec'});

  @override
  Widget build(BuildContext context) {
    return Wrap(spacing: 8, runSpacing: 8, children: [
      for (final it in items)
        FilterChip(
          key: ValueKey('$keyPrefix-${it.code}'),
          label: Text(jobLabel(s, 'job_spec_', it)),
          selected: selected.contains(it.code),
          selectedColor: color.withValues(alpha: 0.18),
          checkmarkColor: color,
          side: BorderSide(color: selected.contains(it.code) ? color : AppColors.line),
          onSelected: (on) => onChanged(on ? ({...selected, it.code}) : ({...selected}..remove(it.code))),
        ),
    ]);
  }
}

/// One small toggle of a row (tap again → back to "not given").
class _Pick extends StatelessWidget {
  final String label;
  final bool on;
  final Color color;
  final VoidCallback onTap;
  final IconData? icon;
  const _Pick({super.key, required this.label, required this.on, required this.color, required this.onTap, this.icon});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: on ? color.withValues(alpha: 0.16) : Colors.transparent,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10), side: BorderSide(color: on ? color : AppColors.line)),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (icon != null) ...[Icon(icon, size: 16, color: on ? color : AppColors.textSoft), const SizedBox(width: 4)],
            Text(label,
                style: TextStyle(fontSize: 13, color: on ? color : AppColors.textSoft, fontWeight: on ? FontWeight.w500 : FontWeight.w400)),
          ]),
        ),
      ),
    );
  }
}

/// Driver: "has it" ✓ · "does not" ✗ · "ready to obtain"; nothing = not given.
class SkillAnswerRow extends StatelessWidget {
  final String label;
  final String code;
  final SkillState? value;
  final ValueChanged<SkillState?> onChanged;
  final AppStrings s;
  const SkillAnswerRow(
      {super.key, required this.label, required this.code, required this.value, required this.onChanged, required this.s});

  @override
  Widget build(BuildContext context) {
    Widget pick(SkillState st, String text, Color c, IconData? icon) => _Pick(
          key: ValueKey('skill-$code-${st.name}'),
          label: text,
          icon: icon,
          on: value == st,
          color: c,
          onTap: () => onChanged(value == st ? null : st),
        );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: TextStyle(fontSize: 14.5, color: AppColors.text)),
        const SizedBox(height: 6),
        Wrap(spacing: 6, runSpacing: 6, children: [
          pick(SkillState.yes, s.t('job_st_yes'), AppColors.online, Icons.check),
          pick(SkillState.no, s.t('job_st_no'), AppColors.danger, Icons.close),
          pick(SkillState.ready, s.t('job_st_ready'), AppColors.promoPremium, null),
        ]),
      ]),
    );
  }
}

/// Employer: "Mütləq" · "Arzuolunan" (nothing = not required) and, for a
/// required document, "I can help to obtain it".
class RequirementRow extends StatelessWidget {
  final String label;
  final String code;
  final bool helpable;
  final ReqLevel? value;
  final bool canHelp;
  final ValueChanged<ReqLevel?> onChanged;
  final ValueChanged<bool> onHelp;
  final AppStrings s;
  const RequirementRow(
      {super.key,
      required this.label,
      required this.code,
      required this.helpable,
      required this.value,
      required this.canHelp,
      required this.onChanged,
      required this.onHelp,
      required this.s});

  @override
  Widget build(BuildContext context) {
    Widget pick(ReqLevel l, String text) => _Pick(
          key: ValueKey('req-$code-${l.name}'),
          label: text,
          on: value == l,
          color: jobEmployerColor,
          onTap: () => onChanged(value == l ? null : l),
        );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: TextStyle(fontSize: 14.5, color: AppColors.text)),
        const SizedBox(height: 6),
        Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
          pick(ReqLevel.must, s.t('job_req_must')),
          pick(ReqLevel.nice, s.t('job_req_nice')),
          if (helpable && value != null)
            _Pick(
              key: ValueKey('req-$code-help'),
              label: s.t('job_can_help'),
              on: canHelp,
              color: AppColors.online,
              icon: Icons.handshake_outlined,
              onTap: () => onHelp(!canHelp),
            ),
        ]),
      ]),
    );
  }
}

/// The percentage badge (information only).
class MatchBadge extends StatelessWidget {
  final int? percent;
  final AppStrings s;
  const MatchBadge({super.key, required this.percent, required this.s});

  @override
  Widget build(BuildContext context) {
    final p = percent;
    final c = p == null ? AppColors.textSoft : (p >= 60 ? AppColors.online : (p >= 30 ? AppColors.promoPremium : AppColors.danger));
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: c.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(10)),
      child: Text(p == null ? '—' : s.t('job_match_pct', {'n': '$p'}),
          style: TextStyle(fontSize: 12.5, color: c, fontWeight: FontWeight.w500)),
    );
  }
}

/// One line of the comparison: ✓ green, ✗ red, — not given, or "ready".
class CheckLine extends StatelessWidget {
  final MatchCheck check;
  final String label;
  final AppStrings s;
  const CheckLine({super.key, required this.check, required this.label, required this.s});

  @override
  Widget build(BuildContext context) {
    final (IconData icon, Color color, String? note) = switch (check.state) {
      CheckState.yes => (Icons.check_circle, AppColors.online, null),
      CheckState.no => (Icons.cancel, AppColors.danger, null),
      CheckState.ready => (Icons.schedule, AppColors.promoPremium, s.t('job_ready_note')),
      CheckState.unknown => (Icons.remove_circle_outline, AppColors.textSoft, s.t('job_unknown')),
    };
    final extra = [
      if (check.level != null) s.t(check.level == ReqLevel.must ? 'job_req_must' : 'job_req_nice'),
      if (note != null) note,
      if (check.canHelp && check.state != CheckState.yes) s.t('job_help_note'),
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 17, color: color, key: ValueKey('chk-${check.kind.name}-${check.code ?? ''}-${check.state.name}')),
        const SizedBox(width: 6),
        Expanded(
          child: Text.rich(TextSpan(children: [
            TextSpan(text: label, style: TextStyle(color: AppColors.text)),
            if (extra.isNotEmpty) TextSpan(text: '  $extra', style: TextStyle(color: AppColors.textSoft, fontSize: 12.5)),
          ])),
        ),
      ]),
    );
  }
}

/// Profilə bax · Mesaj yaz · Zəng · WhatsApp (the existing Mesajlar; the
/// phone only when its owner chose to show it — decided on the server).
class JobContactActions extends ConsumerStatefulWidget {
  final String userId;
  final String? phone;
  final bool whatsapp;
  final AppStrings s;
  final Color color;
  const JobContactActions(
      {super.key, required this.userId, required this.phone, required this.whatsapp, required this.s, required this.color});

  @override
  ConsumerState<JobContactActions> createState() => _JobContactActionsState();
}

class _JobContactActionsState extends ConsumerState<JobContactActions> {
  bool _opening = false;

  Future<void> _message() async {
    setState(() => _opening = true);
    try {
      final conv = await ref.read(groupRepositoryProvider).openDirect(widget.userId);
      ref.invalidate(conversationByIdProvider(conv.id));
      if (mounted) context.pushOnce('/chat/${conv.id}');
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(widget.s.t('chat_open_failed'))));
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.s;
    final digits = (widget.phone ?? '').replaceAll(RegExp(r'[^0-9+]'), '');
    final hasPhone = digits.replaceAll('+', '').length >= 7;
    final style = OutlinedButton.styleFrom(
      foregroundColor: widget.color,
      side: BorderSide(color: widget.color.withValues(alpha: 0.6)),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      minimumSize: const Size(0, 36),
      visualDensity: VisualDensity.compact,
    );
    return Wrap(spacing: 6, runSpacing: 6, children: [
      OutlinedButton.icon(
        key: ValueKey('job-profile-${widget.userId}'),
        style: style,
        onPressed: () => context.pushOnce('/user/${widget.userId}'),
        icon: const Icon(Icons.person_outline, size: 17),
        label: Text(s.t('job_view_profile')),
      ),
      OutlinedButton.icon(
        key: ValueKey('job-message-${widget.userId}'),
        style: style,
        onPressed: _opening ? null : _message,
        icon: const Icon(Icons.chat_bubble_outline, size: 17),
        label: Text(s.t('job_message')),
      ),
      if (hasPhone)
        OutlinedButton.icon(
          key: ValueKey('job-call-${widget.userId}'),
          style: style,
          onPressed: () => launchUrl(Uri.parse('tel:$digits')),
          icon: const Icon(Icons.call_outlined, size: 17),
          label: Text(s.t('job_call')),
        ),
      if (hasPhone && widget.whatsapp)
        OutlinedButton.icon(
          key: ValueKey('job-wa-${widget.userId}'),
          style: style,
          onPressed: () => launchUrl(Uri.parse('https://wa.me/${digits.replaceAll('+', '')}'),
              mode: LaunchMode.externalApplication),
          icon: const Icon(Icons.chat_outlined, size: 17),
          label: Text(s.t('job_whatsapp')),
        ),
    ]);
  }
}
