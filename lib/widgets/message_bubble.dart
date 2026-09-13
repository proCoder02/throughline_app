import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/chat_message.dart';
import '../theme.dart';
import 'action_card.dart';
import 'formatted_text.dart';
import 'streaming_formatted_text.dart';

class MessageBubble extends StatelessWidget {
  final ChatMessage message;
  // Swipe-to-reply (WhatsApp-style): when provided, wraps the bubble in a
  // Dismissible that never actually dismisses -- swiping just reveals a
  // reply icon and invokes this callback, leaving the message in place.
  final VoidCallback? onReply;

  // True only for the assistant reply that just this-session arrived --
  // the host screen tracks that by identity (see e.g. GlobalChatBody's
  // _streamingMessage) so a message reloaded from history never replays.
  final bool streamIn;
  final VoidCallback? onStreamTick;
  final VoidCallback? onStreamDone;

  const MessageBubble({
    super.key,
    required this.message,
    this.onReply,
    this.streamIn = false,
    this.onStreamTick,
    this.onStreamDone,
  });

  @override
  Widget build(BuildContext context) {
    final isOutgoing = message.role == 'user';
    final bubble = Align(
      alignment: isOutgoing ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
        decoration: BoxDecoration(
          color: isOutgoing ? AppColors.dmBubbleOut : AppColors.dmBubbleIn,
          // Uniform, tail-less rounding -- see direct_message_screen.dart's
          // _MessageBubble for the same treatment on the 1:1 chat screen.
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.dmBubbleBorder),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isAppDarkMode ? 0.22 : 0.05),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (message.replyToPreview != null) ...[
              _ReplyQuote(text: message.replyToPreview!),
              const SizedBox(height: 6),
            ],
            // Session-only -- see ChatMessage.localImage's doc comment. Only
            // ever set for a message sent earlier in the current session,
            // never for one loaded from cache/server.
            if (message.localImage != null) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Image.file(message.localImage!, fit: BoxFit.cover),
              ),
              const SizedBox(height: 6),
            ],
            streamIn
                ? StreamingFormattedText(
                    message.content,
                    style: TextStyle(color: AppColors.dmText),
                    onTick: onStreamTick,
                    onDone: onStreamDone,
                  )
                : FormattedText(message.content, style: TextStyle(color: AppColors.dmText)),
            // Cognitive Commerce (Swiggy MCP) -- only present on an
            // assistant reply that actually found real, orderable results.
            if (message.actionCard != null) ActionCard(card: message.actionCard!),
            const SizedBox(height: 2),
            Text(
              DateFormat.Hm().format(message.createdAt),
              style: TextStyle(color: AppColors.dmTextSoft, fontSize: 11),
            ),
          ],
        ),
      ),
    );

    if (onReply == null) return bubble;

    return Dismissible(
      key: ValueKey('${message.createdAt.microsecondsSinceEpoch}-${message.role}'),
      direction: DismissDirection.startToEnd,
      // Swiping just triggers reply -- the message must never actually be
      // removed, so confirmDismiss always returns false.
      confirmDismiss: (_) async {
        onReply?.call();
        return false;
      },
      background: Container(
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.only(left: 24),
        child: const Icon(Icons.reply, color: AppColors.dmAccent),
      ),
      child: bubble,
    );
  }
}

class _ReplyQuote extends StatelessWidget {
  final String text;

  const _ReplyQuote({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: isAppDarkMode ? 0.18 : 0.05),
        borderRadius: BorderRadius.circular(6),
        border: const Border(left: BorderSide(color: AppColors.dmAccent, width: 3)),
      ),
      child: Text(
        text,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: AppColors.dmTextSoft, fontSize: 12.5),
      ),
    );
  }
}
