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

/// Set once the published night palette has been asked for on this device
/// (also when there is none), so later starts never wait for it.
const kNightThemeCheckedKey = 'night_theme_checked';

/// Before runApp: the saved mode becomes the app's colours. At night the
/// admin's published palette (0076) is asked for:
///  * first start on this device: waited for (a short wait at most, as
///    before) so the very first screen has the right colours;
///  * later starts (owner, 08.11.2026 — faster start): the copy kept from
///    the last start is used at once and the server's answer is kept for
///    the NEXT start, so the colours never change on an open screen.
/// [serverReady] completes once Supabase is initialised.
Future<void> loadSavedTheme({Future<void>? serverReady}) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final mode = prefs.getString(kThemeModeKey);
    if (mode == kThemeDay) {
      AppColors.use(AppPalette.light);
      return;
    }
    final preview = _specFrom(prefs.getString(kNightThemePreviewKey));
    nightPreviewActive = preview != null;
    final cached = prefs.getString(kNightThemeCacheKey);
    final night = preview ?? _specFrom(cached);
    AppColors.use(paletteFor(mode, night: night));
    final known = cached != null || (prefs.getBool(kNightThemeCheckedKey) ?? false);
    final refresh = _refreshPublishedNightTheme(prefs, serverReady);
    if (known) return; // kept for the next start
    // First start: put it on screen only if it arrives within the short
    // wait (a later answer is kept for the next start, never shown live).
    final published = await refresh.timeout(const Duration(milliseconds: 1500));
    if (published != null && preview == null) AppColors.use(paletteFor(mode, night: published.spec));
  } catch (_) {
    // Offline, slow or 0076 not run yet: what is already in use stays
    // (the copy from the last start, or the classic night).
  }
}

/// Asks the server for the published night palette and keeps it on the
/// device (for this and the next starts). Null = could not ask.
Future<PublishedNightTheme?> _refreshPublishedNightTheme(SharedPreferences prefs, Future<void>? serverReady) async {
  try {
    if (serverReady != null) await serverReady;
    final published = await fetchPublishedNightTheme();
    if (published == null) return null;
    final spec = published.spec;
    if (spec == null) {
      await prefs.remove(kNightThemeCacheKey);
    } else {
      await prefs.setString(kNightThemeCacheKey, jsonEncode(spec.toJson()));
    }
    await prefs.setBool(kNightThemeCheckedKey, true);
    return published;
  } catch (_) {
    return null;
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
