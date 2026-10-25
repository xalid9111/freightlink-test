import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Gold VIP frame around the picture of a VIP ad (owner, 24.10.2026,
/// sample picture): a shiny gold border with a dark inner line, a gold
/// ribbon across the top-left corner, a black-and-gold "VIP" seal with a
/// crown on it, and a few small sparkles. Only the picture is framed —
/// the text under it stays as it is. Drawn in code, so it is sharp at any
/// size and looks the same by day and by night. It replaces the older
/// marks (orange card frame, gold medal, VIP chip, crown icon), so a VIP
/// ad never shows two of them.
class VipPictureFrame extends StatelessWidget {
  final Widget child;
  /// Corner radius of the picture (matches the card).
  final double radius;
  /// False: only the round VIP seal, no gold band, ribbon or sparkles
  /// (TIR Bazarı feed, owner 25.10.2026).
  final bool frame;
  const VipPictureFrame({super.key, required this.child, this.radius = 14, this.frame = true});

  @override
  Widget build(BuildContext context) {
    return Stack(fit: StackFit.expand, children: [
      ClipRRect(borderRadius: BorderRadius.circular(radius), child: child),
      IgnorePointer(
        child: CustomPaint(
            key: ValueKey(frame ? 'vip-frame' : 'vip-seal'), painter: VipFramePainter(radius: radius, frame: frame)),
      ),
    ]);
  }
}

class VipFramePainter extends CustomPainter {
  final double radius;
  final bool frame;
  const VipFramePainter({this.radius = 14, this.frame = true});

  static const _gold = AppColors.vipGold;
  static const _dark = AppColors.vipGoldDark;
  static const _light = AppColors.vipGoldLight;
  static const _ink = AppColors.vipInk;
  static const _spark = AppColors.vipSpark;

  Shader _metal(Rect r) => const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [_light, _gold, _dark, _gold, _light, _gold, _dark],
        stops: [0.0, 0.18, 0.34, 0.5, 0.66, 0.84, 1.0],
      ).createShader(r);

  @override
  void paint(Canvas canvas, Size size) {
    final s = math.min(size.width, size.height);
    final t = (s * 0.04).clamp(3.0, 9.0); // band width
    final rect = Offset.zero & size;
    final c = Offset(s * 0.2, s * 0.2); // seal centre
    final rr = s * 0.155; // seal radius
    if (!frame) {
      _seal(canvas, c, rr);
      return;
    }

    // 1) The gold band, a dark line inside it and a light edge outside.
    final band = RRect.fromRectAndRadius(rect.deflate(t / 2), Radius.circular(math.max(0, radius - t / 2)));
    canvas.drawRRect(band, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = t
      ..shader = _metal(rect));
    canvas.drawRRect(
        RRect.fromRectAndRadius(rect.deflate(t + 0.8), Radius.circular(math.max(0, radius - t))),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4
          ..color = _ink.withValues(alpha: 0.85));
    canvas.drawRRect(
        RRect.fromRectAndRadius(rect.deflate(0.6), Radius.circular(radius)),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = _light.withValues(alpha: 0.9));

    // 2) Ribbon across the top-left corner, under the seal.
    final w = s * 0.075; // ribbon width
    final ribbon = Path()
      ..moveTo(0, s * 0.42 - w)
      ..lineTo(s * 0.42 - w, 0)
      ..lineTo(s * 0.42 + w * 0.2, 0)
      ..lineTo(0, s * 0.42 + w * 0.2)
      ..close();
    canvas.save();
    canvas.clipRRect(RRect.fromRectAndRadius(rect, Radius.circular(radius)));
    canvas.drawPath(ribbon, Paint()..shader = _metal(Rect.fromLTWH(0, 0, s * 0.45, s * 0.45)));
    canvas.drawPath(ribbon, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = _dark);
    canvas.restore();

    // 3) The seal.
    _seal(canvas, c, rr);

    // 4) Small sparkles on the band (not near the heart, top right).
    void sparkle(Offset p, double r) {
      canvas.drawCircle(p, r * 0.9, Paint()
        ..color = _light.withValues(alpha: 0.75)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.7));
      final star = Path()
        ..moveTo(p.dx, p.dy - r * 1.6)
        ..quadraticBezierTo(p.dx, p.dy, p.dx + r * 1.6, p.dy)
        ..quadraticBezierTo(p.dx, p.dy, p.dx, p.dy + r * 1.6)
        ..quadraticBezierTo(p.dx, p.dy, p.dx - r * 1.6, p.dy)
        ..quadraticBezierTo(p.dx, p.dy, p.dx, p.dy - r * 1.6)
        ..close();
      canvas.drawPath(star, Paint()..color = _spark);
    }

    final r = (s * 0.022).clamp(2.0, 6.0);
    sparkle(Offset(size.width * 0.34, t / 2), r);
    sparkle(Offset(size.width - t / 2, size.height * 0.36), r * 0.9);
    sparkle(Offset(t / 2, size.height * 0.58), r);
    sparkle(Offset(size.width * 0.5, size.height - t / 2), r);
    sparkle(Offset(size.width - t * 0.9, size.height - t * 0.9), r * 0.9);
  }

  /// The seal: gold ring, black disc, crown and "VIP".
  void _seal(Canvas canvas, Offset c, double rr) {
    canvas.drawCircle(c + Offset(0, rr * 0.06), rr * 1.04, Paint()
      ..color = _ink.withValues(alpha: 0.45)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.5));
    canvas.drawCircle(c, rr, Paint()..shader = _metal(Rect.fromCircle(center: c, radius: rr)));
    canvas.drawCircle(c, rr * 0.8, Paint()..color = _ink);
    canvas.drawCircle(c, rr * 0.8, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1, rr * 0.05)
      ..color = _light.withValues(alpha: 0.9));
    // Crown.
    final cw = rr * 0.62, ch = rr * 0.3;
    final top = c.dy - rr * 0.6;
    final crown = Path()
      ..moveTo(c.dx - cw / 2, top + ch)
      ..lineTo(c.dx - cw / 2, top + ch * 0.25)
      ..lineTo(c.dx - cw / 4, top + ch * 0.62)
      ..lineTo(c.dx, top)
      ..lineTo(c.dx + cw / 4, top + ch * 0.62)
      ..lineTo(c.dx + cw / 2, top + ch * 0.25)
      ..lineTo(c.dx + cw / 2, top + ch)
      ..close();
    canvas.drawPath(crown, Paint()..shader = _metal(Rect.fromLTWH(c.dx - cw / 2, top, cw, ch)));
    // "VIP".
    final tp = TextPainter(
      text: TextSpan(
        text: 'VIP',
        style: TextStyle(
          fontSize: rr * 0.72,
          fontWeight: FontWeight.w900,
          height: 1,
          letterSpacing: -0.5,
          foreground: Paint()..shader = _metal(Rect.fromCenter(center: c, width: rr * 1.4, height: rr * 0.8)),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(c.dx - tp.width / 2, c.dy - tp.height / 2 + rr * 0.16));
  }

  @override
  bool shouldRepaint(covariant VipFramePainter old) => old.radius != radius || old.frame != frame;
}
