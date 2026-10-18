import 'package:shared_preferences/shared_preferences.dart';

import '../autofix/autofix_platform_stub.dart' if (dart.library.js_interop) '../autofix/autofix_platform_web.dart' as platform;
import 'app_theme.dart';

/// Day / night mode chosen in Settings, kept on this device
/// (SharedPreferences; nothing is stored on the server). Night is the
/// default, so nobody's app changes until they pick day.
const kThemeModeKey = 'app_theme_mode';
const kThemeDay = 'day';
const kThemeNight = 'night';

AppPalette paletteFor(String? saved) => saved == kThemeDay ? AppPalette.light : AppPalette.dark;

/// Before runApp: the saved mode becomes the app's colours.
Future<void> loadSavedTheme() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    AppColors.use(paletteFor(prefs.getString(kThemeModeKey)));
  } catch (_) {
    AppColors.use(AppPalette.dark);
  }
}

/// Saves the choice and restarts the app page so every screen is drawn
/// in the new colours (the page reloads at the same address).
Future<void> chooseTheme({required bool day}) async {
  if (day == AppColors.isDay) return;
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(kThemeModeKey, day ? kThemeDay : kThemeNight);
  } catch (_) {}
  AppColors.use(day ? AppPalette.light : AppPalette.dark);
  platform.reloadPage();
}
