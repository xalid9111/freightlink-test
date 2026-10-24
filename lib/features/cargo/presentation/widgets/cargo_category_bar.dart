import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/localization/app_strings.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/mouse_drag_scroll.dart';
import '../../domain/cargo_categories.dart';
import '../providers/category_providers.dart';

/// The load-type choices (owner, 21.10.2026): TENT · REF · KONTEYNER ·
/// SAMOSVAL · QRUPAJ · AÇIQ · SİSTERN, then the six of 25.10.2026 — only
/// the picture and the name, no tile behind them; the chosen one is
/// orange. One row that scrolls sideways with a finger when it does not
/// fit the screen. The remembered choice is brought into view when the
/// page opens (owner, 25.10.2026).
class CargoTypeTiles extends ConsumerStatefulWidget {
  final AppStrings strings;
  final double tileHeight;
  final VoidCallback? onChanged;
  const CargoTypeTiles({super.key, required this.strings, this.tileHeight = 64, this.onChanged});

  @override
  ConsumerState<CargoTypeTiles> createState() => _CargoTypeTilesState();
}

class _CargoTypeTilesState extends ConsumerState<CargoTypeTiles> {
  static const _choiceWidth = 64.0;
  static const _gap = 12.0;
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _reveal(ref.read(cargoCategoryFilterProvider), animate: false);
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// Scrolls the row only when the chosen one is (partly) out of view.
  void _reveal(CargoCategoryFilter f, {required bool animate}) {
    final i = kCategoryChoices.indexOf(f.groupage ? 'groupage' : (f.truckType ?? ''));
    if (i < 0) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      final pos = _scroll.position;
      final left = i * (_choiceWidth + _gap);
      final right = left + _choiceWidth;
      if (left >= pos.pixels && right <= pos.pixels + pos.viewportDimension) return;
      final to = (left - (pos.viewportDimension - _choiceWidth) / 2).clamp(0.0, pos.maxScrollExtent);
      if (animate) {
        _scroll.animateTo(to, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      } else {
        _scroll.jumpTo(to);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final f = ref.watch(cargoCategoryFilterProvider);
    // A choice that arrives later (the account's saved one) is shown too.
    ref.listen(cargoCategoryFilterProvider, (prev, next) {
      if (prev != next) _reveal(next, animate: true);
    });
    void set(CargoCategoryFilter n) {
      ref.read(cargoCategoryFilterProvider.notifier).state = n;
      widget.onChanged?.call();
    }

    return SizedBox(
      height: widget.tileHeight,
      child: MouseDragScroll(child: ListView.separated(
          controller: _scroll,
          scrollDirection: Axis.horizontal,
          itemCount: kCategoryChoices.length,
          // 4½ choices fit a phone: the cut one shows there is more to the side.
          separatorBuilder: (_, __) => const SizedBox(width: _gap),
          itemBuilder: (_, i) {
            final c = kCategoryChoices[i];
            final groupage = c == 'groupage';
            return CargoTypeChoice(
              key: ValueKey('cat-$c'),
              code: c,
              label: widget.strings.t('cat_$c'),
              selected: groupage ? f.groupage : f.truckType == c,
              onTap: () => set(groupage ? f.tapGroupage() : f.tapTruck(c)),
            );
          },
        )),
    );
  }
}

/// One choice: the truck picture and its name — white at night, dark in
/// day mode — orange with a short orange line when chosen.
class CargoTypeChoice extends StatelessWidget {
  final String code;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const CargoTypeChoice({super.key, required this.code, required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.accent : AppColors.text;
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: SizedBox(
        width: 64,
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          SizedBox(
            height: 27,
            child: Image.asset(categoryIconAsset(code, night: !AppColors.isDay),
                fit: BoxFit.contain, color: color, colorBlendMode: BlendMode.srcIn),
          ),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(label, maxLines: 1, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: color)),
          ),
          const SizedBox(height: 3),
          AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            height: 2.5,
            width: selected ? 24 : 0,
            decoration: BoxDecoration(color: AppColors.accent, borderRadius: BorderRadius.circular(2)),
          ),
        ]),
      ),
    );
  }
}

/// One white tile: dark picture + short label; selected = light orange.
class CargoTypeTile extends StatelessWidget {
  final String code;
  final String label;
  final bool selected;
  final double height;
  final VoidCallback onTap;
  const CargoTypeTile(
      {super.key, required this.code, required this.label, required this.selected, required this.onTap, this.height = 78});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.tileSelectedBg : AppColors.tileBg,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          height: height,
          padding: const EdgeInsets.fromLTRB(6, 8, 6, 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: selected ? AppColors.accent : AppColors.tileLine, width: selected ? 1.6 : 1),
            // Night: the chosen tile glows orange (owner's night picture).
            boxShadow: selected && !AppColors.isDay
                ? [BoxShadow(color: AppColors.accent.withValues(alpha: 0.45), blurRadius: 12)]
                : null,
          ),
          child: Column(children: [
            Expanded(child: Image.asset(categoryIconAsset(code, night: !AppColors.isDay), fit: BoxFit.contain)),
            const SizedBox(height: 5),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(label,
                  maxLines: 1,
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: selected ? AppColors.accent : AppColors.tileFg)),
            ),
          ]),
        ),
      ),
    );
  }
}
