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
  // Zero or more action cards the backend attaches to a reply -- a
  // Cognitive Commerce (Swiggy MCP) "want me to order?" card (raw JSON:
  // id/server/need/items, rendered generically by ActionCard), and/or one
  // per staged tool action (call/email_draft/expense_confirm/message_draft
  // -- see app.py's run_agent_tool_loop). A single request can trigger
  // several of these at once (e.g. "log this expense AND message Kunal
  // about it"), so this is a list, not one card -- collecting only the
  // last one silently dropped every earlier action's card. Unlike
  // localImage, this DOES round-trip through toJson()/fromJson(): a
  // pending card should still be tappable after an app restart, not just
  // for the rest of the current session. Each card's own resolved_at/
  // status guard server-side (e.g. confirm_email_draft, confirm_message_draft)
  // is what actually prevents acting twice on a stale/already-resolved
  // card -- this field is just display data, never trusted as proof an
  // action is still valid.
  final List<Map<String, dynamic>>? actionCards;

  ChatMessage({
    required this.role,
    required this.content,
    required this.createdAt,
    this.replyToPreview,
    this.localImage,
    this.actionCards,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
        role: json['role'],
        content: json['content'],
        createdAt: DateTime.parse(json['created_at']).toLocal(),
        replyToPreview: json['reply_to_preview'] as String?,
        actionCards: (json['action_cards'] as List?)?.map((e) => e as Map<String, dynamic>).toList(),
      );

  Map<String, dynamic> toJson() => {
        'role': role,
        'content': content,
        'created_at': createdAt.toUtc().toIso8601String(),
        if (replyToPreview != null) 'reply_to_preview': replyToPreview,
        if (actionCards != null && actionCards!.isNotEmpty) 'action_cards': actionCards,
      };
}
