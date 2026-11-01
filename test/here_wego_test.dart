import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freightlink/core/localization/app_strings.dart';
import 'package:freightlink/features/chat/presentation/widgets/location_message.dart';
import 'package:freightlink/services/here_wego.dart';

final _az = AppStrings(Map<String, String>.from(jsonDecode(File('assets/i18n/az.json').readAsStringSync()) as Map));

/// HERE WeGo Pro in the "Naviqasiyanı başlat" list (owner, 01.11.2026).
void main() {
  group('map links pasted from WhatsApp are recognized', () {
    test('a shared WhatsApp location (maps.google.com ?q=lat%2Clng)', () {
      final l = ChatLocation.parse('https://maps.google.com/maps?q=40.409300%2C49.867100&z=17&hl=az')!;
      expect([l.lat, l.lng, l.hasOrigin], [40.4093, 49.8671, false]);
    });
    test('a Google route link: start and destination', () {
      final l = ChatLocation.parse('Yol: https://www.google.com/maps/dir/40.3777,49.8920/40.5897,49.6686/@40.48,49.78,11z')!;
      expect([l.fromLat, l.fromLng, l.lat, l.lng], [40.3777, 49.892, 40.5897, 49.6686]);
    });
    test('saddr / daddr', () {
      final l = ChatLocation.parse('https://maps.google.com/?saddr=40.1,49.2&daddr=40.4,49.8')!;
      expect([l.fromLat, l.fromLng, l.lat, l.lng], [40.1, 49.2, 40.4, 49.8]);
    });
    test('a short link has no coordinates (opened as it is)', () {
      final l = ChatLocation.parse('https://maps.app.goo.gl/AbCdEf123')!;
      expect(l.hasCoords, isFalse);
    });
    test('the old links keep working the same', () {
      final l = ChatLocation.parse(ChatLocation.messageFor(40.4093, 49.8671))!;
      expect([l.lat, l.lng, l.hasOrigin], [40.4093, 49.8671, false]);
      final at = ChatLocation.parse('https://www.google.com/maps/place/Baku/@40.40,49.86,12z')!;
      expect([at.lat, at.lng], [40.40, 49.86]);
    });
  });

  group('the HERE link (official share.here.com route format)', () {
    test('truck route; only the measurements the truck has; cm', () {
      expect(hereWeGoRouteLink(fromLat: 40.1, fromLng: 49.2, toLat: 40.4, toLng: 49.8).toString(),
          'https://share.here.com/r/40.100000,49.200000/40.400000,49.800000?m=tr');
      expect(
          hereWeGoRouteLink(fromLat: 40.1, fromLng: 49.2, toLat: 40.4, toLng: 49.8, truck: const TruckDims(heightM: 4, widthM: 2.55, lengthM: 16.5))
              .toString(),
          'https://share.here.com/r/40.100000,49.200000/40.400000,49.800000?m=tr&vdh=400&vdl=1650&vdw=255');
      expect(hereWeGoRouteLink(fromLat: 1, fromLng: 2, toLat: 3, toLng: 4, truck: const TruckDims(heightM: 4)).query, 'm=tr&vdh=400');
    });
    test('nothing invented: empty / impossible values are left out', () {
      final d = TruckDims.fromRow({'height_m': null, 'width_m': '0', 'length_m': 'abc'});
      expect(d.isEmpty, isTrue);
      expect(TruckDims.fromRow({'height_m': '3.95'}).heightM, 3.95);
    });
  });

  testWidgets('the list: the old choices in the same order, then HERE WeGo Pro, then "Linki aç"', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showNavigationPicker(context, _az, const ChatLocation(url: 'https://maps.app.goo.gl/x')),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    final here = tester.getTopLeft(find.text('HERE WeGo Pro')).dy;
    expect(here, lessThan(tester.getTopLeft(find.text('Linki aç')).dy));
    // A link without coordinates: a clear message, "Linki aç" stays.
    await tester.tap(find.byKey(const ValueKey('nav-here')));
    await tester.pumpAndSettle();
    expect(find.text(_az.t('nav_here_no_dest')), findsOneWidget);
  });

  test('wired: the existing choices are kept; HERE uses only the documented link; no new tables', () {
    final src = File('lib/features/chat/presentation/widgets/location_message.dart').readAsStringSync();
    expect(src, contains('for (final app in navigationService.availableApps())'));
    final picker = src.substring(src.indexOf('Future<void> showNavigationPicker('));
    expect(picker.indexOf("key: const ValueKey('nav-here')"), greaterThan(picker.indexOf('navigationService.availableApps()')));
    expect(picker.indexOf("key: const ValueKey('nav-here')"), lessThan(picker.indexOf("strings.t('chat_location_open_link')")));
    final here = File('lib/services/here_wego.dart').readAsStringSync();
    expect(here, contains("'https://share.here.com/r/"));
    expect(here.contains('vw='), isFalse, reason: 'no weight in the trucks table — never invented');
    expect(here.contains('.insert(') || here.contains('.update(') || here.contains('.upsert('), isFalse, reason: 'read only');
  });
}
