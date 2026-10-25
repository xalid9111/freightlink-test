// TIR Bazarı catalogue (owner, 25.10.2026, Mərhələ 2, 0064): about 120
// brands, medium / light trucks, body type, other spellings, logo
// fallback. Server side: supabase/tests/local/101_market_catalog.sql.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:freightlink/features/market/domain/market_brand_index.dart';
import 'package:freightlink/features/market/domain/market_brand_logos.dart';
import 'package:freightlink/features/market/domain/market_catalog.dart';
import 'package:freightlink/features/market/domain/market_models.dart';

/// The catalogue before Mərhələ 2 — every brand and model must stay.
const Map<MarketCategory, Map<String, List<String>>> kOldCatalog = {
  MarketCategory.truck: {
    'DAF': ['XF 105', 'XF 106', 'XF 480', 'XF 530', 'XG', 'XG+', 'CF', 'LF'],
    'Mercedes-Benz': ['Actros', 'Actros 1845', 'Actros 1848', 'Actros 1851', 'Arocs', 'Atego', 'Axor'],
    'Volvo': ['FH 460', 'FH 500', 'FH 540', 'FH16', 'FM', 'FMX'],
    'Scania': ['R410', 'R450', 'R500', 'R540', 'S450', 'S500', 'G410', 'P410'],
    'MAN': ['TGX 18.440', 'TGX 18.480', 'TGX 18.510', 'TGS', 'TGM', 'TGL'],
    'Iveco': ['S-Way', 'Stralis', 'Eurocargo', 'Trakker', 'X-Way'],
    'Renault': ['T 460', 'T 480', 'T 520', 'C', 'K', 'D'],
    'Ford Trucks': ['F-MAX', '1848T', 'Cargo'],
    'KAMAZ': ['5490', '54901', '6520', '65115', '43118'],
    'MAZ': ['5440', '6430', '6501'],
    'Isuzu': ['F-Series', 'N-Series', 'Giga'],
    'Hyundai': ['Xcient', 'HD'],
    'Shacman': ['X3000', 'F3000'],
    'Howo': ['T7H', 'A7', 'TX'],
    'FAW': ['J6P', 'J7'],
  },
  MarketCategory.trailer: {
    'Schmitz Cargobull': ['S.KO', 'S.CS', 'Z.KO'],
    'Krone': ['Profi Liner', 'Cool Liner', 'Box Liner'],
    'Kögel': ['Cargo', 'Mega'],
    'Wielton': ['Curtainsider', 'Tipper'],
    'Tırsan': ['Kässbohrer', 'Tenteli', 'Frigo'],
  },
  MarketCategory.semitrailer: {
    'Schmitz Cargobull': ['S.CS Mega', 'S.KO Cool', 'S.KI'],
    'Krone': ['SD Profi Liner', 'SD Cool Liner', 'SD Mega Liner'],
    'Kögel': ['Cargo', 'Mega', 'Port'],
    'Wielton': ['NS', 'NW', 'NK'],
    'Tırsan': ['Tenteli', 'Frigo', 'Lowbed'],
    'Kässbohrer': ['Lowbed', 'Tanker', 'Container'],
    'Chereau': ['Inogam', 'Frigo'],
    'Lamberet': ['SR2', 'Frigo'],
    'Fliegl': ['SDS', 'Lowbed'],
  },
  MarketCategory.construction: {
    'Caterpillar': ['320', '330', '336', '950', '966', 'D6', 'D8'],
    'Komatsu': ['PC200', 'PC300', 'WA380', 'D65'],
    'JCB': ['3CX', '4CX', 'JS220', '540-170'],
    'Hitachi': ['ZX200', 'ZX350'],
    'Volvo CE': ['EC220', 'EC380', 'L120', 'A30G'],
    'Liebherr': ['R 924', 'R 936', 'L 566', 'LTM'],
    'Hyundai CE': ['R220', 'HX300', 'HL960'],
    'Doosan': ['DX225', 'DX300', 'DL420'],
    'XCMG': ['XE215', 'ZL50', 'QY25'],
  },
  MarketCategory.other: {},
};

void main() {
  group('catalogue', () {
    test('every brand and model of the first catalogue is kept, same spelling', () {
      kOldCatalog.forEach((cat, brands) {
        brands.forEach((brand, models) {
          expect(marketBrands(cat), contains(brand), reason: '$cat $brand');
          for (final m in models) {
            expect(marketModels(cat, brand), contains(m), reason: '$cat $brand $m');
          }
        });
      });
    });

    test('about 120 brands; no brand twice in a category; no model twice for a brand', () {
      final all = {for (final c in kMarketCatalog.values) ...c.keys};
      expect(all.length, inInclusiveRange(115, 160));
      kMarketCatalog.forEach((cat, brands) {
        final keys = brands.keys.map(marketNameKey).toList();
        expect(keys.toSet().length, keys.length, reason: '$cat');
        brands.forEach((b, models) {
          final mk = models.map(marketNameKey).toList();
          expect(mk.toSet().length, mk.length, reason: '$cat $b');
        });
      });
      for (final c in [MarketCategory.mediumTruck, MarketCategory.lightTruck]) {
        expect(marketBrands(c).length, greaterThanOrEqualTo(15), reason: '$c');
      }
      expect(marketModels(MarketCategory.lightTruck, 'GAZ'), contains('GAZelle Next'));
    });

    test('aliases point to a catalogue brand and never to two brands', () {
      final all = {for (final c in kMarketCatalog.values) ...c.keys};
      final seen = <String, String>{};
      kMarketBrandAliases.forEach((brand, aliases) {
        expect(all, contains(brand), reason: brand);
        for (final a in aliases) {
          final k = marketNameKey(a);
          expect(all.map(marketNameKey), isNot(contains(k)), reason: 'alias $a is itself a brand');
          expect(seen[k], anyOf(isNull, brand), reason: 'alias $a twice');
          seen[k] = brand;
        }
      });
      kMarketModelAliases.forEach((brand, models) {
        expect(all, contains(brand));
        models.forEach((m, _) {
          final has = kMarketCatalog.values.any((c) => (c[brand] ?? const []).contains(m));
          expect(has, isTrue, reason: '$brand $m');
        });
      });
    });

    test('other spellings find the catalogue name; unknown ones stay as typed', () {
      expect(canonicalMarketBrand('mercedes'), 'Mercedes-Benz');
      expect(canonicalMarketBrand('Mercedes Benz'), 'Mercedes-Benz'); // by the key, no alias needed
      expect(canonicalMarketBrand('Мерседес'), 'Mercedes-Benz');
      expect(canonicalMarketBrand('КАМАЗ'), 'KAMAZ');
      expect(canonicalMarketBrand('Qazel'), 'GAZ');
      expect(canonicalMarketBrand('sinotruk howo'), 'Howo');
      expect(canonicalMarketBrand('Develon'), 'Doosan');
      expect(canonicalMarketBrand('Tirsan'), 'Tırsan');
      expect(canonicalMarketBrand('  Brand X '), 'Brand X');
      expect(canonicalMarketModel('Volvo', 'FH-16'), 'FH16');
      expect(canonicalMarketModel('MAN', 'TGX18.480'), 'TGX 18.480');
      expect(canonicalMarketModel('ГАЗ', 'Газель Next'), 'GAZelle Next');
      expect(canonicalMarketModel('Volvo', 'Unknown 1'), 'Unknown 1');
      expect(marketBrandSpellings('Mercedes-Benz'), containsAll(['Mercedes-Benz', 'Mercedes', 'MB']));
      expect(marketModelSpellings('GAZ', 'GAZelle Next'), containsAll(['GAZelle Next', 'Газель Next']));
    });

    test('counts on the "Marka" page join the spellings (stored ads unchanged)', () {
      final rows = [
        {'brand': 'Mercedes-Benz', 'model': 'Actros'},
        {'brand': 'Mercedes', 'model': 'actros'},
        {'brand': 'Мерседес', 'model': 'Aktros'},
        {'brand': 'Volvo', 'model': 'FH-16'},
        {'brand': 'Volvo', 'model': 'FH16'},
      ];
      final i = MarketBrandIndex.fromRows(rows);
      expect(i.countOf('Mercedes-Benz'), 3);
      expect(i.countOf('mercedes'), 3);
      expect(i.models('Mercedes-Benz', marketModels(MarketCategory.truck, 'Mercedes-Benz'))
          .firstWhere((m) => m.name == 'Actros').count, 3);
      expect(i.models('Volvo', const []).single.count, 2);
      expect(rows[1]['brand'], 'Mercedes');
    });
  });

  group('category and body type are separate', () {
    test('two new categories after TIR; the five stored names unchanged', () {
      expect(MarketCategory.values.map((c) => c.wire),
          ['truck', 'medium_truck', 'light_truck', 'trailer', 'semitrailer', 'construction', 'other']);
      for (final c in MarketCategory.values) {
        expect(MarketCategoryX.parse(c.wire), c);
      }
      expect(MarketCategoryX.parse('nope'), MarketCategory.truck);
    });

    test('body type: optional, only known codes, kept apart from the model', () {
      final l = MarketListing.fromJson({'id': 'x', 'listing_no': 1, 'owner_id': 'o', 'status': 'active',
        'category': 'light_truck', 'brand': 'GAZ', 'model': 'GAZelle Next', 'body_type': 'tow_truck', 'created_at': '2026-10-25T10:00:00Z'});
      expect((l.category, l.model, l.bodyType), (MarketCategory.lightTruck, 'GAZelle Next', 'tow_truck'));
      expect(MarketListing.fromJson({'id': 'x', 'listing_no': 1, 'owner_id': 'o', 'status': 'active', 'category': 'truck',
        'body_type': 'rocket', 'created_at': '2026-10-25T10:00:00Z'}).bodyType, isNull);
      expect(MarketListing.fromJson({'id': 'x', 'listing_no': 1, 'owner_id': 'o', 'status': 'active', 'category': 'truck',
        'created_at': '2026-10-25T10:00:00Z'}).bodyType, isNull);
      final d = MarketDraft.from(l);
      expect(d.toJson()['body_type'], 'tow_truck');
      expect(d.missingForPublish(), isNot(contains('mk_err_body')));
      expect((MarketDraft()..bodyType = null).toJson()['body_type'], isNull);
    });

    test('search sends the 0064 parameters only when used (works before 0064)', () {
      final plain = const MarketFilter(category: MarketCategory.truck).toParams();
      expect(plain.keys, isNot(anyElement(isIn(['p_body_type', 'p_brands', 'p_models']))));
      final p = const MarketFilter(brand: 'Mercedes-Benz', model: 'Actros', bodyType: 'manipulator').toParams();
      expect(p['p_brand'], 'Mercedes-Benz');
      expect(p['p_brands'], containsAll(['Mercedes', 'MB']));
      expect(p['p_models'], contains('Aktros'));
      expect(p['p_body_type'], 'manipulator');
      expect(const MarketFilter(bodyType: 'x').toParams().containsKey('p_body_type'), isFalse);
      final repo = File('lib/features/market/data/market_repository.dart').readAsStringSync();
      expect(repo.contains("e.code == 'PGRST202'"), isTrue);
      expect(repo.contains("['location_exact', 'body_type']"), isTrue);
    });

    test('six languages: the two categories and every body type', () {
      for (final lang in ['az', 'tr', 'en', 'ru', 'ka', 'zh']) {
        final j = File('assets/i18n/$lang.json').readAsStringSync();
        for (final k in ['mk_cat_medium_truck', 'mk_cat_light_truck', 'mk_body_type', 'mk_body_type_optional',
          for (final b in kMarketBodyTypes) 'mk_body_$b']) {
          expect(j.contains('"$k"'), isTrue, reason: '$lang $k');
        }
      }
    });

    test('form: body type chips, not required; filter and detail show it', () {
      final form = File('lib/features/market/presentation/market_edit_screen.dart').readAsStringSync();
      expect(form.contains("ValueKey('mk-body-\$b')"), isTrue);
      expect(form.contains("s.t('mk_body_type_optional')"), isTrue);
      expect(File('lib/features/market/presentation/market_home_screen.dart').readAsStringSync().contains("ValueKey('mk-filter-body')"), isTrue);
      expect(File('lib/features/market/presentation/market_detail_screen.dart').readAsStringSync().contains('if (l.bodyType != null)'), isTrue);
    });
  });

  group('logos', () {
    test('only packaged, listed logos; otherwise the letters stay', () {
      kMarketBrandLogos.forEach((brand, file) {
        expect({for (final c in kMarketCatalog.values) ...c.keys}, contains(brand));
        expect(File('assets/images/brands/$file').existsSync(), isTrue, reason: file);
        expect(File('docs/brand_logos.md').readAsStringSync().contains(file), isTrue, reason: 'source of $file');
      });
      expect(marketBrandLogoAsset('Brand without logo'), isNull);
      // Mərhələ 3: 48 logos, 128 x 128 with transparency, each with its source.
      expect(kMarketBrandLogos.length, 48);
      for (final b in ['Mercedes-Benz', 'Volvo', 'KAMAZ', 'GAZ', 'Scania', 'DAF', 'MAN', 'Krone', 'Kögel', 'Schmitz Cargobull']) {
        expect(kMarketBrandLogos.containsKey(b), isTrue, reason: b);
      }
      // Not found in a checked source: letters stay (no drawn or guessed logo).
      for (final b in ['Howo', 'Ford Trucks', 'Wielton', 'Komatsu']) {
        expect(marketBrandLogoAsset(b), isNull, reason: b);
      }
      for (final file in kMarketBrandLogos.values) {
        final b = File('assets/images/brands/$file').readAsBytesSync();
        final w = (b[16] << 24) | (b[17] << 16) | (b[18] << 8) | b[19];
        final h = (b[20] << 24) | (b[21] << 16) | (b[22] << 8) | b[23];
        expect((w, h), (128, 128), reason: file);
        final png = String.fromCharCodes(b.take(1200));
        expect(b[25] == 6 || png.contains('tRNS'), isTrue, reason: '$file transparent');
      }
      expect(marketBrandLogoAsset('mercedes'), 'assets/images/brands/mercedes_benz.png');
      expect(marketBrandLogoAsset('Renault Trucks'), 'assets/images/brands/renault.png');
      expect(File('pubspec.yaml').readAsStringSync(), contains('- assets/images/brands/'));
      expect(File('lib/features/market/presentation/market_home_desktop.dart').readAsStringSync(),
          contains('BrandBadge(b, size: 24)'));
      expect(brandInitials('Mercedes-Benz'), 'MB');
      final picker = File('lib/features/market/presentation/market_brand_picker.dart').readAsStringSync();
      expect(picker.contains('marketBrandLogoAsset(brand)'), isTrue);
      expect(picker.contains('errorBuilder'), isTrue);
    });
  });

  test('0064 is safe and in the SQL suite', () {
    final sql = File('supabase/migrations/0064_market_catalog_body_type.sql').readAsStringSync().toLowerCase();
    for (final bad in ['drop table', 'truncate', 'delete from', 'update public', 'drop column', 'drop policy']) {
      expect(sql.contains(bad), isFalse, reason: bad);
    }
    expect(RegExp(r'drop constraint (\w+)').allMatches(sql).map((m) => m.group(1)).toSet(), {'market_listings_category_check'});
    expect(RegExp(r'drop function if exists public\.(\w+)').allMatches(sql).map((m) => m.group(1)).toSet(), {'market_search'});
    // One transaction with a final check: all or nothing.
    expect(sql.contains('\nbegin;\n'), isTrue);
    expect(sql.trimRight().endsWith('commit;'), isTrue);
    expect(sql.contains('0064: final check failed'), isTrue);
    final run = File('supabase/tests/local/run_local.sh').readAsStringSync();
    expect(run, contains('0064_market_catalog_body_type.sql'));
    expect(run, contains('101_market_catalog.sql'));
  });
}
