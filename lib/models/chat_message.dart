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
  // Cognitive Commerce (Swiggy MCP): the "want me to order?" card the
  // backend attaches to a reply, as raw JSON (id/server/need/items) --
  // ActionCard renders it generically. Unlike localImage, this DOES
  // round-trip through toJson()/fromJson(): a suggestion should still be
  // tappable after an app restart, not just for the rest of the current
  // session. The backend's own resolved_at guard (see
  // commerce/swiggy_adapter.py confirm_action/dismiss_action) is what
  // actually prevents acting twice on a stale/already-resolved card --
  // this field is just display data, never trusted as proof an action is
  // still valid.
  final Map<String, dynamic>? actionCard;

  ChatMessage({
    required this.role,
    required this.content,
    required this.createdAt,
    this.replyToPreview,
    this.localImage,
    this.actionCard,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
        role: json['role'],
        content: json['content'],
        createdAt: DateTime.parse(json['created_at']).toLocal(),
        replyToPreview: json['reply_to_preview'] as String?,
        actionCard: json['action_card'] as Map<String, dynamic>?,
      );

  Map<String, dynamic> toJson() => {
        'role': role,
        'content': content,
        'created_at': createdAt.toUtc().toIso8601String(),
        if (replyToPreview != null) 'reply_to_preview': replyToPreview,
        if (actionCard != null) 'action_card': actionCard,
      };
}
