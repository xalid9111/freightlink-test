import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freightlink/core/layout/desktop_layout.dart';
import 'package:freightlink/features/cargo/presentation/cargo_marketplace_screen.dart';
import 'package:freightlink/models/cargo_model.dart';

CargoModel _load(String from, String fromCity, String to, String toCity, {String? truck}) => CargoModel(
      id: 'x',
      ownerId: 'o',
      pickupCountry: from,
      pickupCity: fromCity,
      destinationCountry: to,
      destinationCity: toCity,
      weightKg: 20000,
      truckType: truck,
      pickupDate: DateTime(2026, 10, 20),
      offeredPrice: 1000,
    );

void main() {
  group('Desktop layout only on wide windows (mobile unchanged)', () {
    Future<bool> desktopAt(WidgetTester tester, double width) async {
      late bool result;
      await tester.pumpWidget(MediaQuery(
        data: MediaQueryData(size: Size(width, 800)),
        child: Builder(builder: (context) {
          result = isDesktopLayout(context);
          return const SizedBox();
        }),
      ));
      return result;
    }

    testWidgets('phones and tablets keep the mobile layout', (tester) async {
      expect(await desktopAt(tester, 390), isFalse);
      expect(await desktopAt(tester, 820), isFalse);
      expect(await desktopAt(tester, kDesktopMinWidth - 1), isFalse);
    });
    testWidgets('1366 / 1440 / 1920 use the desktop layout', (tester) async {
      expect(await desktopAt(tester, 1366), isTrue);
      expect(await desktopAt(tester, 1440), isTrue);
      expect(await desktopAt(tester, 1920), isTrue);
    });

    test('mobile bottom bar and mobile loads page are still there', () {
      final shell = File('lib/core/router/main_shell.dart').readAsStringSync();
      expect(shell.contains('_BottomBar(') && shell.contains('if (isDesktopLayout(context))'), isTrue);
      final loads = File('lib/features/cargo/presentation/cargo_marketplace_screen.dart').readAsStringSync();
      expect(loads.contains('if (isDesktopLayout(context)) return const _DesktopMarketplace();'), isTrue);
    });

    test('every language has a flag for the sidebar language button', () {
      for (final code in ['az', 'tr', 'en', 'ru', 'ka', 'zh']) {
        expect(languageFlag(code), isNot('🌐'), reason: code);
      }
    });
  });

  group('Desktop loads search (top search field)', () {
    final load = _load('AZ', 'Bakı', 'GE', 'Tbilisi', truck: 'Tent');
    test('empty search shows everything', () {
      expect(deskLoadMatches(load, '', 'az'), isTrue);
      expect(deskLoadMatches(load, '   ', 'az'), isTrue);
    });
    test('finds by city, country code and truck type, any case', () {
      expect(deskLoadMatches(load, 'bakı', 'az'), isTrue);
      expect(deskLoadMatches(load, 'TBILISI', 'az'), isTrue);
      expect(deskLoadMatches(load, 'ge', 'az'), isTrue);
      expect(deskLoadMatches(load, 'tent', 'az'), isTrue);
    });
    test('every word must match', () {
      expect(deskLoadMatches(load, 'Bakı Tbilisi', 'az'), isTrue);
      expect(deskLoadMatches(load, 'Bakı Moskva', 'az'), isFalse);
    });
  });
}
