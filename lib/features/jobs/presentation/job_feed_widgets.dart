import 'package:flutter/material.dart';

import '../../../core/constants/cities.dart';
import '../../../core/constants/countries.dart';
import '../../../core/localization/app_strings.dart';
import '../../../core/router/safe_navigation.dart';
import '../../../core/theme/app_theme.dart';
import '../domain/job_feed.dart';
import '../domain/job_match.dart';
import '../domain/job_models.dart';
import 'job_widgets.dart';

/// "1 500" style amounts.
String jobMoneyText(double v) =>
    v.round().toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ' ');

/// "TIR sürücüsü tələb olunur" / "REF sürücüsü iş axtarır" (picture 1).
String jobFeedTitle(AppStrings s, JobFeedItem it, List<JobCatalogItem> specs) {
  String? what;
  final first = it.specialties.firstOrNull;
  if (it.isVacancy && it.vacancy!.jobType == 'tir' && (first == null || first == 'tent')) {
    what = 'TIR';
  } else if (first != null) {
    what = jobCodeLabel(s, 'job_spec_', first, specs);
  }
  if (it.isVacancy) {
    return what == null ? s.t('job_title_need_any') : s.t('job_title_need', {'what': what});
  }
  return what == null ? s.t('job_title_seek_any') : s.t('job_title_seek', {'what': what});
}

/// Where: the vacancy's route (or work countries / place), the driver's
/// countries (or place).
String? jobFeedWhere(JobFeedItem it, String lang) {
  String countries(List<String> cs) => [for (final c in cs) Countries.find(c)?.name(lang) ?? c].join(' / ');
  String? place(String? city, String? country) {
    final p = [if (city != null) Cities.label(city, lang), if (country != null) Countries.find(country)?.name(lang) ?? country];
    return p.isEmpty ? null : p.join(', ');
  }

  if (it.isVacancy) {
    final v = it.vacancy!;
    if (v.routes != null) return v.routes;
    if (v.countries.isNotEmpty) return countries(v.countries);
    return place(v.city, v.country);
  }
  final p = it.seeker!;
  if (p.countries.isNotEmpty) return countries(p.countries);
  return p.routes ?? place(p.city, p.country);
}

/// The vacancy's salary range / the driver's wish.
String? jobFeedSalary(JobFeedItem it) {
  if (it.isVacancy) {
    final v = it.vacancy!;
    final cur = v.currency ?? 'AZN';
    if (v.salaryMin != null && v.salaryMax != null && v.salaryMin != v.salaryMax) {
      return '${jobMoneyText(v.salaryMin!)} – ${jobMoneyText(v.salaryMax!)} $cur';
    }
    final one = v.salaryMax ?? v.salaryMin;
    return one == null ? null : '${jobMoneyText(one)} $cur';
  }
  final p = it.seeker!;
  return p.salaryMin == null ? null : '${jobMoneyText(p.salaryMin!)} ${p.currency ?? 'AZN'}';
}

/// One card of "Aktiv elanlar" / "Uyğun təkliflər" (picture 1): the icon
/// square (vacancy = briefcase, driver = truck), title, transport ·
/// licence · experience, where, salary; › opens the page of the ad.
class JobFeedCard extends StatelessWidget {
  final JobFeedItem item;
  final AppStrings s;
  final String lang;
  final List<JobCatalogItem> specs;
  final List<JobCatalogItem> skills;
  final JobMatch? match;
  const JobFeedCard(
      {super.key, required this.item, required this.s, required this.lang, required this.specs, required this.skills, this.match});

  @override
  Widget build(BuildContext context) {
    final c = item.isVacancy ? AppColors.accent : AppColors.blue;
    final lic = topLicence(item.licences);
    final where = jobFeedWhere(item, lang);
    final salary = jobFeedSalary(item);
    final exp = item.experience;
    Widget fact(IconData icon, String text, {Color? iconColor}) => Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 18, color: iconColor ?? AppColors.textSoft),
          const SizedBox(width: 6),
          Flexible(child: Text(text, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14.5, color: AppColors.text))),
        ]);
    return Material(
      color: AppColors.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: AppColors.line)),
      child: InkWell(
        key: ValueKey('job-feed-${item.isVacancy ? 'v' : 'd'}-${item.id}'),
        borderRadius: BorderRadius.circular(16),
        onTap: () => context.pushOnce(item.route),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 10, 14),
          child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(color: c.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(14)),
              child: Icon(item.isVacancy ? Icons.work : Icons.local_shipping, color: c, size: 26),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(jobFeedTitle(s, item, specs),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.w600, color: AppColors.text)),
                if (match != null) ...[const SizedBox(height: 4), MatchBadge(percent: match!.percent, s: s)],
                const SizedBox(height: 6),
                Wrap(spacing: 14, runSpacing: 4, children: [
                  if (item.specialties.isNotEmpty)
                    fact(Icons.local_shipping_outlined, jobCodeLabel(s, 'job_spec_', item.specialties.first, specs)),
                  if (lic != null) fact(Icons.description_outlined, jobCodeLabel(s, 'job_lic_', lic, skills)),
                  if (exp != null && exp > 0) fact(Icons.bar_chart_rounded, s.t('job_exp_years', {'n': '$exp'}), iconColor: AppColors.blue),
                ]),
                if (where != null) ...[
                  const SizedBox(height: 4),
                  fact(Icons.place, where, iconColor: AppColors.accent),
                ],
                if (salary != null) ...[
                  const SizedBox(height: 4),
                  fact(Icons.payments_outlined, salary, iconColor: AppColors.accent),
                ],
              ]),
            ),
            const SizedBox(width: 6),
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(color: AppColors.cardAlt, shape: BoxShape.circle),
              child: Icon(Icons.chevron_right, color: AppColors.text),
            ),
          ]),
        ),
      ),
    );
  }
}
