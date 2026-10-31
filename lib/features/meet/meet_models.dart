/// Data shapes for Throughline Meet -- mirrors the backend's meet/ package
/// (see meet/routes.py there for the API).
class MeetPerson {
  final int? id;
  final String name;
  final String? photo;

  const MeetPerson({this.id, required this.name, this.photo});

  factory MeetPerson.fromJson(Map<String, dynamic> j) =>
      MeetPerson(id: j['id'] as int?, name: (j['name'] as String?) ?? 'Someone', photo: j['photo'] as String?);
}

/// My own editable card, or the other person's (then [person] is set).
class MeetCard {
  final String headline;
  final String about;
  final List<String> interests;
  final List<String> likes;
  final bool sharing;
  final MeetPerson? person;

  const MeetCard({
    this.headline = '',
    this.about = '',
    this.interests = const [],
    this.likes = const [],
    this.sharing = true,
    this.person,
  });

  static List<String> _list(dynamic v) => (v as List?)?.map((e) => e.toString()).toList() ?? const [];

  factory MeetCard.fromJson(Map<String, dynamic> j) => MeetCard(
        headline: (j['headline'] as String?) ?? '',
        about: (j['about'] as String?) ?? '',
        interests: _list(j['interests']),
        likes: _list(j['likes']),
        sharing: (j['sharing'] as bool?) ?? true,
        person: j['name'] != null ? MeetPerson.fromJson(j) : null,
      );

  Map<String, dynamic> toJson() =>
      {'headline': headline, 'about': about, 'interests': interests, 'likes': likes, 'sharing': sharing};

  bool get isEmpty => headline.isEmpty && about.isEmpty && interests.isEmpty && likes.isEmpty;
}

class MyMeetCard {
  final bool saved;
  final MeetCard card;
  final MeetPerson me;

  const MyMeetCard({required this.saved, required this.card, required this.me});
}

/// Everything the phone needs to broadcast and judge a "touch" -- tunables
/// come from the server so they can be adjusted without a new app build.
class MeetSession {
  final String code;
  final String serviceUuid;
  final String uuidPrefix;
  final Duration rotateAfter;
  final int rssiThreshold;
  final Duration touchFor;

  const MeetSession({
    required this.code,
    required this.serviceUuid,
    required this.uuidPrefix,
    required this.rotateAfter,
    required this.rssiThreshold,
    required this.touchFor,
  });

  factory MeetSession.fromJson(Map<String, dynamic> j) => MeetSession(
        code: j['code'] as String,
        serviceUuid: j['service_uuid'] as String,
        uuidPrefix: j['uuid_prefix'] as String,
        rotateAfter: Duration(seconds: (j['rotate_after'] as num?)?.toInt() ?? 120),
        rssiThreshold: (j['rssi_threshold'] as num?)?.toInt() ?? -40,
        touchFor: Duration(milliseconds: (j['touch_ms'] as num?)?.toInt() ?? 800),
      );
}

/// pending -> shared | declined | expired | removed
class MeetEncounter {
  final int id;
  final String status;
  final MeetPerson other;
  final bool iConfirmed;
  final bool theyConfirmed;
  final MeetCard? card;
  final bool cardHidden;
  final DateTime? createdAt;

  const MeetEncounter({
    required this.id,
    required this.status,
    required this.other,
    this.iConfirmed = false,
    this.theyConfirmed = false,
    this.card,
    this.cardHidden = false,
    this.createdAt,
  });

  factory MeetEncounter.fromJson(Map<String, dynamic> j) => MeetEncounter(
        id: j['id'] as int,
        status: j['status'] as String,
        other: MeetPerson.fromJson((j['other'] as Map).cast<String, dynamic>()),
        iConfirmed: (j['i_confirmed'] as bool?) ?? false,
        theyConfirmed: (j['they_confirmed'] as bool?) ?? false,
        card: j['card'] is Map ? MeetCard.fromJson((j['card'] as Map).cast<String, dynamic>()) : null,
        cardHidden: (j['card_hidden'] as bool?) ?? false,
        createdAt: DateTime.tryParse((j['created_at'] as String?) ?? ''),
      );

  bool get isPending => status == 'pending';
  bool get isShared => status == 'shared';
  bool get isFinished => !isPending;
}

/// Result of reporting "I'm touching code X".
class MeetSighting {
  final String status; // waiting | matched | unknown | invalid | limited
  final MeetEncounter? encounter;
  final String? error;

  const MeetSighting(this.status, {this.encounter, this.error});
}
