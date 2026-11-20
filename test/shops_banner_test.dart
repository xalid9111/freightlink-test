// The map pages (Parklar · Servislər · Mağazalar) lost their banners (owner,
// 20.11.2026: "tam çıxsın") — the "Xəritə" header stands there instead. The
// banner tables stay in the database (nothing deleted); the TIR Bazarı
// banner is unchanged.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:freightlink/core/widgets/page_hero.dart';

String src(String p) => File(p).readAsStringSync();

void main() {
  test('no banner on the map pages, phone or computer; the header instead', () {
    final svc = src('lib/features/services/presentation/services_map_screen.dart');
    final tp = src('lib/features/tirpark/presentation/tir_park_screen.dart');
    for (final page in [svc, tp]) {
      expect(page.contains('PageHeroBanner('), isFalse);
      expect(page.contains('MapPageBanner('), isFalse);
      expect(page, contains('MapPageHeader(s: s)'));
    }
    expect(File('lib/features/tirpark/presentation/map_page_banner.dart').existsSync(), isFalse);
    expect(src('lib/features/market/presentation/market_home_screen.dart'), contains("page: 'market',"), reason: 'TIR Bazarı keeps its banner');
  });

  test('the banner tables are kept (nothing deleted); the start-up asks for none of them', () {
    expect(kPageHeroTables['shops'], 'shops_hero');
    expect(kPageHeroTables['services'], 'services_hero');
    expect(kPageHeroTables['tirpark'], 'tirpark_hero');
    expect(PageHeroPrefetch.pageOf(Uri.parse('https://a/#/tirpark')), isNull);
  });

  test('SQL 0108 stays as it was: its table, nothing deleted', () {
    final sql = src('supabase/migrations/0108_shops_banner.sql');
    expect(sql, contains('create table if not exists public.shops_hero ('));
    final lower = sql.toLowerCase();
    expect(lower.contains('drop table') || lower.contains('truncate') || lower.contains('delete from'), isFalse);
  });
}
