import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/localization/app_strings.dart';
import '../../../../core/router/safe_navigation.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../admin/data/admin_repository.dart' show missingFunctionText;
import '../../../services/presentation/services_providers.dart';
import '../../data/activities_repository.dart';
import '../../domain/activities.dart';

IconData activityIcon(Activity a) => switch (a) {
      Activity.carrier => Icons.local_shipping_outlined,
      Activity.shipper => Icons.inventory_2_outlined,
      Activity.service => Icons.build_outlined,
      Activity.seller => Icons.sell_outlined,
    };

/// Top of the Profile: Daşıyıcı · Yük verən · Usta / Servis · Satış.
/// Grey = off, orange = on; any number can be on; tapping again turns it
/// off. Off never deletes anything (offers, chats, service stay).
class ActivityButtons extends ConsumerWidget {
  final AppStrings s;
  const ActivityButtons({super.key, required this.s});

  Future<void> _tap(BuildContext context, WidgetRef ref, Activity a) async {
    final messenger = ScaffoldMessenger.of(context);
    final wasOn = (ref.read(myActivitiesProvider).valueOrNull ?? const {}).contains(a);
    try {
      await ref.read(myActivitiesProvider.notifier).toggle(a);
    } catch (e) {
      final raw = e.toString();
      final text = raw.contains('PGRST202') || raw.contains('Could not find the function')
          ? missingFunctionText(raw)
          : s.t('act_save_failed');
      messenger.showSnackBar(SnackBar(content: Text(text)));
      return;
    }
    // Usta / Servis on without a service profile yet → offer to create it.
    if (!wasOn && a == Activity.service && ref.read(myServiceProvider).valueOrNull == null && context.mounted) {
      messenger.showSnackBar(SnackBar(
        content: Text(s.t('act_service_hint')),
        action: SnackBarAction(label: s.t('act_service_create'), onPressed: () => context.pushOnce('/service-join')),
      ));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final on = ref.watch(myActivitiesProvider).valueOrNull ?? const <Activity>{};
    // Same height for all four; a larger text size makes them taller
    // instead of cutting the label.
    return IntrinsicHeight(
      child: Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final a in Activity.values) ...[
          if (a != Activity.values.first) const SizedBox(width: 8),
          Expanded(
            child: _ActivityButton(
              key: ValueKey('act-${a.wire}'),
              icon: activityIcon(a),
              label: s.t(a.labelKey),
              selected: on.contains(a),
              onTap: () => _tap(context, ref, a),
            ),
          ),
        ],
      ],
      ),
    );
  }
}

class _ActivityButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _ActivityButton({super.key, required this.icon, required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final fg = selected ? Colors.white : AppColors.textSoft;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: Material(
        color: selected ? AppColors.accentFill : AppColors.card,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            constraints: const BoxConstraints(minHeight: 68),
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: selected ? AppColors.accent : AppColors.line),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 22, color: fg),
                const SizedBox(height: 4),
                Text(
                  label,
                  maxLines: 2,
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11.5, height: 1.1, fontWeight: FontWeight.w700, color: fg),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
