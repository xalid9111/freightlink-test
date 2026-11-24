import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freightlink/core/theme/app_theme.dart';
import 'package:freightlink/core/theme/theme_mode.dart';
import 'package:freightlink/core/widgets/neu_surface.dart';

/// "Neumorf" look (owner, 24.11.2026, SQL 0137): switched on / off by the
/// admin, night and day; off = the app exactly as before.
void main() {
  tearDown(() => AppColors.use(AppPalette.dark));

  test('off = the classic palettes, unchanged', () {
    expect(paletteFor(kThemeNight), same(AppPalette.dark));
    expect(paletteFor(kThemeDay), same(AppPalette.light));
    expect(AppPalette.dark.neumorph, isFalse);
    expect(AppPalette.light.neumorph, isFalse);
  });

  test('on = neumorf at night and by day; it goes before an admin night palette', () {
    expect(paletteFor(kThemeNight, neumorph: true), same(AppPalette.neuDark));
    expect(paletteFor(kThemeDay, neumorph: true), same(AppPalette.neuLight));
    expect(AppPalette.neuDark.isDay, isFalse);
    expect(AppPalette.neuLight.isDay, isTrue);
  });

  test('the classic theme has no neumorf shadows; neumorf has two', () {
    AppColors.use(AppPalette.dark);
    expect(AppColors.neuRaised(), isEmpty);
    final classic = AppTheme.current;
    expect(classic.cardTheme.elevation, 0);
    AppColors.use(AppPalette.neuDark);
    expect(AppColors.neuRaised().length, 2);
    final neu = AppTheme.current;
    expect(neu.cardTheme.elevation, greaterThan(0));
    expect(neu.scaffoldBackgroundColor, const Color(0xFF2A2D31));
    AppColors.use(AppPalette.neuLight);
    expect(AppTheme.current.scaffoldBackgroundColor, const Color(0xFFE8EBF0));
  });

  testWidgets('NeuSurface adds nothing when off', (t) async {
    AppColors.use(AppPalette.dark);
    await t.pumpWidget(const Directionality(textDirection: TextDirection.ltr, child: NeuSurface(child: SizedBox(width: 10, height: 10))));
    expect(find.byKey(const ValueKey('neu-surface')), findsNothing);
    AppColors.use(AppPalette.neuDark);
    await t.pumpWidget(const Directionality(textDirection: TextDirection.ltr, child: NeuSurface(child: SizedBox(width: 11, height: 10))));
    expect(find.byKey(const ValueKey('neu-surface')), findsOneWidget);
  });

  test('wired: admin switch, server, nav, start-up', () {
    final admin = File('lib/features/admin/presentation/admin_design_page.dart').readAsStringSync();
    expect(admin, contains("ValueKey('design-neumorph')"));
    expect(admin, contains('setNeumorphForAll('));
    final sql = File('supabase/migrations/0137_ui_style_neumorph.sql').readAsStringSync();
    expect(sql, contains('perform public._require_admin();'));
    expect(sql, contains('grant execute on function public.ui_style_current() to anon, authenticated;'));
    expect(sql.contains('drop table'), isFalse);
    final nav = File('lib/core/router/floating_nav.dart').readAsStringSync();
    expect(nav, contains("ValueKey('nav-neu-selected')"));
    final mode = File('lib/core/theme/theme_mode.dart').readAsStringSync();
    expect(mode, contains('kNeumorphCheckedKey'), reason: 'later starts never wait for it');
  });

  test('stage 2 (approved picture B): every screen piece has its neumorf form, the classic one kept', () {
    String src(String p) => File(p).readAsStringSync();
    final loads = src('lib/features/cargo/presentation/cargo_marketplace_screen.dart');
    expect(loads, contains('(AppColors.neumorph ? _NeuHero.new : _Hero.new)('));
    expect(loads, contains("ValueKey('neu-map-frame')"), reason: 'the live map kept (B)');
    expect(loads, contains("ValueKey('route-search-neu')"));
    expect(loads, contains("key: ValueKey(isFrom ? 'route-from' : 'route-to')"));
    expect(src('lib/features/empty_trucks/presentation/empty_truck_widgets.dart'), contains("ValueKey('loads-section-neu')"));
    expect(src('lib/features/cargo/presentation/widgets/cargo_category_bar.dart'), contains("ValueKey('cat-neu-\$code')"));
    expect(src('lib/features/cargo/presentation/widgets/cargo_picture.dart'), contains("ValueKey('header-circle-neu')"));
    final market = src('lib/features/market/presentation/market_home_screen.dart');
    expect(market, contains('NeuInsetFrame('), reason: 'the banner kept (B)');
    expect(market, contains("ValueKey('mk-search-neu')"));
    expect(src('lib/features/market/presentation/market_card.dart'), contains("ValueKey('mk-feed-neu')"));
    expect(src('lib/features/tirpark/presentation/map_page_header.dart'), contains('neuInsetDecoration(radius: 20)'));
  });

  testWidgets('the top of the page blends into the iPhone\'s black bar only in Neumorf at night', (t) async {
    Future<bool> shown(AppPalette p) async {
      AppColors.use(p);
      await t.pumpWidget(MediaQuery(
          data: const MediaQueryData(size: Size(390, 844)),
          child: Directionality(textDirection: TextDirection.ltr, child: NeuTopBlend(key: UniqueKey(), child: const SizedBox.expand()))));
      return find.byKey(const ValueKey('neu-top-blend')).evaluate().isNotEmpty;
    }

    expect(await shown(AppPalette.dark), isFalse, reason: 'classic: nothing added');
    expect(await shown(AppPalette.neuLight), isFalse, reason: 'day: the light bar');
    expect(await shown(AppPalette.neuDark), isTrue);
    final index = File('web/index.html').readAsStringSync();
    expect(index, contains('html.neu, html.neu body, html.neu #app-loading { background: #2A2D31; }'));
    expect(index, contains("localStorage.getItem('flutter.ui_neumorph_preview')"));
    expect(index, contains('<meta name="apple-mobile-web-app-status-bar-style" content="black">'),
        reason: 'the solid bar stays (a see-through one moved every tap, 24.10.2026)');
  });
}
