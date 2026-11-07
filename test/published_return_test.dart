// "Dərc olundu ✓" (owner, 07.11.2026): after publishing a load, a TIR
// Bazarı ad, a service / shop or a park request the page goes straight back
// to its section with a clear green notice; an edit keeps going back where
// it came from. Prostoy (free waiting) is optional: nothing chosen on a new
// load, a second tap takes the choice off.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freightlink/core/widgets/published_notice.dart';

String src(String p) => File(p).readAsStringSync();

void main() {
  testWidgets('the notice: green, with a tick, and it stays while the page changes', (tester) async {
    final nav = GlobalKey<NavigatorState>();
    await tester.pumpWidget(MaterialApp(
      navigatorKey: nav,
      home: Scaffold(body: Builder(builder: (c) {
        return TextButton(
          onPressed: () {
            showPublishedNotice(c, 'Yükünüz dərc olundu ✓');
            nav.currentState!.pushReplacement(MaterialPageRoute(builder: (_) => const Scaffold(body: Text('Yüklər'))));
          },
          child: const Text('go'),
        );
      })),
    ));
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(find.text('Yüklər'), findsOneWidget);
    expect(find.text('Yükünüz dərc olundu ✓'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle), findsOneWidget);
    final bar = tester.widget<SnackBar>(find.byKey(const ValueKey('published-notice')));
    expect(bar.backgroundColor, isNotNull);
  });

  test('a new load goes back to Yüklər; an edit goes back as before', () {
    final f = src('lib/features/cargo/presentation/cargo_quick_form.dart');
    final i = f.indexOf("showPublishedNotice(context, strings.t('pub_cargo_done'));");
    expect(i, greaterThan(0));
    expect(f.indexOf("context.go('/cargo');", i), greaterThan(i));
    expect(f.contains("context.go('/cargo/\$id');\n      }\n    } on AppException"), isTrue, reason: 'edit opened alone still shows the load');
  });

  test('a new TIR Bazarı ad goes back to TIR Bazarı; a draft / edit pops', () {
    final f = src('lib/features/market/presentation/market_edit_screen.dart');
    expect(f.contains('if (publish && _orig == null) {'), isTrue);
    expect(f.contains("context.go('/market');"), isTrue);
    expect(f.contains("'pub_market_done'"), isTrue);
  });

  test('a new service / shop goes back to its own map; an edit opens its page', () {
    final f = src('lib/features/services/presentation/service_edit_screen.dart');
    expect(f.contains("showPublishedNotice(context, s.t(_shopForm ? 'pub_shop_done' : 'pub_service_done'));"), isTrue);
    expect(f.contains("context.go(_shopForm ? '/services?shops=1' : '/services');"), isTrue);
    expect(f.contains("context.pushReplacement('/service/\${saved.id}');"), isTrue);
  });

  test('a park request goes back to TIRPark; setup keeps opening the panel', () {
    final f = src('lib/features/tirpark/presentation/tir_park_manage.dart');
    expect(f.contains("showPublishedNotice(context, s.t('tpo_apply_sent'));\n        context.go('/tirpark');"), isTrue);
    expect(f.contains("showPublishedNotice(context, s.t('tpo_setup_done'));"), isTrue);
  });

  test('Prostoy is optional: none on a new load, a second tap takes it off', () {
    final f = src('lib/features/cargo/presentation/cargo_quick_form.dart');
    expect(f.contains('  int? _freeWait;'), isTrue);
    expect(f.contains('c.freeWaitHours : null;'), isTrue);
    expect(f.contains('_freeWait = _freeWait == h ? null : h'), isTrue);
  });

  test('the texts in all six languages', () {
    for (final l in ['az', 'tr', 'en', 'ru', 'ka', 'zh']) {
      final j = jsonDecode(src('assets/i18n/$l.json')) as Map;
      for (final k in ['pub_cargo_done', 'pub_market_done', 'pub_service_done', 'pub_shop_done']) {
        expect(j.containsKey(k), isTrue, reason: '$l $k');
      }
    }
  });
}
