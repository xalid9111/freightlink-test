// Servislər and Mağazalar each have their own map banner (owner,
// 08.11.2026, 0108): picture, texts and the pencil of the chosen section;
// TIRPark's banner unchanged.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freightlink/core/localization/app_strings.dart';
import 'package:freightlink/core/widgets/page_hero.dart';
import 'package:freightlink/features/auth/domain/app_user.dart';
import 'package:freightlink/features/auth/presentation/providers/auth_providers.dart';
import 'package:freightlink/features/tirpark/presentation/map_page_banner.dart';

String src(String p) => File(p).readAsStringSync();
final _az = AppStrings(Map<String, String>.from(jsonDecode(src('assets/i18n/az.json')) as Map));

class _Repo implements PageHeroRepository {
  final asked = <String>[];
  @override
  Future<PageHero?> fetch(String page) async {
    asked.add(page);
    return null;
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

Widget _banner(String page, {String? asset}) => MapPageBanner(
      s: _az,
      page: page,
      brandIcon: Icons.storefront,
      editIcon: Icons.storefront,
      brandAccent: '',
      brandRest: page,
      defaultTitle: 'T-$page',
      defaultAccent: 'A-$page',
      defaultSubtitle: 'S-$page',
      asset: asset,
    );

void main() {
  testWidgets('each section asks for its own banner and has its own pencil', (tester) async {
    final repo = _Repo();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        pageHeroRepositoryProvider.overrideWithValue(repo),
        currentUserIdProvider.overrideWithValue('a1'),
        currentUserProvider.overrideWithValue(const AppUser(id: 'a1', email: 'a@x.az', fullName: 'Admin', role: 'admin', isVerified: false)),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: Column(children: [
            _banner('services'),
            _banner('shops', asset: 'assets/images/profile/cover_shop.jpg'),
          ]),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(repo.asked.toSet(), {'services', 'shops'});
    expect(find.byKey(const ValueKey('page-hero-edit-services')), findsOneWidget);
    expect(find.byKey(const ValueKey('page-hero-edit-shops')), findsOneWidget);
    expect(find.text('T-shops'), findsOneWidget);
    expect(find.text('T-services'), findsOneWidget);
    // Mağazalar shows its own start picture until the admin sets one.
    expect(find.byWidgetPredicate((w) => w is Image && w.image is AssetImage && (w.image as AssetImage).assetName.endsWith('cover_shop.jpg')),
        findsOneWidget);
  });

  test('the shops banner has its own table; it stays in memory like the other map banners', () {
    expect(kPageHeroTables['shops'], 'shops_hero');
    expect(kPageHeroTables['services'], 'services_hero', reason: 'Servislər keeps its banner');
    expect(kPageHeroTables['tirpark'], 'tirpark_hero');
    expect(kMapBannerPages, containsAll(['tirpark', 'services', 'shops']));
  });

  test('wired: Mağazalar (phone and computer) uses the shops banner; Servislər and TIRPark unchanged', () {
    final s = src('lib/features/services/presentation/services_map_screen.dart');
    expect(RegExp("page: 'shops',").allMatches(s).length, 2, reason: 'phone + computer');
    expect(RegExp("page: 'services',").allMatches(s).length, 2);
    expect(s, contains("asset: 'assets/images/profile/cover_shop.jpg',"));
    expect(src('lib/features/tirpark/presentation/tir_park_screen.dart'), contains("page: 'tirpark',"));
    for (final l in ['az', 'tr', 'en', 'ru', 'ka', 'zh']) {
      final j = jsonDecode(src('assets/i18n/$l.json')) as Map;
      for (final k in ['shop_hero_title', 'shop_hero_accent', 'shop_hero_subtitle']) {
        expect(j.containsKey(k), isTrue, reason: '$l $k');
      }
    }
  });

  test('SQL 0108: new table, functions take shops, nothing deleted', () {
    final sql = src('supabase/migrations/0108_shops_banner.sql');
    expect(sql, contains('create table if not exists public.shops_hero ('));
    expect(RegExp("elsif p_page = 'shops' then").allMatches(sql).length, 3);
    expect(RegExp("elsif p_page = 'tirpark' then").allMatches(sql).length, 3, reason: 'TIRPark part kept');
    expect(sql, contains('perform public._require_admin();'));
    final lower = sql.toLowerCase();
    expect(lower.contains('drop table') || lower.contains('truncate') || lower.contains('delete from'), isFalse);
    expect(src('supabase/tests/local/run_local.sh'), contains('145_shops_banner.sql'));
  });
}
