import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'app_theme.dart';

/// The night colours the admin chooses (owner, 29.10.2026: Admin → Dizayn
/// və Rənglər → Gecə rejimi). Only night mode: the day palette
/// ([AppPalette.light]) never changes. Status colours (online, danger,
/// route, VIP gold, WhatsApp …) and pictures keep their own colours.
class NightThemeSpec {
  final Color background, card, button, accent, line, text, textSoft;

  /// 0…1: how much the accent tints the top / bottom bars.
  final double gradient;

  /// 0…1: soft shadow / glow under cards and buttons.
  final double glow;

  const NightThemeSpec({
    required this.background,
    required this.card,
    required this.button,
    required this.accent,
    required this.line,
    required this.text,
    required this.textSoft,
    this.gradient = 0,
    this.glow = 0,
  });

  /// "Klassik FreightLink": the existing navy / orange night (exactly
  /// [AppPalette.dark]).
  static final classic = NightThemeSpec(
    background: AppPalette.dark.background,
    card: AppPalette.dark.card,
    button: AppPalette.dark.accentFill,
    accent: AppPalette.dark.accent,
    line: AppPalette.dark.line,
    text: AppPalette.dark.text,
    textSoft: AppPalette.dark.textSoft,
  );

  /// "Bordo Premium" (owner's pictures and colours, 29.10.2026).
  static const bordo = NightThemeSpec(
    background: Color(0xFF090A0E),
    card: Color(0xFF1C171D),
    button: Color(0xFF8F2945),
    accent: Color(0xFFC34467),
    line: Color(0xFF512837),
    text: Color(0xFFF5F2F4),
    textSoft: Color(0xFFA9A4AB),
    gradient: 0.35,
    glow: 0.3,
  );

  static const colorKeys = ['background', 'card', 'button', 'accent', 'line', 'text', 'text_soft'];

  Color colorOf(String key) => switch (key) {
        'background' => background,
        'card' => card,
        'button' => button,
        'accent' => accent,
        'line' => line,
        'text' => text,
        _ => textSoft,
      };

  NightThemeSpec withColor(String key, Color c) => NightThemeSpec(
        background: key == 'background' ? c : background,
        card: key == 'card' ? c : card,
        button: key == 'button' ? c : button,
        accent: key == 'accent' ? c : accent,
        line: key == 'line' ? c : line,
        text: key == 'text' ? c : text,
        textSoft: key == 'text_soft' ? c : textSoft,
        gradient: gradient,
        glow: glow,
      );

  NightThemeSpec withLevels({double? gradient, double? glow}) => NightThemeSpec(
        background: background,
        card: card,
        button: button,
        accent: accent,
        line: line,
        text: text,
        textSoft: textSoft,
        gradient: (gradient ?? this.gradient).clamp(0.0, 1.0),
        glow: (glow ?? this.glow).clamp(0.0, 1.0),
      );

  /// Same colours and levels as "Klassik FreightLink".
  bool get isClassic => sameAs(classic);

  bool sameAs(NightThemeSpec o) =>
      [for (final k in colorKeys) colorOf(k).toARGB32()].join() == [for (final k in colorKeys) o.colorOf(k).toARGB32()].join() &&
      (gradient - o.gradient).abs() < 0.005 &&
      (glow - o.glow).abs() < 0.005;

  Map<String, dynamic> toJson() => {
        for (final k in colorKeys) k: hexOf(colorOf(k)),
        'gradient': double.parse(gradient.toStringAsFixed(2)),
        'glow': double.parse(glow.toStringAsFixed(2)),
      };

  /// Null when anything is missing or not a #RRGGBB colour (the server
  /// checks the same, migration 0076).
  static NightThemeSpec? fromJson(Object? j) {
    if (j is! Map) return null;
    final c = <String, Color>{};
    for (final k in colorKeys) {
      final v = parseHex(j[k]?.toString());
      if (v == null) return null;
      c[k] = v;
    }
    double level(Object? v) => (v is num ? v.toDouble() : double.tryParse('$v') ?? 0).clamp(0.0, 1.0);
    return NightThemeSpec(
      background: c['background']!,
      card: c['card']!,
      button: c['button']!,
      accent: c['accent']!,
      line: c['line']!,
      text: c['text']!,
      textSoft: c['text_soft']!,
      gradient: level(j['gradient']),
      glow: level(j['glow']),
    );
  }

  /// The app palette for these colours. "Klassik" gives [AppPalette.dark]
  /// itself, so nothing changes for it; the status colours stay classic.
  AppPalette toPalette() {
    if (isClassic) return AppPalette.dark;
    const d = AppPalette.dark;
    return AppPalette(
      brightness: Brightness.dark,
      background: background,
      hero: background,
      card: card,
      cardAlt: Color.lerp(card, text, 0.04)!,
      line: line,
      lineSoft: Color.lerp(line, card, 0.5)!,
      text: text,
      textSoft: textSoft,
      accent: accent,
      accentFill: button,
      myBubble: button,
      route: d.route,
      routeSoft: d.routeSoft,
      blue: d.blue,
      online: d.online,
      danger: d.danger,
      urgentBg: d.urgentBg,
      urgentFg: d.urgentFg,
      newBg: d.newBg,
      newFg: d.newFg,
      gradient: gradient,
      glow: glow,
      custom: true,
    );
  }
}

/// "#RRGGBB" (upper case).
String hexOf(Color c) => '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

/// "#RRGGBB" / "RRGGBB" → an opaque colour; null otherwise.
Color? parseHex(String? s) {
  final t = (s ?? '').trim().replaceFirst('#', '');
  if (!RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(t)) return null;
  return Color(0xFF000000 | int.parse(t, radix: 16));
}

/// WCAG contrast ratio of two colours (1…21).
double contrastRatio(Color a, Color b) {
  double lum(Color c) {
    double ch(double v) => v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
    return 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b);
  }

  final l1 = lum(a), l2 = lum(b);
  return (math.max(l1, l2) + 0.05) / (math.min(l1, l2) + 0.05);
}

/// One line of the automatic readability check.
class ContrastCheck {
  final String label;
  final double ratio, need;
  const ContrastCheck(this.label, this.ratio, this.need);
  bool get ok => ratio >= need;
}

/// Text on the page and on cards ≥ 4.5, grey text ≥ 3, white on the
/// buttons ≥ 3, accent on cards ≥ 3. Publishing needs the first two.
List<ContrastCheck> contrastChecks(NightThemeSpec s) => [
      ContrastCheck('Əsas mətn / fon', contrastRatio(s.text, s.background), 4.5),
      ContrastCheck('Əsas mətn / kart', contrastRatio(s.text, s.card), 4.5),
      ContrastCheck('İkinci mətn / kart', contrastRatio(s.textSoft, s.card), 3),
      ContrastCheck('Ağ yazı / düymə', contrastRatio(Colors.white, s.button), 3),
      ContrastCheck('Vurğu / kart', contrastRatio(s.accent, s.card), 3),
    ];

/// Publishing is allowed when the main text reads well on the page and cards.
bool readableEnough(NightThemeSpec s) => contrastChecks(s).take(2).every((c) => c.ok);
