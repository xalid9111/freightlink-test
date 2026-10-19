import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Display size chosen in Settings (Kiçik 90 % · Normal 100 % · Böyük 115 %),
/// kept on this device. Not a zoom of the whole screen: text grows through
/// Flutter's text scaling (so rows re-flow and long text wraps), icons
/// follow the same scale, and buttons / tap areas / spacing come from the
/// theme (visual density, minimum sizes). Normal changes nothing at all.
enum AppUiScale {
  small('small', 0.90),
  normal('normal', 1.00),
  large('large', 1.15);

  const AppUiScale(this.key, this.factor);
  final String key;
  final double factor;

  static AppUiScale fromKey(String? key) =>
      AppUiScale.values.firstWhere((s) => s.key == key, orElse: () => AppUiScale.normal);
}

const kUiScaleKey = 'app_ui_scale';

/// Read before runApp so the first frame already has the saved size.
AppUiScale _initialUiScale = AppUiScale.normal;

Future<void> loadSavedUiScale() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    _initialUiScale = AppUiScale.fromKey(prefs.getString(kUiScaleKey));
  } catch (_) {
    _initialUiScale = AppUiScale.normal;
  }
}

class UiScaleController extends StateNotifier<AppUiScale> {
  UiScaleController() : super(_initialUiScale);

  /// Applied at once on every page (no reload) and saved for next time.
  Future<void> choose(AppUiScale scale) async {
    if (scale == state) return;
    state = scale;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(kUiScaleKey, scale.key);
    } catch (_) {}
  }
}

final uiScaleProvider = StateNotifierProvider<UiScaleController, AppUiScale>((ref) => UiScaleController());

/// The device's own text size (browser / OS setting) times the chosen size.
class ScaledTextScaler extends TextScaler {
  const ScaledTextScaler(this.base, this.factor);
  final TextScaler base;
  final double factor;

  @override
  double scale(double fontSize) => base.scale(fontSize) * factor;

  @override
  // ignore: deprecated_member_use
  double get textScaleFactor => base.textScaleFactor * factor;

  @override
  bool operator ==(Object other) => other is ScaledTextScaler && other.base == base && other.factor == factor;

  @override
  int get hashCode => Object.hash(base, factor);
}

/// Theme for the chosen size. Normal returns [base] unchanged.
ThemeData themeForUiScale(ThemeData base, AppUiScale scale) {
  if (scale == AppUiScale.normal) return base;
  final large = scale == AppUiScale.large;
  // Icons (also ones with an explicit size) follow the text scale.
  final icons = base.iconTheme.copyWith(applyTextScaling: true);
  const minTap = Size(48, 48);
  return base.copyWith(
    iconTheme: icons,
    primaryIconTheme: base.primaryIconTheme.copyWith(applyTextScaling: true),
    // Large: roomier buttons and list rows, more space between them.
    // Small: a little tighter, tap areas stay at the platform minimum.
    visualDensity: large ? const VisualDensity(horizontal: 1, vertical: 1) : const VisualDensity(horizontal: -1, vertical: -1),
    materialTapTargetSize: MaterialTapTargetSize.padded,
    iconButtonTheme: large
        ? IconButtonThemeData(style: IconButton.styleFrom(minimumSize: minTap))
        : base.iconButtonTheme,
    textButtonTheme: large
        ? TextButtonThemeData(style: (base.textButtonTheme.style ?? const ButtonStyle()).copyWith(
            minimumSize: const WidgetStatePropertyAll(minTap),
          ))
        : base.textButtonTheme,
    elevatedButtonTheme: large
        ? ElevatedButtonThemeData(style: (base.elevatedButtonTheme.style ?? const ButtonStyle()).copyWith(
            minimumSize: const WidgetStatePropertyAll(minTap),
          ))
        : base.elevatedButtonTheme,
    listTileTheme: large ? base.listTileTheme.copyWith(minTileHeight: 56) : base.listTileTheme,
  );
}

/// Wraps the whole app (MaterialApp.builder): text of every page follows
/// the chosen size. Normal leaves the page exactly as it was.
Widget applyUiScale(BuildContext context, AppUiScale scale, Widget? child) {
  final page = child ?? const SizedBox.shrink();
  if (scale == AppUiScale.normal) return page;
  final mq = MediaQuery.of(context);
  return MediaQuery(
    data: mq.copyWith(textScaler: ScaledTextScaler(mq.textScaler, scale.factor)),
    child: page,
  );
}
