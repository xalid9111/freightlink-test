import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// The site's address shown under the wordmark.
const String kTirLinkSite = 'www.tirlink.app';

/// "TırLink" wordmark (owner, 13.11.2026): "Tır" white, "Link" in the
/// accent colour — a new night design (Admin → Dizayn və Rənglər) changes
/// only the colour of "Link". By day on a light ground "Tır" is dark so it
/// stays readable. Under it, small and in the same colour as "Tır",
/// www.tirlink.app.
///
/// The TIR Link logo (owner, 14.11.2026) replaces the old orange chart icon:
/// with [showLogo] it stands left of "TırLink", never taller than the
/// capital T, and www.tirlink.app stays right under the word.
class TirLinkWordmark extends StatelessWidget {
  final double size;
  final bool showSite;
  final bool showLogo;
  final CrossAxisAlignment align;
  const TirLinkWordmark(
      {super.key,
      required this.size,
      this.showSite = true,
      this.showLogo = false,
      this.align = CrossAxisAlignment.start});

  /// The logo picture (assets/images/brand, from the owner's file).
  static const logoAsset = 'assets/images/brand/tirlink_logo.png';

  /// Height of the capital T of "TırLink" (Arial cap height ≈ 0.716 em):
  /// the logo is never taller.
  static double capHeight(double size) => size * 0.716;

  /// The colour of "Tır" and of the site line: white, dark only by day.
  static Color get baseColor => AppColors.isDay ? AppColors.text : Colors.white;

  @override
  Widget build(BuildContext context) {
    final base = baseColor;
    final word = Text.rich(
      key: const ValueKey('tirlink-wordmark'),
      TextSpan(children: [
        TextSpan(text: 'Tır', style: AppFonts.display(size: size, color: base)),
        TextSpan(text: 'Link', style: AppFonts.display(size: size, color: AppColors.accent)),
      ]),
      maxLines: 1,
    );
    final site = Text(
      kTirLinkSite,
      key: const ValueKey('tirlink-site'),
      maxLines: 1,
      style: TextStyle(
          fontSize: (size * 0.42).clamp(8.0, 13.0),
          fontWeight: FontWeight.w400,
          color: base,
          height: 1.1,
          letterSpacing: 0.3),
    );
    if (!showLogo) {
      if (!showSite) return word;
      return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: align, children: [word, site]);
    }
    final logoSide = capHeight(size);
    final gap = size * 0.25;
    final logo = Image.asset(
      logoAsset,
      key: const ValueKey('tirlink-logo'),
      width: logoSide,
      height: logoSide,
      filterQuality: FilterQuality.medium,
      // A missing / undecodable file never breaks the header.
      errorBuilder: (_, __, ___) => SizedBox(width: logoSide, height: logoSide),
    );
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(mainAxisSize: MainAxisSize.min, children: [logo, SizedBox(width: gap), word]),
      if (showSite) Padding(padding: EdgeInsets.only(left: logoSide + gap), child: site),
    ]);
  }
}
