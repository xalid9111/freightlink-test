import 'package:flutter/widgets.dart';

/// Width (in pixels) a network picture is decoded at: the box it is shown
/// in × the screen's pixel ratio, so a 169 pt list tile does not hold an
/// 800 px picture in memory and a full-width page stays sharp. The larger
/// side of the box is used (BoxFit.cover may need it). [fallback] when the
/// box has no finite size.
int decodeWidthFor(BoxConstraints c, double devicePixelRatio, {int min = 240, int max = 1200, int fallback = 800}) {
  final w = c.hasBoundedWidth ? c.maxWidth : double.nan;
  final h = c.hasBoundedHeight ? c.maxHeight : double.nan;
  final side = [w, h].where((v) => v.isFinite && v > 0).fold<double>(0, (a, b) => a > b ? a : b);
  if (side <= 0) return fallback;
  return (side * devicePixelRatio).round().clamp(min, max);
}
