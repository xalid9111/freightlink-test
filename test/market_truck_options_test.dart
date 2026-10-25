// TIR Bazarı (owner, 25.10.2026, 0065): "Satışdadır" / "Sifarişlə", wheel
// formula, equipment, damage, popular brands with logos in the filter.
// Server side: supabase/tests/local/102_market_truck_options.sql.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:freightlink/features/market/domain/market_brand_logos.dart';
import 'package:freightlink/features/market/domain/market_catalog.dart';
import 'package:freightlink/features/market/domain/market_models.dart';

Map<String, dynamic> _row([Map<String, dynamic> more = const {}]) => {
      'id': 'x', 'listing_no': 1, 'owner_id': 'o', 'status': 'active', 'category': 'truck', //
      'created_at': '2026-10-25T10:00:00Z', ...more,
    };

void main() {
  test('older ads (no values) are in stock, with nothing else given', () {
    final l = MarketListing.fromJson(_row());
    expect((l.onOrder, l.axleFormula, l.damaged), (false, null, null));
    expect(l.equipment, isEmpty);
    expect(MarketListing.fromJson(_row({'availability': 'in_stock'})).onOrder, isFalse);
  });

  test('stored values are read; unknown ones are dropped', () {
    final l = MarketListing.fromJson(_row({
      'availability': 'on_order', 'axle_formula': '6x4', 'equipment': ['adr', 'jacuzzi', 'retarder'], 'damaged': false,
    }));
    expect((l.onOrder, l.axleFormula, l.damaged), (true, '6x4', false));
    expect(l.equipment, ['retarder', 'adr']);
    expect(MarketListing.fromJson(_row({'axle_formula': '10x10'})).axleFormula, isNull);
  });

  test('the form saves the choices; a trailer has no wheel formula', () {
    final d = MarketDraft.from(MarketListing.fromJson(_row({
      'availability': 'on_order', 'axle_formula': '8x4', 'equipment': ['sleeper'], 'damaged': true,
    })));
    final j = d.toJson();
    expect((j['availability'], j['axle_formula'], j['damaged']), ('on_order', '8x4', true));
    expect(j['equipment'], ['sleeper']);
    expect(MarketDraft().toJson()['availability'], 'in_stock');
    expect(MarketDraft().toJson()['damaged'], isNull);
    expect((MarketDraft(category: MarketCategory.semitrailer)..axleFormula = '4x2').toJson()['axle_formula'], isNull);
    expect(marketHasAxleFormula(MarketCategory.trailer), isFalse);
    expect(marketHasAxleFormula(null), isTrue);
  });

  test('search sends the 0065 parameters only when chosen (works before 0065)', () {
    final plain = const MarketFilter().toParams();
    expect(plain.keys, isNot(anyElement(isIn(['p_availability', 'p_axle_formula', 'p_equipment', 'p_damaged']))));
    final p = const MarketFilter(availability: 'on_order', axleFormula: '6x4', equipment: ['adr'], damaged: false).toParams();
    expect((p['p_availability'], p['p_axle_formula'], p['p_damaged']), ('on_order', '6x4', false));
    expect(p['p_equipment'], ['adr']);
    expect(const MarketFilter(availability: 'soon', axleFormula: 'x').toParams().keys,
        isNot(anyElement(isIn(['p_availability', 'p_axle_formula']))));
    expect(const MarketFilter(equipment: ['adr']), const MarketFilter(equipment: ['adr']));
    expect(const MarketFilter(equipment: ['adr']) == const MarketFilter(equipment: ['sleeper']), isFalse);
    expect(const MarketFilter(damaged: true).hasDetails, isTrue);
    final repo = File('lib/features/market/data/market_repository.dart').readAsStringSync();
    // Before 0065: "on order" / truck options find nothing, "in stock" finds all.
    expect(repo, contains("params['p_availability'] == 'on_order'"));
    expect(repo, contains("'availability', 'axle_formula', 'equipment', 'damaged'"));
  });

  test('12 popular brands, all in the catalogue and all with a logo', () {
    expect(kMarketPopularBrands.length, 12);
    final all = {for (final c in MarketCategory.values) ...marketBrands(c)};
    for (final b in kMarketPopularBrands) {
      expect(all, contains(b), reason: b);
      expect(marketBrandLogoAsset(b), isNotNull, reason: b);
    }
    expect(kMarketPopularBrands.take(4), ['Mercedes-Benz', 'DAF', 'Scania', 'Volvo']);
    expect(kMarketPopularBrands, containsAll(['Schmitz Cargobull', 'Kögel', 'Krone']));
  });

  test('wired: filter, form, card, detail and the computer', () {
    final home = File('lib/features/market/presentation/market_home_screen.dart').readAsStringSync();
    for (final k in ["ValueKey('mk-filter-popular')", "ValueKey('mk-filter-avail-\$a')", "ValueKey('mk-filter-axle-\$a')",
      "ValueKey('mk-filter-eq-\$e')", "ValueKey('mk-filter-damage-\$d')", 'BrandBadge(brand, size: 44)']) {
      expect(home, contains(k));
    }
    final form = File('lib/features/market/presentation/market_edit_screen.dart').readAsStringSync();
    for (final k in ["ValueKey('mk-avail-\$a')", "ValueKey('mk-axle-\$a')", "ValueKey('mk-eq-\$e')", "ValueKey('mk-damage-\$d')"]) {
      expect(form, contains(k));
    }
    expect(File('lib/features/market/presentation/market_card.dart').readAsStringSync(),
        contains('if (l.onOrder) Positioned(left: 8, bottom: 8, child: MarketOnOrderTag(s: s))'));
    final detail = File('lib/features/market/presentation/market_detail_screen.dart').readAsStringSync();
    for (final k in ['mk-detail-on-order', 'mk-detail-axle', 'mk-detail-equipment', 'mk-detail-damage']) {
      expect(detail, contains(k));
    }
    final desk = File('lib/features/market/presentation/market_home_desktop.dart').readAsStringSync();
    for (final k in ['desk-mk-avail-', 'desk-mk-axle-', 'desk-mk-eq-', 'desk-mk-damage-']) {
      expect(desk, contains(k));
    }
  });

  test('six languages', () {
    for (final lang in ['az', 'tr', 'en', 'ru', 'ka', 'zh']) {
      final j = File('assets/i18n/$lang.json').readAsStringSync();
      for (final k in ['mk_availability', 'mk_avail_in_stock', 'mk_avail_on_order', 'mk_popular_brands', 'mk_axle_formula',
        'mk_equipment', for (final e in kMarketEquipment) 'mk_eq_$e', 'mk_condition', 'mk_damage_no', 'mk_damage_yes']) {
        expect(j.contains('"$k"'), isTrue, reason: '$lang $k');
      }
    }
  });

  test('0065 is safe and in the SQL suite', () {
    final sql = File('supabase/migrations/0065_market_truck_options.sql').readAsStringSync().toLowerCase();
    for (final bad in ['drop table', 'truncate', 'delete from', 'update public', 'drop column', 'drop policy', 'drop constraint']) {
      expect(sql.contains(bad), isFalse, reason: bad);
    }
    expect(RegExp(r'drop function if exists public\.(\w+)').allMatches(sql).map((m) => m.group(1)).toSet(), {'market_search'});
    expect(sql.contains('\nbegin;\n'), isTrue);
    expect(sql.trimRight().endsWith('commit;'), isTrue);
    expect(sql.contains('0065: final check failed'), isTrue);
    final run = File('supabase/tests/local/run_local.sh').readAsStringSync();
    expect(run, contains('0065_market_truck_options.sql'));
    expect(run, contains('102_market_truck_options.sql'));
  });
}
