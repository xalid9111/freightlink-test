// Computer browsers (Windows / Mac): GPS messages, map tiles backup and
// the bundled flag font. Pure logic + source guards.
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freightlink/core/widgets/map_tiles.dart';
import 'package:freightlink/core/widgets/mouse_drag_scroll.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:freightlink/features/services/presentation/gps_logic.dart';
import 'package:geolocator/geolocator.dart';

void main() {
  group('GPS: allowed in the browser must not say "not allowed"', () {
    test('denied and not granted → denied', () {
      expect(gpsStateForError(const PermissionDeniedException('User denied Geolocation'), LocationPermission.deniedForever),
          GpsState.denied);
    });
    test('denied but the browser permission is granted → device location is off', () {
      expect(gpsStateForError(const PermissionDeniedException('x'), LocationPermission.whileInUse), GpsState.systemOff);
    });
    test('position unavailable while granted → device location is off', () {
      expect(gpsStateForError(const PositionUpdateException('Network location provider: no response'), LocationPermission.whileInUse),
          GpsState.systemOff);
    });
    test('position unavailable, permission unknown → not found', () {
      expect(gpsStateForError(const PositionUpdateException('x'), null), GpsState.unavailable);
    });
    test('timeout → not found (slow / indoors), never "not allowed"', () {
      expect(gpsStateForError(TimeoutException('t'), LocationPermission.whileInUse), GpsState.unavailable);
      expect(gpsStateForError(TimeoutException('t'), LocationPermission.denied), GpsState.unavailable);
    });
    test('banner texts', () {
      expect(gpsMessageKey(GpsState.denied), 'svc_gps_denied');
      expect(gpsMessageKey(GpsState.unavailable), 'svc_gps_unavailable');
      expect(gpsMessageKey(GpsState.systemOff), 'svc_gps_system_off');
      expect(gpsMessageKey(GpsState.ok), isNull);
      expect(gpsMessageKey(GpsState.locating), isNull);
    });
    test('the GPS button message says why, not just "failed"', () {
      for (final f in ['services_map_screen.dart', 'service_edit_screen.dart']) {
        final src = File('lib/features/services/presentation/$f').readAsStringSync();
        expect(src.contains("gpsMessageKey(ref.read(userLocationProvider).state) ?? 'svc_gps_failed'"), isTrue, reason: f);
      }
    });
    test('web does not use requestPermission (it reports every failure as denied)', () {
      final src = File('lib/features/services/presentation/services_providers.dart').readAsStringSync();
      expect(src.contains('if (!kIsWeb && perm == LocationPermission.denied)'), isTrue);
      expect(src.contains('gpsStateForError(e, now)'), isTrue);
    });
  });

  group('Map tiles backup', () {
    test('one lost tile does not switch, a blocked server does', () {
      final c = TileFailureCounter();
      final t0 = DateTime(2026, 10, 14, 10);
      expect(c.add(t0), isFalse);
      expect(c.add(t0.add(const Duration(seconds: 1))), isFalse);
      expect(c.add(t0.add(const Duration(seconds: 2))), isFalse);
      expect(c.add(t0.add(const Duration(seconds: 3))), isTrue);
    });
    test('failures far apart (weak connection) do not switch', () {
      final c = TileFailureCounter();
      final t0 = DateTime(2026, 10, 14, 10);
      for (var i = 0; i < 10; i++) {
        expect(c.add(t0.add(Duration(seconds: 30 * i))), isFalse);
      }
    });
    test('every map uses the shared tile layer (no direct OpenStreetMap URL)', () {
      final files = Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'));
      for (final f in files) {
        if (f.path.endsWith('map_tiles.dart')) continue;
        final s = f.readAsStringSync();
        expect(s.contains('tile.openstreetmap.org'), isFalse, reason: f.path);
        expect(RegExp(r'(?<![A-Za-z])TileLayer\(').hasMatch(s), isFalse, reason: f.path);
      }
    });
  });

  group('Flags font (no "□□" when the emoji download fails)', () {
    test('font file is bundled and declared as an asset', () {
      expect(File('assets/fonts/flags/NotoColorEmoji-Flags.woff2').existsSync(), isTrue);
      expect(File('assets/fonts/flags/OFL.txt').existsSync(), isTrue);
      expect(File('pubspec.yaml').readAsStringSync().contains('- assets/fonts/flags/'), isTrue);
    });
    test('theme falls back to it and main loads it after the first frame', () {
      final theme = File('lib/core/theme/app_theme.dart').readAsStringSync();
      expect(theme.contains('fontFamilyFallback: AppFonts.fallback'), isTrue);
      expect(File('lib/main.dart').readAsStringSync().contains('addPostFrameCallback((_) => loadFlagFont())'), isTrue);
    });
  });

  group('Computer without GPS: approximate position by internet connection', () {
    test('parses geojs (text numbers) and ipwho.is (numbers)', () {
      expect(parseIpGeo({'latitude': '40.3777', 'longitude': '49.892'}), (40.3777, 49.892));
      expect(parseIpGeo({'success': true, 'latitude': 40.4, 'longitude': 49.87}), (40.4, 49.87));
    });
    test('rejects failures and nonsense', () {
      expect(parseIpGeo({'success': false, 'message': 'limit'}), isNull);
      expect(parseIpGeo({'latitude': 'nil'}), isNull);
      expect(parseIpGeo({'latitude': 0, 'longitude': 0}), isNull);
      expect(parseIpGeo({'latitude': 95, 'longitude': 10}), isNull);
      expect(parseIpGeo('x'), isNull);
    });
    test('approximate state has its own information text', () {
      expect(gpsMessageKey(GpsState.approximate), 'svc_gps_approx');
    });
    test('used only on the web, never after a real "Block", never for the service address pin', () {
      final src = File('lib/features/services/presentation/services_providers.dart').readAsStringSync();
      expect(src.contains('if (allowApprox && kIsWeb && failed != GpsState.denied)'), isTrue);
      final edit = File('lib/features/services/presentation/service_edit_screen.dart').readAsStringSync();
      expect(edit.contains('locate(allowApprox: false)'), isTrue);
    });
  });

  group('Horizontal rows can be dragged with the mouse (computers)', () {
    test('every horizontal row is wrapped', () {
      final files = Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'));
      for (final f in files) {
        final s = f.readAsStringSync();
        final rows = 'scrollDirection: Axis.horizontal'.allMatches(s).length;
        if (rows == 0) continue;
        expect('MouseDragScroll(child:'.allMatches(s).length, rows, reason: f.path);
      }
    });
    testWidgets('a mouse drag scrolls the row', (tester) async {
      final ctrl = ScrollController();
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 40,
            child: MouseDragScroll(
              child: ListView(
                controller: ctrl,
                scrollDirection: Axis.horizontal,
                children: [for (var i = 0; i < 30; i++) SizedBox(width: 100, child: Text('chip $i'))],
              ),
            ),
          ),
        ),
      ));
      final g = await tester.startGesture(const Offset(400, 20), kind: PointerDeviceKind.mouse);
      for (var i = 0; i < 10; i++) {
        await g.moveBy(const Offset(-30, 0));
        await tester.pump();
      }
      await g.up();
      await tester.pumpAndSettle();
      expect(ctrl.offset, greaterThan(100));
    });
  });

  group('Services: "Tent təmiri" category', () {
    test('migration adds it once and the app has its icon', () {
      final sql = File('supabase/migrations/0036_service_category_tarp.sql').readAsStringSync();
      expect(sql.contains("'tarp_repair', 'Tent təmiri'"), isTrue);
      expect(sql.contains('on conflict (id) do nothing'), isTrue);
      expect(File('lib/features/services/presentation/services_providers.dart').readAsStringSync().contains("'tarp' => Icons.roofing"), isTrue);
    });
  });

  group('Services: "Ehtiyat hissələri satışı" category', () {
    test('migration adds it once, first in the list, and the app has its icon', () {
      final sql = File('supabase/migrations/0043_service_category_spare_parts.sql').readAsStringSync();
      expect(sql.contains("'spare_parts', 'Ehtiyat hissələri satışı'"), isTrue);
      expect(sql.contains("'parts', 0)"), isTrue);
      expect(sql.contains('on conflict (id) do nothing'), isTrue);
      expect(File('lib/features/services/presentation/services_providers.dart').readAsStringSync().contains("'parts' => Icons.inventory_2"), isTrue);
    });
  });
}
