class Friend {
  final int id;
  final String username;

  Friend({required this.id, required this.username});

  factory Friend.fromJson(Map<String, dynamic> json) =>
      Friend(id: json['id'], username: json['username']);
}

/// A single compiled emoji for whichever 2-hour clock-aligned window has
/// the most recent data -- not a raw per-conversation timeline. See
/// FLUTTER_UPDATE_mood_emoji_and_fcm.md. moodLabel/emoji are both null if
/// nothing's been logged yet today.
class CompiledMood {
  final int friendId;
  final DateTime windowStart;
  final DateTime windowEnd;
  final String? moodLabel;
  final String? emoji;

  CompiledMood({
    required this.friendId,
    required this.windowStart,
    required this.windowEnd,
    required this.moodLabel,
    required this.emoji,
  });

  factory CompiledMood.fromJson(Map<String, dynamic> json) => CompiledMood(
        friendId: json['friend_id'],
        windowStart: DateTime.parse(json['window_start']).toLocal(),
        windowEnd: DateTime.parse(json['window_end']).toLocal(),
        moodLabel: json['mood_label'],
        emoji: json['emoji'],
      );
}
