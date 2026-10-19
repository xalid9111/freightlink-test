import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freightlink/core/theme/ui_scale.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Minimal app wired exactly like main.dart (theme + builder).
class _App extends ConsumerWidget {
  const _App();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scale = ref.watch(uiScaleProvider);
    return MaterialApp(
      theme: themeForUiScale(ThemeData(useMaterial3: true), scale),
      builder: (context, child) => applyUiScale(context, scale, child),
      home: Scaffold(
        body: Builder(
          builder: (context) => Column(children: [
            Text('scale:${MediaQuery.textScalerOf(context).scale(10).toStringAsFixed(2)}'),
            TextButton(key: const ValueKey('btn'), onPressed: () {}, child: const Text('OK')),
            IconButton(key: const ValueKey('icon'), onPressed: () {}, icon: const Icon(Icons.add)),
            const Icon(Icons.star, key: ValueKey('star'), size: 20),
            Consumer(
              builder: (context, ref, _) => Row(children: [
                for (final s in AppUiScale.values)
                  TextButton(key: ValueKey('pick-${s.key}'), onPressed: () => ref.read(uiScaleProvider.notifier).choose(s), child: Text(s.key)),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

void main() {
  test('three sizes: 90 % · 100 % · 115 %, unknown → normal', () {
    expect(AppUiScale.small.factor, 0.90);
    expect(AppUiScale.normal.factor, 1.00);
    expect(AppUiScale.large.factor, 1.15);
    expect(AppUiScale.fromKey('large'), AppUiScale.large);
    expect(AppUiScale.fromKey(null), AppUiScale.normal);
    expect(AppUiScale.fromKey('zoom'), AppUiScale.normal);
  });

  test('normal changes nothing in the theme', () {
    final base = ThemeData(useMaterial3: true);
    expect(identical(themeForUiScale(base, AppUiScale.normal), base), isTrue);
  });

  test('large: roomier density, 48×48 tap areas, icons follow the text size', () {
    final t = themeForUiScale(ThemeData(useMaterial3: true), AppUiScale.large);
    expect(t.visualDensity.vertical, greaterThan(0));
    expect(t.materialTapTargetSize, MaterialTapTargetSize.padded);
    expect(t.iconTheme.applyTextScaling, isTrue);
    expect(t.iconButtonTheme.style!.minimumSize!.resolve({}), const Size(48, 48));
    expect(t.textButtonTheme.style!.minimumSize!.resolve({}), const Size(48, 48));
  });

  test('the device text size is kept and multiplied', () {
    const s = ScaledTextScaler(TextScaler.linear(1.2), 1.15);
    expect(s.scale(10), closeTo(13.8, 1e-9));
  });

  testWidgets('choosing a size applies at once and is saved', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await loadSavedUiScale();
    await tester.pumpWidget(const ProviderScope(child: _App()));
    expect(find.text('scale:10.00'), findsOneWidget);
    final starNormal = tester.getSize(find.byKey(const ValueKey('star')));

    await tester.tap(find.byKey(const ValueKey('pick-large')));
    await tester.pumpAndSettle();
    expect(find.text('scale:11.50'), findsOneWidget);
    expect(tester.getSize(find.byKey(const ValueKey('star'))).width, closeTo(starNormal.width * 1.15, 0.01));
    expect(tester.getSize(find.byKey(const ValueKey('btn'))).height, greaterThanOrEqualTo(48));
    expect(tester.getSize(find.byKey(const ValueKey('icon'))).height, greaterThanOrEqualTo(48));
    expect((await SharedPreferences.getInstance()).getString(kUiScaleKey), 'large');

    await tester.tap(find.byKey(const ValueKey('pick-small')));
    await tester.pumpAndSettle();
    expect(find.text('scale:9.00'), findsOneWidget);
    expect((await SharedPreferences.getInstance()).getString(kUiScaleKey), 'small');
  });

  testWidgets('the saved size is used on the next start', (tester) async {
    SharedPreferences.setMockInitialValues({kUiScaleKey: 'large'});
    await loadSavedUiScale();
    await tester.pumpWidget(const ProviderScope(child: _App()));
    expect(find.text('scale:11.50'), findsOneWidget);
  });
}
