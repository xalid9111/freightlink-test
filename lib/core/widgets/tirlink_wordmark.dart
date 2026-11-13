import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// The site's address shown under the wordmark.
const String kTirLinkSite = 'www.tirlink.app';

/// "TırLink" wordmark (owner, 13.11.2026): "Tır" white, "Link" in the
/// accent colour — a new night design (Admin → Dizayn və Rənglər) changes
/// only the colour of "Link". By day on a light ground "Tır" is dark so it
/// stays readable. Under it, small and in the same colour as "Tır",
/// www.tirlink.app.
class TirLinkWordmark extends StatelessWidget {
  final double size;
  final bool showSite;
  final CrossAxisAlignment align;
  const TirLinkWordmark({super.key, required this.size, this.showSite = true, this.align = CrossAxisAlignment.start});

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
    if (!showSite) return word;
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: align, children: [
      word,
      Text(
        kTirLinkSite,
        key: const ValueKey('tirlink-site'),
        maxLines: 1,
        style: TextStyle(fontSize: (size * 0.42).clamp(8.0, 13.0), fontWeight: FontWeight.w400, color: base, height: 1.1, letterSpacing: 0.3),
      ),
    ]);
  }
}
