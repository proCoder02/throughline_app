import 'package:flutter/material.dart';

import '../../models/friend.dart';
import '../../services/friend_service.dart';
import '../../theme.dart';
import '../../utils/call_format.dart';
import 'friend_mood_screen.dart';

/// Per-friend call log (WhatsApp/Telegram-style) -- what tapping a friend
/// row opens. Mood, rename, and remove-friend all live here in the app bar
/// rather than crowding the friends list row itself.
class CallHistoryScreen extends StatefulWidget {
  final Friend friend;

  const CallHistoryScreen({super.key, required this.friend});

  @override
  State<CallHistoryScreen> createState() => _CallHistoryScreenState();
}

class _CallHistoryScreenState extends State<CallHistoryScreen> {
  final _service = FriendService();
  late Future<List<CallHistoryEntry>> _future;
  late Friend _friend;

  @override
  void initState() {
    super.initState();
    _friend = widget.friend;
    _future = _service.callHistory(_friend.id);
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return m > 0 ? '${m}m ${s}s' : '${s}s';
  }

  Future<void> _rename() async {
    final controller = TextEditingController(text: _friend.nickname ?? '');
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Set nickname'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(hintText: _friend.username),
          onSubmitted: (v) => Navigator.of(context).pop(v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.of(context).pop(controller.text), child: const Text('Save')),
        ],
      ),
    );
    if (result == null) return;
    final nickname = await _service.setNickname(_friend.id, result.trim());
    if (!mounted) return;
    setState(() {
      _friend = Friend(
        id: _friend.id,
        username: _friend.username,
        nickname: nickname,
        lastCallAt: _friend.lastCallAt,
        lastCallOutgoing: _friend.lastCallOutgoing,
        callCount: _friend.callCount,
      );
    });
  }

  Future<void> _remove() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove friend'),
        content: Text('Remove ${_friend.displayName} from your friends? This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Remove', style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _service.remove(_friend.id);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_friend.displayName),
        actions: [
          IconButton(
            icon: const Icon(Icons.mood_outlined),
            tooltip: 'Mood',
            onPressed: () =>
                Navigator.of(context).push(MaterialPageRoute(builder: (_) => FriendMoodScreen(friend: _friend))),
          ),
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Set nickname',
            onPressed: _rename,
          ),
          IconButton(
            icon: const Icon(Icons.person_remove_outlined),
            tooltip: 'Remove friend',
            onPressed: _remove,
          ),
        ],
      ),
      body: FutureBuilder<List<CallHistoryEntry>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(child: Text('Failed to load call history: ${snap.error}'));
          }
          final calls = snap.data ?? [];
          if (calls.isEmpty) {
            return const Center(child: Text('No calls yet', style: TextStyle(color: AppColors.textSoft)));
          }
          return ListView.separated(
            itemCount: calls.length,
            separatorBuilder: (_, __) => const Divider(height: 1, color: AppColors.border),
            itemBuilder: (context, i) {
              final c = calls[i];
              final duration = c.endedAt?.difference(c.createdAt);
              return ListTile(
                tileColor: AppColors.panel,
                leading: Icon(
                  c.missed
                      ? Icons.call_missed
                      : (c.outgoing ? Icons.call_made : Icons.call_received),
                  color: c.missed ? AppColors.danger : AppColors.accent,
                ),
                title: Text(
                  c.missed ? 'Missed call' : (c.outgoing ? 'Outgoing' : 'Incoming'),
                  style: c.missed ? const TextStyle(color: AppColors.danger) : null,
                ),
                subtitle: Text(
                  !c.missed && duration != null && duration.inSeconds > 0
                      ? '${formatCallTimestamp(c.createdAt)}  ·  ${_formatDuration(duration)}'
                      : formatCallTimestamp(c.createdAt),
                  style: const TextStyle(color: AppColors.textSoft),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
