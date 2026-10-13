import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app_strings.dart';
import 'localization_service.dart';

const _prefsKey = 'fl_locale';

/// Populated once in main.dart (via ProviderScope overrides) after
/// LocalizationService.loadAll() completes, before runApp(). Every
/// other localization provider reads from this — nothing re-fetches
/// the JSON files.
final localeCatalogProvider = Provider<Map<Locale, AppStrings>>((ref) {
  throw StateError(
    'localeCatalogProvider was not overridden — main.dart must call '
    'LocalizationService.loadAll() and override this provider before runApp().',
  );
});

class LocaleController extends StateNotifier<Locale> {
  LocaleController() : super(LocalizationService.fallbackLocale) {
    _restore();
  }

  Future<void> _restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_prefsKey);
      if (saved != null) {
        final match = LocalizationService.supportedLocales
            .where((l) => l.languageCode == saved);
        if (match.isNotEmpty) {
          state = match.first;
          return;
        }
      }
    } catch (_) {
      // SharedPreferences unavailable (shouldn't happen on web/mobile,
      // but never let a storage hiccup block the app from launching).
    }

    // First launch, nothing saved yet: try the device/browser language,
    // but only ever as a starting point — the user can always change it
    // (see ProfileScreen's language switcher), and this never overrides
    // a choice they already saved.
    final deviceLocale = WidgetsBinding.instance.platformDispatcher.locale;
    final deviceMatch = LocalizationService.supportedLocales
        .where((l) => l.languageCode == deviceLocale.languageCode);
    state = deviceMatch.isNotEmpty ? deviceMatch.first : LocalizationService.fallbackLocale;
  }

  Future<void> setLocale(Locale locale) async {
    state = locale;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, locale.languageCode);
    } catch (_) {
      // Selection still applies for this session even if it can't be
      // persisted — never block the user's action on storage working.
    }
  }
}

final currentLocaleProvider = StateNotifierProvider<LocaleController, Locale>((ref) {
  return LocaleController();
});

/// What every screen actually watches: `ref.watch(stringsProvider).t('key')`.
final stringsProvider = Provider<AppStrings>((ref) {
  final catalog = ref.watch(localeCatalogProvider);
  final locale = ref.watch(currentLocaleProvider);
  return catalog[locale] ?? catalog[LocalizationService.fallbackLocale]!;
});
