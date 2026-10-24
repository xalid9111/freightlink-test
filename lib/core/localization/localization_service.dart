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
    // All files are requested at once (not one after another): start-up
    // waits for one round trip instead of seven (owner, 24.10.2026).
    Future<Map<String, String>> read(String code) async {
      try {
        final raw = await rootBundle.loadString('assets/i18n/$code.json');
        return (json.decode(raw) as Map<String, dynamic>).map((k, v) => MapEntry(k, v.toString()));
      } catch (_) {
        return const {};
      }
    }

    final files = await Future.wait([read('en'), for (final l in supportedLocales) read(l.languageCode)]);
    // English is the safety net: a key missing in one language shows the
    // English text instead of the raw key.
    final english = files.first;
    final result = <Locale, AppStrings>{};
    for (var i = 0; i < supportedLocales.length; i++) {
      result[supportedLocales[i]] = AppStrings({...english, ...files[i + 1]});
    }
    return result;
  }
}
