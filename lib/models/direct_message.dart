enum TickState { sent, delivered, read }

class DirectMessage {
  final int id;
  final int senderId;
  final int recipientId;
  final String content;
  final DateTime createdAt;
  final DateTime? deliveredAt;
  final DateTime? readAt;
  // Object storage (Cloudflare R2) attachment -- see MEDIA_STORAGE_PLAN.md.
  // All three null on a plain text message; thumbnailDataUrl is a small
  // inline base64 data: URL (never an R2 reference), so it keeps rendering
  // even after attachmentUrl's underlying object expires via an R2 Object
  // Lifecycle Rule.
  final String? attachmentUrl;
  final String? attachmentType;
  final String? thumbnailDataUrl;
  // Cognitive Sharing add-on: a 20-30 word LLM summary of a shared
  // document's content, only ever present when both people in this DM pair
  // have sharing turned on -- see app.py's _generate_attachment_summary.
  // Null for plain text messages, images/videos, and whenever the sharing
  // gate isn't open.
  final String? attachmentSummary;

  DirectMessage({
    required this.id,
    required this.senderId,
    required this.recipientId,
    required this.content,
    required this.createdAt,
    this.deliveredAt,
    this.readAt,
    this.attachmentUrl,
    this.attachmentType,
    this.thumbnailDataUrl,
    this.attachmentSummary,
  });

  bool sentByMe(int myUserId) => senderId == myUserId;

  /// Single tick (sent) -> double grey (delivered) -> double blue (read),
  /// same three states WhatsApp/Telegram show.
  TickState get tickState => readAt != null
      ? TickState.read
      : deliveredAt != null
          ? TickState.delivered
          : TickState.sent;

  DirectMessage copyWith({DateTime? deliveredAt, DateTime? readAt}) => DirectMessage(
        id: id,
        senderId: senderId,
        recipientId: recipientId,
        content: content,
        createdAt: createdAt,
        deliveredAt: deliveredAt ?? this.deliveredAt,
        readAt: readAt ?? this.readAt,
        attachmentUrl: attachmentUrl,
        attachmentType: attachmentType,
        thumbnailDataUrl: thumbnailDataUrl,
        attachmentSummary: attachmentSummary,
      );

  factory DirectMessage.fromJson(Map<String, dynamic> json) => DirectMessage(
        id: json['id'],
        senderId: json['sender_id'],
        recipientId: json['recipient_id'],
        content: json['content'],
        createdAt: DateTime.parse(json['created_at']).toLocal(),
        deliveredAt: json['delivered_at'] != null ? DateTime.parse(json['delivered_at']).toLocal() : null,
        readAt: json['read_at'] != null ? DateTime.parse(json['read_at']).toLocal() : null,
        // Missing on any message cached before this field existed --
        // Map access for an absent key is null in Dart, not a throw, so
        // old cached JSON deserializes fine with these simply unset.
        attachmentUrl: json['attachment_url'] as String?,
        attachmentType: json['attachment_type'] as String?,
        thumbnailDataUrl: json['thumbnail_data_url'] as String?,
        attachmentSummary: json['attachment_summary'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'sender_id': senderId,
        'recipient_id': recipientId,
        'content': content,
        'created_at': createdAt.toUtc().toIso8601String(),
        'delivered_at': deliveredAt?.toUtc().toIso8601String(),
        'read_at': readAt?.toUtc().toIso8601String(),
        'attachment_url': attachmentUrl,
        'attachment_type': attachmentType,
        'thumbnail_data_url': thumbnailDataUrl,
        'attachment_summary': attachmentSummary,
      };
}
