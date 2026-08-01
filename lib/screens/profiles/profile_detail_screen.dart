import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/profile.dart';
import '../../theme.dart';
import '../chats/chat_thread_screen.dart';

class ProfileDetailScreen extends StatelessWidget {
  final Profile profile;

  const ProfileDetailScreen({super.key, required this.profile});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(profile.name)),
      body: ListView.separated(
        itemCount: profile.notes.length,
        separatorBuilder: (_, __) => const Divider(height: 1, color: AppColors.border),
        itemBuilder: (context, i) {
          final n = profile.notes[i];
          final category = n.category.isEmpty ? '' : n.category[0].toUpperCase() + n.category.substring(1);
          return ListTile(
            tileColor: AppColors.panel,
            title: Text('$category · ${DateFormat('MMM d, HH:mm').format(n.createdAt)}'),
            subtitle: Text(n.observation),
            trailing: n.conversationId != null
                ? IconButton(
                    icon: const Icon(Icons.chat_bubble_outline, size: 18),
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => ChatThreadScreen(conversationId: n.conversationId!)),
                    ),
                  )
                : null,
          );
        },
      ),
    );
  }
}
