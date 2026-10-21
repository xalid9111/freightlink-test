import 'message_model.dart';

/// public.chat_groups (migration 0014).
class ChatGroup {
  final String id;
  final String name;
  final String createdBy;
  final DateTime createdAt;

  const ChatGroup({required this.id, required this.name, required this.createdBy, required this.createdAt});

  factory ChatGroup.fromJson(Map<String, dynamic> j) => ChatGroup(
        id: j['id'] as String,
        name: (j['name'] as String?) ?? '',
        createdBy: j['created_by'] as String,
        createdAt: DateTime.tryParse('${j['created_at']}') ?? DateTime.fromMillisecondsSinceEpoch(0),
      );
}

/// public.chat_group_members (migration 0014).
class GroupMember {
  final String groupId;
  final String userId;
  final bool isAdmin;
  final DateTime lastReadAt;
  final DateTime joinedAt;

  const GroupMember({
    required this.groupId,
    required this.userId,
    required this.isAdmin,
    required this.lastReadAt,
    required this.joinedAt,
  });

  factory GroupMember.fromJson(Map<String, dynamic> j) => GroupMember(
        groupId: j['group_id'] as String,
        userId: j['user_id'] as String,
        isAdmin: j['is_admin'] == true,
        lastReadAt: DateTime.tryParse('${j['last_read_at']}') ?? DateTime.fromMillisecondsSinceEpoch(0),
        joinedAt: DateTime.tryParse('${j['joined_at']}') ?? DateTime.fromMillisecondsSinceEpoch(0),
      );
}

/// public.group_messages (migration 0014).
class GroupMessage {
  final String id;
  final String groupId;
  final String senderId;
  final String? message;
  final String? attachmentPath;
  final String? attachmentType;
  final String? attachmentName;
  final int? attachmentSize;
  final int? audioDurationMs;
  final DateTime createdAt;
  /// Set when the sender deleted the message for everyone (0031).
  final DateTime? deletedAt;
  /// Deleted by the founder without a trace (0048): not shown at all.
  final bool deletedSilent;

  const GroupMessage({
    required this.id,
    required this.groupId,
    required this.senderId,
    this.message,
    this.attachmentPath,
    this.attachmentType,
    this.attachmentName,
    this.attachmentSize,
    this.audioDurationMs,
    required this.createdAt,
    this.deletedAt,
    this.deletedSilent = false,
  });

  bool get hasAttachment => attachmentPath != null && attachmentPath!.isNotEmpty;
  bool get isDeleted => deletedAt != null;

  factory GroupMessage.fromJson(Map<String, dynamic> j) => GroupMessage(
        id: j['id'] as String,
        groupId: j['group_id'] as String,
        senderId: j['sender_id'] as String,
        message: j['message'] as String?,
        attachmentPath: j['attachment_path'] as String?,
        attachmentType: j['attachment_type'] as String?,
        attachmentName: j['attachment_name'] as String?,
        attachmentSize: (j['attachment_size'] as num?)?.toInt(),
        audioDurationMs: (j['audio_duration_ms'] as num?)?.toInt(),
        createdAt: DateTime.tryParse('${j['created_at']}') ?? DateTime.now(),
        deletedAt: j['deleted_at'] is String ? DateTime.tryParse(j['deleted_at'] as String) : null,
        deletedSilent: j['deleted_silent'] == true,
      );

  /// Same shape as a 1-to-1 message, so the existing attachment / voice
  /// / location widgets can render group messages unchanged.
  MessageModel asMessage() => MessageModel(
        id: id,
        conversationId: groupId,
        senderId: senderId,
        receiverId: '',
        message: message,
        attachmentPath: attachmentPath,
        attachmentType: attachmentType,
        attachmentName: attachmentName,
        attachmentSize: attachmentSize,
        audioDurationMs: audioDurationMs,
        createdAt: createdAt,
        deletedAt: deletedAt,
        deletedSilent: deletedSilent,
      );
}

/// A user found by name search (for new chats / groups).
class UserHit {
  final String id;
  final String fullName;
  final String? avatarUrl;
  final String? role;

  const UserHit({required this.id, required this.fullName, this.avatarUrl, this.role});

  factory UserHit.fromJson(Map<String, dynamic> j) => UserHit(
        id: j['id'] as String,
        fullName: (j['full_name'] as String?) ?? '',
        avatarUrl: j['avatar_url'] as String?,
        role: j['role'] as String?,
      );

  String get initials {
    final parts = fullName.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    final a = String.fromCharCode(parts.first.runes.first);
    final b = parts.length > 1 ? String.fromCharCode(parts[1].runes.first) : '';
    return (a + b).toUpperCase();
  }
}
