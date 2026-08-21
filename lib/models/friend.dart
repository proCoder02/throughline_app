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

  Map<String, dynamic> toJson() => {
        'id': id,
        'username': username,
        'nickname': nickname,
        'last_call_at': lastCallAt?.toUtc().toIso8601String(),
        'last_call_outgoing': lastCallOutgoing,
        'call_count': callCount,
      };
}

/// One entry in a friend's full call log (FriendProfileScreen) -- see
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

/// My own cognitive-sharing level for one friend, plus whether BOTH
/// directions are currently 'limited' or higher. Deliberately never carries
/// the other side's actual level -- see GET /friends/<id>/cognitive-sharing
/// in app.py, which never returns it either (that itself would leak their
/// privacy posture).
class CognitiveSharingStatus {
  final String myLevel; // 'off' | 'limited' | 'collaborative'
  final bool bothEnabled;

  CognitiveSharingStatus({required this.myLevel, required this.bothEnabled});

  factory CognitiveSharingStatus.fromJson(Map<String, dynamic> json) => CognitiveSharingStatus(
        myLevel: json['my_level'] as String,
        bothEnabled: json['both_enabled'] as bool,
      );
}

/// Phase 2/3 of COGNITIVE_SHARING_INTERVENTION_PLAN.md -- the result of an
/// on-demand "find common ground" request (POST/GET
/// /friends/<id>/cognitive-suggestion). `dismissed` reflects only the
/// viewer's OWN side (dismissed_by_a/dismissed_by_b on the server) --
/// dismissing never affects what the other participant still sees.
class CognitiveSuggestion {
  final int id;
  final String suggestionText;
  final DateTime? createdAt;
  final bool dismissed;

  CognitiveSuggestion({
    required this.id,
    required this.suggestionText,
    required this.createdAt,
    required this.dismissed,
  });

  factory CognitiveSuggestion.fromJson(Map<String, dynamic> json) => CognitiveSuggestion(
        id: json['id'],
        suggestionText: json['suggestion_text'] as String,
        createdAt: json['created_at'] != null ? DateTime.parse(json['created_at']).toLocal() : null,
        dismissed: json['dismissed'] as bool? ?? false,
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
