import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/supabase_config.dart';
import '../../../models/group_models.dart';
import '../../../models/message_model.dart';
import '../../../repositories/profile_repository.dart' show isMissingRelation;

const _netTimeout = Duration(seconds: 20);

/// Group chats, person-to-person chats and user search (migration 0014).
/// Every membership change goes through a server function that checks
/// who is allowed to do it; reads are limited by RLS to your own groups.
class GroupRepository {
  final SupabaseClient _c = SupabaseConfig.client;

  String? get _me => _c.auth.currentUser?.id;

  // ---- people ---------------------------------------------------------

  /// Users whose name contains [query] (case-insensitive), excluding me.
  Future<List<UserHit>> searchUsers(String query, {int limit = 25}) async {
    final q = query.trim().replaceAll(RegExp(r'[%_,()]'), ' ').trim();
    if (q.isEmpty) return const [];
    // Public profile view (migration 0019); public.users is own-row only.
    Future<List<dynamic>> run(String table) {
      var req = _c.from(table).select('id,full_name,avatar_url,role,is_active').ilike('full_name', '%$q%');
      final me = _me;
      if (me != null) req = req.neq('id', me);
      return req.order('full_name').limit(limit).timeout(_netTimeout);
    }
    List<dynamic> rows;
    try {
      rows = await run('user_profiles');
    } on PostgrestException catch (e) {
      if (!isMissingRelation(e)) rethrow;
      rows = await run('users'); // 0019 not applied yet
    }
    return rows
        .map((r) => Map<String, dynamic>.from(r as Map))
        .where((r) => r['is_active'] != false)
        .map(UserHit.fromJson)
        .where((u) => u.fullName.trim().isNotEmpty)
        .toList();
  }

  /// Opens (or creates) a 1-to-1 chat with [userId], not tied to a load.
  Future<ConversationModel> openDirect(String userId) async {
    final row = await _c.rpc('get_or_create_direct_conversation', params: {'p_other': userId}).timeout(_netTimeout);
    if (row is Map) return ConversationModel.fromJson(Map<String, dynamic>.from(row));
    if (row is List && row.isNotEmpty) return ConversationModel.fromJson(Map<String, dynamic>.from(row.first as Map));
    throw StateError('conversation_not_returned');
  }

  // ---- groups -----------------------------------------------------------

  Stream<List<GroupMember>> watchMyMemberships(String uid) => _c
      .from('chat_group_members')
      .stream(primaryKey: ['group_id', 'user_id'])
      .eq('user_id', uid)
      .map((rows) => rows.map(GroupMember.fromJson).toList());

  Stream<List<GroupMember>> watchMembers(String groupId) => _c
      .from('chat_group_members')
      .stream(primaryKey: ['group_id', 'user_id'])
      .eq('group_id', groupId)
      .map((rows) => rows.map(GroupMember.fromJson).toList());

  Future<List<ChatGroup>> fetchGroups(List<String> ids) async {
    if (ids.isEmpty) return const [];
    final rows = await _c.from('chat_groups').select().inFilter('id', ids).timeout(_netTimeout);
    return (rows as List).map((r) => ChatGroup.fromJson(Map<String, dynamic>.from(r as Map))).toList();
  }

  Future<ChatGroup?> fetchGroup(String id) async {
    final row = await _c.from('chat_groups').select().eq('id', id).maybeSingle().timeout(_netTimeout);
    return row == null ? null : ChatGroup.fromJson(row);
  }

  /// Latest messages of all my groups (RLS-limited) — drives "last
  /// message" ordering and unread counters on the list.
  Stream<List<GroupMessage>> watchMyGroupMessages() => _c
      .from('group_messages')
      .stream(primaryKey: ['id'])
      .order('created_at', ascending: false)
      .limit(500)
      .map((rows) => rows.map(GroupMessage.fromJson).toList());

  Stream<List<GroupMessage>> watchGroupMessages(String groupId) => _c
      .from('group_messages')
      .stream(primaryKey: ['id'])
      .eq('group_id', groupId)
      .order('created_at')
      .map((rows) => rows.map(GroupMessage.fromJson).toList());

  Future<ChatGroup> createGroup(String name, List<String> memberIds) async {
    final row = await _c.rpc('create_chat_group', params: {'p_name': name, 'p_members': memberIds}).timeout(_netTimeout);
    if (row is Map) return ChatGroup.fromJson(Map<String, dynamic>.from(row));
    if (row is List && row.isNotEmpty) return ChatGroup.fromJson(Map<String, dynamic>.from(row.first as Map));
    throw StateError('group_not_returned');
  }

  Future<void> addMembers(String groupId, List<String> memberIds) async {
    await _c.rpc('add_chat_group_members', params: {'p_group': groupId, 'p_members': memberIds}).timeout(_netTimeout);
  }

  Future<void> removeMember(String groupId, String userId) async {
    await _c.rpc('remove_chat_group_member', params: {'p_group': groupId, 'p_user': userId}).timeout(_netTimeout);
  }

  Future<void> rename(String groupId, String name) async {
    await _c.rpc('rename_chat_group', params: {'p_group': groupId, 'p_name': name}).timeout(_netTimeout);
  }

  Future<void> markRead(String groupId) async {
    try {
      await _c.rpc('mark_chat_group_read', params: {'p_group': groupId}).timeout(_netTimeout);
    } catch (_) {
      // a missed read-marker only affects the unread badge
    }
  }

  Future<void> sendText(String groupId, String text) async {
    final me = _me;
    if (me == null) throw StateError('not_signed_in');
    await _c.from('group_messages').insert({'group_id': groupId, 'sender_id': me, 'message': text}).timeout(_netTimeout);
  }

  Future<void> sendAttachment({
    required String groupId,
    required Uint8List bytes,
    required String type,
    required String fileName,
    String? contentType,
    int? audioDurationMs,
  }) async {
    final me = _me;
    if (me == null) throw StateError('not_signed_in');
    final safeName = fileName.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final path = 'g/$groupId/${DateTime.now().millisecondsSinceEpoch}_$safeName';
    await _c.storage
        .from('chat-files')
        .uploadBinary(path, bytes, fileOptions: FileOptions(contentType: contentType, upsert: false))
        .timeout(const Duration(minutes: 2));
    await _c.from('group_messages').insert({
      'group_id': groupId,
      'sender_id': me,
      'attachment_path': path,
      'attachment_type': type,
      'attachment_name': fileName,
      'attachment_size': bytes.length,
      if (audioDurationMs != null) 'audio_duration_ms': audioDurationMs,
    }).timeout(_netTimeout);
  }
}

final groupRepositoryProvider = Provider<GroupRepository>((ref) => GroupRepository());
