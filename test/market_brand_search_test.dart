// TIR Bazarı search (owner, 24.10.2026): a tap opens a "Marka" page like
// big car markets — popular brands with real ad counts, all brands A–Z,
// then the models of the chosen brand.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:freightlink/features/market/domain/market_brand_index.dart';
import 'package:freightlink/features/market/domain/market_catalog.dart';

void main() {
  final rows = [
    {'brand': 'DAF', 'model': 'XF 106'},
    {'brand': 'daf', 'model': 'xf 106'},
    {'brand': 'DAF', 'model': 'XF 480'},
    {'brand': 'Volvo', 'model': 'FH 500'},
    {'brand': 'Volvo', 'model': null},
    {'brand': 'Tatra', 'model': 'Phoenix'}, // not in the catalogue
    {'brand': '', 'model': 'x'},
  ];
  final index = MarketBrandIndex.fromRows(rows);

  test('popular: most ads first, real counts, case does not split a brand', () {
    expect([for (final b in index.popular()) '${b.name}:${b.count}'], ['DAF:3', 'Volvo:2', 'Tatra:1']);
  });

  test('all brands: catalogue + brands that have ads, A–Z; no ads = no number', () {
    final all = index.all(['Volvo', 'MAN', 'DAF']);
    expect([for (final b in all) '${b.name}:${b.count}'], ['DAF:3', 'MAN:0', 'Tatra:1', 'Volvo:2']);
  });

  test('models of a brand with their counts', () {
    final m = index.models('daf', ['XF 106', 'XG']);
    expect([for (final x in m) '${x.name}:${x.count}'], ['XF 106:2', 'XF 480:1', 'XG:0']);
    expect(index.countOf('Daf'), 3);
    expect(MarketBrandIndex.empty.popular(), isEmpty);
  });

  test('letters on the brand square', () {
    expect(brandInitials('DAF'), 'DAF');
    expect(brandInitials('Mercedes-Benz'), 'MB');
    expect(brandInitials('Schmitz Cargobull'), 'SC');
    expect(brandInitials('Volvo'), 'VO');
  });

  test('wired: the search box opens the page; one tap on a brand picks it', () {
    final home = File('lib/features/market/presentation/market_home_screen.dart').readAsStringSync();
    expect(home, contains('readOnly: true'));
    // Owner, 25.10.2026: after a pick the brand is not left selected.
    expect(home, contains('canRequestFocus: false'));
    expect(home, contains('enableInteractiveSelection: false'));
    expect(home, contains('onOpen: () => _openSearch(context, s, filter)'));
    final page = File('lib/features/market/presentation/market_brand_picker.dart').readAsStringSync();
    // Owner, 25.10.2026: no extra "«…» üzrə axtar" row and no second step.
    expect(page, isNot(contains("ValueKey('mk-pick-text')")));
    expect(page, isNot(contains('_ModelPage')));
    expect(page, contains('Navigator.of(context).pop(MarketSearchPick(brand: brand))'));
    expect(page, contains("s.t('mk_brand_not_found')"));
    expect(page, contains("s.t('mk_popular')"));
    final repo = File('lib/features/market/data/market_repository.dart').readAsStringSync();
    expect(repo, contains(".select('brand, model').eq('status', 'active')"));
  });

  group('typing filters at once (owner, 25.10.2026)', () {
    test('first letters, any case, other spellings and languages', () {
      expect(marketBrandMatch('Mercedes-Benz', 'mer'), 0);
      expect(marketBrandMatch('Mercedes-Benz', 'MERCE'), 0);
      expect(marketBrandMatch('Mercedes-Benz', 'мерс'), 0);
      expect(marketBrandMatch('Mercedes-Benz', 'benz'), 1);
      expect(marketBrandMatch('KAMAZ', 'кам'), 0);
      expect(marketBrandMatch('GAZ', 'qazel'), 0);
      expect(marketBrandMatch('Kögel', 'kog'), 0);
      expect(marketBrandMatch('Kögel', 'KÖG'), 0);
      expect(marketBrandMatch('Tırsan', 'tir'), 0);
      expect(marketBrandMatch('Tırsan', 'TIRSAN'), 0);
      expect(marketBrandMatch('Citroën', 'citroen'), 0);
      expect(marketBrandMatch('Schmitz Cargobull', 'schmitzcargo'), 0);
      expect(marketBrandMatch('Mercedes-Benz', 'xyz'), isNull);
      expect(marketBrandMatch('DAF', ''), 0);
    });

    test('folding: Azerbaijani / Turkish letters, case, spaces', () {
      expect(marketSearchKey('İSUZU'), 'isuzu');
      expect(marketSearchKey('Tırsan'), 'tirsan');
      expect(marketSearchKey('Ərsan Şüçğö'), 'ersansucgo');
      expect(marketSearchKey('Gray & Adams'), 'grayadams');
    });
  });
}
