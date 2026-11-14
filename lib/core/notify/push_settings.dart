import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../localization/app_strings.dart';
import '../localization/locale_controller.dart';
import '../theme/app_theme.dart';
import 'web_push.dart';

/// Ayarlar → Bildirişlər → "Proqram bağlı olanda da bildiriş" (owner,
/// 14.11.2026, SQL 0121): this device on / off (the permission is asked only
/// after the tap), why not (iPhone: add to Home Screen; denied; not
/// supported), and — when on — Mesajlar · Vacib bildirişlər · Mesajın ilk
/// 80 simvolu (off by default: "Əli: Yeni mesajınız var").
class PushSettingsCard extends ConsumerStatefulWidget {
  const PushSettingsCard({super.key});

  @override
  ConsumerState<PushSettingsCard> createState() => _PushSettingsCardState();
}

class _PushSettingsCardState extends ConsumerState<PushSettingsCard> {
  bool _busy = false;
  PushDevice? _now;

  void _snack(String text) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text), duration: const Duration(seconds: 6)));

  /// Called straight from the tap: the browser asks for permission at once.
  void _on(AppStrings s) {
    if (_busy) return;
    setState(() => _busy = true);
    pushTurnOn(ref.read(pushRepositoryProvider)).then((d) {
      if (!mounted) return;
      setState(() => _now = d);
      ref.invalidate(pushDeviceProvider);
      _snack(s.t(switch (d) {
        PushDevice.on => 'push_on_done',
        PushDevice.denied => 'push_denied',
        PushDevice.notReady => 'push_not_ready',
        PushDevice.tapAgain => 'push_tap_again',
        PushDevice.iosInstall => 'push_ios_install',
        PushDevice.unsupported => 'push_unsupported',
        _ => 'push_failed',
      }));
    }).catchError((Object e) {
      if (mounted) _snack(s.t(e is PushNotReady ? 'push_not_ready' : 'push_failed'));
    }).whenComplete(() {
      if (mounted) setState(() => _busy = false);
    });
  }

  Future<void> _off(AppStrings s) async {
    if (_busy) return;
    setState(() => _busy = true);
    await pushTurnOff(ref.read(pushRepositoryProvider));
    if (!mounted) return;
    setState(() {
      _busy = false;
      _now = PushDevice.off;
    });
    ref.invalidate(pushDeviceProvider);
  }

  Future<void> _prefs(PushPrefs p, AppStrings s) async {
    try {
      await ref.read(pushRepositoryProvider).setPrefs(p);
      ref.invalidate(pushPrefsProvider);
    } catch (e) {
      if (mounted) _snack(s.t(e is PushNotReady ? 'push_not_ready' : 'push_failed'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    final device = _now ?? ref.watch(pushDeviceProvider).valueOrNull;
    final on = device == PushDevice.on;
    final note = switch (device) {
      PushDevice.on => 'push_state_on',
      PushDevice.iosInstall => 'push_ios_install',
      PushDevice.denied => 'push_denied',
      PushDevice.unsupported => 'push_unsupported',
      PushDevice.notReady => 'push_not_ready',
      _ => 'push_state_off',
    };
    final canTurnOn = device == PushDevice.off || device == PushDevice.ask || device == PushDevice.notReady || device == PushDevice.tapAgain;
    return Column(key: const ValueKey('push-card'), crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(4, 10, 4, 4),
        child: Row(children: [
          Icon(on ? Icons.notifications_active : Icons.notifications_off_outlined, color: on ? AppColors.online : AppColors.textSoft),
          const SizedBox(width: 10),
          Expanded(
            child: Text(s.t('push_title'), style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: AppColors.text)),
          ),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(4, 2, 4, 8),
        child: Text(s.t(note), key: const ValueKey('push-note'), style: TextStyle(fontSize: 13, color: AppColors.textSoft)),
      ),
      if (on)
        OutlinedButton.icon(
          key: const ValueKey('push-off'),
          onPressed: _busy ? null : () => _off(s),
          icon: const Icon(Icons.notifications_off_outlined),
          label: Text(s.t('push_turn_off')),
        )
      else if (canTurnOn)
        FilledButton.icon(
          key: const ValueKey('push-on'),
          onPressed: _busy ? null : () => _on(s),
          style: FilledButton.styleFrom(backgroundColor: AppColors.accentFill),
          icon: const Icon(Icons.notifications_active_outlined),
          label: Text(s.t('push_turn_on')),
        ),
      if (on)
        Consumer(builder: (context, ref, _) {
          final p = ref.watch(pushPrefsProvider).valueOrNull ?? const PushPrefs();
          Widget sw(String key, String label, bool v, PushPrefs Function(bool) next) => SwitchListTile(
                key: ValueKey(key),
                contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                title: Text(s.t(label), style: TextStyle(fontSize: 14, color: AppColors.text)),
                value: v,
                onChanged: (x) => _prefs(next(x), s),
              );
          return Column(children: [
            sw('push-messages', 'push_pref_messages', p.messages, (x) => p.copyWith(messages: x)),
            sw('push-important', 'push_pref_important', p.important, (x) => p.copyWith(important: x)),
            sw('push-preview', 'push_pref_preview', p.preview, (x) => p.copyWith(preview: x)),
          ]);
        }),
    ]);
  }
}
