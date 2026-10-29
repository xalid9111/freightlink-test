import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../autofix/autofix_platform_stub.dart' if (dart.library.js_interop) '../autofix/autofix_platform_web.dart' as platform;
import 'app_theme.dart';
import 'night_theme.dart';
import 'night_theme_remote.dart';

export 'night_theme_remote.dart' show PublishedNightTheme, fetchPublishedNightTheme;

/// Day / night mode chosen in Settings, kept on this device
/// (SharedPreferences; nothing is stored on the server). Night is the
/// default, so nobody's app changes until they pick day.
const kThemeModeKey = 'app_theme_mode';
const kThemeDay = 'day';
const kThemeNight = 'night';

/// The night colours published by the admin (0076), kept on the device so
/// the next start shows them at once; and an admin's own try-out on this
/// device only ("Önizlə").
const kNightThemeCacheKey = 'night_theme_cache';
const kNightThemePreviewKey = 'night_theme_preview';

AppPalette paletteFor(String? saved, {NightThemeSpec? night}) =>
    saved == kThemeDay ? AppPalette.light : (night?.toPalette() ?? AppPalette.dark);

/// True while an admin tries a palette on this device ("Önizlə").
bool nightPreviewActive = false;

NightThemeSpec? _specFrom(String? raw) {
  if (raw == null || raw.isEmpty) return null;
  try {
    return NightThemeSpec.fromJson(jsonDecode(raw));
  } catch (_) {
    return null;
  }
}

/// Before runApp: the saved mode becomes the app's colours. At night the
/// admin's published palette is asked for (a short wait at most; the copy
/// from the last start is used meanwhile / when offline).
Future<void> loadSavedTheme() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final mode = prefs.getString(kThemeModeKey);
    if (mode == kThemeDay) {
      AppColors.use(AppPalette.light);
      return;
    }
    final preview = _specFrom(prefs.getString(kNightThemePreviewKey));
    nightPreviewActive = preview != null;
    var night = preview ?? _specFrom(prefs.getString(kNightThemeCacheKey));
    AppColors.use(paletteFor(mode, night: night));
    final published = await fetchPublishedNightTheme().timeout(const Duration(milliseconds: 1500));
    if (published == null) return;
    final spec = published.spec;
    if (spec == null) {
      await prefs.remove(kNightThemeCacheKey);
    } else {
      await prefs.setString(kNightThemeCacheKey, jsonEncode(spec.toJson()));
    }
    if (preview == null) AppColors.use(paletteFor(mode, night: spec));
  } catch (_) {
    // Offline, slow or 0076 not run yet: what is already in use stays
    // (the copy from the last start, or the classic night).
  }
}

/// "Önizlə": [spec] on this device only (the admin), until [endNightPreview].
Future<void> startNightPreview(NightThemeSpec spec) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(kNightThemePreviewKey, jsonEncode(spec.toJson()));
  if (prefs.getString(kThemeModeKey) == kThemeDay) await prefs.setString(kThemeModeKey, kThemeNight);
  platform.reloadPage();
}

Future<void> endNightPreview() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.remove(kNightThemePreviewKey);
  platform.reloadPage();
}

/// After publishing: this device shows the new palette at once.
Future<void> applyPublishedNightTheme(NightThemeSpec? spec) async {
  final prefs = await SharedPreferences.getInstance();
  if (spec == null) {
    await prefs.remove(kNightThemeCacheKey);
  } else {
    await prefs.setString(kNightThemeCacheKey, jsonEncode(spec.toJson()));
  }
  await prefs.remove(kNightThemePreviewKey);
  if (!AppColors.isDay) platform.reloadPage();
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
