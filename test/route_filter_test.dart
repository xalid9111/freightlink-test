// "Haradan → Haraya" filter: key format used for saved routes.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:freightlink/features/cargo/presentation/widgets/route_city_sheet.dart';
import 'package:freightlink/models/cargo_model.dart';
import 'package:freightlink/features/cargo/presentation/providers/route_filter.dart';

void main() {
  test('empty filter is inactive and has the wildcard key', () {
    const f = RouteFilter();
    expect(f.isActive, isFalse);
    expect(f.key, '*>*');
  });

  test('key round-trips through fromKey', () {
    for (final f in const [RouteFilter(from: 'AZ', to: 'RU'), RouteFilter(from: 'AZ'), RouteFilter(to: 'TR')]) {
      final back = RouteFilter.fromKey(f.key)!;
      expect(back.from, f.from);
      expect(back.to, f.to);
      expect(back.isActive, isTrue);
    }
  });

  test('malformed keys are rejected', () {
    expect(RouteFilter.fromKey('AZ'), isNull);
    expect(RouteFilter.fromKey('AZ>RU>TR'), isNull);
  });

  // Owner, 24.10.2026: cities and districts inside the chosen country.
  group('city / district inside the country', () {
    CargoModel load(String fromCountry, String fromCity, String toCountry, String toCity) => CargoModel(
          id: 'x', ownerId: 'o', pickupCountry: fromCountry, pickupCity: fromCity,
          destinationCountry: toCountry, destinationCity: toCity, weightKg: 1, pickupDate: DateTime(2026, 10, 30), offeredPrice: 1);

    test('city keys round-trip; old saved keys stay valid', () {
      const f = RouteFilter(from: 'AZ', fromCity: 'Baku', to: 'AZ', toCity: 'Ganja');
      expect(f.key, 'AZ/Baku>AZ/Ganja');
      final back = RouteFilter.fromKey(f.key)!;
      expect([back.from, back.fromCity, back.to, back.toCity], ['AZ', 'Baku', 'AZ', 'Ganja']);
      final old = RouteFilter.fromKey('AZ>RU')!;
      expect([old.from, old.fromCity, old.to, old.toCity], ['AZ', null, 'RU', null]);
    });

    test('a city matches in any language / spelling; whole country unchanged', () {
      final l = load('Azerbaijan', 'Bakı', 'Azerbaijan', 'Gence');
      expect(const RouteFilter(from: 'AZ', fromCity: 'Baku').matches(l), isTrue);
      expect(const RouteFilter(from: 'AZ', fromCity: 'Baku', to: 'AZ', toCity: 'Ganja').matches(l), isTrue);
      expect(const RouteFilter(from: 'AZ', fromCity: 'Sumqayit').matches(l), isFalse);
      expect(const RouteFilter(from: 'AZ', to: 'AZ').matches(l), isTrue);
      expect(const RouteFilter(from: 'AZ', fromCity: 'Baku').swapped.toCity, 'Baku');
    });

    test('districts of Azerbaijan are listed, with real load counts', () {
      final loads = [load('Azerbaijan', 'Baku', 'Georgia', 'Tbilisi'), load('Azerbaijan', 'Bakı', 'Russia', 'Moscow'), load('Azerbaijan', 'Masallı', 'Azerbaijan', 'Baku')];
      final rows = routeCitiesOf('AZ', loads, isFrom: true, lang: 'az');
      expect(rows.length, greaterThanOrEqualTo(70));
      expect(rows.firstWhere((r) => r.value == 'Baku').loads, 2);
      expect(rows.firstWhere((r) => r.value == 'Masally').loads, 1);
      expect(rows.firstWhere((r) => r.value == 'Lerik').loads, 0);
      expect(rows.any((r) => r.label == 'Qəbələ'), isTrue);
      // Azerbaijani alphabet order: Ağcabədi before Astara, Şəki after Sabirabad.
      final labels = [for (final r in rows) r.label];
      expect(labels.indexOf('Ağcabədi'), lessThan(labels.indexOf('Astara')));
      expect(labels.indexOf('Sabirabad'), lessThan(labels.indexOf('Şəki')));
      expect(labels.indexOf('Xaçmaz'), lessThan(labels.indexOf('İmişli')));
      // A place not in the catalogue but named by a load is offered too.
      final extra = routeCitiesOf('AZ', [load('Azerbaijan', 'Hövsan', 'Georgia', 'Tbilisi')], isFrom: true, lang: 'az');
      expect(extra.any((r) => r.value == 'Hövsan' && r.loads == 1), isTrue);
    });

    test('wired on phone and computer: country, then city list', () {
      final m = File('lib/features/cargo/presentation/cargo_marketplace_screen.dart').readAsStringSync();
      expect(m, contains('RouteCitySheet('));
      expect(m, contains('filter.swapped'));
      final d = File('lib/features/cargo/presentation/cargo_marketplace_desktop.dart').readAsStringSync();
      expect(d, contains('mobile._label(code, city, lang'));
    });
  });
}
