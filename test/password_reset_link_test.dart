// Owner, 21.11.2026: "istifadəçi parolu unudub … şifrəni sıfırla basdıqda
// bu səhifəyə yönləndirilir və parolunu sıfırlaya bilmir" + "dil seçimini
// yuxarıda göstər, istifadəçi rus dilini bilməyə bilər".
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freightlink/core/auth/auth_link_problem.dart';
import 'package:freightlink/core/localization/app_strings.dart';
import 'package:freightlink/core/localization/locale_controller.dart';
import 'package:freightlink/core/router/password_recovery.dart';
import 'package:freightlink/features/auth/presentation/reset_password_screen.dart';
import 'package:freightlink/features/auth/presentation/widgets/auth_language_button.dart';
import 'package:shared_preferences/shared_preferences.dart';

String _read(String p) => File(p).readAsStringSync();
AppStrings _lang(String l) => AppStrings(Map<String, String>.from(jsonDecode(_read('assets/i18n/$l.json')) as Map));

class _NoAccount implements AccountLanguage {
  @override
  Future<String?> read() async => null;
  @override
  Future<bool> write(String code) async => false;
  @override
  Stream<void> get signedIn => const Stream.empty();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('a reset link Supabase refused', () {
    test('otp_expired / "Email link is invalid" in the address are recognised', () {
      expect(
          urlHasAuthLinkError(
              'https://tirlink.app/#error=access_denied&error_code=otp_expired&error_description=Email+link+is+invalid+or+has+expired'),
          isTrue);
      expect(urlHasAuthLinkError('/error=access_denied&error_code=otp_expired'), isTrue);
      expect(urlHasAuthLinkError('https://tirlink.app/?error=access_denied&error_description=Email%20link%20is%20invalid%20or%20has%20expired#/reset-password'),
          isTrue);
    });
    test('a cancelled Google sign-in and ordinary pages are left alone', () {
      expect(urlHasAuthLinkError('https://tirlink.app/#error=access_denied&error_description=User+cancelled'), isFalse);
      expect(urlHasAuthLinkError('/reset-password?token_hash=abc&type=recovery'), isFalse);
      expect(urlHasAuthLinkError('/cargo'), isFalse);
      expect(urlHasAuthLinkError('/login?from=%2Fprofile'), isFalse);
      expect(urlHasAuthLinkError('%E0%A4%A'), isFalse, reason: 'a broken address never throws');
    });
    test('wired: the router sends it to the reset page, never to the bare login page', () {
      final r = _read('lib/core/router/app_router.dart');
      final redirect = r.substring(r.indexOf('redirect: (context, state) {'));
      final check = redirect.indexOf('authLinkErrorIn(state.uri)');
      expect(check, greaterThan(0));
      expect(check, lessThan(redirect.indexOf("if (loc == '/reset-password') return null;")),
          reason: 'checked before every other rule');
      expect(redirect, contains("return '/reset-password?link_error=1';"));
      expect(r, contains("linkError: state.uri.queryParameters['link_error'] != null,"));
      // The notice on top is not shown again over the reset page.
      expect(_read('lib/core/auth/auth_link_notice.dart'), contains("if (path == '/reset-password') return;"));
    });

    testWidgets('the reset page explains it and offers a new link right there', (t) async {
      await t.pumpWidget(ProviderScope(
        overrides: [
          stringsProvider.overrideWithValue(_lang('az')),
          currentLocaleProvider.overrideWith((ref) => LocaleController(account: _NoAccount())),
          passwordRecoveryProvider.overrideWith((ref) => PasswordRecoveryState(const Stream.empty())),
        ],
        child: const MaterialApp(home: ResetPasswordScreen(linkError: true)),
      ));
      await t.pump();
      await t.pump();
      expect(find.byKey(const ValueKey('pw-link-invalid')), findsOneWidget);
      expect(find.textContaining('ən son gələn məktubdakı linki'), findsOneWidget);
      expect(find.byKey(const ValueKey('pw-link-new')), findsOneWidget);
      expect(find.text('Yeni link göndər'), findsOneWidget);
      expect(find.text('Girişə qayıt'), findsOneWidget);
      expect(find.byKey(const ValueKey('auth-lang')), findsOneWidget, reason: 'the language at the top here too');
      // The new link asks for the address first.
      await t.tap(find.byKey(const ValueKey('pw-link-new')));
      await t.pumpAndSettle();
      expect(find.byType(TextField), findsOneWidget);
    });
  });

  group('the language at the top of the sign-in pages', () {
    testWidgets('flag + code; a tap lists the six languages and changes it', (t) async {
      final container = ProviderContainer(overrides: [
        currentLocaleProvider.overrideWith((ref) => LocaleController(account: _NoAccount())),
      ]);
      addTearDown(container.dispose);
      await t.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: Consumer(
          builder: (c, ref, _) {
            final code = ref.watch(currentLocaleProvider).languageCode;
            return ProviderScope(
              overrides: [stringsProvider.overrideWithValue(_lang(code == 'ru' ? 'ru' : 'az'))],
              child: const MaterialApp(home: Scaffold(body: Center(child: AuthLanguageButton()))),
            );
          },
        ),
      ));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('auth-lang')));
      await t.pumpAndSettle();
      for (final n in ['Azərbaycanca', 'Türkçe', 'English', 'Русский', 'ქართული', '简体中文']) {
        expect(find.text(n), findsOneWidget, reason: n);
      }
      await t.tap(find.text('Русский'));
      await t.pumpAndSettle();
      expect(container.read(currentLocaleProvider).languageCode, 'ru');
      expect(find.text('RU'), findsOneWidget);
    });

    test('wired on the login, register and reset pages', () {
      final l = _read('lib/features/auth/presentation/login_screen.dart');
      expect(l, contains('const Positioned(top: 8, right: 8, child: AuthLanguageButton()),'));
      expect(_read('lib/features/auth/presentation/register_screen.dart'), contains('child: AuthLanguageButton())'));
      expect(_read('lib/features/auth/presentation/reset_password_screen.dart'), contains('child: AuthLanguageButton())'));
    });

    test('texts in all six languages', () {
      for (final l in ['az', 'tr', 'en', 'ru', 'ka', 'zh']) {
        final m = jsonDecode(_read('assets/i18n/$l.json')) as Map<String, dynamic>;
        for (final k in ['pw_link_used', 'pw_link_new']) {
          expect((m[k] as String?)?.isNotEmpty, isTrue, reason: '$l $k');
        }
      }
    });
  });
}
