import 'dart:typed_data';

import '../../../models/message_model.dart';

abstract class MessageRepository {
  Future<ConversationModel> getOrCreateConversation({
    required String cargoId,
    required String cargoOwnerId,
    required String carrierUserId,
  });

  Future<void> send({
    required String conversationId,
    required String senderId,
    required String receiverId,
    required String message,
  });

  /// Realtime stream of messages in a conversation, backed by Supabase
  /// Realtime (migration 0001 publishes public.messages).
  Stream<List<MessageModel>> watchConversation(String conversationId);

  /// All conversations the signed-in user is part of (RLS already
  /// scopes "part of" — see conversations_participants in migration
  /// 0002), newest first.
  Future<List<ConversationModel>> fetchMyConversations();

  /// Live list of messages addressed to [userId] (used to count unread).
  Stream<List<MessageModel>> watchReceived(String userId);

  /// Marks every unread message in [conversationId] addressed to
  /// [userId] as read (RLS messages_mark_read, migration 0002).
  Future<void> markConversationRead({required String conversationId, required String userId});

  /// Uploads [bytes] to the private chat-files bucket under the
  /// conversation's folder and posts a message pointing at it
  /// (migration 0010). [type] is 'image', 'file' or 'audio'.
  Future<void> sendAttachment({
    required String conversationId,
    required String senderId,
    required String receiverId,
    required Uint8List bytes,
    required String type,
    required String fileName,
    String? contentType,
    int? audioDurationMs,
  });

  /// Short-lived link for viewing/downloading a private attachment.
  Future<String> signedUrl(String path);

  /// A single conversation by id (null if not visible to this user).
  Future<ConversationModel?> fetchConversation(String conversationId);

  /// Live list of the signed-in user's conversations.
  Stream<List<ConversationModel>> watchMyConversations();

  /// Cargo owner opens (or creates) the chat with the carrier behind an
  /// offer ([carrierId] = carriers.id).
  Future<ConversationModel> openConversationAsOwner({required String cargoId, required String carrierId});
}
