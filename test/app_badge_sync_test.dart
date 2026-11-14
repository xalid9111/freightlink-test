// The app icon's "1" stayed after the message was read (owner, 14.11.2026):
// Android counts the notifications left in the shade. An open chat now closes
// its own notification; no unread left = every chat notification closed and
// the icon number cleared; otherwise the icon shows the unread count.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:freightlink/core/notify/web_push.dart';

String src(String p) => File(p).readAsStringSync();

void main() {
  test('the chat tag matches the server (0121) and the service worker', () {
    expect(AppBadgeSync.chatTag('abc'), 'chat-abc');
    expect(src('supabase/migrations/0121_web_push.sql'), contains("'chat-' || new.conversation_id"));
    expect(src('web/push_sw.js'), contains('tag: tag'));
  });

  test('push.js closes read chats and sets / clears the icon number, never asks', () {
    final js = src('web/push.js');
    expect(js, contains('async function clear(tag)'));
    expect(js, contains('reg.getNotifications()'));
    expect(js, contains('list[i].close()'));
    expect(js, contains('navigator.setAppBadge(n)'));
    expect(js, contains('navigator.clearAppBadge()'));
    expect(js, contains('clear: clear, badge: badge'));
    // Clearing never requests a permission.
    final body = js.substring(js.indexOf('async function clear(tag)'), js.indexOf('window.flPush ='));
    expect(body, isNot(contains('requestPermission')));
  });

  test('the shell follows the unread count; an open chat clears its own', () {
    expect(src('lib/core/router/main_shell.dart'), contains('AppBadgeSync.update(unread.toInt())'));
    final push = src('lib/core/notify/web_push.dart');
    expect(push, contains('AppBadgeSync.chatOpened(id)'));
    expect(push, contains('if (unread <= 0) impl.pushClear(chatTagPrefix)'));
  });

  testWidgets('update is safe off the web and repeats only on change', (t) async {
    AppBadgeSync.reset();
    AppBadgeSync.update(2);
    AppBadgeSync.update(2);
    AppBadgeSync.update(0);
    AppBadgeSync.chatOpened('x');
    expect(t.takeException(), isNull);
  });
}
