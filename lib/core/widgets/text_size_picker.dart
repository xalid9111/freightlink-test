import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../theme/app_theme.dart';
import '../theme/ui_scale.dart';

/// Text size 1—2—3—4—5 (owner, 24.10.2026): five round steps on one line,
/// a small "A" on the left and a big one on the right. Applied at once on
/// every page and kept on this device. Used in Profil and in Settings.
class TextSizePicker extends ConsumerWidget {
  const TextSizePicker({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(uiScaleProvider);
    // The picker itself keeps one size, so it never jumps while choosing.
    return MediaQuery.withNoTextScaling(
      child: Row(key: const ValueKey('ui-scale'), children: [
        Text('A', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textSoft)),
        const SizedBox(width: 10),
        Expanded(
          child: Row(children: [
            for (final s in AppUiScale.values) ...[
              if (s.index > 0) Expanded(child: Container(height: 2, color: s.index <= current.index ? AppColors.accent : AppColors.line)),
              _Step(scale: s, selected: s == current, passed: s.index <= current.index),
            ],
          ]),
        ),
        const SizedBox(width: 10),
        Text('A', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.textSoft)),
      ]),
    );
  }
}

class _Step extends ConsumerWidget {
  final AppUiScale scale;
  final bool selected;
  final bool passed;
  const _Step({required this.scale, required this.selected, required this.passed});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final size = selected ? 36.0 : 28.0;
    return Semantics(
      button: true,
      selected: selected,
      label: '${scale.level}',
      child: InkResponse(
        key: ValueKey('ui-scale-${scale.level}'),
        radius: 26,
        onTap: () => ref.read(uiScaleProvider.notifier).choose(scale),
        child: SizedBox(
          width: 40,
          height: 44,
          child: Center(
            child: Container(
              width: size,
              height: size,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: selected ? AppColors.accentFill : (passed ? AppColors.accent.withValues(alpha: 0.18) : AppColors.card),
                border: Border.all(color: passed ? AppColors.accent : AppColors.line, width: 1.5),
              ),
              child: Text('${scale.level}',
                  style: TextStyle(
                      fontSize: selected ? 16 : 14,
                      fontWeight: FontWeight.w800,
                      color: selected ? Colors.white : AppColors.text)),
            ),
          ),
        ),
      ),
    );
  }
}
