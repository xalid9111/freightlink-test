// TIRPark map data from OpenStreetMap (owner, 11.11.2026, SQL 0117):
// never Azerbaijan, only on the map, marked "Xəritə məlumatı", nothing
// bookable or made up, read from our own table one screen at a time.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freightlink/core/localization/app_strings.dart';
import 'package:freightlink/features/tirpark/domain/osm_truck_park.dart';
import 'package:freightlink/features/tirpark/presentation/osm_parks.dart';

String src(String p) => File(p).readAsStringSync();
final _az = AppStrings(Map<String, String>.from(jsonDecode(src('assets/i18n/az.json')) as Map));

void main() {
  group('the area asked for', () {
    test('nothing below zoom 7 or for a huge screen', () {
      expect(OsmBounds.of(south: 40, west: 44, north: 42, east: 47, zoom: 6.9), isNull);
      expect(OsmBounds.of(south: 30, west: 10, north: 50, east: 60, zoom: 8), isNull);
    });

    test('snapped to 0.5°, so a small move asks nothing new', () {
      final a = OsmBounds.of(south: 41.62, west: 44.71, north: 41.88, east: 45.02, zoom: 10)!;
      expect((a.south, a.west, a.north, a.east), (41.5, 44.5, 42.0, 45.5));
      final b = OsmBounds.of(south: 41.6, west: 44.75, north: 41.9, east: 45.1, zoom: 11)!;
      expect(b, a);
      expect(b.hashCode, a.hashCode);
    });
  });

  group('only the source\'s facts', () {
    test('what is not in the source is not shown', () {
      final p = OsmTruckPark.fromJson({
        'id': 'way/5',
        'lat': 41.8,
        'lng': 44.9,
        'name': '  ',
        'tags': {'kind': 'rest_area', 'capacity:hgv': 'about 20', 'toilets': 'yes', 'shower': 'no'},
      });
      expect(p.name, isNull);
      expect(p.kind, 'rest_area');
      expect(p.paid, isNull, reason: 'no fee tag = not said');
      expect(p.capacity, isNull, reason: 'only a plain number is a capacity');
      expect(p.facilities, ['toilets']);
      expect(p.openingHours, isNull);
      expect(p.sourceUrl, 'https://www.openstreetmap.org/way/5');
    });

    testWidgets('the sheet: mark, not checked, no booking, the source named', (t) async {
      var nav = 0;
      final p = OsmTruckPark.fromJson({
        'id': 'node/1',
        'lat': 41.7,
        'lng': 44.8,
        'name': 'TIR Park Tbilisi',
        'tags': {'kind': 'parking', 'fee': 'yes', 'capacity:hgv': '40', 'opening_hours': '24/7'},
      });
      await t.pumpWidget(MaterialApp(home: Scaffold(body: OsmParkSheet(s: _az, park: p, onNavigate: () => nav++))));
      expect(find.text('TIR Park Tbilisi'), findsOneWidget);
      expect(find.text('Xəritə məlumatı'), findsOneWidget);
      expect(find.byKey(const ValueKey('osm-unverified')), findsOneWidget);
      expect(find.textContaining('Platforma tərəfindən yoxlanılmayıb'), findsOneWidget);
      expect(find.text('Ödənişli'), findsOneWidget);
      expect(find.text('TIR yeri: 40'), findsOneWidget);
      expect(find.text('İş saatları: 24/7'), findsOneWidget);
      expect(find.textContaining('OpenStreetMap'), findsWidgets);
      // Nothing of a platform park: no booking, no rating, no favourite, no hide for users.
      expect(find.byKey(const ValueKey('osm-hide')), findsNothing);
      expect(find.byIcon(Icons.favorite_border), findsNothing);
      expect(find.byIcon(Icons.star), findsNothing);
      expect(find.textContaining('Rezerv et'), findsNothing);
      await t.tap(find.byKey(const ValueKey('osm-navigate')));
      expect(nav, 1);
    });

    testWidgets('no name in the source: "TIR dayanacağı"; admins get Gizlət', (t) async {
      var hidden = 0;
      const p = OsmTruckPark(id: 'node/2', lat: 1, lng: 2);
      await t.pumpWidget(MaterialApp(
          home: Scaffold(body: OsmParkSheet(s: _az, park: p, onNavigate: () {}, onHide: () => hidden++))));
      expect(find.text('TIR dayanacağı'), findsWidgets);
      await t.tap(find.byKey(const ValueKey('osm-hide')));
      expect(hidden, 1);
    });
  });

  group('wiring', () {
    final screen = src('lib/features/tirpark/presentation/tir_park_screen.dart');
    final repo = src('lib/features/tirpark/data/tir_park_repository.dart');

    test('the nearby list stays the platform\'s parks; OSM only on the map', () {
      expect(screen.contains('nearbyParks(parks, from.latitude'), isTrue);
      expect(RegExp(r'nearbyParks\([^)]*osm').hasMatch(screen), isFalse);
      expect(screen.contains("ValueKey('tp-osm-\${o.id}')"), isTrue);
      expect(screen.contains('OsmParkPin('), isTrue);
      expect(screen.contains('osmOn = _osmBounds != null && _needs.isEmpty'), isTrue, reason: 'facility filters stay the platform\'s');
      expect(screen.contains('Duration(milliseconds: 400)'), isTrue, reason: 'asked after the map stops');
    });

    test('read from our own table, never from an outside API', () {
      expect(repo.contains("rpc('osm_truck_parks_in_bounds'"), isTrue);
      for (final f in Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'))) {
        final c = f.readAsStringSync().toLowerCase();
        expect(c.contains('overpass-api') || c.contains('geofabrik.de'), isFalse, reason: f.path);
      }
    });

    test('0117: never AZ, its own tables, the platform\'s parks untouched', () {
      final m = src('supabase/migrations/0117_osm_truck_parks.sql');
      expect(m.contains("country_code <> 'AZ'"), isTrue);
      expect(m.contains("raise exception 'not_allowed_az'"), isTrue);
      expect(RegExp(r'alter\s+table\s+public\.tir_parks|drop\s+table|truncate', caseSensitive: false).hasMatch(m), isFalse);
      expect(m.contains('grant execute on function public.osm_truck_parks_upsert(text, jsonb, text, text) to service_role'), isTrue);
      expect(m.contains('revoke all on public.osm_truck_parks from anon, authenticated'), isTrue);
    });
  });
}
