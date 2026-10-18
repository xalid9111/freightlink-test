import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:freightlink/features/market/domain/market_catalog.dart';
import 'package:freightlink/features/market/domain/market_models.dart';

String _read(String p) => File(p).readAsStringSync();

void main() {
  group('MarketListing', () {
    test('fromJson reads numbers given as strings, title and cover', () {
      final l = MarketListing.fromJson({
        'id': 'a1',
        'listing_no': 10001,
        'owner_id': 'u1',
        'status': 'active',
        'category': 'semitrailer',
        'brand': 'Schmitz',
        'model': 'S.KO',
        'year': '2019',
        'price': '32500.00',
        'currency': 'EUR',
        'photos': ['p1.jpg', 'p2.jpg'],
        'created_at': '2026-10-01T10:00:00Z',
      });
      expect(l.category, MarketCategory.semitrailer);
      expect(l.status, MarketStatus.active);
      expect(l.year, 2019);
      expect(l.price, 32500);
      expect(l.title, 'Schmitz S.KO — 2019');
      expect(l.cover, 'p1.jpg');
    });
    test('unknown status / category fall back safely', () {
      final l = MarketListing.fromJson({'id': 'x', 'owner_id': 'u', 'status': '??', 'category': null});
      expect(l.status, MarketStatus.draft);
      expect(l.category, MarketCategory.truck);
      expect(l.cover, isNull);
      expect(l.currency, 'USD');
    });
    test('VIP badge only while active and not expired', () {
      final now = DateTime(2026, 10, 18);
      MarketListing vip(bool on, DateTime? until) => MarketListing.fromJson({
            'id': 'v',
            'owner_id': 'u',
            'is_vip': on,
            'vip_until': until?.toIso8601String(),
          });
      expect(vip(true, null).vipActive(now), isTrue);
      expect(vip(true, now.add(const Duration(days: 3))).vipActive(now), isTrue);
      expect(vip(true, now.subtract(const Duration(days: 1))).vipActive(now), isFalse);
      expect(vip(false, null).vipActive(now), isFalse);
    });
  });

  group('MarketDraft', () {
    test('a draft can be empty, publishing needs the 6 main fields', () {
      final d = MarketDraft();
      expect(d.missingForPublish(), ['mk_err_brand', 'mk_err_model', 'mk_err_year', 'mk_err_price', 'mk_err_city', 'mk_err_photos']);
      d
        ..brand = 'DAF'
        ..model = 'XF'
        ..year = 2017
        ..price = 0
        ..city = 'Bakı'
        ..photos = ['a.jpg'];
      expect(d.missingForPublish(), ['mk_err_price']);
      d.price = 67000;
      expect(d.missingForPublish(), isEmpty);
    });
    test('toJson trims text and never sends server-only fields', () {
      final j = (MarketDraft(brand: '  Volvo ', description: '   ')).toJson();
      expect(j['brand'], 'Volvo');
      expect(j['description'], isNull);
      for (final k in ['status', 'is_vip', 'vip_until', 'views', 'owner_id', 'listing_no', 'admin_note']) {
        expect(j.containsKey(k), isFalse, reason: k);
      }
    });
  });

  group('MarketFilter', () {
    test('toParams: empty text is null, paging passed', () {
      const f = MarketFilter(category: MarketCategory.trailer, q: '  ', brand: 'Krone');
      final p = f.toParams(limit: 20, offset: 40);
      expect(p['p_category'], 'trailer');
      expect(p['p_q'], isNull);
      expect(p['p_brand'], 'Krone');
      expect(p['p_limit'], 20);
      expect(p['p_offset'], 40);
    });
    test('equality drives the feed reload', () {
      expect(const MarketFilter(brand: 'DAF') == const MarketFilter(brand: 'DAF'), isTrue);
      expect(const MarketFilter(brand: 'DAF') == const MarketFilter(brand: 'MAN'), isFalse);
      expect(const MarketFilter().hasDetails, isFalse);
      expect(const MarketFilter(maxMileage: 500000).hasDetails, isTrue);
    });
  });

  group('helpers', () {
    test('price and km formatting', () {
      expect(marketPrice(32500, 'EUR'), '32 500 €');
      expect(marketPrice(67000, 'USD'), r'$67 000');
      expect(marketPrice(1500, 'XYZ'), '1 500 XYZ');
      expect(marketPrice(null, 'USD'), '—');
      expect(marketKm(420000), '420 000 km');
      expect(marketKm(null), '—');
    });
    test('photo reorder keeps every photo', () {
      expect(movePhoto(['a', 'b', 'c'], 2, 0), ['c', 'a', 'b']);
      expect(movePhoto(['a', 'b', 'c'], 0, 2), ['b', 'c', 'a']);
      expect(movePhoto(['a', 'b'], 5, 0), ['a', 'b']);
      expect(kMarketMaxPhotos, 20);
    });
    test('time ago', () {
      final now = DateTime(2026, 10, 18, 12);
      expect(marketAgo(now.subtract(const Duration(seconds: 5)), now), ('mk_ago_min', 1));
      expect(marketAgo(now.subtract(const Duration(hours: 3)), now), ('mk_ago_hours', 3));
      expect(marketAgo(now.subtract(const Duration(days: 4)), now), ('mk_ago_days', 4));
      expect(marketAgo(now.subtract(const Duration(days: 400)), now), ('mk_ago_years', 1));
    });
    test('years list and offer message', () {
      final ys = marketYears(DateTime(2026));
      expect(ys.first, 2027);
      expect(ys.last, 1980);
      expect(
        marketOfferMessage(label: 'Qiymət təklifi', title: 'DAF XF — 2017', listingNo: 10001, amount: r'$60 000', note: ' son qiymət '),
        'Qiymət təklifi: DAF XF — 2017 (#10001) — \$60 000\nson qiymət',
      );
    });
    test('catalog: every category but "Digər" has brands, models are per brand', () {
      for (final c in MarketCategory.values.where((c) => c != MarketCategory.other)) {
        expect(marketBrands(c), isNotEmpty, reason: c.name);
      }
      final b = marketBrands(MarketCategory.truck).first;
      expect(marketModels(MarketCategory.truck, b), isNotEmpty);
      expect(marketModels(MarketCategory.truck, 'nope'), isEmpty);
    });
  });

  group('guards', () {
    test('dynamic texts exist in all 6 languages', () {
      final keys = [
        for (final c in MarketCategory.values) c.labelKey,
        for (final s in MarketStatus.values) 'mk_state_${s.name}',
        for (final s in MarketStatus.values) 'mk_status_${s.name}',
        for (final g in kMarketGearboxes) 'mk_gear_$g',
        for (final f in kMarketFuels) 'mk_fuel_$f',
        'mk_ago_min', 'mk_ago_hours', 'mk_ago_days', 'mk_ago_months', 'mk_ago_years',
        'mk_err_brand', 'mk_err_model', 'mk_err_year', 'mk_err_price', 'mk_err_city', 'mk_err_photos',
      ];
      for (final lang in ['az', 'tr', 'en', 'ru', 'ka', 'zh']) {
        final m = jsonDecode(_read('assets/i18n/$lang.json')) as Map<String, dynamic>;
        for (final k in keys) {
          expect((m[k] as String?)?.isNotEmpty, isTrue, reason: '$lang:$k');
        }
      }
    });
    test('TIR Bazarı pages are routed through the deferred module', () {
      final r = _read('lib/core/router/app_router.dart');
      for (final p in ["'/market/new'", "'/market/edit/:id'", "'/market/l/:id'", "'/market/mine'", "'/market/favorites'"]) {
        expect(r.contains(p), isTrue, reason: p);
      }
      expect(r.contains("market_home_screen.dart'"), isFalse);
    });
    test('admin panel has the sale ads section (deferred)', () {
      final a = _read('lib/features/admin/presentation/admin_shell.dart');
      expect(a.contains("AdminSection('market'"), isTrue);
      expect(a.contains('market.AdminMarketPage()'), isTrue);
    });
    test('sale ads go to admin approval; owner cannot set VIP / status', () {
      final sql = _read('supabase/migrations/0040_market.sql');
      expect(sql.contains('market_listing_guard'), isTrue);
      expect(sql.contains("'pending'"), isTrue);
      expect(sql.contains('enable row level security'), isTrue);
      expect(RegExp(r'\b(drop table|truncate)\b', caseSensitive: false).hasMatch(sql), isFalse);
    });
  });
}
