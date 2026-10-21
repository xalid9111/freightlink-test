// Page banners (0049): TIR Bazarı and Services, a night and a day picture,
// admins change them. Server rules: supabase/tests/local/87_page_banners.sql.
import 'dart:io';

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
