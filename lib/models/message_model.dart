class ConversationModel {
  final String id;
  final String? cargoId;
  final String? shipmentId;
  final String cargoOwnerId;
  final String carrierUserId;
  final DateTime createdAt;

  ConversationModel({
    required this.id,
    this.cargoId,
    this.shipmentId,
    required this.cargoOwnerId,
    required this.carrierUserId,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);

  /// The other participant's user id, from [me]'s point of view.
  String otherParticipant(String me) => me == cargoOwnerId ? carrierUserId : cargoOwnerId;

  factory ConversationModel.fromJson(Map<String, dynamic> j) => ConversationModel(
        id: j['id'] as String,
        cargoId: j['cargo_id'] as String?,
        shipmentId: j['shipment_id'] as String?,
        cargoOwnerId: j['cargo_owner_id'] as String,
        carrierUserId: j['carrier_user_id'] as String,
        createdAt: j['created_at'] is String ? DateTime.tryParse(j['created_at'] as String) : null,
      );
}

class MessageModel {
  final String id;
  final String conversationId;
  final String senderId;
  final String receiverId;
  final String? message;
  final String? attachmentId;
  // Attachment fields from migration 0010 (null on plain text messages,
  // and on every message before that migration runs).
  final String? attachmentPath;
  final String? attachmentType; // 'image' | 'file' | 'audio'
  final String? attachmentName;
  final int? attachmentSize;
  final int? audioDurationMs;
  final DateTime? readAt;
  final DateTime createdAt;
  /// Set when the sender deleted the message for everyone (0031).
  final DateTime? deletedAt;

  bool get hasAttachment => attachmentPath != null && attachmentPath!.isNotEmpty;
  bool get isDeleted => deletedAt != null;

  const MessageModel({
    required this.id,
    required this.conversationId,
    required this.senderId,
    required this.receiverId,
    this.message,
    this.attachmentId,
    this.attachmentPath,
    this.attachmentType,
    this.attachmentName,
    this.attachmentSize,
    this.audioDurationMs,
    this.readAt,
    required this.createdAt,
    this.deletedAt,
  });

  factory MessageModel.fromJson(Map<String, dynamic> j) => MessageModel(
        id: j['id'] as String,
        conversationId: j['conversation_id'] as String,
        senderId: j['sender_id'] as String,
        receiverId: j['receiver_id'] as String,
        message: j['message'] as String?,
        attachmentId: j['attachment_id'] as String?,
        attachmentPath: j['attachment_path'] as String?,
        attachmentType: j['attachment_type'] as String?,
        attachmentName: j['attachment_name'] as String?,
        attachmentSize: (j['attachment_size'] as num?)?.toInt(),
        audioDurationMs: (j['audio_duration_ms'] as num?)?.toInt(),
        readAt: j['read_at'] != null ? DateTime.parse(j['read_at']) : null,
        createdAt: DateTime.parse(j['created_at'] as String),
        deletedAt: j['deleted_at'] is String ? DateTime.tryParse(j['deleted_at'] as String) : null,
      );
}
