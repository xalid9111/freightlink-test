import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/supabase_config.dart';
import '../../auth/presentation/providers/auth_providers.dart';

/// Deleting messages and chats (migration 0031).
///
/// * "Delete for me" only hides things from the signed-in user's own view
///   (message_hidden / chat_clears). The other person keeps everything.
/// * "Delete for everyone" is allowed only for your own message: the text
///   / attachment is blanked on the server and both sides see
///   "This message was deleted".
class ChatDeleteRepository {
  final SupabaseClient _client = SupabaseConfig.client;

  /// [kind] 'direct' | 'group', [everyone] false = only for me.
  Future<void> deleteMessage(String messageId, {required String kind, required bool everyone}) async {
    await _client.rpc('delete_message', params: {
      'p_message': messageId,
      'p_kind': kind,
      'p_scope': everyone ? 'everyone' : 'me',
    });
  }

  /// Clears every chat with person [targetId] ('direct') or group [targetId]
  /// ('group') from the signed-in user's view. Newer messages show again.
  /// Returns how many chats were cleared (0 = nothing matched).
  Future<int> clearChat(String targetId, {required String kind}) async {
    final n = await _client.rpc('clear_chat_for_me', params: {'p_target': targetId, 'p_kind': kind});
    return n is num ? n.toInt() : int.tryParse('$n') ?? 0;
  }

  Future<Set<String>> hiddenMessageIds() async {
    final rows = await _client.from('message_hidden').select('message_id');
    return {for (final r in rows as List) '${r['message_id']}'};
  }

  /// chat id → cleared at.
  Future<Map<String, DateTime>> clears() async {
    final rows = await _client.from('chat_clears').select('chat_id, cleared_at');
    return {
      for (final r in rows as List)
        if (DateTime.tryParse('${r['cleared_at']}') case final t?) '${r['chat_id']}': t,
    };
  }

  /// conversation id → time of its last message (hidden ones ignored).
  Future<Map<String, DateTime>> activity() async {
    final rows = await _client.rpc('my_chat_activity');
    return {
      for (final r in rows as List)
        if (DateTime.tryParse('${r['last_message_at']}') case final t?) '${r['conversation_id']}': t,
    };
  }
}

final chatDeleteRepositoryProvider = Provider<ChatDeleteRepository>((ref) => ChatDeleteRepository());

/// Message ids the signed-in user deleted "for me". Empty before 0031.
final hiddenMessagesProvider = FutureProvider<Set<String>>((ref) async {
  if (ref.watch(currentUserIdProvider) == null) return const <String>{};
  try {
    return await ref.read(chatDeleteRepositoryProvider).hiddenMessageIds();
  } catch (_) {
    return const <String>{};
  }
});

/// Chats the signed-in user cleared: chat id → cleared at.
final chatClearsProvider = FutureProvider<Map<String, DateTime>>((ref) async {
  if (ref.watch(currentUserIdProvider) == null) return const <String, DateTime>{};
  try {
    return await ref.read(chatDeleteRepositoryProvider).clears();
  } catch (_) {
    return const <String, DateTime>{};
  }
});

/// Last message time per direct conversation (list sorting / reappearing).
final chatActivityProvider = FutureProvider<Map<String, DateTime>>((ref) async {
  if (ref.watch(currentUserIdProvider) == null) return const <String, DateTime>{};
  try {
    return await ref.read(chatDeleteRepositoryProvider).activity();
  } catch (_) {
    return const <String, DateTime>{};
  }
});

/// Messages deleted on this device in this session, shown as deleted right
/// away without waiting for the server: 'me:<id>' (hidden for me) and
/// 'all:<id>' (deleted for everyone).
final locallyDeletedProvider = StateProvider<Set<String>>((ref) => const <String>{});

/// True when message [id] was deleted for everyone (server or this device).
bool deletedForAll(String id, bool serverDeleted, Set<String> local) => serverDeleted || local.contains('all:$id');

/// True when [createdAt] / [id] should be visible to me in chat [chatId].
bool visibleToMe({
  required String id,
  required String chatId,
  required DateTime createdAt,
  required Set<String> hidden,
  required Map<String, DateTime> clears,
  Set<String> local = const <String>{},
}) {
  if (hidden.contains(id) || local.contains('me:$id')) return false;
  final cleared = clears[chatId];
  return cleared == null || createdAt.isAfter(cleared);
}
