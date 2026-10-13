import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter/widgets.dart' show Locale;
import 'app_strings.dart';

/// Loads every supported language's JSON file ONCE at app startup (see
/// main.dart) into memory. After that, reading a translation is a plain
/// synchronous map lookup (via stringsProvider) — no per-screen
/// FutureBuilder/loading-flicker for something this small and static.
class LocalizationService {
  LocalizationService._();

  // AZ, TR, RU, EN, Georgian (KA) and Simplified Chinese (zh-CN).
  // Every language is available to every user — the language is never
  // tied to the user's country or phone code.
  static const List<Locale> supportedLocales = [
    Locale('az'),
    Locale('tr'),
    Locale('ru'),
    Locale('en'),
    Locale('ka'),
    Locale('zh', 'CN'),
  ];

  static const Locale fallbackLocale = Locale('az');

  static Future<Map<Locale, AppStrings>> loadAll() async {
    final result = <Locale, AppStrings>{};
    // English is the safety net: a key missing in one language shows the
    // English text instead of the raw key.
    Map<String, String> english = const {};
    try {
      final rawEn = await rootBundle.loadString('assets/i18n/en.json');
      english = (json.decode(rawEn) as Map<String, dynamic>).map((k, v) => MapEntry(k, v.toString()));
    } catch (_) {}
    for (final locale in supportedLocales) {
      Map<String, String> own = const {};
      try {
        final raw = await rootBundle.loadString('assets/i18n/${locale.languageCode}.json');
        own = (json.decode(raw) as Map<String, dynamic>).map((k, v) => MapEntry(k, v.toString()));
      } catch (_) {}
      result[locale] = AppStrings({...english, ...own});
    }
    return result;
  }
}
