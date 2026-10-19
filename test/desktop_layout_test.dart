import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freightlink/core/layout/desktop_layout.dart';
import 'package:freightlink/core/layout/desktop_preview.dart';
import 'package:freightlink/core/localization/app_strings.dart';
import 'package:freightlink/core/localization/locale_controller.dart';
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
  group('Desktop preview on a phone (test only)', () {
    Future<Size> pageSizeIn(WidgetTester tester, Size screen, bool on) async {
      late Size page;
      tester.view.physicalSize = screen;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ProviderScope(
        overrides: [stringsProvider.overrideWithValue(const AppStrings({'desk_preview_exit': 'Mobil görünüş'}))],
        child: MaterialApp(
          builder: (context, child) => applyDesktopPreview(context, on, child!),
          home: Builder(builder: (context) {
            page = MediaQuery.sizeOf(context);
            return const SizedBox();
          }),
        ),
      ));
      return page;
    }

    testWidgets('off: the phone page is exactly as before', (tester) async {
      expect(await pageSizeIn(tester, const Size(390, 844), false), const Size(390, 844));
      expect(find.byKey(const ValueKey('desktop-preview')), findsNothing);
    });
    testWidgets('on: the page is laid out 1440 px wide, zoomable, with a way back', (tester) async {
      expect(await pageSizeIn(tester, const Size(390, 844), true), kDesktopPreviewCanvas);
      expect(find.byKey(const ValueKey('desktop-preview')), findsOneWidget);
      expect(find.byKey(const ValueKey('desktop-preview-exit')), findsOneWidget);
    });
    testWidgets('on a real computer screen it changes nothing', (tester) async {
      expect(await pageSizeIn(tester, const Size(1440, 900), true), const Size(1440, 900));
      expect(find.byKey(const ValueKey('desktop-preview')), findsNothing);
    });
    test('off by default, switch is admin-only in Settings', () {
      expect(DesktopPreviewController().state, isFalse);
      final settings = File('lib/features/auth/presentation/settings_screen.dart').readAsStringSync();
      expect(settings.contains('ref.watch(currentUserProvider)?.role == AppConstants.roleAdmin &&\n              (ref.watch(desktopPreviewProvider)'), isTrue);
    });
  });
}
