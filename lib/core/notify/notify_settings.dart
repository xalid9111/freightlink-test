import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../features/auth/presentation/providers/auth_providers.dart';
import '../config/supabase_config.dart';
import '../localization/locale_controller.dart';
import 'message_alert.dart';

/// Settings → Notifications. Saved on this device.
class NotifySettings {
  final bool cargoNotify;
  final bool cargoSound;
  final bool msgNotify;
  final bool msgSound;
  const NotifySettings({this.cargoNotify = true, this.cargoSound = true, this.msgNotify = true, this.msgSound = true});

  NotifySettings copyWith({bool? cargoNotify, bool? cargoSound, bool? msgNotify, bool? msgSound}) => NotifySettings(
        cargoNotify: cargoNotify ?? this.cargoNotify,
        cargoSound: cargoSound ?? this.cargoSound,
        msgNotify: msgNotify ?? this.msgNotify,
        msgSound: msgSound ?? this.msgSound,
      );
}

class NotifySettingsController extends StateNotifier<NotifySettings> {
  static const _kCargoNotify = 'notify_cargo';
  static const _kCargoSound = 'sound_cargo';
  static const _kMsgNotify = 'notify_msg';
  static const _kMsgSound = 'sound_msg';

  NotifySettingsController() : super(const NotifySettings()) {
    _restore();
  }

  Future<void> _restore() async {
    try {
      final p = await SharedPreferences.getInstance();
      state = NotifySettings(
        cargoNotify: p.getBool(_kCargoNotify) ?? true,
        cargoSound: p.getBool(_kCargoSound) ?? true,
        msgNotify: p.getBool(_kMsgNotify) ?? true,
        msgSound: p.getBool(_kMsgSound) ?? true,
      );
    } catch (_) {}
  }

  Future<void> _save(String key, bool on) async {
    try {
      (await SharedPreferences.getInstance()).setBool(key, on);
    } catch (_) {}
  }

  void setCargoNotify(bool on) {
    state = state.copyWith(cargoNotify: on);
    _save(_kCargoNotify, on);
  }

  void setCargoSound(bool on) {
    state = state.copyWith(cargoSound: on);
    _save(_kCargoSound, on);
  }

  void setMsgNotify(bool on) {
    state = state.copyWith(msgNotify: on);
    _save(_kMsgNotify, on);
  }

  void setMsgSound(bool on) {
    state = state.copyWith(msgSound: on);
    _save(_kMsgSound, on);
  }
}

final notifySettingsProvider =
    StateNotifierProvider<NotifySettingsController, NotifySettings>((ref) => NotifySettingsController());

/// While signed in: every 45 s look at the newest open loads; when a load
/// from someone else appears → sound and/or notification (per settings).
/// A small query (ids only), only while the app is open.
final newCargoWatcherProvider = Provider<void>((ref) {
  final uid = ref.watch(currentUserIdProvider);
  if (uid == null) return;
  Set<String>? known;
  var busy = false;
  Future<void> tick() async {
    if (busy) return;
    busy = true;
    try {
      final s = ref.read(notifySettingsProvider);
      if (!s.cargoNotify && !s.cargoSound) {
        known = null;
        return;
      }
      final rows = await SupabaseConfig.client
          .from('cargo')
          .select('id, owner_id')
          .eq('status', 'new')
          .order('created_at', ascending: false)
          .limit(20);
      final list = [for (final r in rows as List) Map<String, dynamic>.from(r as Map)];
      final before = known;
      if (before != null) {
        final fresh = list.where((r) => !before.contains('${r['id']}') && '${r['owner_id']}' != uid);
        if (fresh.isNotEmpty) {
          if (s.cargoSound) playCargoSound();
          if (s.cargoNotify) showCargoNotification('FreightLink', ref.read(stringsProvider).t('notif_new_cargo'));
        }
      }
      known = {...?before, for (final r in list) '${r['id']}'};
    } catch (_) {
      // Offline / temporary error: try again on the next tick.
    } finally {
      busy = false;
    }
  }

  tick();
  final timer = Timer.periodic(const Duration(seconds: 45), (_) => tick());
  ref.onDispose(timer.cancel);
});
