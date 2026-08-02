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
  late Future<CompiledMood> _future;

  @override
  void initState() {
    super.initState();
    _future = _service.mood(widget.friend.id);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("${widget.friend.username}'s mood")),
      body: FutureBuilder<CompiledMood>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(child: Text('Failed to load mood: ${snap.error}'));
          }
          final mood = snap.data;
          if (mood?.emoji == null) {
            return const Center(child: Text('No mood data logged yet today', style: TextStyle(color: AppColors.textSoft)));
          }
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(mood!.emoji!, style: const TextStyle(fontSize: 64)),
                const SizedBox(height: 8),
                Text(
                  mood.moodLabel![0].toUpperCase() + mood.moodLabel!.substring(1),
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: AppColors.text),
                ),
                const SizedBox(height: 4),
                Text(
                  'As of ${DateFormat.Hm().format(mood.windowStart)}–${DateFormat.Hm().format(mood.windowEnd)}',
                  style: const TextStyle(fontSize: 12.5, color: AppColors.textSoft),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
