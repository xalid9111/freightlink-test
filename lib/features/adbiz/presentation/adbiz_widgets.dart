import 'package:flutter/material.dart';

import '../../../core/localization/app_strings.dart';
import '../../../core/theme/app_theme.dart';
import '../../finance/domain/finance_models.dart';
import '../data/adbiz_repository.dart';
import '../domain/adbiz_models.dart';

/// UTEP Reklam's own logo — only in this module (owner, 10.11.2026); the
/// rest of the app keeps its own. On a white plate, so it reads in the
/// night theme too (like the brand logos).
const kUtepLogo = 'assets/images/utep/utep_reklam_logo.png';

class UtepLogo extends StatelessWidget {
  final double height;
  const UtepLogo({super.key, this.height = 34});

  @override
  Widget build(BuildContext context) => Container(
        key: const ValueKey('utep-logo'),
        padding: EdgeInsets.symmetric(horizontal: height * 0.25, vertical: height * 0.12),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(height * 0.25)),
        child: Image.asset(kUtepLogo, height: height, fit: BoxFit.contain, filterQuality: FilterQuality.medium),
      );
}

/// The page's app bar title: the logo + the page name.
class UtepTitle extends StatelessWidget {
  final String title;
  const UtepTitle(this.title, {super.key});

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        const UtepLogo(height: 30),
        const SizedBox(width: 10),
        Flexible(child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis)),
      ]);
}

/// The server's refusal / error in words.
String adbizError(AppStrings s, Object e) {
  if (e is AdbizRefused) return s.t('adb_err_${e.reason}');
  if (e is AdbizNotReady) return s.t('adb_not_ready');
  return s.t('adb_err_generic');
}

void adbizSnack(BuildContext context, String text) => ScaffoldMessenger.of(context)
  ..hideCurrentSnackBar()
  ..showSnackBar(SnackBar(content: Text(text)));

class AdbizCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? color;
  const AdbizCard({super.key, required this.child, this.padding = const EdgeInsets.all(14), this.color});

  @override
  Widget build(BuildContext context) => Container(
        padding: padding,
        decoration: BoxDecoration(
          color: color ?? AppColors.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.line),
        ),
        child: child,
      );
}

/// One number with its label (Hədəf · Toplanan · Qalan, Gəlir · Xərc …).
class AdbizStat extends StatelessWidget {
  final IconData icon;
  final String label, value;
  final Color color;
  final String? valueKey;
  const AdbizStat({super.key, required this.icon, required this.label, required this.value, required this.color, this.valueKey});

  @override
  Widget build(BuildContext context) => Row(children: [
        Icon(icon, color: color, size: 26),
        const SizedBox(width: 8),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, color: AppColors.textSoft)),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(value,
                  key: valueKey == null ? null : ValueKey(valueKey),
                  style: TextStyle(fontSize: 19, fontWeight: FontWeight.w600, color: color)),
            ),
          ]),
        ),
      ]);
}

/// Hədəf · Toplanan · Qalan + the bar with the percentage.
class DayProgressCard extends StatelessWidget {
  final AppStrings s;
  final DayProgress p;
  const DayProgressCard({super.key, required this.s, required this.p});

  @override
  Widget build(BuildContext context) {
    final stats = [
      AdbizStat(icon: Icons.track_changes, label: s.t('adb_target'), value: money(p.target), color: AppColors.text, valueKey: 'adb-target'),
      AdbizStat(icon: Icons.savings_outlined, label: s.t('adb_collected'), value: money(p.collected), color: AppColors.online, valueKey: 'adb-collected'),
      AdbizStat(icon: Icons.speed, label: s.t('adb_remaining'), value: money(p.remaining), color: AppColors.accent, valueKey: 'adb-remaining'),
    ];
    return AdbizCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        LayoutBuilder(
          builder: (context, c) => c.maxWidth >= 420
              ? Row(children: [for (final w in stats) Expanded(child: w)])
              : Column(children: [for (final w in stats) Padding(padding: const EdgeInsets.only(bottom: 8), child: w)]),
        ),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                key: const ValueKey('adb-progress'),
                value: p.bar,
                minHeight: 12,
                backgroundColor: AppColors.line,
                color: AppColors.online,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Text('${p.percent}%', style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.text)),
        ]),
        if (p.reached)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(s.t('adb_target_reached'), style: TextStyle(color: AppColors.online, fontWeight: FontWeight.w500)),
          ),
      ]),
    );
  }
}

String hhmm(DateTime? t) => t == null ? '' : '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
String dmy(DateTime d) => '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';

/// Title + amount editor (a job or an expense). Returns (title, amount).
Future<(String, double)?> askTitleAmount(BuildContext context, AppStrings s,
    {required String heading, String title = '', double? amount}) {
  final t = TextEditingController(text: title);
  final a = TextEditingController(text: amount == null ? '' : amount.toStringAsFixed(2));
  String? err;
  return showDialog<(String, double)>(
    context: context,
    builder: (ctx) => StatefulBuilder(builder: (ctx, set) {
      void ok() {
        final v = parseAmount(a.text);
        if (t.text.trim().isEmpty || v == null) {
          set(() => err = s.t('adb_err_form'));
          return;
        }
        Navigator.pop(ctx, (t.text.trim(), v));
      }

      return AlertDialog(
        title: Text(heading),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
              key: const ValueKey('adb-dlg-title'),
              controller: t,
              autofocus: true,
              maxLength: 120,
              decoration: InputDecoration(labelText: s.t('adb_job_name'))),
          TextField(
            key: const ValueKey('adb-dlg-amount'),
            controller: a,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(labelText: s.t('adb_amount'), suffixText: 'AZN'),
            onSubmitted: (_) => ok(),
          ),
          if (err != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(err!, style: TextStyle(color: AppColors.danger))),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(s.t('common_cancel'))),
          FilledButton(key: const ValueKey('adb-dlg-save'), onPressed: ok, child: Text(s.t('adb_save'))),
        ],
      );
    }),
  );
}

Future<bool> adbizConfirm(BuildContext context, AppStrings s, String title, String body, {String? ok}) async =>
    await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(s.t('common_cancel'))),
          FilledButton(key: const ValueKey('adb-confirm'), onPressed: () => Navigator.pop(ctx, true), child: Text(ok ?? s.t('adb_yes'))),
        ],
      ),
    ) ==
    true;
