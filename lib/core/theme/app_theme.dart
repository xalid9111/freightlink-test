import 'package:flutter/material.dart';
import '../router/browser_nav.dart';
import 'flag_font.dart';

/// One set of app colours. [dark] is the approved "night map" design
/// (dark navy ground, orange accent, teal route colour) and must never
/// change; [light] is the day mode (white ground) chosen in Settings.
class AppPalette {
  final Brightness brightness;
  final Color background, hero, card, cardAlt, line, lineSoft, text, textSoft;
  final Color accent, accentFill, myBubble, route, routeSoft, blue, online, danger;
  final Color urgentBg, urgentFg, newBg, newFg;
  const AppPalette({
    required this.brightness,
    required this.background,
    required this.hero,
    required this.card,
    required this.cardAlt,
    required this.line,
    required this.lineSoft,
    required this.text,
    required this.textSoft,
    required this.accent,
    required this.accentFill,
    required this.myBubble,
    required this.route,
    required this.routeSoft,
    required this.blue,
    required this.online,
    required this.danger,
    required this.urgentBg,
    required this.urgentFg,
    required this.newBg,
    required this.newFg,
  });

  /// Night (the existing look, unchanged).
  static const dark = AppPalette(
    brightness: Brightness.dark,
    background: Color(0xFF02050C), // page ground = sea of the live map
    hero: Color(0xFF02050C), // map panel, bars, inputs (same tone as the page)
    card: Color(0xFF0C1322),
    cardAlt: Color(0xFF131B2B),
    line: Color(0xFF1C2638),
    lineSoft: Color(0xFF161F30),
    text: Color(0xFFF2F4F7),
    textSoft: Color(0xFF9AA4B5),
    accent: Color(0xFFFF6B33), // orange on dark (text/icons)
    accentFill: Color(0xFFD4420E), // orange fills with white text
    myBubble: Color(0xFFC93D0C),
    route: Color(0xFF2BB3A9), // teal: route lines, done steps
    routeSoft: Color(0xFF0F2B2A),
    blue: Color(0xFF3BA3FF),
    online: Color(0xFF4ADE80),
    danger: Color(0xFFFF6B6B),
    // Badge tints (background, foreground) — readable on dark cards.
    urgentBg: Color(0xFF3A1A10),
    urgentFg: Color(0xFFFF8A5C),
    newBg: Color(0xFF0F2B2A),
    newFg: Color(0xFF5FD4C9),
  );

  /// Day: white ground, light cards with soft borders, same orange / teal.
  static const light = AppPalette(
    brightness: Brightness.light,
    background: Color(0xFFFFFFFF),
    hero: Color(0xFFFFFFFF),
    card: Color(0xFFFFFFFF),
    cardAlt: Color(0xFFF2F5F9),
    line: Color(0xFFE2E7EE),
    lineSoft: Color(0xFFEDF1F5),
    text: Color(0xFF0F1B2D),
    textSoft: Color(0xFF5B6676),
    accent: Color(0xFFE8521A),
    accentFill: Color(0xFFE8521A),
    myBubble: Color(0xFFE8521A),
    route: Color(0xFF12998F),
    routeSoft: Color(0xFFE1F5F2),
    blue: Color(0xFF1F7FE0),
    online: Color(0xFF16A34A),
    danger: Color(0xFFDC2626),
    urgentBg: Color(0xFFFFEADF),
    urgentFg: Color(0xFFC2410C),
    newBg: Color(0xFFE1F5F2),
    newFg: Color(0xFF0F766E),
  );

  bool get isDay => brightness == Brightness.light;
}

/// The app's colours for the current mode (night unless the user chose day
/// in Settings; set once at start-up in main.dart, a change reloads the
/// app). Keep this the only place colours are defined so screens stay
/// visually consistent.
class AppColors {
  AppColors._();
  static AppPalette _p = AppPalette.dark;
  static AppPalette get palette => _p;
  static bool get isDay => _p.isDay;
  static void use(AppPalette p) => _p = p;

  /// Load-type tiles on the Loads page and the load form (owner,
  /// 21.10.2026). Day: a white tile, dark navy picture and text, a thin
  /// light grey border. Night: a dark navy tile, white picture and text, a
  /// thin blue-grey border. Selected: orange.
  static Color get tileBg => isDay ? const Color(0xFFFFFFFF) : const Color(0xFF0E1A2E);
  static Color get tileFg => isDay ? const Color(0xFF16243A) : const Color(0xFFFFFFFF);
  static Color get tileLine => isDay ? const Color(0xFFE2E7EE) : const Color(0xFF2A3B57);
  static Color get tileSelectedBg => isDay ? const Color(0xFFFFEADF) : const Color(0xFF1A1410);

  /// Ground of a big / small card without a picture (both modes).
  static const Color sizeCardBg = Color(0xFF16243A);
  /// WhatsApp brand green (call sheet).
  static const Color whatsapp = Color(0xFF25D366);
  /// VIP gold (TIR Bazarı and VIP loads, owner 23.10.2026).
  static const Color vipGold = Color(0xFFFFC83D);
  /// VIP medal: gold rim shade and the dark centre / ribbons.
  static const Color vipGoldDark = Color(0xFF7A5200);
  static const Color vipInk = Color(0xFF1A1206);
  /// VIP picture frame (owner, 24.10.2026): light gold of the metal shine
  /// and the white of the small sparkles.
  static const Color vipGoldLight = Color(0xFFFFF0B3);
  static const Color vipSpark = Color(0xFFFFFDF2);

  static Color get background => _p.background;
  static Color get hero => _p.hero;
  static Color get card => _p.card;
  static Color get cardAlt => _p.cardAlt;
  static Color get line => _p.line;
  static Color get lineSoft => _p.lineSoft;
  static Color get text => _p.text;
  static Color get textSoft => _p.textSoft;
  static Color get accent => _p.accent;
  static Color get accentFill => _p.accentFill;
  static Color get myBubble => _p.myBubble;
  static Color get route => _p.route;
  static Color get routeSoft => _p.routeSoft;
  static Color get blue => _p.blue;
  static Color get online => _p.online;
  static Color get danger => _p.danger;
  static Color get urgentBg => _p.urgentBg;
  static Color get urgentFg => _p.urgentFg;
  static Color get newBg => _p.newBg;
  static Color get newFg => _p.newFg;
}

/// WhatsApp-like chat palette, so chats feel familiar.
class ChatPalette {
  final Color background, dots, mine, theirs, meta, readTick, dateChip, text;
  const ChatPalette({
    required this.text,
    required this.background,
    required this.dots,
    required this.mine,
    required this.theirs,
    required this.meta,
    required this.readTick,
    required this.dateChip,
  });

  static const dark = ChatPalette(
    text: Color(0xFFFFFFFF), // message text on both bubbles
    background: Color(0xFF0B141A),
    dots: Color(0xFF13212A),
    mine: Color(0xFF005C4B),
    theirs: Color(0xFF1F2C34),
    meta: Color(0xFF8696A0),
    readTick: Color(0xFF53BDEB),
    dateChip: Color(0xFF182229),
  );

  static const light = ChatPalette(
    text: Color(0xFF111B21),
    background: Color(0xFFEFEAE2),
    dots: Color(0xFFE2DBD0),
    mine: Color(0xFFD9FDD3),
    theirs: Color(0xFFFFFFFF),
    meta: Color(0xFF667781),
    readTick: Color(0xFF34A6E0),
    dateChip: Color(0xFFFFFFFF),
  );
}

class ChatColors {
  ChatColors._();
  static ChatPalette get _p => AppColors.isDay ? ChatPalette.light : ChatPalette.dark;
  static Color get background => _p.background;
  static Color get dots => _p.dots;
  static Color get mine => _p.mine;
  static Color get theirs => _p.theirs;
  static Color get meta => _p.meta;
  static Color get readTick => _p.readTick;
  static Color get dateChip => _p.dateChip;
  static Color get text => _p.text;
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

  /// Theme of the current mode (AppColors.palette): night = the approved
  /// dark design, day = the same layout on white.
  static ThemeData get current {
    final brightness = AppColors.palette.brightness;
    final base = ThemeData(useMaterial3: true, brightness: brightness, fontFamily: AppFonts.family, fontFamilyFallback: AppFonts.fallback);
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.accentFill,
      brightness: brightness,
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
          side: BorderSide(color: AppColors.line),
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.hero,
        foregroundColor: AppColors.text,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        titleTextStyle: AppFonts.display(size: 22, color: AppColors.text),
        shape: Border(bottom: BorderSide(color: AppColors.lineSoft)),
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
        labelStyle: TextStyle(color: AppColors.textSoft),
        hintStyle: TextStyle(color: AppColors.textSoft),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: AppColors.line)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: AppColors.line)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: AppColors.accent, width: 1.5)),
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
          side: BorderSide(color: AppColors.line),
          minimumSize: const Size(48, 48),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: AppColors.accent),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: AppColors.accentFill,
        foregroundColor: Colors.white,
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: AppColors.cardAlt,
        side: BorderSide(color: AppColors.line),
        // Chips do not take the text theme's font list → flags fallback here too.
        labelStyle: TextStyle(color: AppColors.text, fontWeight: FontWeight.w600, fontFamilyFallback: AppFonts.fallback),
      ),
      dividerTheme: DividerThemeData(color: AppColors.line),
      bottomSheetTheme: BottomSheetThemeData(backgroundColor: AppColors.card, surfaceTintColor: Colors.transparent),
      dialogTheme: DialogThemeData(backgroundColor: AppColors.card, surfaceTintColor: Colors.transparent),
      snackBarTheme: SnackBarThemeData(backgroundColor: AppColors.cardAlt, contentTextStyle: TextStyle(color: AppColors.text)),
    );
  }

  /// Night theme (also what [current] gives in night mode).
  static ThemeData get dark => current;
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
