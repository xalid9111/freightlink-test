// Page banners (0049): TIR Bazarı and Services, a night and a day picture,
// admins change them. Server rules: supabase/tests/local/87_page_banners.sql.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freightlink/core/widgets/page_hero.dart';

void main() {
  group('night / day picture', () {
    test('each theme its own picture', () {
      const h = PageHero(imageUrl: 'n.jpg', imageUrlDay: 'd.jpg');
      expect(h.imageFor(day: false), 'n.jpg');
      expect(h.imageFor(day: true), 'd.jpg');
    });
    test('one missing → the other one; none → the ground', () {
      expect(const PageHero(imageUrl: 'n.jpg').imageFor(day: true), 'n.jpg');
      expect(const PageHero(imageUrlDay: 'd.jpg').imageFor(day: false), 'd.jpg');
      expect(const PageHero().imageFor(day: true), isNull);
    });
    test('the current TIR Bazarı picture stays the night one', () {
      final h = PageHero.fromJson({'image_url': 'old.jpg', 'title': ' A ', 'subtitle': ''});
      expect([h.imageUrl, h.imageUrlDay, h.title, h.subtitle], ['old.jpg', null, 'A', null]);
    });
  });

  group('picture with its own writing (0050)', () {
    test('texts on by default and on old rows', () {
      expect(PageHero.fromJson({'image_url': 'n.jpg'}).showText, isTrue);
      expect(PageHero.fromJson({'image_url': 'n.jpg', 'show_text': false}).showText, isFalse);
    });
    test('off → no texts and no shade on the picture; switch in the editor', () {
      final f = File('lib/core/widgets/page_hero.dart').readAsStringSync();
      expect(f.contains('final texts = !onPhoto || (hero?.showText ?? true);'), isTrue);
      expect(f.contains('if (onPhoto && texts)'), isTrue);
      expect(f.contains("key: const ValueKey('page-hero-show-text'),"), isTrue);
      final d = File('lib/features/market/presentation/market_home_desktop.dart').readAsStringSync();
      expect(d.contains('final texts = !onPhoto || (hero?.showText ?? true);'), isTrue);
      final sql = File('supabase/migrations/0050_page_banner_text_toggle.sql').readAsStringSync();
      expect(RegExp(r'admin_set_page_hero[\s\S]*?perform public\._require_admin\(\);').hasMatch(sql), isTrue);
    });
  });

  group('part of the picture in front (0051)', () {
    test('middle by default; each picture its own point; follows the picture shown', () {
      expect(const PageHero(imageUrl: 'n').alignmentFor(day: false), Alignment.center);
      final h = PageHero.fromJson({'image_url': 'n', 'image_url_day': 'd', 'focus_x': 0.5, 'focus_y': -1, 'focus_day_x': -0.3, 'focus_day_y': 0.2});
      expect(h.alignmentFor(day: false), const Alignment(0.5, -1));
      expect(h.alignmentFor(day: true), const Alignment(-0.3, 0.2));
      // No day picture: the night picture is shown with its own point.
      final n = PageHero.fromJson({'image_url': 'n', 'focus_x': 1, 'focus_day_x': -1});
      expect(n.alignmentFor(day: true), const Alignment(1, 0));
    });
    test('out of range is clamped', () {
      expect(PageHero.fromJson({'image_url': 'n', 'focus_x': 4}).focusX, 1);
    });
    test('banner, computer TIR Bazarı and editor use the point', () {
      final f = File('lib/core/widgets/page_hero.dart').readAsStringSync();
      expect(f.contains('align: hero!.alignmentFor(day: AppColors.isDay),'), isTrue);
      expect(f.contains('onScaleUpdate:'), isTrue);
      expect(File('lib/features/market/presentation/market_home_desktop.dart').readAsStringSync()
          .contains('align: hero!.alignmentFor(day: AppColors.isDay),'), isTrue);
    });
  });

  group('zoom (0052)', () {
    test('1 by default and on old rows, limited to 1..3, follows the picture shown', () {
      expect(const PageHero(imageUrl: 'n').zoomFor(day: true), 1);
      final h = PageHero.fromJson({'image_url': 'n', 'image_url_day': 'd', 'zoom': 2, 'zoom_day': 9});
      expect([h.zoomFor(day: false), h.zoomFor(day: true)], [2, 3]);
      expect(PageHero.fromJson({'image_url': 'n', 'zoom': 1.5, 'zoom_day': 3}).zoomFor(day: true), 1.5);
    });
    test('editor: slider and two-finger zoom', () {
      final f = File('lib/core/widgets/page_hero.dart').readAsStringSync();
      expect(f.contains("key: ValueKey('page-hero-zoom-\${day ? 'day' : 'night'}'),"), isTrue);
      expect(f.contains('if (d.pointerCount > 1) _setZoom(day, _zoomStart * d.scale);'), isTrue);
    });
  });

  test('TIR Bazarı part: a stale cached app reloads itself fresh once (no data touched)', () {
    expect(File('lib/core/widgets/deferred_page.dart').readAsStringSync().contains('if (platform.freshReload())'), isTrue);
    final js = File('web/pwa_guard.js').readAsStringSync();
    expect(js.contains('window.flFreshReload = function () {'), isTrue);
    expect(js.contains("{ cache: 'reload' }"), isTrue);
    expect(js.contains('localStorage.'), isFalse);
  });

  group('guards', () {
    String read(String p) => File(p).readAsStringSync();
    test('banners on the phone TIR Bazarı page and on Services (phone + computer)', () {
      expect(read('lib/features/market/presentation/market_home_screen.dart').contains("page: 'market',"), isTrue);
      expect(read('lib/features/services/presentation/services_map_screen.dart').contains("page: 'services',"), isTrue);
      expect(read('lib/features/market/presentation/market_home_desktop.dart').contains("ref.watch(pageHeroProvider('market'))"), isTrue);
    });
    test('pencil only for admins; saving is checked on the server', () {
      expect(read('lib/core/widgets/page_hero.dart').contains('if (admin)'), isTrue);
      final sql = read('supabase/migrations/0049_page_banners.sql');
      expect(RegExp(r'admin_set_page_hero[\s\S]*?perform public\._require_admin\(\);').hasMatch(sql), isTrue);
      expect(sql.contains('revoke all on public.services_hero from anon, authenticated;'), isTrue);
      expect(RegExp(r'\b(drop table|truncate|delete from)\b', caseSensitive: false).hasMatch(sql), isFalse);
    });
  });
}
