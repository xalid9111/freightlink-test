import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../autofix/autofix_platform_stub.dart' if (dart.library.js_interop) '../autofix/autofix_platform_web.dart' as platform;
import 'app_theme.dart';
import 'night_theme.dart';
import 'night_theme_remote.dart';

export 'night_theme_remote.dart' show PublishedNightTheme, fetchPublishedNightTheme, fetchNeumorphOn;

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

AppPalette paletteFor(String? saved, {NightThemeSpec? night, bool neumorph = false}) => neumorph
    ? (saved == kThemeDay ? AppPalette.neuLight : AppPalette.neuDark)
    : (saved == kThemeDay ? AppPalette.light : (night?.toPalette() ?? AppPalette.dark));

/// The "Neumorf" look (0137) the admin switched on, kept on the device so
/// the next start shows it at once; and an admin's own try-out on this
/// device only ("Önizlə"). It counts at night and by day and goes before
/// an admin's night colours (0076) while it is on.
const kNeumorphCacheKey = 'ui_neumorph';
const kNeumorphPreviewKey = 'ui_neumorph_preview';
/// Set once the server was asked on this device (also without an answer),
/// so later starts never wait for it.
const kNeumorphCheckedKey = 'ui_neumorph_checked';

/// True while an admin tries the Neumorf look on this device.
bool neumorphPreviewActive = false;

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
    // Neumorf (0137): this device's try-out, else the copy kept from the
    // last start; the server's answer is kept for the NEXT start (never
    // changes an open screen), and on a device's first start it is waited
    // for as briefly as the night colours.
    final neuPreview = prefs.getBool(kNeumorphPreviewKey);
    neumorphPreviewActive = neuPreview != null;
    final neuCached = prefs.getBool(kNeumorphCacheKey);
    final neuRefresh = _refreshNeumorph(prefs, serverReady);
    // Both answers are asked for at the same time (one short wait at most).
    final refresh = mode == kThemeDay ? null : _refreshPublishedNightTheme(prefs, serverReady);
    var neu = neuPreview ?? neuCached ?? false;
    // Waited for only on a NEW device (nothing kept yet); a device that
    // already ran the app keeps its start as fast as before and gets the
    // answer on its next start.
    final newDevice = mode == null &&
        prefs.getString(kNightThemeCacheKey) == null &&
        !(prefs.getBool(kNightThemeCheckedKey) ?? false) &&
        !(prefs.getBool(kNeumorphCheckedKey) ?? false);
    if (neuPreview == null && neuCached == null && newDevice) {
      neu = (await neuRefresh.timeout(const Duration(milliseconds: 1500), onTimeout: () => null)) ?? false;
    }
    if (mode == kThemeDay) {
      AppColors.use(paletteFor(mode, neumorph: neu));
      return;
    }
    final preview = _specFrom(prefs.getString(kNightThemePreviewKey));
    nightPreviewActive = preview != null;
    final cached = prefs.getString(kNightThemeCacheKey);
    final night = preview ?? _specFrom(cached);
    AppColors.use(paletteFor(mode, night: night, neumorph: neu));
    final known = cached != null || (prefs.getBool(kNightThemeCheckedKey) ?? false);
    if (neu || refresh == null) return;
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

/// Asks the server whether the Neumorf look is on and keeps the answer on
/// the device. Null = could not ask (0137 not run, offline).
Future<bool?> _refreshNeumorph(SharedPreferences prefs, Future<void>? serverReady) async {
  try {
    if (serverReady != null) await serverReady;
    final on = await fetchNeumorphOn();
    if (on != null) await prefs.setBool(kNeumorphCacheKey, on);
    await prefs.setBool(kNeumorphCheckedKey, true);
    return on;
  } catch (_) {
    return null;
  }
}

/// "Önizlə" of the Neumorf look on this device only (the admin).
Future<void> startNeumorphPreview(bool on) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool(kNeumorphPreviewKey, on);
  platform.reloadPage();
}

Future<void> endNeumorphPreview() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.remove(kNeumorphPreviewKey);
  platform.reloadPage();
}

/// After the admin switched it: this device follows at once.
Future<void> applyNeumorph(bool on) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool(kNeumorphCacheKey, on);
  await prefs.remove(kNeumorphPreviewKey);
  platform.reloadPage();
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
  AppColors.use(day
      ? (AppColors.neumorph ? AppPalette.neuLight : AppPalette.light)
      : (AppColors.neumorph ? AppPalette.neuDark : AppPalette.dark));
  platform.reloadPage();
}
