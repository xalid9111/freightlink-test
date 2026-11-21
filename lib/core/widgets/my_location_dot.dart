import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// The user's own place on the maps (owner, 21.11.2026: "konum olduğum yer
/// işıq kimi yanıb sönsün, diqqət çəksin"): the blue dot with a white ring,
/// a soft glow that breathes with it, and a light wave that spreads out of
/// it and fades — every [kMyLocationPulse]. Phones that ask for less motion
/// get the same dot with a still halo. One small animation in its own
/// RepaintBoundary, so the map under it is never repainted for it.
const Duration kMyLocationPulse = Duration(milliseconds: 1800);

/// The marker box the dot needs (the wave reaches its edge).
const double kMyLocationBox = 64;

class MyLocationDot extends StatefulWidget {
  /// The blue dot's own size (the white ring included).
  final double dot;
  const MyLocationDot({super.key, this.dot = 18});

  @override
  State<MyLocationDot> createState() => _MyLocationDotState();
}

class _MyLocationDotState extends State<MyLocationDot> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: kMyLocationPulse);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (still) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return RepaintBoundary(
      child: SizedBox(
        key: const ValueKey('my-location-dot'),
        width: kMyLocationBox,
        height: kMyLocationBox,
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, _) => CustomPaint(
            painter: MyLocationPainter(t: still ? -1 : _c.value, dot: widget.dot, color: AppColors.blue),
          ),
        ),
      ),
    );
  }
}

/// [t] 0…1 = the moment of the pulse; −1 = still (no wave, a steady halo).
class MyLocationPainter extends CustomPainter {
  final double t;
  final double dot;
  final Color color;
  const MyLocationPainter({required this.t, required this.dot, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = dot / 2;
    final maxR = size.shortestSide / 2;
    if (t < 0) {
      canvas.drawCircle(c, r * 1.9, Paint()..color = color.withValues(alpha: 0.22));
    } else {
      // The wave: grows from the dot to the box's edge and fades out.
      final e = Curves.easeOut.transform(t);
      final waveR = r + (maxR - r) * e;
      canvas.drawCircle(c, waveR, Paint()..color = color.withValues(alpha: 0.38 * (1 - e)));
      canvas.drawCircle(
        c,
        waveR,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = color.withValues(alpha: 0.55 * (1 - e)),
      );
      // The glow breathes: brightest when the wave leaves the dot.
      final glow = 0.5 + 0.5 * (1 - (2 * t - 1).abs());
      canvas.drawCircle(
        c,
        r * 1.6,
        Paint()
          ..color = color.withValues(alpha: 0.35 + 0.35 * glow)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, 4 + 4 * glow),
      );
    }
    canvas.drawCircle(c, r, Paint()..color = Colors.white);
    canvas.drawCircle(c, r - 2.5, Paint()..color = color);
  }

  @override
  bool shouldRepaint(MyLocationPainter old) => old.t != t || old.dot != dot || old.color != color;
}
