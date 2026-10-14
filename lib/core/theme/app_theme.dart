import 'package:flutter/material.dart';
import '../router/browser_nav.dart';
import 'flag_font.dart';

/// Design tokens for the approved "night map" design (dark navy ground,
/// orange accent, teal route color — see the FreightLink mobile design
/// canvas). Keep this the only place colors and fonts are defined so
/// screens stay visually consistent.
class AppColors {
  AppColors._();
  static const background = Color(0xFF02050C); // page ground = sea of the live map
  static const hero = Color(0xFF02050C); // map panel, bars, inputs (same tone as the page)
  static const card = Color(0xFF0C1322);
  static const cardAlt = Color(0xFF131B2B);
  static const line = Color(0xFF1C2638);
  static const lineSoft = Color(0xFF161F30);
  static const text = Color(0xFFF2F4F7);
  static const textSoft = Color(0xFF9AA4B5);
  static const accent = Color(0xFFFF6B33); // orange on dark (text/icons)
  static const accentFill = Color(0xFFD4420E); // orange fills with white text
  static const myBubble = Color(0xFFC93D0C);
  static const route = Color(0xFF2BB3A9); // teal: route lines, done steps
  static const routeSoft = Color(0xFF0F2B2A);
  static const blue = Color(0xFF3BA3FF);
  static const online = Color(0xFF4ADE80);
  static const danger = Color(0xFFFF6B6B);

  // Badge tints (background, foreground) — readable on dark cards.
  static const urgentBg = Color(0xFF3A1A10);
  static const urgentFg = Color(0xFFFF8A5C);
  static const newBg = Color(0xFF0F2B2A);
  static const newFg = Color(0xFF5FD4C9);
}

/// WhatsApp-like chat palette (dark), so chats feel familiar.
class ChatColors {
  ChatColors._();
  static const background = Color(0xFF0B141A);
  static const dots = Color(0xFF13212A);
  static const mine = Color(0xFF005C4B);
  static const theirs = Color(0xFF1F2C34);
  static const meta = Color(0xFF8696A0);
  static const readTick = Color(0xFF53BDEB);
  static const dateChip = Color(0xFF182229);
}

/// The whole app uses ONE font: Arial (bundled; see pubspec.yaml).
/// `display` (headings, prices) and `mono` (ids, small caps labels) only
/// change size / weight / spacing — never the font.
class AppFonts {
  AppFonts._();

  static const family = 'Arial';

  /// Characters Arial does not have: country flags (see flag_font.dart).
  static const fallback = [kFlagFontFamily];

  static TextStyle display({double size = 22, Color? color, FontWeight weight = FontWeight.w800, double? height}) =>
      TextStyle(fontFamily: family, fontFamilyFallback: fallback, fontSize: size, color: color, fontWeight: weight, height: height, letterSpacing: 0.2);

  static TextStyle mono({double size = 11, Color? color, FontWeight weight = FontWeight.w700, double letterSpacing = 0.6}) =>
      TextStyle(fontFamily: family, fontFamilyFallback: fallback, fontSize: size, color: color, fontWeight: weight, letterSpacing: letterSpacing);
}

class AppTheme {
  AppTheme._();

  /// The app uses this one dark theme everywhere (MaterialApp forces
  /// ThemeMode.dark) — the approved design has no light variant.
  static ThemeData get dark {
    final base = ThemeData(useMaterial3: true, brightness: Brightness.dark, fontFamily: AppFonts.family, fontFamilyFallback: AppFonts.fallback);
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.accentFill,
      brightness: Brightness.dark,
    ).copyWith(
      primary: AppColors.accentFill,
      onPrimary: Colors.white,
      secondary: AppColors.route,
      onSecondary: AppColors.background,
      surface: AppColors.card,
      onSurface: AppColors.text,
      onSurfaceVariant: AppColors.textSoft,
      surfaceContainerHighest: AppColors.cardAlt,
      outline: AppColors.line,
      outlineVariant: AppColors.lineSoft,
      error: AppColors.danger,
    );

    final textTheme = base.textTheme.apply(fontFamily: AppFonts.family, bodyColor: AppColors.text, displayColor: AppColors.text);

    return base.copyWith(
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.background,
      textTheme: textTheme,
      // One short, single page transition (fade + small rise) on every
      // platform. The default iOS transition also slides the previous page
      // and, in Safari, adds the browser's own animation — together they
      // looked like the page changed twice.
      pageTransitionsTheme: const PageTransitionsTheme(builders: {
        TargetPlatform.iOS: _SoftPageTransitionsBuilder(),
        TargetPlatform.android: _SoftPageTransitionsBuilder(),
        TargetPlatform.macOS: _SoftPageTransitionsBuilder(),
        TargetPlatform.windows: _SoftPageTransitionsBuilder(),
        TargetPlatform.linux: _SoftPageTransitionsBuilder(),
        TargetPlatform.fuchsia: _SoftPageTransitionsBuilder(),
      }),
      cardTheme: CardThemeData(
        elevation: 0,
        color: AppColors.card,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: AppColors.line),
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.hero,
        foregroundColor: AppColors.text,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        titleTextStyle: AppFonts.display(size: 22, color: AppColors.text),
        shape: const Border(bottom: BorderSide(color: AppColors.lineSoft)),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: AppColors.hero,
        surfaceTintColor: Colors.transparent,
        indicatorColor: AppColors.accent.withValues(alpha: 0.16),
        iconTheme: WidgetStateProperty.resolveWith((states) => IconThemeData(
              color: states.contains(WidgetState.selected) ? AppColors.accent : AppColors.textSoft,
            )),
        labelTextStyle: WidgetStateProperty.resolveWith((states) => TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              color: states.contains(WidgetState.selected) ? AppColors.accent : AppColors.textSoft,
            )),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.hero,
        labelStyle: const TextStyle(color: AppColors.textSoft),
        hintStyle: const TextStyle(color: AppColors.textSoft),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.line)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.line)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.accent, width: 1.5)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.accentFill,
          foregroundColor: Colors.white,
          minimumSize: const Size(48, 48),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.text,
          side: const BorderSide(color: AppColors.line),
          minimumSize: const Size(48, 48),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: AppColors.accent),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppColors.accentFill,
        foregroundColor: Colors.white,
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: AppColors.cardAlt,
        side: const BorderSide(color: AppColors.line),
        // Chips do not take the text theme's font list → flags fallback here too.
        labelStyle: const TextStyle(color: AppColors.text, fontWeight: FontWeight.w600, fontFamilyFallback: AppFonts.fallback),
      ),
      dividerTheme: const DividerThemeData(color: AppColors.line),
      bottomSheetTheme: const BottomSheetThemeData(backgroundColor: AppColors.card, surfaceTintColor: Colors.transparent),
      dialogTheme: const DialogThemeData(backgroundColor: AppColors.card, surfaceTintColor: Colors.transparent),
      snackBarTheme: const SnackBarThemeData(backgroundColor: AppColors.cardAlt, contentTextStyle: TextStyle(color: AppColors.text)),
    );
  }

  /// Kept so any older reference still compiles; identical to [dark].
  static ThemeData get light => dark;
}

/// New page fades in and rises 2 %; the page underneath does not move.
class _SoftPageTransitionsBuilder extends PageTransitionsBuilder {
  const _SoftPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    // Back / forward done by the browser itself (Safari swipe, back
    // button): Safari has already animated it — animating again here was
    // the "double transition". The leaving page disappears at once and the
    // arriving one is shown as is. Taps inside the app keep the animation.
    if (recentBrowserNavigation()) {
      return animation.status == AnimationStatus.reverse ? const SizedBox.shrink() : child;
    }
    final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInCubic);
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween<Offset>(begin: const Offset(0, 0.02), end: Offset.zero).animate(curved),
        child: child,
      ),
    );
  }
}
