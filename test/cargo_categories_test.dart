// Load categories (0055, owner 21.10.2026): tiles, big / small, QRUPAJ and
// "Yolüstü yük". The server rules are tested in
// supabase/tests/local/93_cargo_categories.sql.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:freightlink/features/cargo/domain/cargo_categories.dart';
import 'package:freightlink/features/cargo/domain/en_route.dart';
import 'package:freightlink/models/cargo_model.dart';
import 'package:latlong2/latlong.dart';

CargoModel load({String? truck, String? size, bool groupage = false}) => CargoModel(
      id: 'x',
      ownerId: 'o',
      pickupCountry: 'Azerbaijan',
      pickupCity: 'Baku',
      destinationCountry: 'Georgia',
      destinationCity: 'Tbilisi',
      weightKg: 1000,
      pickupDate: DateTime(2026, 10, 22),
      offeredPrice: 100,
      truckType: truck,
      loadSize: size,
      groupage: groupage,
    );

void main() {
  group('category filter', () {
    test('a tile selects, a second tap clears; one tile at a time', () {
      var f = const CargoCategoryFilter();
      f = f.tapTruck('tent');
      expect(f.truckType, 'tent');
      f = f.tapGroupage();
      expect((f.truckType, f.groupage), (null, true));
      f = f.tapGroupage();
      expect(f.isActive, isFalse);
    });

    test('size works together with a tile', () {
      final f = const CargoCategoryFilter().tapTruck('ref').tapSize(kLoadSizeSmall);
      expect(f.matches(load(truck: 'ref', size: 'small')), isTrue);
      expect(f.matches(load(truck: 'ref', size: 'big')), isFalse);
      expect(f.matches(load(truck: 'tent', size: 'small')), isFalse);
    });

    test('a load whose size is not known is in neither big nor small, but in the list', () {
      final old = load(truck: 'tent');
      expect(const CargoCategoryFilter(size: kLoadSizeBig).matches(old), isFalse);
      expect(const CargoCategoryFilter(size: kLoadSizeSmall).matches(old), isFalse);
      expect(const CargoCategoryFilter().matches(old), isTrue);
    });

    test('QRUPAJ is its own category and always small', () {
      expect(const CargoCategoryFilter(groupage: true).matches(load(truck: 'tent', size: 'small', groupage: true)), isTrue);
      expect(const CargoCategoryFilter(groupage: true).matches(load(truck: 'tent', size: 'small')), isFalse);
      expect(effectiveLoadSize(groupage: true, picked: kLoadSizeBig), kLoadSizeSmall);
      expect(effectiveLoadSize(groupage: false, picked: null), isNull);
      expect(kCategoryTruckTypes.contains('groupage'), isFalse);
    });

    test('every truck type is still offered (4 tiles + Açıq, Sistern)', () {
      expect({...kCategoryTruckTypes, ...kOtherTruckTypes}, {'tent', 'ref', 'container', 'dump', 'open', 'tanker'});
      for (final c in [...kCategoryTruckTypes, 'groupage']) {
        expect(File(categoryIconAsset(c)).existsSync(), isTrue, reason: c);
      }
    });

    test('size columns are left out of a save until 0055 is run', () {
      final j = load(size: 'small', groupage: true).toInsertJson(withSize: false);
      expect(j.containsKey('load_size') || j.containsKey('groupage'), isFalse);
      final k = load(size: 'small', groupage: true).toInsertJson();
      expect((k['load_size'], k['groupage']), ('small', true));
      final back = CargoModel.fromJson({
        'id': 'x', 'owner_id': 'o', 'pickup_country': 'A', 'pickup_city': 'a', 'destination_country': 'B',
        'destination_city': 'b', 'weight_kg': 1, 'pickup_date': '2026-10-22', 'offered_price': 1,
      });
      expect((back.loadSize, back.groupage), (null, false));
    });
  });

  group('Yolüstü yük — on the carrier\'s road, in his direction', () {
    // A straight road Baku → Tbilisi (west), points along it.
    final route = [const LatLng(40.40, 49.87), const LatLng(40.68, 46.36), const LatLng(41.72, 44.79)];
    ({String load, LatLng pickup, LatLng drop}) l(String id, LatLng p, LatLng d) => (load: id, pickup: p, drop: d);

    test('pickup and delivery near the road, same direction → on the way', () {
      final r = findEnRoute<String>(route: route, loads: [
        l('on', const LatLng(40.45, 49.30), const LatLng(40.70, 46.40)), // Baku area → Ganja
        l('back', const LatLng(40.70, 46.40), const LatLng(40.45, 49.30)), // opposite direction
        l('far', const LatLng(38.50, 48.80), const LatLng(40.70, 46.40)), // pickup ~200 km off
      ]);
      expect(r.map((m) => m.load), ['on']);
      expect(r.single.pickupOffKm, lessThan(50));
    });

    test('same country but off the road is NOT on the way', () {
      // Both ends in Azerbaijan, but Lankaran / Astara are far from Baku → Tbilisi.
      final r = findEnRoute<String>(route: route, loads: [l('az', const LatLng(38.75, 48.85), const LatLng(38.43, 48.87))]);
      expect(r, isEmpty);
    });

    test('the corridor width matters; sorted in driving order', () {
      final loads = [
        l('b', const LatLng(41.20, 45.60), const LatLng(41.70, 44.85)),
        l('a', const LatLng(40.80, 49.00), const LatLng(40.70, 46.50)), // ~40 km off the road
      ];
      expect(findEnRoute<String>(route: route, loads: loads, maxOffKm: 25).map((m) => m.load), ['b']);
      expect(findEnRoute<String>(route: route, loads: loads, maxOffKm: 50).map((m) => m.load), ['a', 'b']);
    });

    test('no road route → nothing', () {
      expect(findEnRoute<String>(route: const [LatLng(40, 49)], loads: [l('x', const LatLng(40, 49), const LatLng(40, 48))]), isEmpty);
    });

    test('the screen only uses a real road route (never a country match)', () {
      final s = File('lib/features/cargo/presentation/en_route_screen.dart').readAsStringSync();
      expect(s.contains("if (!route.isRoad) return _show('enroute_no_route');"), isTrue);
      expect(s.contains('pickupCountry =='), isFalse);
    });
  });

  group('Loads page wiring', () {
    final mobile = File('lib/features/cargo/presentation/cargo_marketplace_screen.dart').readAsStringSync();
    final desk = File('lib/features/cargo/presentation/cargo_marketplace_desktop.dart').readAsStringSync();
    test('"Populyar marşrutlar" is gone; tiles + big / small cards on phone and computer', () {
      expect(mobile.contains('home_popular_routes'), isFalse);
      expect(desk.contains('_DeskPopularRoutes'), isFalse);
      for (final f in [mobile, desk]) {
        expect(f.contains('CargoTypeTiles('), isTrue);
        expect(f.contains('CargoSizeCards('), isTrue);
        expect(f.contains("key: const ValueKey('cat-reset')"), isTrue);
      }
    });

    test('tile pictures are packaged', () {
      expect(File('pubspec.yaml').readAsStringSync().contains('    - assets/images/cargo/'), isTrue);
    });

    test('the form keeps groupage separate from the truck type', () {
      final form = File('lib/features/cargo/presentation/cargo_quick_form.dart').readAsStringSync();
      expect(form.contains('onTap: () => setState(() => _groupage = !_groupage),'), isTrue);
      expect(form.contains('loadSize: effectiveLoadSize(groupage: _groupage, picked: _size),'), isTrue);
    });
  });
}
