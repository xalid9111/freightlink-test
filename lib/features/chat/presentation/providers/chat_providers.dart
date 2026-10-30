import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../../../core/config/supabase_config.dart';
import '../../../../models/cargo_model.dart';
import '../../../../models/message_model.dart';
import '../../data/message_repository_impl.dart';
import '../../domain/message_repository.dart';

final messageRepositoryProvider = Provider<MessageRepository>((ref) => MessageRepositoryImpl());

class ConversationWithCargo {
  final ConversationModel conversation;
  final CargoModel? cargo;
  const ConversationWithCargo({required this.conversation, required this.cargo});
}

/// Same two-query pattern as ShipmentWithCargo (see
/// repositories/shipment_repository.dart) and for the same reason: the
/// conversation list needs the cargo route to be a useful label, and
/// that lives on `cargo`, not `conversations`.
final myConversationsProvider = StreamProvider<List<ConversationWithCargo>>((ref) {
  final uid = ref.watch(currentUserIdProvider); // re-subscribe when the signed-in account changes
  final repo = ref.watch(messageRepositoryProvider);
  // Live: a carrier's new chat shows up in the owner's list at once.
  return repo.watchMyConversations().asyncMap((list) async {
    // RLS also lets an admin read every conversation (for moderation), but
    // the Messages tab must only list chats I am actually part of —
    // otherwise other people's chats appear here and cannot be deleted.
    final conversations = [
      for (final c in list)
        if (uid != null && (c.cargoOwnerId == uid || c.carrierUserId == uid)) c,
    ]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    if (conversations.isEmpty) return <ConversationWithCargo>[];
    final cargoIds = conversations.map((c) => c.cargoId).whereType<String>().toSet().toList();
    final cargoById = <String, CargoModel>{};
    if (cargoIds.isNotEmpty) {
      final rows = await SupabaseConfig.client.from('cargo').select().inFilter('id', cargoIds);
      for (final row in (rows as List)) {
        cargoById[row['id'] as String] = CargoModel.fromJson(row);
      }
    }
    return conversations
        .map((c) => ConversationWithCargo(conversation: c, cargo: c.cargoId != null ? cargoById[c.cargoId] : null))
        .toList();
  });
});

/// One conversation by id, fetched directly — the chat screen must not
/// depend on the (possibly stale) list to know who it is talking to.
final conversationByIdProvider = FutureProvider.family<ConversationModel?, String>((ref, id) {
  ref.watch(currentUserIdProvider);
  return ref.watch(messageRepositoryProvider).fetchConversation(id);
});

// autoDispose: a chat's realtime subscription is closed when nobody shows
// that chat any more (before, every chat ever opened kept a live channel
// until the app was reloaded — heavy on iPhone PWAs).
/// Keyed by (chat id, how many of the newest messages): "Köhnə mesajlar"
/// asks for a bigger number.
final conversationMessagesProvider = StreamProvider.autoDispose.family<List<MessageModel>, (String, int)>((ref, key) {
  ref.watch(currentUserIdProvider); // re-fetch when the signed-in account changes
  return ref.watch(messageRepositoryProvider).watchConversation(key.$1, limit: key.$2);
});

/// Number of unread messages addressed to the signed-in user, live
/// (drives the badge on the Messages tab). 0 when signed out.
/// ONE live subscription to the messages I received (before, the unread
/// count and the per-chat badges each opened their own identical channel
/// and each downloaded the full list).
final receivedMessagesProvider = StreamProvider<List<MessageModel>>((ref) {
  final uid = ref.watch(currentUserIdProvider);
  if (uid == null) return Stream.value(const <MessageModel>[]);
  return ref.watch(messageRepositoryProvider).watchReceived(uid);
});

/// Keeps the last value while the stream re-subscribes (no badge flicker
/// to 0 after every app resume).
AsyncValue<R> _derive<R>(AsyncValue<List<MessageModel>> a, R Function(List<MessageModel>) f) {
  final list = a.valueOrNull;
  if (list != null) return AsyncData<R>(f(list));
  if (a.hasError) return AsyncError<R>(a.error!, a.stackTrace ?? StackTrace.empty);
  return AsyncLoading<R>();
}

final unreadCountProvider = Provider<AsyncValue<int>>((ref) {
  return _derive(ref.watch(receivedMessagesProvider), (list) => list.where((m) => m.readAt == null).length);
});

/// Signed (1 h) link for a private chat attachment, cached per path.
final attachmentUrlProvider = FutureProvider.family<String, String>((ref, path) {
  return ref.watch(messageRepositoryProvider).signedUrl(path);
});

/// Unread messages per conversation id (badges on the conversation list).
final unreadByConversationProvider = Provider<AsyncValue<Map<String, int>>>((ref) {
  return _derive(ref.watch(receivedMessagesProvider), (list) {
    final counts = <String, int>{};
    for (final m in list) {
      if (m.readAt == null) counts[m.conversationId] = (counts[m.conversationId] ?? 0) + 1;
    }
    return counts;
  });
});
