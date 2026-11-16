// Owner, 16.11.2026 (SQL 0125): the "Önə çıxar" cards stand on EVERY active
// TIR Bazarı ad page for a signed-in user, so a friend can promote (and pay
// for) the seller's ad; visitors see none (they cannot pay or read prices).
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String src(String p) => File(p).readAsStringSync();

void main() {
  test('the cards are on every active ad page, for signed-in users', () {
    final page = src('lib/features/market/presentation/market_detail_screen.dart');
    expect(page, contains('if (signedIn && l.status == MarketStatus.active) ...['));
    expect(page, contains("MarketPromoOptions(key: const ValueKey('mk-promo-on-page'), s: s, target: MarketPromoTarget(l))"));
    expect(page, contains("if (!isOwner) ...[\n                Text(s.t('mk_promo_friend_hint'),"));
    expect(page, contains('signedIn: me != null'));
    // The owner keeps his own button under his actions, as before.
    expect(page, contains('below: l.status == MarketStatus.active ? _vipButton(s, l) : null'));
  });

  test('the server lets anybody signed in order, never a visitor (0125)', () {
    final sql = src('supabase/migrations/0125_promote_any_ad.sql');
    expect(sql, isNot(contains('owner_id is distinct from v_uid')));
    expect('if v_l.id is null then raise exception \'listing_not_found\''.allMatches(sql).length, 2);
    expect(sql, contains('revoke all on function public.market_vip_order_create(uuid, integer) from public, anon;'));
    expect(sql, contains('revoke all on function public.market_promo_order_create(uuid, text, integer) from public, anon;'));
  });

  test('the sheet speaks of "the ad", not "your ad", in all six languages', () {
    for (final l in ['az', 'tr', 'en', 'ru', 'ka', 'zh']) {
      final d = jsonDecode(src('assets/i18n/$l.json')) as Map<String, dynamic>;
      expect((d['mk_promo_friend_hint'] as String).isNotEmpty, isTrue, reason: l);
      for (final k in ['bump', 'vip', 'premium']) {
        final t = d['mk_promo_${k}_body'] as String;
        for (final your in ['Elanınız', 'İlanınız', 'Your ad', 'Ваше', 'თქვენი', '您的']) {
          expect(t.contains(your), isFalse, reason: '$l $k');
        }
      }
    }
  });
}
