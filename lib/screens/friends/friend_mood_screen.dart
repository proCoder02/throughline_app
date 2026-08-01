import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/friend.dart';
import '../../services/friend_service.dart';
import '../../theme.dart';

class FriendMoodScreen extends StatefulWidget {
  final Friend friend;

  const FriendMoodScreen({super.key, required this.friend});

  @override
  State<FriendMoodScreen> createState() => _FriendMoodScreenState();
}

class _FriendMoodScreenState extends State<FriendMoodScreen> {
  final _service = FriendService();
  late Future<List<MoodEntry>> _future;

  @override
  void initState() {
    super.initState();
    _future = _service.mood(widget.friend.id);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("${widget.friend.username}'s mood today")),
      body: FutureBuilder<List<MoodEntry>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(child: Text('Failed to load mood: ${snap.error}'));
          }
          final entries = snap.data ?? [];
          if (entries.isEmpty) {
            return const Center(child: Text('No mood entries yet today', style: TextStyle(color: AppColors.textSoft)));
          }
          return ListView.separated(
            itemCount: entries.length,
            separatorBuilder: (_, __) => const Divider(height: 1, color: AppColors.border),
            itemBuilder: (context, i) {
              final e = entries[i];
              return ListTile(
                tileColor: AppColors.panel,
                leading: Text(DateFormat.Hm().format(e.createdAt)),
                title: Text(e.moodLabel),
              );
            },
          );
        },
      ),
    );
  }
}
