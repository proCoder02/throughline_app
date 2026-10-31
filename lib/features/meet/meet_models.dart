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
  final String method; // bluetooth | qr
  /// While pending: seconds left to tap Share, as of [receivedAt].
  final int? expiresIn;
  final DateTime receivedAt;

  MeetEncounter({
    required this.id,
    required this.status,
    required this.other,
    this.iConfirmed = false,
    this.theyConfirmed = false,
    this.card,
    this.cardHidden = false,
    this.createdAt,
    this.method = 'bluetooth',
    this.expiresIn,
    DateTime? receivedAt,
  }) : receivedAt = receivedAt ?? DateTime.now();

  factory MeetEncounter.fromJson(Map<String, dynamic> j) => MeetEncounter(
        id: j['id'] as int,
        status: j['status'] as String,
        other: MeetPerson.fromJson((j['other'] as Map).cast<String, dynamic>()),
        iConfirmed: (j['i_confirmed'] as bool?) ?? false,
        theyConfirmed: (j['they_confirmed'] as bool?) ?? false,
        card: j['card'] is Map ? MeetCard.fromJson((j['card'] as Map).cast<String, dynamic>()) : null,
        cardHidden: (j['card_hidden'] as bool?) ?? false,
        createdAt: DateTime.tryParse((j['created_at'] as String?) ?? ''),
        method: (j['method'] as String?) ?? 'bluetooth',
        expiresIn: (j['expires_in'] as num?)?.toInt(),
      );

  /// Seconds left to tap Share right now, counted on the server's clock.
  int? secondsLeft([DateTime? now]) {
    final e = expiresIn;
    if (e == null) return null;
    final gone = (now ?? DateTime.now()).difference(receivedAt).inSeconds;
    return (e - gone).clamp(0, e);
  }

  bool get isPending => status == 'pending';
  bool get isShared => status == 'shared';
  bool get isFinished => !isPending;
}

/// A touch seen by this phone: the other phone's code and how strong its
/// signal was (sent to the server, which checks both sides).
class MeetTouch {
  final String code;
  final int rssi;

  const MeetTouch(this.code, this.rssi);
}

/// An on-screen QR code for the QR fallback.
class MeetQr {
  final String token;
  final String payload;
  final Duration expiresIn;

  const MeetQr({required this.token, required this.payload, required this.expiresIn});

  factory MeetQr.fromJson(Map<String, dynamic> j) => MeetQr(
        token: j['token'] as String,
        payload: j['payload'] as String,
        expiresIn: Duration(seconds: (j['expires_in'] as num?)?.toInt() ?? 120),
      );
}

/// Result of reporting "I'm touching code X" (or scanning a QR code).
class MeetSighting {
  final String status; // waiting | matched | too_far | unknown | invalid | limited | expired
  final MeetEncounter? encounter;
  final String? error;

  const MeetSighting(this.status, {this.encounter, this.error});
}
