// Web Push (owner, 14.11.2026, SQL 0121): the device states, the
// subscription, the Settings card, and the guards that keep start-up and the
// old service-worker clean-up as they were.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freightlink/core/localization/app_strings.dart';
import 'package:freightlink/core/localization/locale_controller.dart';
import 'package:freightlink/core/notify/push_settings.dart';
import 'package:freightlink/core/notify/web_push.dart';

String src(String p) => File(p).readAsStringSync();
final _az = AppStrings(Map<String, String>.from(jsonDecode(src('assets/i18n/az.json')) as Map));

Widget _host(PushDevice d, {PushPrefs prefs = const PushPrefs()}) => ProviderScope(
      key: UniqueKey(),
      overrides: [
        stringsProvider.overrideWithValue(_az),
        pushDeviceProvider.overrideWith((ref) async => d),
        pushPrefsProvider.overrideWith((ref) async => prefs),
      ],
      child: const MaterialApp(home: Scaffold(body: SingleChildScrollView(child: PushSettingsCard()))),
    );

void main() {
  test('the device state from the browser', () {
    expect(pushDeviceOf('granted', subscribed: true), PushDevice.on);
    expect(pushDeviceOf('granted', subscribed: false), PushDevice.off);
    expect(pushDeviceOf('default', subscribed: false), PushDevice.ask);
    expect(pushDeviceOf('denied', subscribed: false), PushDevice.denied);
    expect(pushDeviceOf('ios_install', subscribed: false), PushDevice.iosInstall);
    expect(pushDeviceOf('whatever', subscribed: false), PushDevice.unsupported);
  });

  test('the subscription as the browser gives it', () {
    final s = PushSub.parse(jsonEncode({
      'status': 'granted',
      'sub': {
        'endpoint': 'https://fcm.googleapis.com/fcm/send/abc',
        'keys': {'p256dh': 'BKeyKey', 'auth': 'authauth'},
      },
      'platform': 'android',
    }))!;
    expect((s.endpoint, s.p256dh, s.auth, s.platform), ('https://fcm.googleapis.com/fcm/send/abc', 'BKeyKey', 'authauth', 'android'));
    expect(PushSub.parse(''), isNull);
    expect(PushSub.parse('{"status":"denied"}'), isNull);
    expect(PushSub.parse('not json'), isNull);
    const p = PushPrefs();
    expect((p.messages, p.important, p.preview), (true, true, false), reason: 'standard: "Əli: Yeni mesajınız var"');
  });

  testWidgets('Settings: off → "Bildirişləri aktiv et"; on → Söndür + the three choices', (t) async {
    await t.pumpWidget(_host(PushDevice.ask));
    await t.pumpAndSettle();
    expect(find.text('Proqram bağlı olanda da bildiriş'), findsOneWidget);
    expect(find.byKey(const ValueKey('push-on')), findsOneWidget);
    expect(find.byKey(const ValueKey('push-preview')), findsNothing);

    await t.pumpWidget(_host(PushDevice.on));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('push-off')), findsOneWidget);
    expect(find.byKey(const ValueKey('push-messages')), findsOneWidget);
    expect(find.byKey(const ValueKey('push-important')), findsOneWidget);
    final preview = t.widget<SwitchListTile>(find.byKey(const ValueKey('push-preview')));
    expect(preview.value, isFalse, reason: 'the preview is off unless the user turns it on');
  });

  testWidgets('iPhone in a Safari tab: how to add it to the Home Screen; denied / unsupported explained', (t) async {
    await t.pumpWidget(_host(PushDevice.iosInstall));
    await t.pumpAndSettle();
    expect(find.textContaining('Ana ekrana əlavə et'), findsOneWidget);
    expect(find.byKey(const ValueKey('push-on')), findsNothing);
    await t.pumpWidget(_host(PushDevice.denied));
    await t.pumpAndSettle();
    expect(find.textContaining('icazə verilməyib'), findsOneWidget);
    await t.pumpWidget(_host(PushDevice.unsupported));
    await t.pumpAndSettle();
    expect(find.textContaining('dəstəkləmir'), findsOneWidget);
  });

  group('guards', () {
    test('the push worker: only push + notificationclick, no fetch, no cache', () {
      final sw = src('web/push_sw.js');
      expect(sw.contains("addEventListener('push'"), isTrue);
      expect(sw.contains("addEventListener('notificationclick'"), isTrue);
      expect(sw.contains("'fetch'"), isFalse);
      expect(RegExp(r'caches\.|cache\.(put|add)').hasMatch(sw), isFalse);
      expect(src('web/flutter_service_worker.js'), contains('unregister'), reason: 'the old Flutter worker stays a kill switch');
    });

    test('pwa_guard keeps removing old workers, but not the push worker', () {
      final g = src('web/pwa_guard.js');
      expect(g.contains('push_sw'), isTrue);
      expect(g.contains('r.unregister()'), isTrue);
      final html = src('web/index.html');
      expect(html.indexOf('pwa_guard.js') < html.indexOf('push.js'), isTrue);
      final js = src('web/push.js');
      final sub = js.substring(js.indexOf('async function subscribe('), js.indexOf('function enable('));
      expect('serviceWorker.register('.allMatches(js).length, 1);
      expect(sub.contains('serviceWorker.register('), isTrue, reason: 'registered only after the user allowed it');
    });

    test('the permission is asked only inside a real browser gesture (touchend / click), armed by the tap', () {
      final js = src('web/push.js');
      expect(RegExp(r'requestPermission').allMatches(js).length, 1, reason: 'only in ask()');
      final ask = js.substring(js.indexOf('function ask()'), js.indexOf("['touchend', 'click']"));
      expect(ask.contains('Notification.requestPermission()'), isTrue);
      expect(js.contains("['touchend', 'click'].forEach(function (ev) { window.addEventListener(ev, ask, { capture: true, passive: true }); });"), isTrue);
      final enable = js.substring(js.indexOf('function enable('), js.indexOf("// This device's subscription"));
      expect(enable.contains('pending = {'), isTrue, reason: 'the tap only arms the request');
      expect(enable.contains('requestPermission'), isFalse);
      final dart = src('lib/core/notify/web_push.dart');
      expect(dart.contains('Future<void> pushResync()') && !dart.substring(dart.indexOf('Future<void> pushResync()')).split('class ChatPresence')[0].contains('pushEnable'),
          isTrue, reason: 'the start-up re-check never asks');
    });

    test('sign-out removes this device; the chat tells the server it is being read; start-up waits', () {
      expect(src('lib/features/auth/data/auth_repository_impl.dart').contains('await pushLeaveOnSignOut();'), isTrue);
      final chat = src('lib/features/chat/presentation/conversation_thread_screen.dart');
      expect(chat.contains('_presence.start()') && chat.contains('_presence.stop()'), isTrue);
      expect(src('lib/core/router/main_shell.dart').contains('Future<void>.delayed(const Duration(seconds: 8), pushResync)'), isTrue);
    });

    test('server: no secret in the repository, Vault + service role, deploy by hand', () {
      final sql = src('supabase/migrations/0121_web_push.sql');
      expect(sql.contains('vault.create_secret(replace(gen_random_uuid()'), isTrue, reason: 'the secret is made inside the database');
      expect(sql.contains('grant execute on function public.push_outbox_take(uuid) to service_role'), isTrue);
      final fn = src('supabase/functions/push-send/index.ts');
      expect(fn.contains("Deno.env.get('VAPID_PRIVATE_KEY')"), isTrue);
      expect(RegExp(r'-----BEGIN|VAPID_PRIVATE_KEY\s*=').hasMatch(fn), isFalse);
      expect(src('supabase/config.toml'), contains('[functions.push-send]'));
      expect(src('.github/workflows/supabase-functions.yml'), contains('- push-send'));
    });

    test('texts in all six languages', () {
      final keys = (jsonDecode(src('assets/i18n/az.json')) as Map<String, dynamic>).keys.where((k) => k.startsWith('push_')).toList();
      expect(keys.length, greaterThanOrEqualTo(14));
      for (final l in ['tr', 'en', 'ru', 'ka', 'zh']) {
        final m = jsonDecode(src('assets/i18n/$l.json')) as Map<String, dynamic>;
        for (final k in keys) {
          expect((m[k] as String?)?.isNotEmpty, isTrue, reason: '$l $k');
        }
      }
    });
  });
}
