/// One event within a synced TV watch session -- see GET /tv/activity.
class TvActivityEvent {
  final DateTime at;
  final String type; // 'power_on' | 'power_off' | 'media_session'
  final String? appPackage;
  final String? mediaTitle;
  final String? playbackState;

  TvActivityEvent({
    required this.at,
    required this.type,
    this.appPackage,
    this.mediaTitle,
    this.playbackState,
  });

  factory TvActivityEvent.fromJson(Map<String, dynamic> json) => TvActivityEvent(
        at: DateTime.parse(json['at']).toLocal(),
        type: json['type'],
        appPackage: json['app_package'],
        mediaTitle: json['media_title'],
        playbackState: json['playback_state'],
      );
}

class TvActivitySession {
  final int id;
  final DateTime startedAt;
  final DateTime? endedAt;
  final List<TvActivityEvent> events;

  TvActivitySession({
    required this.id,
    required this.startedAt,
    this.endedAt,
    required this.events,
  });

  factory TvActivitySession.fromJson(Map<String, dynamic> json) => TvActivitySession(
        id: json['id'],
        startedAt: DateTime.parse(json['started_at']).toLocal(),
        endedAt: json['ended_at'] != null ? DateTime.parse(json['ended_at']).toLocal() : null,
        events: (json['events'] as List? ?? [])
            .map((e) => TvActivityEvent.fromJson(e))
            .toList(),
      );
}

/// One correlated moment -- see GET /tv/activity/correlate.
class TvActivityCorrelation {
  final String type; // 'conversation' | 'task' | 'mood'
  final int id;
  final String label;
  final DateTime at;
  final List<String> watching;
  final int eventCount;

  TvActivityCorrelation({
    required this.type,
    required this.id,
    required this.label,
    required this.at,
    required this.watching,
    required this.eventCount,
  });

  factory TvActivityCorrelation.fromJson(Map<String, dynamic> json) => TvActivityCorrelation(
        type: json['type'],
        id: json['id'],
        label: json['label'] ?? '',
        at: DateTime.parse(json['at']).toLocal(),
        watching: (json['watching'] as List? ?? []).cast<String>(),
        eventCount: json['event_count'],
      );
}
