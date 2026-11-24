import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// The "Neumorf" look (0137): a raised surface — shade lower right, light
/// upper left — around [child]. With Neumorf off it returns [child] as it
/// is, so nothing changes in the classic look.
class NeuSurface extends StatelessWidget {
  final Widget child;
  final double radius;
  final double depth;
  const NeuSurface({super.key, required this.child, this.radius = 16, this.depth = 1});

  @override
  Widget build(BuildContext context) {
    if (!AppColors.neumorph) return child;
    return DecoratedBox(
      key: const ValueKey('neu-surface'),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        boxShadow: AppColors.neuRaised(depth: depth),
      ),
      child: child,
    );
  }
}

/// Neumorf (0137): a pressed-in surface (search fields, the switch track,
/// the map's frame) — darker ground, the shade on its upper left edge and
/// the light on its lower right, as in the owner's approved picture.
BoxDecoration neuInsetDecoration({double radius = 16}) => BoxDecoration(
      color: AppColors.cardAlt,
      borderRadius: BorderRadius.circular(radius),
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color.lerp(AppColors.cardAlt, AppColors.neuShade, 0.45)!,
          AppColors.cardAlt,
          Color.lerp(AppColors.cardAlt, AppColors.neuLight, 0.25)!,
        ],
        stops: const [0, 0.35, 1],
      ),
      border: Border.all(color: AppColors.neuShade.withValues(alpha: 0.35), width: 0.8),
    );

/// Neumorf: a raised surface's decoration (card colour + two shadows).
BoxDecoration neuRaisedDecoration({double radius = 16, double depth = 1, Color? color}) => BoxDecoration(
      color: color ?? AppColors.card,
      borderRadius: BorderRadius.circular(radius),
      boxShadow: AppColors.neuRaised(depth: depth),
    );

/// Neumorf: a round raised button (bell, heart, share, filter …).
class NeuRoundButton extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final double size;
  final String? tooltip;
  const NeuRoundButton({super.key, required this.child, this.onTap, this.size = 44, this.tooltip});

  @override
  Widget build(BuildContext context) {
    Widget b = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: AppColors.card, shape: BoxShape.circle, boxShadow: AppColors.neuRaised(depth: size / 48)),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(customBorder: const CircleBorder(), onTap: onTap, child: Center(child: child)),
      ),
    );
    if (tooltip != null) b = Tooltip(message: tooltip!, child: b);
    return b;
  }
}

/// Neumorf: [child] (a picture: the live map, a banner) in a pressed-in
/// frame; with Neumorf off it is [child] as it is.
class NeuInsetFrame extends StatelessWidget {
  final Widget child;
  final double radius;
  const NeuInsetFrame({super.key, required this.child, this.radius = 24});

  @override
  Widget build(BuildContext context) {
    if (!AppColors.neumorph) return child;
    return Container(
      key: const ValueKey('neu-inset-frame'),
      padding: const EdgeInsets.all(8),
      decoration: neuInsetDecoration(radius: radius),
      child: ClipRRect(borderRadius: BorderRadius.circular(radius - 6), child: child),
    );
  }
}
