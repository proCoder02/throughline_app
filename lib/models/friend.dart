class Friend {
  final int id;
  final String username;
  final String? nickname;
  final DateTime? lastCallAt;
  final bool? lastCallOutgoing;
  final int callCount;

  Friend({
    required this.id,
    required this.username,
    this.nickname,
    this.lastCallAt,
    this.lastCallOutgoing,
    this.callCount = 0,
  });

  /// Your own private alias for this friend, falling back to their
  /// username when unset -- matches the web client's `nickname || username`.
  String get displayName => (nickname != null && nickname!.isNotEmpty) ? nickname! : username;

  factory Friend.fromJson(Map<String, dynamic> json) => Friend(
        id: json['id'],
        username: json['username'],
        nickname: json['nickname'] as String?,
        lastCallAt: json['last_call_at'] != null ? DateTime.parse(json['last_call_at']).toLocal() : null,
        lastCallOutgoing: json['last_call_outgoing'] as bool?,
        callCount: json['call_count'] ?? 0,
      );
}

/// One entry in a friend's full call log (CallHistoryScreen) -- see
/// GET /friends/<id>/calls.
class CallHistoryEntry {
  final int callId;
  final DateTime createdAt;
  final DateTime? endedAt;
  final String status;
  final bool outgoing;
  final String myStatus; // call_participants.status for me: invited/joined/declined/left

  CallHistoryEntry({
    required this.callId,
    required this.createdAt,
    required this.endedAt,
    required this.status,
    required this.outgoing,
    required this.myStatus,
  });

  /// An incoming call I never actually joined (timed out unanswered, or I
  /// explicitly declined) -- WhatsApp/Telegram both surface either case the
  /// same way in the call log.
  bool get missed => !outgoing && myStatus != 'joined';

  factory CallHistoryEntry.fromJson(Map<String, dynamic> json) => CallHistoryEntry(
        callId: json['call_id'],
        createdAt: DateTime.parse(json['created_at']).toLocal(),
        endedAt: json['ended_at'] != null ? DateTime.parse(json['ended_at']).toLocal() : null,
        status: json['status'],
        outgoing: json['outgoing'] as bool,
        myStatus: json['my_status'] ?? 'invited',
      );
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
