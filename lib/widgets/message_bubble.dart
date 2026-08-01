import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/chat_message.dart';
import '../theme.dart';

class MessageBubble extends StatelessWidget {
  final ChatMessage message;

  const MessageBubble({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    final isOutgoing = message.role == 'user';
    return Align(
      alignment: isOutgoing ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
        decoration: BoxDecoration(
          color: isOutgoing ? AppColors.bubbleOut : AppColors.bubbleIn,
          borderRadius: BorderRadius.circular(8),
          boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 1, offset: Offset(0, 1))],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message.content, style: const TextStyle(color: AppColors.text)),
            const SizedBox(height: 2),
            Text(
              DateFormat.Hm().format(message.createdAt),
              style: const TextStyle(color: AppColors.textSoft, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}
