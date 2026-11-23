import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freightlink/core/localization/app_strings.dart';
import 'package:freightlink/features/adbiz/presentation/adbiz_company_screen.dart'
    show AdbizOldMonthDialog, adbizFlipSign;

/// The iPhone's number pad has no minus key (owner, 23.11.2026: "mənfi seçə
/// bilmirəm"): the "Köhnə hesab" fields carry a "−/+" button.
void main() {
  test('the sign turns round, also for the typographic minus', () {
    expect(adbizFlipSign('215'), '-215');
    expect(adbizFlipSign('-215'), '215');
    expect(adbizFlipSign('−4693'), '4693');
    expect(adbizFlipSign(''), '-');
  });

  testWidgets('−/+ in the field makes a typed amount negative and back; saving keeps the minus', (t) async {
    (double?, double?)? got;
    await t.pumpWidget(MaterialApp(
      home: Builder(
        builder: (c) => Scaffold(
          body: TextButton(
            onPressed: () async => got = await showDialog<(double?, double?)>(
                context: c, builder: (_) => const AdbizOldMonthDialog(s: AppStrings({}), title: 'Noyabr')),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const ValueKey('adb-old-gap')), '215');
    await t.tap(find.byKey(const ValueKey('adb-old-gap-sign')));
    await t.pump();
    expect(find.text('-215'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('adb-old-gap-sign')));
    await t.pump();
    expect(find.text('215'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('adb-old-gap-sign')));
    await t.enterText(find.byKey(const ValueKey('adb-old-net')), '1475');
    await t.tap(find.byKey(const ValueKey('adb-old-save')));
    await t.pumpAndSettle();
    expect(got, (1475.0, -215.0));
    expect(find.byKey(const ValueKey('adb-old-net-sign')), findsNothing, reason: 'dialog closed');
  });
}
