import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/feedback/wheel_feedback.dart';
import '../../../core/localization/app_strings.dart';
import '../../../core/localization/locale_controller.dart';
import '../../../core/localization/localization_service.dart';
import '../../../core/notify/notify_settings.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/router/safe_navigation.dart';

/// Each language in its own native name (deliberately not translated).
String languageName(Locale l) => switch (l.languageCode) {
      'az' => 'Azərbaycanca',
      'tr' => 'Türkçe',
      'ru' => 'Русский',
      'en' => 'English',
      'ka' => 'ქართული',
      'zh' => '简体中文',
      _ => l.languageCode,
    };

/// Every language as a button; the choice applies at once and is saved.
Future<void> showLanguagePicker(BuildContext context, WidgetRef ref, AppStrings strings) {
  final current = ref.read(currentLocaleProvider);
  return showModalBottomSheet<void>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(strings.t('profile_language_choose'), style: Theme.of(ctx).textTheme.titleMedium),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final l in LocalizationService.supportedLocales)
                  l.languageCode == current.languageCode
                      ? FilledButton.icon(
                          onPressed: () => Navigator.of(ctx).pop(),
                          icon: const Icon(Icons.check, size: 18),
                          label: Text(languageName(l)),
                        )
                      : OutlinedButton(
                          onPressed: () {
                            ref.read(currentLocaleProvider.notifier).setLocale(l);
                            Navigator.of(ctx).pop();
                          },
                          child: Text(languageName(l)),
                        ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

/// Ayarlar: notifications & sounds, haptic, language, password, privacy.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  Future<void> _openPrivacy() async {
    final uri = Uri.base.resolve('privacy.html');
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final locale = ref.watch(currentLocaleProvider);
    final ns = ref.watch(notifySettingsProvider);
    final nc = ref.read(notifySettingsProvider.notifier);
    final haptic = ref.watch(wheelSettingsProvider).haptic;

    return Scaffold(
      appBar: AppBar(title: Text(s.t('settings_title'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          _Section(
            icon: Icons.notifications,
            title: s.t('settings_notifications'),
            children: [
              _SwitchRow(icon: Icons.local_shipping_outlined, label: s.t('settings_notif_cargo'), value: ns.cargoNotify, onChanged: nc.setCargoNotify),
              _SwitchRow(icon: Icons.volume_up_outlined, label: s.t('settings_sound_cargo'), value: ns.cargoSound, onChanged: nc.setCargoSound),
              _SwitchRow(icon: Icons.chat_outlined, label: s.t('settings_notif_msg'), value: ns.msgNotify, onChanged: nc.setMsgNotify),
              _SwitchRow(icon: Icons.volume_up_outlined, label: s.t('settings_sound_msg'), value: ns.msgSound, onChanged: nc.setMsgSound),
              _SwitchRow(
                icon: Icons.vibration,
                label: s.t('settings_haptic'),
                value: haptic,
                onChanged: (v) => ref.read(wheelSettingsProvider.notifier).setHaptic(v),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _Section(
            icon: Icons.language,
            iconColor: AppColors.accent,
            title: s.t('settings_lang_region'),
            children: [
              _LinkRow(
                icon: Icons.translate,
                label: s.t('settings_app_language'),
                value: languageName(locale),
                onTap: () => showLanguagePicker(context, ref, s),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _Section(
            icon: Icons.lock,
            title: s.t('settings_privacy_security'),
            children: [
              _LinkRow(icon: Icons.lock_outline, label: s.t('pw_change_title'), onTap: () => context.pushOnce('/change-password')),
              _LinkRow(icon: Icons.verified_user_outlined, label: s.t('settings_privacy_policy'), onTap: _openPrivacy),
            ],
          ),
          const SizedBox(height: 14),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(s.t('settings_notif_note'), style: const TextStyle(color: AppColors.textSoft, fontSize: 12, height: 1.35)),
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final IconData icon;
  final Color? iconColor;
  final String title;
  final List<Widget> children;
  const _Section({required this.icon, required this.title, required this.children, this.iconColor});

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
        child: Row(
          children: [
            Icon(icon, color: iconColor ?? AppColors.text, size: 24),
            const SizedBox(width: 14),
            Expanded(child: Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800))),
          ],
        ),
      ),
    ];
    for (final c in children) {
      rows.add(const Divider(height: 1, indent: 16, endIndent: 16, color: AppColors.line));
      rows.add(c);
    }
    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: rows),
    );
  }
}

class _SwitchRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  const _SwitchRow({required this.icon, required this.label, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onChanged(!value),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 10, 6),
        child: Row(
          children: [
            Icon(icon, color: AppColors.textSoft, size: 22),
            const SizedBox(width: 14),
            Expanded(child: Text(label, style: const TextStyle(fontSize: 15))),
            Switch(
              value: value,
              onChanged: onChanged,
              activeTrackColor: AppColors.accentFill,
              thumbColor: const WidgetStatePropertyAll(Colors.white),
            ),
          ],
        ),
      ),
    );
  }
}

class _LinkRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? value;
  final VoidCallback onTap;
  const _LinkRow({required this.icon, required this.label, required this.onTap, this.value});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 15, 12, 15),
        child: Row(
          children: [
            Icon(icon, color: AppColors.textSoft, size: 22),
            const SizedBox(width: 14),
            Expanded(child: Text(label, style: const TextStyle(fontSize: 15))),
            if (value != null) ...[
              Text(value!, style: const TextStyle(color: AppColors.textSoft, fontSize: 14)),
              const SizedBox(width: 6),
            ],
            const Icon(Icons.chevron_right, color: AppColors.textSoft),
          ],
        ),
      ),
    );
  }
}
