import 'dart:io';

class ChatMessage {
  final String role; // "user" | "assistant"
  final String content;
  final DateTime createdAt;
  // Short quoted snippet of the message this one was sent as a reply to --
  // a client-side compose-time affordance only (the backend /chat and
  // /chat/global APIs have no message-threading concept), so this is null
  // for anything loaded fresh from the server; it round-trips through the
  // app's own local cache (toJson/fromJson) so it survives a restart for
  // messages sent this session, but won't reappear after a true reload
  // from the server for older history.
  final String? replyToPreview;
  // The image picked for an outgoing image message, for immediate bubble
  // display -- deliberately NOT included in toJson()/fromJson(). The backend
  // never persists raw image bytes (only the vision-extracted text, stored
  // as a regular conversation), so there is nothing to round-trip: this is
  // always null for any message loaded from LocalCache or from the server,
  // and only ever set for a message sent earlier in the current app session.
  final File? localImage;

  ChatMessage({
    required this.role,
    required this.content,
    required this.createdAt,
    this.replyToPreview,
    this.localImage,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
        role: json['role'],
        content: json['content'],
        createdAt: DateTime.parse(json['created_at']).toLocal(),
        replyToPreview: json['reply_to_preview'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'role': role,
        'content': content,
        'created_at': createdAt.toUtc().toIso8601String(),
        if (replyToPreview != null) 'reply_to_preview': replyToPreview,
      };
}
