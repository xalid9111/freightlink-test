// "Saytı açarkən bildiriş səsi gəlir, halbuki heç bir bildiriş yoxdur" (owner,
// 15.11.2026): old unread messages never ring when the site opens — also when
// the first list arrives empty and the old ones come a moment later; a message
// that arrives while the site is open rings once.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:freightlink/core/notify/message_sound_rule.dart';

void main() {
  final start = DateTime.utc(2026, 11, 15, 16, 0);

  test('opening the site: old unread messages are silent (also after an empty first list)', () {
    final r = MessageSoundRule(sessionStart: start);
    expect(r.shouldRing(const []), isFalse, reason: 'live connection not ready yet');
    expect(r.shouldRing([('old1', DateTime.utc(2026, 11, 15, 9)), ('old2', DateTime.utc(2026, 11, 14))]), isFalse);
  });

  test('a message that arrives while the site is open rings once', () {
    final r = MessageSoundRule(sessionStart: start);
    r.shouldRing([('old1', DateTime.utc(2026, 11, 15, 9))]);
    final fresh = ('new1', DateTime.utc(2026, 11, 15, 16, 5));
    expect(r.shouldRing([('old1', DateTime.utc(2026, 11, 15, 9)), fresh]), isTrue);
    expect(r.shouldRing([('old1', DateTime.utc(2026, 11, 15, 9)), fresh]), isFalse, reason: 'the 20 s re-read never rings twice');
  });

  test('a phone clock a little ahead of the server still rings for a real new message', () {
    final r = MessageSoundRule(sessionStart: start);
    expect(r.shouldRing([('n', start.subtract(const Duration(seconds: 50)))]), isTrue);
    expect(r.shouldRing([('o', start.subtract(const Duration(minutes: 10)))]), isFalse);
  });

  test('the shell uses the rule for private and group messages', () {
    final s = File('lib/core/router/main_shell.dart').readAsStringSync();
    expect(s, contains('_soundRules.putIfAbsent(uid, MessageSoundRule.new)'));
    expect(s, contains('_groupSoundRules.putIfAbsent(uid, MessageSoundRule.new)'));
    expect(s, isNot(contains('_seenUnread')));
  });
}
