// Computer browsers (Windows / Mac): GPS messages, map tiles backup and
// the bundled flag font. Pure logic + source guards.
import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:freightlink/core/widgets/map_tiles.dart';
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
}
