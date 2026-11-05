import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// Premium (promoted) map markers — the owner's icons (05.11.2026): a gold
/// ring with a crown and the place's sign (TIR park, service, shop).
/// 20 % bigger than the ordinary marker; ordinary markers do not change.
enum PremiumPinKind { park, service, shop }

extension PremiumPinKindX on PremiumPinKind {
  String get asset => 'assets/images/premium/pin_$name.png';
}

/// The size of a premium marker: the ordinary marker's circle × 1.2 (the
/// icon's ring takes ~72 % of the picture).
const double kPremiumPinSize = 64;
const double kPremiumPinSelectedSize = 72;

class PremiumMapPin extends StatelessWidget {
  final PremiumPinKind kind;
  final double size;
  const PremiumMapPin({super.key, required this.kind, this.size = kPremiumPinSize});

  @override
  Widget build(BuildContext context) => Image.asset(
        kind.asset,
        key: ValueKey('premium-pin-${kind.name}'),
        width: size,
        height: size,
        filterQuality: FilterQuality.medium,
      );
}

/// A premium marker with, for Premium itself, the small "Premium" label
/// under its tip (owner's picture, 05.11.2026). The label hangs below the
/// marker's box, so the tip stays exactly on the place's point.
class PremiumMarker extends StatelessWidget {
  final PremiumPinKind kind;
  final double size;
  final String? label;
  const PremiumMarker({super.key, required this.kind, this.size = kPremiumPinSize, this.label});

  @override
  Widget build(BuildContext context) => Stack(clipBehavior: Clip.none, alignment: Alignment.topCenter, children: [
        PremiumMapPin(kind: kind, size: size),
        if (label != null)
          Positioned(
            top: size - 4,
            child: Container(
              key: const ValueKey('premium-label'),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.vipInk,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.vipGold, width: 1.2),
              ),
              child: Text(label!,
                  style: const TextStyle(color: AppColors.vipGoldLight, fontSize: 11, fontWeight: FontWeight.w500, height: 1.1)),
            ),
          ),
      ]);
}

/// A service that sells (spare parts — "Ehtiyat hissələri satışı", 0043)
/// is a shop on the map; the others are services.
PremiumPinKind premiumKindOfService(List<String> categories) =>
    categories.contains('spare_parts') ? PremiumPinKind.shop : PremiumPinKind.service;

/// The drop on entering the map (owner, 05.11.2026): each promoted marker
/// falls a little from above onto its own point, squashes once, bounces a
/// little and settles. Markers start one after another ([staggerMs]),
/// once per visit; the map moving never replays it.
class PremiumDrop {
  PremiumDrop._();

  static const durationMs = 800;
  static const staggerMs = 140;
  /// After this many markers the rest start together (no long wait).
  static const maxStagger = 10;
  static const fallPx = 34.0;
  static const bouncePx = 7.0;

  /// The whole run for every marker.
  static Duration get total => const Duration(milliseconds: durationMs + staggerMs * maxStagger);

  /// Marker [index]'s own progress (0–1) at [clock] (0–1 of [total]).
  static double local(double clock, int index) {
    final ms = clock * (durationMs + staggerMs * maxStagger) - math.min(index, maxStagger) * staggerMs;
    return (ms / durationMs).clamp(0.0, 1.0);
  }

  /// (dy, scaleX, scaleY, opacity) at [t]: fall → squash → small bounce → rest.
  static (double, double, double, double) at(double t) {
    if (t <= 0) return (-fallPx, 1, 1, 0);
    if (t >= 1) return (0, 1, 1, 1);
    final op = (t / 0.2).clamp(0.0, 1.0);
    if (t < 0.55) {
      final u = Curves.easeIn.transform(t / 0.55);
      return (-fallPx * (1 - u), 1, 1, op);
    }
    if (t < 0.7) {
      final k = math.sin((t - 0.55) / 0.15 * math.pi);
      return (0, 1 + 0.12 * k, 1 - 0.16 * k, 1);
    }
    if (t < 0.85) {
      final u = Curves.easeOut.transform((t - 0.7) / 0.15);
      return (-bouncePx * u, 1, 1, 1);
    }
    final u = Curves.easeIn.transform((t - 0.85) / 0.15);
    return (-bouncePx * (1 - u), 1, 1, 1);
  }
}

/// Wraps a premium marker: hidden until the drop starts, then falls onto its
/// point (its bottom stays the anchor). [index] null = it came later: shown
/// still, no animation.
class PremiumDropIn extends StatelessWidget {
  final Animation<double> clock;
  final bool started;
  final int? index;
  final Widget child;
  const PremiumDropIn({super.key, required this.clock, required this.started, required this.index, required this.child});

  @override
  Widget build(BuildContext context) {
    if (!started) return IgnorePointer(child: Opacity(opacity: 0, child: child));
    final i = index;
    if (i == null) return child;
    return AnimatedBuilder(
      animation: clock,
      child: child,
      builder: (context, c) {
        final (dy, sx, sy, op) = PremiumDrop.at(PremiumDrop.local(clock.value, i));
        return Opacity(
          opacity: op,
          child: Transform.translate(
            offset: Offset(0, dy),
            child: Transform(alignment: Alignment.bottomCenter, transform: Matrix4.diagonal3Values(sx, sy, 1), child: c),
          ),
        );
      },
    );
  }
}

/// The screen's side of the drop: map ready → 1 s → (promotions known) →
/// start once; the order of the promoted markers is fixed at the start.
mixin PremiumDropHost<T extends StatefulWidget> on State<T>, TickerProvider {
  AnimationController? _clock;
  AnimationController get premiumClock => _clock ??= AnimationController(vsync: this, duration: PremiumDrop.total);
  Timer? _readyTimer;
  bool _dropReady = false;
  bool premiumStarted = false;
  final Map<String, int> _dropOrder = {};

  /// Call from the map's onMapReady.
  void premiumMapReady() {
    _readyTimer?.cancel();
    _readyTimer = Timer(const Duration(seconds: 1), () {
      if (!mounted) return;
      setState(() => _dropReady = true);
    });
  }

  /// Call from build with the promoted ids on the map (null = not known yet).
  void premiumMaybeStart(List<String>? promotedIds) {
    if (premiumStarted || !_dropReady || promotedIds == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || premiumStarted) return;
      for (final id in promotedIds) {
        _dropOrder.putIfAbsent(id, () => _dropOrder.length);
      }
      setState(() => premiumStarted = true);
      premiumClock.forward(from: 0);
    });
  }

  /// Marker [id]'s place in the drop (null = came after the start).
  int? premiumIndex(String id) => _dropOrder[id];

  void disposePremium() {
    _readyTimer?.cancel();
    _clock?.dispose(); // only if it was made (never made while closing)
  }
}
