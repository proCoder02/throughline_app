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
/// Three parts, like a spoken introduction: who I am (headline/role,
/// organization, city, education), personality (traits, how I communicate,
/// about) and what I'm into / how to stay in touch (interests, likes, links).
class MeetCard {
  final String headline;
  final String organization;
  final String city;
  final String education;
  final String about;
  final String style;
  /// One line people read first ("Builds AI products; happiest on a trail.").
  final String hook;
  /// A conversation starter ("trekking in Ladakh").
  final String askMe;
  /// One of the server's colour names, or '' for "pick from my name".
  final String color;
  final List<String> traits;
  final List<String> interests;
  final List<String> likes;
  final List<String> links;
  final bool sharing;
  final MeetPerson? person;

  const MeetCard({
    this.headline = '',
    this.organization = '',
    this.city = '',
    this.education = '',
    this.about = '',
    this.style = '',
    this.hook = '',
    this.askMe = '',
    this.color = '',
    this.traits = const [],
    this.interests = const [],
    this.likes = const [],
    this.links = const [],
    this.sharing = true,
    this.person,
  });

  static List<String> _list(dynamic v) => (v as List?)?.map((e) => e.toString()).toList() ?? const [];

  factory MeetCard.fromJson(Map<String, dynamic> j) => MeetCard(
        headline: (j['headline'] as String?) ?? '',
        organization: (j['organization'] as String?) ?? '',
        city: (j['city'] as String?) ?? '',
        education: (j['education'] as String?) ?? '',
        about: (j['about'] as String?) ?? '',
        style: (j['style'] as String?) ?? '',
        hook: (j['hook'] as String?) ?? '',
        askMe: (j['ask_me'] as String?) ?? '',
        color: (j['color'] as String?) ?? '',
        traits: _list(j['traits']),
        interests: _list(j['interests']),
        likes: _list(j['likes']),
        links: _list(j['links']),
        sharing: (j['sharing'] as bool?) ?? true,
        person: j['name'] != null ? MeetPerson.fromJson(j) : null,
      );

  Map<String, dynamic> toJson() => {
        'headline': headline,
        'organization': organization,
        'city': city,
        'education': education,
        'about': about,
        'style': style,
        'hook': hook,
        'ask_me': askMe,
        'color': color,
        'traits': traits,
        'interests': interests,
        'likes': likes,
        'links': links,
        'sharing': sharing,
      };

  bool get isEmpty =>
      [headline, organization, city, education, about, style, hook, askMe].every((s) => s.isEmpty) &&
      [traits, interests, likes, links].every((l) => l.isEmpty);
}

class MyMeetCard {
  final bool saved;
  final MeetCard card;
  final MeetPerson me;
  final List<String> traitOptions;
  final List<String> colors;
  final bool canSuggest;

  const MyMeetCard({
    required this.saved,
    required this.card,
    required this.me,
    this.traitOptions = const [],
    this.colors = const [],
    this.canSuggest = false,
  });
}

/// Drafted personality from Throughline -- only ever lands in the editor.
class MeetSuggestion {
  final List<String> traits;
  final String style;

  const MeetSuggestion({this.traits = const [], this.style = ''});
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
  /// What we share (interests, likes, traits, city...), once both shared.
  final List<String> inCommon;
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
    this.inCommon = const [],
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
        inCommon: (j['in_common'] as List?)?.map((e) => e.toString()).toList() ?? const [],
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
