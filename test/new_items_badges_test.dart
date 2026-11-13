// Counts next to TIRPark / TIR Bazarı (owner, 13.11.2026) and the sound
// that no longer waits for realtime.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:freightlink/core/notify/new_items_badges.dart';
import 'package:shared_preferences/shared_preferences.dart';

String src(String p) => File(p).readAsStringSync();

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('first time: nothing old counts; new ones count since then; opening the section clears it', () async {
    final asked = <NewItemsSection, DateTime>{};
    var fresh = 0;
    final c = NewItemsController(
      uid: 'u1',
      start: false,
      count: (s, since, uid) async {
        asked[s] = since;
        return s == NewItemsSection.market ? fresh : 0;
      },
    );
    final before = DateTime.now().toUtc().subtract(const Duration(seconds: 1));
    await c.refresh();
    expect(asked[NewItemsSection.market]!.isAfter(before), isTrue, reason: 'the first look is "now"');
    expect(c.state[NewItemsSection.market], 0);
    fresh = 2;
    await c.refresh();
    expect(c.state[NewItemsSection.market], 2);
    final firstLook = asked[NewItemsSection.market]!;
    await c.markSeen(NewItemsSection.market);
    expect(c.state[NewItemsSection.market], 0);
    fresh = 0;
    await c.refresh();
    expect(asked[NewItemsSection.market]!.isAfter(firstLook) || asked[NewItemsSection.market] == firstLook, isTrue);
    final p = await SharedPreferences.getInstance();
    expect(p.getString(newItemsSeenKey(NewItemsSection.market, 'u1')), isNotNull, reason: 'kept on the device per account');
    expect(p.getString(newItemsSeenKey(NewItemsSection.market, 'u2')), isNull);
    c.dispose();
  });

  test('a failed count keeps the last number', () async {
    var fail = false;
    final c = NewItemsController(
        uid: null,
        start: false,
        count: (s, since, uid) async {
          if (fail) throw Exception('offline');
          return 3;
        });
    await c.refresh();
    expect(c.state[NewItemsSection.tirpark], 3);
    fail = true;
    await c.refresh();
    expect(c.state[NewItemsSection.tirpark], 3);
    c.dispose();
  });

  test('wiring: TIRPark and TIR Bazarı carry the counts; the open section is marked seen; counts only, not rows', () {
    final shell = src('lib/core/router/main_shell.dart');
    expect(shell.contains("strings.t('nav_tirpark'), badge: fresh[NewItemsSection.tirpark] ?? 0"), isTrue);
    expect(shell.contains("strings.t('nav_market'), badge: fresh[NewItemsSection.market] ?? 0"), isTrue);
    expect(shell.contains('markSeen(openSection)'), isTrue);
    final b = src('lib/core/notify/new_items_badges.dart');
    expect(RegExp(r'count\(CountOption\.exact\)').allMatches(b).length, 3);
    expect(b.contains(".from('tir_parks')") && b.contains(".from('service_providers')") && b.contains(".from('market_listings')"), isTrue);
    expect(b.contains("q.neq('owner_id', uid)"), isTrue, reason: 'one\'s own ad is not news');
  });

  test('sound: one per new unread message id, the list re-read from the server every 20 s', () {
    final shell = src('lib/core/router/main_shell.dart');
    expect(shell.contains('ids.any((id) => !seen.contains(id))'), isTrue);
    final chat = src('lib/features/chat/presentation/providers/chat_providers.dart');
    expect(chat.contains('liveWithResync(ref, () => repo.watchReceived(uid), () => repo.fetchReceived(uid)'), isTrue);
    final js = src('web/msg_alert.js');
    expect(js.contains('AudioContext') && js.contains('decodeAudioData') && js.contains('test: function'), isTrue);
    expect(src('lib/features/auth/presentation/settings_screen.dart').contains("ValueKey('settings-test-sound')"), isTrue);
  });

  test('computer map banners: the whole picture, one height for all three', () {
    final hero = src('lib/core/widgets/page_hero.dart');
    expect(hero.contains('double kDesktopMapBannerHeight(double width) => (width * 0.16).clamp(200.0, 260.0);'), isTrue);
    expect(hero.contains('fit: BoxFit.contain'), isTrue);
    expect(hero.contains('ImageFilter.blur('), isTrue);
    final tp = src('lib/features/tirpark/presentation/tir_park_screen.dart');
    expect(tp.contains("page: 'tirpark'") && tp.contains('whole: true'), isTrue);
    final sv = src('lib/features/services/presentation/services_map_screen.dart');
    expect(RegExp(r'whole: true,\s*height: kDesktopMapBannerHeight').allMatches(sv).length, 2);
  });
}
