import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter/widgets.dart' show Locale;
import 'app_strings.dart';
import 'fresh_text_stub.dart' if (dart.library.js_interop) 'fresh_text_web.dart' as fresh;

/// Loads the languages' JSON files into memory. Reading a translation is
/// then a plain synchronous map lookup (via stringsProvider) — no
/// per-screen FutureBuilder/loading-flicker for something this small.
///
/// Faster start (owner, 08.11.2026): before the first screen only the
/// languages it can use are read — the saved / device language, Azerbaijani
/// (the default) and English (the safety net for a missing key); the other
/// languages follow in the background after the first screen
/// ([LocaleCatalog]). A web build that knows its version ([buildId], set by
/// the deploy) keeps these texts on the device per version, so a repeat
/// start of the same version waits for no network at all.
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
  static const Locale englishLocale = Locale('en');

  /// The published version (deploy.yml passes the commit); empty in local
  /// and test builds — then the texts are simply fetched fresh every time.
  static const String buildId = String.fromEnvironment('BUILD_ID');

  /// One read per file per run (English used to be read twice).
  static final Map<String, Future<Map<String, String>>> _files = {};

  static Future<Map<String, String>> _file(String code) => _files[code] ??= _read(code);

  static Future<Map<String, String>> _read(String code) async {
    final path = 'assets/i18n/$code.json';
    try {
      // 1) this version's copy kept on the device, 2) the server's file as
      //    it is now (never an old cached one), 3) the app's own bundle.
      var raw = buildId.isEmpty ? null : fresh.readCachedText(code, buildId);
      if (raw == null) {
        raw = await fresh.fetchFreshText(path);
        if (raw != null && buildId.isNotEmpty) fresh.storeCachedText(code, buildId, raw);
      }
      raw ??= await rootBundle.loadString(path);
      return (json.decode(raw) as Map<String, dynamic>).map((k, v) => MapEntry(k, v.toString()));
    } catch (_) {
      _files.remove(code); // try again next time it is asked for
      return const {};
    }
  }

  /// [locale]'s texts, English filling any key it does not have.
  static Future<AppStrings> load(Locale locale) async {
    final both = await Future.wait([_file(englishLocale.languageCode), _file(locale.languageCode)]);
    return AppStrings({...both[0], ...both[1]});
  }

  /// The languages the first screen may use: [first] (saved / device
  /// language), Azerbaijani (default) and English. Requested together, so
  /// start-up waits for one round trip at most.
  static Future<Map<Locale, AppStrings>> loadStartup(Locale? first) async {
    final wanted = <Locale>{if (first != null) first, fallbackLocale, englishLocale};
    final loaded = await Future.wait([for (final l in wanted) load(l)]);
    return {for (var i = 0; i < wanted.length; i++) wanted.elementAt(i): loaded[i]};
  }

  /// Every language (tests and tools).
  static Future<Map<Locale, AppStrings>> loadAll() async {
    final loaded = await Future.wait([for (final l in supportedLocales) load(l)]);
    return {for (var i = 0; i < supportedLocales.length; i++) supportedLocales[i]: loaded[i]};
  }

  /// A supported locale for a language code ('zh' → zh-CN), or null.
  static Locale? supported(String? code) {
    if (code == null) return null;
    for (final l in supportedLocales) {
      if (l.languageCode == code) return l;
    }
    return null;
  }
}
