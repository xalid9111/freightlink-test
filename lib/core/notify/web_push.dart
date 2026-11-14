import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

import '../config/env.dart';
import '../config/supabase_config.dart';
import 'web_push_stub.dart' if (dart.library.js_interop) 'web_push_web.dart' as impl;

/// Web Push (owner, 14.11.2026, SQL 0121): notifications while TırLink is
/// closed. The browser part is web/push.js + web/push_sw.js; the server part
/// is the outbox triggers + the Edge Function push-send. Nothing here runs
/// on start-up except a quiet re-check a few seconds after the first frame.

/// This device: on / off / why not.
enum PushDevice { on, off, ask, denied, iosInstall, unsupported, notReady, tapAgain, failed }

/// The browser's own words of the last failed try (shown with "Alınmadı").
String? lastPushError;

PushDevice pushDeviceOf(String state, {required bool subscribed}) => switch (state) {
      'granted' => subscribed ? PushDevice.on : PushDevice.off,
      'default' => PushDevice.ask,
      'denied' => PushDevice.denied,
      'ios_install' => PushDevice.iosInstall,
      _ => PushDevice.unsupported,
    };

/// The browser's subscription (PushSubscription.toJSON()).
class PushSub {
  final String endpoint, p256dh, auth, platform;
  const PushSub(this.endpoint, this.p256dh, this.auth, this.platform);

  /// {"sub": {"endpoint": …, "keys": {"p256dh": …, "auth": …}}, "platform": …}
  static PushSub? parse(String raw) {
    if (raw.isEmpty) return null;
    try {
      final o = jsonDecode(raw) as Map<String, dynamic>;
      final sub = o['sub'] as Map<String, dynamic>?;
      final keys = sub?['keys'] as Map<String, dynamic>?;
      final ep = sub?['endpoint'] as String?;
      final p = keys?['p256dh'] as String?;
      final a = keys?['auth'] as String?;
      if (ep == null || p == null || a == null) return null;
      return PushSub(ep, p, a, (o['platform'] as String?) ?? 'web');
    } catch (_) {
      return null;
    }
  }
}

class PushPrefs {
  final bool messages, important, preview;
  const PushPrefs({this.messages = true, this.important = true, this.preview = false});
  factory PushPrefs.fromJson(Map<String, dynamic> j) =>
      PushPrefs(messages: j['messages'] != false, important: j['important'] != false, preview: j['preview'] == true);
  PushPrefs copyWith({bool? messages, bool? important, bool? preview}) =>
      PushPrefs(messages: messages ?? this.messages, important: important ?? this.important, preview: preview ?? this.preview);
}

/// SQL 0121 / push-send not ready yet.
class PushNotReady implements Exception {
  const PushNotReady();
}

class PushRepository {
  static const _t = Duration(seconds: 15);
  String get keyUrl => '${Env.supabaseUrl}/functions/v1/push-send';

  Future<T> _run<T>(Future<T> Function() f) async {
    try {
      return await f();
    } on PostgrestException catch (e) {
      if (e.code == 'PGRST202' || e.code == '42883' || e.code == 'PGRST205' || e.code == '42P01') throw const PushNotReady();
      rethrow;
    }
  }

  Future<void> save(PushSub s) => _run(() => SupabaseConfig.client.rpc('push_subscribe', params: {
        'p_endpoint': s.endpoint,
        'p_p256dh': s.p256dh,
        'p_auth': s.auth,
        'p_platform': s.platform,
        'p_user_agent': null,
      }).timeout(_t));

  Future<void> remove(String endpoint) =>
      _run(() => SupabaseConfig.client.rpc('push_unsubscribe', params: {'p_endpoint': endpoint}).timeout(_t));

  Future<PushPrefs> prefs() => _run(() async {
        final r = await SupabaseConfig.client.rpc('push_prefs_get').timeout(_t);
        return PushPrefs.fromJson(Map<String, dynamic>.from(r as Map));
      });

  Future<void> setPrefs(PushPrefs p) => _run(() => SupabaseConfig.client.rpc('push_prefs_set',
      params: {'p_messages': p.messages, 'p_important': p.important, 'p_preview': p.preview}).timeout(_t));

  /// The chat being read now (null = none): no push for it meanwhile.
  Future<void> active(String? conversationId) async {
    try {
      await SupabaseConfig.client.rpc('push_active', params: {'p_conversation': conversationId}).timeout(_t);
    } catch (_) {}
  }
}

final pushRepositoryProvider = Provider<PushRepository>((ref) => PushRepository());

final pushPrefsProvider = FutureProvider.autoDispose<PushPrefs>((ref) => ref.watch(pushRepositoryProvider).prefs());

/// This device's state, read without any prompt.
final pushDeviceProvider = FutureProvider.autoDispose<PushDevice>((ref) async {
  final state = impl.pushState();
  final sub = state == 'granted' ? PushSub.parse(await impl.pushCurrent()) : null;
  return pushDeviceOf(state, subscribed: sub != null);
});

/// "Aktiv et" — call it straight from the tap (the permission is asked at
/// once, before anything else). Returns the new state.
Future<PushDevice> pushTurnOn(PushRepository repo) async {
  lastPushError = null;
  final raw = await impl.pushEnable('', repo.keyUrl);
  Map<String, dynamic> o;
  try {
    o = jsonDecode(raw) as Map<String, dynamic>;
  } catch (_) {
    return PushDevice.unsupported;
  }
  final status = '${o['status']}';
  if (status == 'not_ready') return PushDevice.notReady;
  if (status == 'no_gesture' || status == 'tap_again') {
    lastPushError = o['error'] as String?;
    return PushDevice.tapAgain;
  }
  if (status == 'error') {
    lastPushError = o['error'] as String?;
    return PushDevice.failed;
  }
  if (status != 'granted') return pushDeviceOf(status, subscribed: false);
  final sub = PushSub.parse(raw);
  if (sub == null) return PushDevice.off;
  await repo.save(sub);
  return PushDevice.on;
}

/// "Söndür" and signing out: this device stops (browser + server).
Future<void> pushTurnOff(PushRepository repo) async {
  final ep = await impl.pushDisable();
  if (ep.isNotEmpty) {
    try {
      await repo.remove(ep);
    } catch (_) {}
  }
}

/// Before signing out (the session is still valid); never blocks it.
Future<void> pushLeaveOnSignOut() async {
  try {
    await pushTurnOff(PushRepository()).timeout(const Duration(seconds: 3));
  } catch (_) {}
}

/// A few seconds after start / on resume: a device that already allowed it
/// re-saves its subscription (it may have changed). Never asks anything.
Future<void> pushResync() async {
  try {
    if (SupabaseConfig.client.auth.currentSession == null) return;
    if (impl.pushState() != 'granted') return;
    final sub = PushSub.parse(await impl.pushCurrent());
    if (sub != null) await PushRepository().save(sub);
  } catch (_) {}
}

/// Read messages leave the phone (owner, 14.11.2026): Android counts the
/// notifications still in the shade on the app icon, so "1" stayed after the
/// chat was read in the app. An open chat closes its own notification; no
/// unread message left = every chat notification closed and the icon number
/// cleared; otherwise the icon shows the unread count (where supported).
/// Never asks for a permission; does nothing where unsupported.
class AppBadgeSync {
  AppBadgeSync._();
  static int? _last;
  static AppLifecycleListener? _life;

  /// The unread total changed (or the app came back): bring the phone in step.
  static void update(int unread, {bool force = false}) {
    _life ??= AppLifecycleListener(onResume: () => _apply(_last ?? 0), onShow: () => _apply(_last ?? 0));
    if (!force && unread == _last) return;
    _last = unread;
    _apply(unread);
  }

  static void _apply(int unread) {
    impl.pushBadge(unread);
    if (unread <= 0) impl.pushClear(chatTagPrefix);
  }

  /// The tag of a chat's notification (0121: 'chat-' || conversation_id).
  static const chatTagPrefix = 'chat-';
  static String chatTag(String conversationId) => '$chatTagPrefix$conversationId';

  /// The chat is on screen: its notification goes.
  static void chatOpened(String conversationId) => impl.pushClear(chatTag(conversationId));

  @visibleForTesting
  static void reset() => _last = null;
}

/// The open chat tells the server "I am reading this one" every 30 s while
/// the app is visible; nothing when hidden or closed.
class ChatPresence {
  /// The chat on screen (any topic with that person is enough for the server).
  final String? Function() conversationId;
  final PushRepository repo;
  Timer? _timer;
  AppLifecycleListener? _life;
  ChatPresence(this.conversationId, this.repo);

  static const every = Duration(seconds: 30);

  bool _stopped = false;

  void start() {
    _beat();
    // A chat opened by person (not by id) knows its id after the first build.
    Future<void>.delayed(const Duration(seconds: 2), () {
      if (!_stopped) _beat();
    });
    _timer = Timer.periodic(every, (_) => _beat());
    _life = AppLifecycleListener(
      onHide: () {
        try {
          if (SupabaseConfig.client.auth.currentSession != null) repo.active(null);
        } catch (_) {}
      },
      onShow: _beat,
      onResume: _beat,
    );
  }

  void _beat() {
    try {
      final id = conversationId();
      if (id == null || SupabaseConfig.client.auth.currentSession == null) return;
      repo.active(id);
      AppBadgeSync.chatOpened(id);
    } catch (_) {}
  }

  void stop() {
    _stopped = true;
    _timer?.cancel();
    _life?.dispose();
    try {
      if (SupabaseConfig.client.auth.currentSession != null) repo.active(null);
    } catch (_) {}
  }
}
