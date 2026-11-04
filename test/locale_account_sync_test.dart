// The chosen language holds everywhere (owner, 04.11.2026): Safari, an
// in-app browser and the Home Screen app keep separate storage, so the
// choice is also kept on the account (users.preferred_lang).
import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freightlink/core/localization/locale_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeAccount implements AccountLanguage {
  String? lang; // null = signed out
  final written = <String>[];
  final _signIn = StreamController<void>.broadcast();
  _FakeAccount(this.lang);

  @override
  Future<String?> read() async => lang;

  @override
  Future<bool> write(String code) async {
    if (lang == null || !kAccountLangs.contains(code)) return false;
    lang = code;
    written.add(code);
    return true;
  }

  @override
  Stream<void> get signedIn => _signIn.stream;

  void signIn(String accountLang) {
    lang = accountLang;
    _signIn.add(null);
  }
}

Future<void> _settle() async {
  for (var i = 0; i < 10; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('no choice on this browser: the account language is used, not the phone language', () async {
    SharedPreferences.setMockInitialValues({});
    final acc = _FakeAccount('az');
    final c = LocaleController(account: acc);
    await c.syncWithAccount();
    expect(c.state, const Locale('az'));
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('fl_locale'), 'az', reason: 'kept on this browser too');
    c.dispose();
  });

  test('a new choice is written to the account, so every browser shows it', () async {
    SharedPreferences.setMockInitialValues({'fl_locale': 'az', 'fl_locale_account_synced': true});
    final acc = _FakeAccount('az');
    final c = LocaleController(account: acc);
    await c.syncWithAccount();
    await c.setLocale(const Locale('tr'));
    expect(acc.written, ['tr']);
    // Another browser, nothing saved there yet: the account's language.
    SharedPreferences.setMockInitialValues({});
    final other = LocaleController(account: acc);
    await other.syncWithAccount();
    expect(other.state, const Locale('tr'));
    c.dispose();
    other.dispose();
  });

  test('changed on another device: the account wins over this browser''s older choice', () async {
    SharedPreferences.setMockInitialValues({'fl_locale': 'tr', 'fl_locale_account_synced': true});
    final acc = _FakeAccount('az');
    final c = LocaleController(account: acc);
    await c.syncWithAccount();
    expect(c.state, const Locale('az'));
    c.dispose();
  });

  test('a choice made before this update is kept and written to the account once', () async {
    SharedPreferences.setMockInitialValues({'fl_locale': 'ru'});
    final acc = _FakeAccount('az'); // the column's default
    final c = LocaleController(account: acc);
    await c.syncWithAccount();
    expect(c.state, const Locale('ru'));
    expect(acc.written, ['ru']);
    c.dispose();
  });

  test('chosen while signed out: the choice goes to the account at sign-in (not replaced by it)', () async {
    SharedPreferences.setMockInitialValues({'fl_locale': 'az', 'fl_locale_account_synced': true});
    final acc = _FakeAccount(null);
    final c = LocaleController(account: acc);
    await _settle();
    await c.setLocale(const Locale('en'));
    expect(acc.written, isEmpty, reason: 'nobody signed in');
    acc.signIn('az');
    await _settle();
    expect(c.state, const Locale('en'));
    expect(acc.written, ['en']);
    c.dispose();
  });

  test('Chinese stays on the device (the account column has no zh)', () async {
    SharedPreferences.setMockInitialValues({'fl_locale': 'zh', 'fl_locale_account_synced': true});
    final acc = _FakeAccount('az');
    final c = LocaleController(account: acc);
    await c.syncWithAccount();
    expect(c.state.languageCode, 'zh');
    expect(acc.written, isEmpty);
    c.dispose();
  });

  test('offline or signed out: what is shown stays', () async {
    SharedPreferences.setMockInitialValues({'fl_locale': 'tr', 'fl_locale_account_synced': true});
    final c = LocaleController(account: _FakeAccount(null));
    await c.syncWithAccount();
    expect(c.state, const Locale('tr'));
    c.dispose();
  });
}
