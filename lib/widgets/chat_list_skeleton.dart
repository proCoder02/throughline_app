import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

import '../theme.dart';

/// Placeholder rows shaped like _ChatRow (chats_screen.dart) -- shown only
/// on a true cold start (no local cache yet) instead of a blank spinner.
/// Once anything is cached, load is already instant and this never appears.
class ChatListSkeleton extends StatelessWidget {
  final int rowCount;

  const ChatListSkeleton({super.key, this.rowCount = 8});

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: AppColors.border,
      highlightColor: AppColors.panel,
      child: ListView.separated(
        itemCount: rowCount,
        separatorBuilder: (_, __) => const Divider(height: 1, color: AppColors.border, indent: 78),
        itemBuilder: (_, __) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const CircleAvatar(radius: 22, backgroundColor: Colors.white),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(height: 14, width: 160, color: Colors.white),
                    const SizedBox(height: 8),
                    Container(height: 12, width: 90, color: Colors.white),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Placeholder chat bubbles for chat_thread_screen.dart/global_chat_screen.dart's
/// initial (no-cache) load -- alternates sides like a real exchange.
class MessageListSkeleton extends StatelessWidget {
  final int itemCount;

  const MessageListSkeleton({super.key, this.itemCount = 6});

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: AppColors.border,
      highlightColor: AppColors.panel,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: itemCount,
        itemBuilder: (_, i) => Align(
          alignment: i.isEven ? Alignment.centerLeft : Alignment.centerRight,
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
            height: 36,
            width: 160 + (i % 3) * 40,
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8)),
          ),
        ),
      ),
    );
  }
}
