import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../models/ad_models.dart';

/// Draws an ad banner. The SAME widget is used for the live preview, the
/// admin panel and the home feed, so what the customer sees is exactly
/// what gets published.
///
/// Standard banners (version 2) use the fixed 1200×400 coordinate sheet:
/// background (fills everything) → soft dark gradient behind the text area
/// → logo circle (30,120,160×160) → company (220,45,440×85) → activity
/// (220,150,440×75) → phone (220,250,440×70). Every text gets the automatic
/// two-layer shadow and shrinks until it fits its box (1–2 lines, phone 1).
class AdCreativeView extends StatelessWidget {
  final AdCreative creative;
  final BorderRadius? radius;
  /// Editor preview: show "LOGO" / field names where nothing is filled in.
  final bool showPlaceholders;
  const AdCreativeView({super.key, required this.creative, this.radius, this.showPlaceholders = false});

  @override
  Widget build(BuildContext context) {
    final child = creative.isStandard ? _StandardBanner(c: creative, placeholders: showPlaceholders) : _LegacyBanner(c: creative, placeholders: showPlaceholders);
    if (radius == null) return child;
    return ClipRRect(borderRadius: radius!, child: child);
  }
}

/// Every ad is drawn in the app font (Arial). Older ads may still carry
/// another font name in their saved style; it is ignored, so all banners
/// look the same. Layout coordinates are not affected.
TextStyle adFontStyle(String font, TextStyle base) => base.copyWith(fontFamily: AppFonts.family);

/// Shadow from the brief: 0 2px 4px rgba(0,0,0,.9), 0 4px 10px rgba(0,0,0,.65)
/// — scaled with the banner so preview and feed match.
List<Shadow> adTextShadows(double s) => [
      Shadow(color: const Color(0xE6000000), offset: Offset(0, 2 * s), blurRadius: 4 * s),
      Shadow(color: const Color(0xA6000000), offset: Offset(0, 4 * s), blurRadius: 10 * s),
    ];

class _StandardBanner extends StatelessWidget {
  final AdCreative c;
  final bool placeholders;
  const _StandardBanner({required this.c, required this.placeholders});

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: AdStandardLayout.width / AdStandardLayout.height,
      child: LayoutBuilder(
        builder: (context, box) {
          final s = box.maxWidth / AdStandardLayout.width; // banner px → screen px
          final hasLogo = (c.logoUrl ?? '').isNotEmpty;
          return Stack(
            fit: StackFit.expand,
            clipBehavior: Clip.hardEdge,
            children: [
              // 1) background — fills the whole 1200×400, never cropped (same ratio)
              if (c.imageUrl.isNotEmpty)
                Image.network(
                  c.imageUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => ColoredBox(color: AppColors.cardAlt),
                  loadingBuilder: (context, child, p) => p == null ? child : ColoredBox(color: AppColors.cardAlt),
                )
              else
                ColoredBox(color: AppColors.cardAlt),
              // 2) soft dark gradient behind the text area, fading into the photo
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                width: 780 * s,
                child: const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Color(0x8C000000), Color(0x59000000), Color(0x00000000)],
                      stops: [0, 0.6, 1],
                    ),
                  ),
                ),
              ),
              // 3) logo circle — fixed place and size; the logo is cut round to fill it
              if (hasLogo || placeholders)
                Positioned(
                  left: AdStandardLayout.logoX * s,
                  top: AdStandardLayout.logoY * s,
                  width: AdStandardLayout.logoSize * s,
                  height: AdStandardLayout.logoSize * s,
                  // The logo fills the whole circle (cut round, no square
                  // corners); the circle's place and size never change.
                  child: ClipOval(
                    child: Container(
                      color: switch (c.logoBg) {
                        'light' => const Color(0xD9FFFFFF),
                        'none' => Colors.transparent,
                        _ => const Color(0x8C000000),
                      },
                      padding: hasLogo ? EdgeInsets.zero : EdgeInsets.all(14 * s),
                      alignment: Alignment.center,
                      child: hasLogo
                          ? SizedBox.expand(
                              child: Image.network(c.logoUrl!, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const SizedBox()),
                            )
                          : DecoratedBox(
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white54, width: math.max(1.0, 3 * s)),
                              ),
                              child: Center(
                                child: Text('LOGO',
                                    style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w800, fontSize: 34 * s)),
                              ),
                            ),
                    ),
                  ),
                ),
              // 4) texts
              _box(s, 'company', AdStandardLayout.company, FontWeight.w800, placeholderText: 'ŞİRKƏT ADI'),
              _box(s, 'activity', AdStandardLayout.activity, FontWeight.w600, placeholderText: 'Fəaliyyət sahəsi'),
              _box(s, 'phone', AdStandardLayout.phone, FontWeight.w700, placeholderText: '+994 00 000 00 00', icon: Icons.phone_in_talk),
            ],
          );
        },
      ),
    );
  }

  Widget _box(
    double s,
    String key,
    ({double x, double y, double w, double h, int lines, double base}) b,
    FontWeight weight, {
    required String placeholderText,
    IconData? icon,
  }) {
    final raw = (c.texts[key] ?? '').trim();
    final isPlaceholder = raw.isEmpty;
    if (isPlaceholder && !placeholders) return const SizedBox.shrink();
    final text = isPlaceholder ? placeholderText : raw;
    final st = c.styleOf(key);
    final color = Color(adColorValue(st.color));
    final boxW = b.w * s;
    final boxH = b.h * s;
    final iconW = icon == null ? 0.0 : boxH * 0.62 + 10 * s;
    final style = adFontStyle(
      st.font,
      TextStyle(
        color: isPlaceholder ? color.withValues(alpha: 0.55) : color,
        fontWeight: weight,
        height: 1.08,
        shadows: adTextShadows(s),
      ),
    );
    final size = _fit(text, style, b.base * st.size * s, boxW - iconW, boxH, b.lines);
    final textWidget = Text(
      text,
      maxLines: b.lines,
      overflow: TextOverflow.ellipsis,
      softWrap: b.lines > 1,
      style: style.copyWith(fontSize: size),
    );
    return Positioned(
      left: b.x * s,
      top: b.y * s,
      width: boxW,
      height: boxH,
      // FittedBox is only a safety net if a web font arrives a bit wider.
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: SizedBox(
          width: boxW,
          child: Row(
            children: [
              if (icon != null) ...[
                Icon(icon, size: math.min(size * 0.95, boxH * 0.62), color: color, shadows: adTextShadows(s)),
                SizedBox(width: 10 * s),
              ],
              Expanded(child: textWidget),
            ],
          ),
        ),
      ),
    );
  }

  /// Largest font size ≤ [start] at which [text] fits [maxW]×[maxH] in at
  /// most [lines] lines (no word broken, nothing outside the box).
  static double _fit(String text, TextStyle style, double start, double maxW, double maxH, int lines) {
    if (maxW <= 0 || maxH <= 0 || start <= 1) return math.max(1.0, start);
    var size = start;
    final minSize = math.max(1.0, start * 0.25);
    while (size > minSize) {
      final tp = TextPainter(
        text: TextSpan(text: text, style: style.copyWith(fontSize: size)),
        textDirection: TextDirection.ltr,
        maxLines: lines,
      )..layout(maxWidth: maxW);
      // the longest single word must fit on one line too
      final words = text.split(RegExp(r'\s+'));
      var longest = 0.0;
      for (final w in words) {
        final wp = TextPainter(text: TextSpan(text: w, style: style.copyWith(fontSize: size)), textDirection: TextDirection.ltr)
          ..layout();
        longest = math.max(longest, wp.width);
        wp.dispose();
      }
      final ok = !tp.didExceedMaxLines && tp.height <= maxH && longest <= maxW;
      tp.dispose();
      if (ok) return size;
      size *= 0.92;
    }
    return minSize;
  }
}

/// Banners made with the old free layout (0021/0022, 1350×300). They are
/// no longer published; shown only in order history / admin.
class _LegacyBanner extends StatelessWidget {
  final AdCreative c;
  final bool placeholders;
  const _LegacyBanner({required this.c, required this.placeholders});

  static const double _w = 1350, _h = 300;

  @override
  Widget build(BuildContext context) {
    final color = Color(adColorValue(c.color));
    return AspectRatio(
      aspectRatio: _w / _h,
      child: LayoutBuilder(
        builder: (context, box) {
          final w = box.maxWidth;
          final h = box.maxHeight;
          final scale = w / _w;
          return Stack(
            fit: StackFit.expand,
            children: [
              if (c.imageUrl.isNotEmpty)
                Image.network(c.imageUrl, fit: BoxFit.cover, errorBuilder: (_, __, ___) => ColoredBox(color: AppColors.cardAlt))
              else
                ColoredBox(color: AppColors.cardAlt),
              if (c.logo != null && (c.logoUrl != null || placeholders))
                Positioned(
                  left: c.logo!.x * w,
                  top: c.logo!.y * h,
                  width: math.max(0.0, math.min(c.logo!.w * w, w - c.logo!.x * w)),
                  height: math.max(0.0, math.min(c.logo!.h * h, h - c.logo!.y * h)),
                  child: c.logoUrl != null
                      ? Image.network(c.logoUrl!, fit: BoxFit.contain, errorBuilder: (_, __, ___) => const SizedBox())
                      : const SizedBox(),
                ),
              for (final f in c.fields)
                if ((c.texts[f.key] ?? '').trim().isNotEmpty || placeholders)
                  Positioned(
                    left: f.x * w,
                    top: f.y * h,
                    width: math.max(0.0, math.min(f.w * w, w - f.x * w)),
                    child: Text(
                      (c.texts[f.key] ?? '').trim().isEmpty ? f.label : c.texts[f.key]!.trim(),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: color,
                        fontSize: (f.size * scale).clamp(6.0, 200.0).toDouble(),
                        height: 1.1,
                        fontWeight: f.bold ? FontWeight.w800 : FontWeight.w500,
                        shadows: adTextShadows(scale),
                      ),
                    ),
                  ),
            ],
          );
        },
      ),
    );
  }
}
