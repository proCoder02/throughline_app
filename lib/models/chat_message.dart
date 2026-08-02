class ChatMessage {
  final String role; // "user" | "assistant"
  final String content;
  final DateTime createdAt;

  ChatMessage({required this.role, required this.content, required this.createdAt});

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
        role: json['role'],
        content: json['content'],
        createdAt: DateTime.parse(json['created_at']).toLocal(),
      );

  Map<String, dynamic> toJson() => {
        'role': role,
        'content': content,
        'created_at': createdAt.toUtc().toIso8601String(),
      };
}
