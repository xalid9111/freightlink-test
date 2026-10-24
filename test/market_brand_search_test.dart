// TIR Bazarı search (owner, 24.10.2026): a tap opens a "Marka" page like
// big car markets — popular brands with real ad counts, all brands A–Z,
// then the models of the chosen brand.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:freightlink/features/market/domain/market_brand_index.dart';

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

  test('wired: the search box opens the page; free text still searchable', () {
    final home = File('lib/features/market/presentation/market_home_screen.dart').readAsStringSync();
    expect(home, contains('readOnly: true'));
    expect(home, contains('onOpen: () => _openSearch(context, s, filter)'));
    final page = File('lib/features/market/presentation/market_brand_picker.dart').readAsStringSync();
    expect(page, contains("ValueKey('mk-pick-text')"));
    expect(page, contains("s.t('mk_popular')"));
    expect(page, contains("s.t('mk_all_models')"));
    final repo = File('lib/features/market/data/market_repository.dart').readAsStringSync();
    expect(repo, contains(".select('brand, model').eq('status', 'active')"));
  });
}
