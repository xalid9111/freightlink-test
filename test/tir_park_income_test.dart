// "Bu gün" → Günlük · Aylıq · İllik income (owner, 04.11.2026, 0094).
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freightlink/core/localization/app_strings.dart';
import 'package:freightlink/features/tirpark/data/tir_park_repository.dart';
import 'package:freightlink/features/tirpark/domain/tir_park.dart';
import 'package:freightlink/features/tirpark/presentation/tir_park_owner_panel.dart';

String src(String p) => File(p).readAsStringSync();
final _az = AppStrings(Map<String, String>.from(jsonDecode(src('assets/i18n/az.json')) as Map));
const _park = TirPark(id: 'p1', name: 'UTEP', lat: 40.4, lng: 49.8, status: 'approved');

Widget _app(Future<TirParkIncome> Function() load) => ProviderScope(
      key: UniqueKey(),
      overrides: [tirParkIncomeProvider.overrideWith((ref, id) => load())],
      child: MaterialApp(home: Scaffold(body: TirParkIncomeSheet(park: _park, s: _az))),
    );

void main() {
  test('server answer is read; total = exits + paid bookings', () {
    final v = TirParkIncome.fromJson({
      'currency': 'AZN',
      'day': {'cars': 7.4, 'exits': 1, 'bookings': 0},
      'month': {'cars': '17.40', 'exits': 2, 'bookings': 6},
      'year': {'cars': 117.4, 'exits': 3, 'bookings': 6},
    });
    expect(v.day.total, 7.4);
    expect(v.month.total, closeTo(23.4, 1e-9));
    expect(v.year.exits, 3);
  });

  testWidgets('three parts: Günlük, Aylıq, İllik', (tester) async {
    tester.view.physicalSize = const Size(400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_app(() async => const TirParkIncome(
          day: TirParkIncomePart(cars: 7.4, exits: 1),
          month: TirParkIncomePart(cars: 17.4, exits: 2, bookings: 6),
          year: TirParkIncomePart(cars: 117.4, exits: 3, bookings: 6),
        )));
    await tester.pumpAndSettle();
    for (final k in ['day', 'month', 'year']) {
      expect(find.byKey(ValueKey('tpo-income-$k')), findsOneWidget, reason: k);
    }
    expect(find.text('Günlük gəlir'), findsOneWidget);
    expect(find.text('Aylıq gəlir'), findsOneWidget);
    expect(find.text('İllik gəlir'), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(const ValueKey('tpo-income-day-total'))).data, contains('7.40'));
    expect(tester.widget<Text>(find.byKey(const ValueKey('tpo-income-month-total'))).data, contains('23.40'));
    expect(tester.widget<Text>(find.byKey(const ValueKey('tpo-income-year-total'))).data, contains('123.40'));
  });

  testWidgets('before SQL 0094: a clear note, no crash', (tester) async {
    await tester.pumpWidget(_app(() async => throw const TirParkNotReady()));
    await tester.pumpAndSettle();
    expect(find.text(_az.t('tpo_income_not_ready')), findsOneWidget);
  });

  test('"Bu gün" opens it; only the owner\'s function', () {
    final panel = src('lib/features/tirpark/presentation/tir_park_owner_panel.dart');
    expect(panel, contains("ValueKey('tpo-today-open')"));
    expect(panel, contains('onToday: () => showTirParkIncome(context, park, s)'));
    expect(src('supabase/migrations/0094_tir_park_income.sql'), contains('perform public._tir_park_owner_only(p_park);'));
  });
}
