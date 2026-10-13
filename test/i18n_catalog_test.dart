// Checks that all six language files (az, tr, en, ru, ka, zh = zh-CN)
// stay in sync (pure Dart, no device).
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _langs = ['az', 'tr', 'en', 'ru', 'ka', 'zh'];

Map<String, dynamic> _load(String lang) =>
    jsonDecode(File('assets/i18n/$lang.json').readAsStringSync()) as Map<String, dynamic>;

void main() {
  test('every language has exactly the same keys', () {
    final base = _load('az').keys.toSet();
    for (final lang in _langs) {
      expect(_load(lang).keys.toSet(), base, reason: '$lang.json key set differs from az.json');
    }
  });

  test('no empty translations', () {
    for (final lang in _langs) {
      _load(lang).forEach((k, v) {
        expect(v is String && v.trim().isNotEmpty, isTrue, reason: '$lang.json: "$k" is empty');
      });
    }
  });

  test('placeholders like {n} are the same in every language', () {
    final ph = RegExp(r'\{(\w+)\}');
    Set<String> names(Object? v) => ph.allMatches('$v').map((m) => m.group(1)!).toSet();
    final en = _load('en');
    for (final lang in _langs) {
      final m = _load(lang);
      en.forEach((k, v) {
        expect(names(m[k]), names(v), reason: '$lang.json: "$k" placeholders differ from en.json');
      });
    }
  });

  test('phone-country, language and sign-in texts exist in all languages', () {
    const keys = [
      'phone_country_label', 'phone_country_title', 'phone_country_search', 'phone_country_not_found',
      'profile_language_label', 'profile_language_choose', 'error_profile_missing', 'error_profile_load_failed',
    ];
    for (final lang in _langs) {
      final m = _load(lang);
      for (final k in keys) {
        expect(m.containsKey(k), isTrue, reason: '$lang.json is missing $k');
      }
    }
  });

  test('password-management texts exist in all languages', () {
    const keys = [
      'pw_change_title', 'pw_current', 'pw_new', 'pw_confirm', 'pw_show', 'pw_hide', 'pw_submit',
      'pw_forgot', 'pw_reset_title', 'error_pw_wrong_current', 'error_pw_too_short', 'error_pw_network',
    ];
    for (final lang in _langs) {
      final m = _load(lang);
      for (final k in keys) {
        expect(m.containsKey(k), isTrue, reason: '$lang.json is missing $k');
      }
    }
  });
}
