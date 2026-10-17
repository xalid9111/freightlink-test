// Services page — universal search: letters, ranking, distance, pins.
import 'package:flutter_test/flutter_test.dart';
import 'package:freightlink/features/services/presentation/service_search_logic.dart';

void main() {
  group('foldText (Azerbaijani letters, case, spelling)', () {
    test('ə ı ö ü ş ç ğ and capitals fold to the same text', () {
      expect(foldText('ŞƏKİ'), 'seki');
      expect(foldText('Şəki'), 'seki');
      expect(foldText('Bakı'), 'baki');
      expect(foldText('GÜRCÜSTAN Çoban Ağa'), 'gurcustan coban aga');
      expect(foldText('İstanbul'), 'istanbul');
      expect(foldText('Tent  təmiri, 24/7!'), 'tent temiri 24 7');
    });

    test('Georgian and Russian letters are kept', () {
      expect(foldText('თბილისი'), 'თბილისი');
      expect(foldText('Тбилиси'), 'тбилиси');
    });
  });

  group('dbPattern', () {
    test('longest word, ambiguous letters become "_"', () {
      expect(dbPattern('Şəki'), '__k_');
      expect(dbPattern('baki'), 'bak_');
      expect(dbPattern('tent baki'), anyOf('t_nt', 'bak_'));
    });

    test('PostgREST-breaking characters are removed; too short = null', () {
      expect(dbPattern('a'), isNull);
      expect(dbPattern('(),%*'), isNull);
      expect(dbPattern('ab,cd'), 'ab');
    });
  });

  group('serviceMatchRank', () {
    int? rank(String q, String name, {String? city, List<String> cats = const []}) =>
        serviceMatchRank(query: q, name: name, city: city, categoryNames: cats);

    test('exact name beats prefix beats word prefix beats contains beats other fields', () {
      expect(rank('elvin servis', 'Elvin Servis'), 0);
      expect(rank('elvin', 'Elvin Servis'), 1);
      expect(rank('servis', 'Elvin Servis'), 2);
      expect(rank('vin', 'Elvin Servis'), 3);
      expect(rank('baki', 'Elvin Servis', city: 'Bakı'), 4);
      expect(rank('tent', 'Elvin Servis', cats: ['Tent təmiri']), 4);
    });

    test('Azerbaijani letters and case do not matter', () {
      expect(rank('SEKI', 'Şəki Avto'), 1);
      expect(rank('şəki', 'Seki Avto'), 1);
    });

    test('every word must be found; otherwise no match', () {
      expect(rank('elvin gence', 'Elvin Servis', city: 'Bakı'), isNull);
      expect(rank('elvin baki', 'Elvin Servis', city: 'Bakı'), 4);
      expect(rank('', 'Elvin'), isNull);
    });
  });

  group('distance and pins', () {
    test('no fake coordinates: 0,0 and out of range are "no pin"', () {
      expect(hasRealCoords(40.4, 49.8), isTrue);
      expect(hasRealCoords(0, 0), isFalse);
      expect(hasRealCoords(null, 49.8), isFalse);
      expect(hasRealCoords(91, 10), isFalse);
    });

    test('distance only when both positions are real', () {
      expect(userDistanceKm(userLat: null, userLng: null, lat: 40.4, lng: 49.8), isNull);
      expect(userDistanceKm(userLat: 40.4, userLng: 49.8, lat: 0, lng: 0), isNull);
      // Baku → Tbilisi ≈ 450 km straight line.
      final d = userDistanceKm(userLat: 40.4093, userLng: 49.8671, lat: 41.7151, lng: 44.8271)!;
      expect(d, inInclusiveRange(430, 470));
    });
  });

  group('sortHits', () {
    test('better match first; same level → nearest; unknown distance last', () {
      final out = sortHits([
        const RankedHit('far-exact', 0, 500, 'A'),
        const RankedHit('near-city', 4, 1, 'B'),
        const RankedHit('near-exact', 0, 2, 'A'),
        const RankedHit('unknown-exact', 0, null, 'A'),
      ]);
      expect(out, ['near-exact', 'far-exact', 'unknown-exact', 'near-city']);
    });

    test('same name in different cities stays as separate results', () {
      final out = sortHits([
        const RankedHit('usta-gence', 0, 300, 'Usta'),
        const RankedHit('usta-baki', 0, 5, 'Usta'),
      ]);
      expect(out, ['usta-baki', 'usta-gence']);
    });
  });

  group('categoryMatches', () {
    test('any language name, folded', () {
      final names = ['Tent təmiri', 'Tente tamiri', 'Tarp repair', 'Ремонт тента', null];
      expect(categoryMatches('tent', names), isTrue);
      expect(categoryMatches('TEMIRI', names), isTrue);
      expect(categoryMatches('тента', names), isTrue);
      expect(categoryMatches('motor', names), isFalse);
    });
  });

  test('placeZoom: country far, street close', () {
    expect(placeZoom('boundary', 'country'), 6);
    expect(placeZoom('place', 'city'), 12);
    expect(placeZoom('highway', 'residential'), 15);
    expect(placeZoom('place', 'suburb'), 13);
  });
}
