import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/config/supabase_config.dart';
import '../../../models/message_model.dart';
import '../domain/message_repository.dart';

/// Network calls give up after this long instead of leaving a spinner
/// (or a "sending…" bubble) stuck forever on a weak mobile connection.
const _netTimeout = Duration(seconds: 20);

class MessageRepositoryImpl implements MessageRepository {
  final SupabaseClient _client = SupabaseConfig.client;

  @override
  Future<ConversationModel> getOrCreateConversation({
    required String cargoId,
    required String cargoOwnerId,
    required String carrierUserId,
  }) async {
    // Preferred path: one atomic server call (migration 0011) that derives
    // the owner from the cargo, takes the carrier from the session and can
    // never create a duplicate — safe against double taps.
    try {
      final me = _client.auth.currentUser?.id;
      final row = await _client.rpc('get_or_create_conversation', params: {
        'p_cargo_id': cargoId,
        if (me != null && me == cargoOwnerId) 'p_carrier_user_id': carrierUserId,
      }).timeout(_netTimeout);
      if (row is Map<String, dynamic> && row['id'] != null) return ConversationModel.fromJson(row);
      if (row is List && row.isNotEmpty) return ConversationModel.fromJson(row.first as Map<String, dynamic>);
    } on PostgrestException catch (e) {
      // Function not deployed yet → fall back below. Anything else
      // (not a carrier, cargo missing, permission) is a real error.
      final missing = e.code == 'PGRST202' || e.code == '42883' || (e.message.contains('get_or_create_conversation') && e.message.contains('not find'));
      if (!missing) rethrow;
    }

    // Fallback (before 0011): select, then insert; a concurrent insert
    // (unique cargo_id+carrier_user_id) is resolved by re-selecting.
    Future<Map<String, dynamic>?> find() => _client
        .from('conversations')
        .select()
        .eq('cargo_id', cargoId)
        .eq('carrier_user_id', carrierUserId)
        .maybeSingle();
    final existing = await find();
    if (existing != null) return ConversationModel.fromJson(existing);
    try {
      final row = await _client.from('conversations').insert({
        'cargo_id': cargoId,
        'cargo_owner_id': cargoOwnerId,
        'carrier_user_id': carrierUserId,
      }).select().single();
      return ConversationModel.fromJson(row);
    } on PostgrestException catch (e) {
      if (e.code == '23505') {
        final again = await find();
        if (again != null) return ConversationModel.fromJson(again);
      }
      rethrow;
    }
  }

  @override
  Future<ConversationModel> openConversationAsOwner({required String cargoId, required String carrierId}) async {
    try {
      final row = await _client.rpc('get_or_create_conversation', params: {
        'p_cargo_id': cargoId,
        'p_carrier_id': carrierId,
      }).timeout(_netTimeout);
      if (row is Map<String, dynamic> && row['id'] != null) return ConversationModel.fromJson(row);
      if (row is List && row.isNotEmpty) return ConversationModel.fromJson(row.first as Map<String, dynamic>);
      throw StateError('conversation_not_returned');
    } on PostgrestException catch (e) {
      final missing = e.code == 'PGRST202' || e.code == '42883';
      if (!missing) rethrow;
      // Before migration 0011: resolve the carrier's user id, then the
      // generic select-or-insert path.
      final me = _client.auth.currentUser?.id;
      final c = await _client.from('carriers').select('user_id').eq('id', carrierId).single();
      return getOrCreateConversation(cargoId: cargoId, cargoOwnerId: me ?? '', carrierUserId: c['user_id'] as String);
    }
  }

  @override
  Future<ConversationModel?> fetchConversation(String conversationId) async {
    final row = await _client.from('conversations').select().eq('id', conversationId).maybeSingle();
    return row == null ? null : ConversationModel.fromJson(row);
  }

  @override
  Stream<List<ConversationModel>> watchMyConversations() {
    // RLS (conversations_participants) limits rows to the signed-in user;
    // realtime for this table is enabled by migration 0011.
    return _client
        .from('conversations')
        .stream(primaryKey: ['id'])
        .order('created_at')
        .map((rows) => rows.map(ConversationModel.fromJson).toList());
  }

  @override
  Future<void> send({
    required String conversationId,
    required String senderId,
    required String receiverId,
    required String message,
  }) async {
    await _client.from('messages').insert({
      'conversation_id': conversationId,
      'sender_id': senderId,
      'receiver_id': receiverId,
      'message': message,
    }).timeout(_netTimeout);
  }

  @override
  Stream<List<MessageModel>> watchConversation(String conversationId, {int limit = kChatPageSize}) {
    // Only the newest [limit] (not the whole history on every open);
    // shown oldest first as before.
    return _client
        .from('messages')
        .stream(primaryKey: ['id'])
        .eq('conversation_id', conversationId)
        .order('created_at', ascending: false)
        .limit(limit)
        .map((rows) => rows.map(MessageModel.fromJson).toList()..sort((a, b) => a.createdAt.compareTo(b.createdAt)));
  }

  @override
  Future<List<ConversationModel>> fetchMyConversations() async {
    final rows = await _client.from('conversations').select().order('created_at', ascending: false);
    return (rows as List).map((r) => ConversationModel.fromJson(r)).toList();
  }

  @override
  Stream<List<MessageModel>> watchReceived(String userId) {
    return _client
        .from('messages')
        .stream(primaryKey: ['id'])
        .eq('receiver_id', userId)
        // Newest 1000 are plenty for unread badges; the full history is not
        // downloaded again on every app resume (slow on iPhone PWAs).
        .order('created_at', ascending: false)
        .limit(1000)
        .map((rows) => rows.map(MessageModel.fromJson).toList());
  }

  @override
  Future<void> markConversationRead({required String conversationId, required String userId}) async {
    await _client
        .from('messages')
        .update({'read_at': DateTime.now().toUtc().toIso8601String()})
        .eq('conversation_id', conversationId)
        .eq('receiver_id', userId)
        .isFilter('read_at', null);
  }

  @override
  Future<void> sendAttachment({
    required String conversationId,
    required String senderId,
    required String receiverId,
    required Uint8List bytes,
    required String type,
    required String fileName,
    String? contentType,
    int? audioDurationMs,
  }) async {
    final safeName = fileName.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final path = '$conversationId/${DateTime.now().millisecondsSinceEpoch}_$safeName';
    await _client.storage.from('chat-files').uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(contentType: contentType, upsert: false),
        ).timeout(const Duration(minutes: 2));
    await _client.from('messages').insert({
      'conversation_id': conversationId,
      'sender_id': senderId,
      'receiver_id': receiverId,
      'attachment_path': path,
      'attachment_type': type,
      'attachment_name': fileName,
      'attachment_size': bytes.length,
      if (audioDurationMs != null) 'audio_duration_ms': audioDurationMs,
    }).timeout(_netTimeout);
  }

  @override
  Future<String> signedUrl(String path) {
    return _client.storage.from('chat-files').createSignedUrl(path, 60 * 60);
  }
}
