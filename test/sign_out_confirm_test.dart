import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freightlink/core/localization/app_strings.dart';
import 'package:freightlink/features/auth/presentation/widgets/sign_out_confirm.dart';

/// "Hesabdan çıxış" asks first (owner, 24.11.2026: "basan kimi anidən
/// çıxmasın"): only "Bəli, çıx" signs out.
void main() {
  Future<bool?> run(WidgetTester t, Future<void> Function() answer) async {
    bool? got;
    await t.pumpWidget(MaterialApp(
      home: Builder(
        builder: (c) => Scaffold(
          body: TextButton(
            onPressed: () async => got = await confirmSignOut(c, const AppStrings({})),
            child: const Text('out'),
          ),
        ),
      ),
    ));
    await t.tap(find.text('out'));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('sign-out-confirm')), findsOneWidget, reason: 'asked first');
    await answer();
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('sign-out-confirm')), findsNothing);
    return got;
  }

  testWidgets('Bəli signs out', (t) async {
    expect(await run(t, () => t.tap(find.byKey(const ValueKey('sign-out-yes')))), isTrue);
  });

  testWidgets('Xeyr stays signed in', (t) async {
    expect(await run(t, () => t.tap(find.byKey(const ValueKey('sign-out-no')))), isFalse);
  });

  testWidgets('a tap outside stays signed in', (t) async {
    expect(await run(t, () => t.tapAt(const Offset(5, 5))), isFalse);
  });

  test('wired: Profil asks before signOut; texts in 6 languages', () {
    final p = File('lib/features/auth/presentation/profile_screen.dart').readAsStringSync();
    expect(p, contains('if (await confirmSignOut(context, strings))'));
    expect(p.contains('onTap: () => ref.read(authRepositoryProvider).signOut()'), isFalse);
    for (final l in ['az', 'tr', 'en', 'ru', 'ka', 'zh']) {
      final j = File('assets/i18n/$l.json').readAsStringSync();
      for (final k in ['pf_sign_out_q', 'pf_sign_out_body', 'pf_sign_out_no', 'pf_sign_out_yes']) {
        expect(j, contains('"$k"'), reason: '$l $k');
      }
    }
  });
}
