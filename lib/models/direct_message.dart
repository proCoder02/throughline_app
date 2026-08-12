enum TickState { sent, delivered, read }

class DirectMessage {
  final int id;
  final int senderId;
  final int recipientId;
  final String content;
  final DateTime createdAt;
  final DateTime? deliveredAt;
  final DateTime? readAt;

  DirectMessage({
    required this.id,
    required this.senderId,
    required this.recipientId,
    required this.content,
    required this.createdAt,
    this.deliveredAt,
    this.readAt,
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
      );

  factory DirectMessage.fromJson(Map<String, dynamic> json) => DirectMessage(
        id: json['id'],
        senderId: json['sender_id'],
        recipientId: json['recipient_id'],
        content: json['content'],
        createdAt: DateTime.parse(json['created_at']).toLocal(),
        deliveredAt: json['delivered_at'] != null ? DateTime.parse(json['delivered_at']).toLocal() : null,
        readAt: json['read_at'] != null ? DateTime.parse(json['read_at']).toLocal() : null,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'sender_id': senderId,
        'recipient_id': recipientId,
        'content': content,
        'created_at': createdAt.toUtc().toIso8601String(),
        'delivered_at': deliveredAt?.toUtc().toIso8601String(),
        'read_at': readAt?.toUtc().toIso8601String(),
      };
}
