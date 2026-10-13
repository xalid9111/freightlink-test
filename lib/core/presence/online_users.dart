import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/auth/presentation/providers/auth_providers.dart';
import '../config/supabase_config.dart';
import '../../repositories/profile_repository.dart';

/// Who is online right now — Supabase Realtime **Presence** (in-memory on
/// the Realtime server; no database table or migration involved). Every
/// signed-in app instance joins one shared channel and "tracks" its user
/// id; the presence state is the set of user ids currently connected.
/// When the app closes or loses connection, Realtime drops that entry by
/// itself, so "online" can't get stuck on.
///
/// Watched by MainShell so it stays active on every authenticated screen.
class OnlineUsersNotifier extends Notifier<Set<String>> {
  RealtimeChannel? _channel;
  Timer? _heartbeat;

  @override
  Set<String> build() {
    final uid = ref.watch(currentUserIdProvider);
    ref.onDispose(_leave);
    if (uid != null) _join(uid);
    return <String>{};
  }

  void _join(String uid) {
    // "Last seen": stamp now, then once a minute while the app is open.
    // When the app closes the stamps stop, so the last one ≈ last seen.
    final profiles = ref.read(profileRepositoryProvider);
    profiles.touchLastSeen();
    _heartbeat = Timer.periodic(const Duration(seconds: 60), (_) => profiles.touchLastSeen());

    final client = SupabaseConfig.client;
    final channel = client.channel('online-users');
    _channel = channel;
    channel.onPresenceSync((_) {
      final next = _extractUserIds(channel.presenceState());
      // Same people online → no update (avoids needless rebuilds).
      if (next.length != state.length || !next.containsAll(state)) state = next;
    });
    channel.subscribe((status, error) async {
      if (status == RealtimeSubscribeStatus.subscribed) {
        try {
          await channel.track({'user_id': uid, 'online_at': DateTime.now().toUtc().toIso8601String()});
        } catch (_) {
          // Presence is a nicety; never break the app over it.
        }
      }
    });
  }

  void _leave() {
    _heartbeat?.cancel();
    _heartbeat = null;
    final c = _channel;
    _channel = null;
    if (c != null) {
      SupabaseConfig.client.removeChannel(c);
    }
  }

  /// Reads user ids out of the presence state. Written against `dynamic`
  /// so it works with both shapes realtime_client has used
  /// (List<SinglePresenceState> and Map<String, List<Presence>>).
  static Set<String> _extractUserIds(dynamic presenceState) {
    final ids = <String>{};
    void fromPresenceList(dynamic list) {
      if (list is! List) return;
      for (final p in list) {
        try {
          final dynamic payload = (p as dynamic).payload;
          final id = payload is Map ? payload['user_id'] : null;
          if (id is String) ids.add(id);
        } catch (_) {}
      }
    }

    try {
      if (presenceState is Map) {
        for (final v in presenceState.values) {
          fromPresenceList(v);
        }
      } else if (presenceState is List) {
        for (final s in presenceState) {
          try {
            fromPresenceList((s as dynamic).presences);
          } catch (_) {}
        }
      }
    } catch (_) {}
    return ids;
  }
}

final onlineUsersProvider = NotifierProvider<OnlineUsersNotifier, Set<String>>(OnlineUsersNotifier.new);

/// Convenience: is this particular user online right now?
final isUserOnlineProvider = Provider.family<bool, String>((ref, userId) {
  return ref.watch(onlineUsersProvider).contains(userId);
});
