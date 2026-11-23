import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freightlink/core/localization/app_strings.dart';
import 'package:freightlink/features/market/domain/market_models.dart';
import 'package:freightlink/features/market/presentation/market_home_screen.dart' show MarketFilterSheet;

/// TIR Bazarı filters (owner, 23.11.2026): Marka and Model are only picked
/// from the lists — no typing.
void main() {
  const s = AppStrings({});

  Future<void> pump(WidgetTester t, MarketFilter f) async {
    t.view.physicalSize = const Size(420, 2400);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(home: Scaffold(body: MarketFilterSheet(filter: f, s: s))));
    await t.pump();
  }

  String? editableHint(WidgetTester t, String label) {
    for (final e in t.widgetList<TextField>(find.byType(TextField))) {
      if (e.decoration?.labelText == label) return label;
    }
    return null;
  }

  testWidgets('no text field for Marka or Model; Marka is a closed list', (t) async {
    await pump(t, const MarketFilter());
    expect(editableHint(t, 'mk_brand'), isNull, reason: 'Marka is not typed');
    expect(editableHint(t, 'mk_model'), isNull, reason: 'Model is not typed');
    expect(find.byWidgetPredicate((w) => w is DropdownButtonFormField<String?>), findsWidgets);
    expect(find.byKey(const ValueKey('mk-filter-brand:')), findsOneWidget);
  });

  testWidgets('a popular brand tile sets the Marka list; models stay choices', (t) async {
    await pump(t, const MarketFilter());
    await t.tap(find.text('Volvo').first);
    await t.pump();
    expect(find.byKey(const ValueKey('mk-filter-brand:Volvo')), findsOneWidget);
    expect(editableHint(t, 'mk_model'), isNull);
  });

  testWidgets('an earlier brand / model from the search stays shown, still not typed', (t) async {
    await pump(t, const MarketFilter(brand: 'Volvo', model: 'FH'));
    expect(find.byKey(const ValueKey('mk-filter-brand:Volvo')), findsOneWidget);
    expect(editableHint(t, 'mk_brand'), isNull);
    expect(editableHint(t, 'mk_model'), isNull);
  });
}
