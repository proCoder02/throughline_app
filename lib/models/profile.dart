class ProfileNote {
  final String observation;
  final DateTime createdAt;
  final int? conversationId;
  final String category;

  ProfileNote({
    required this.observation,
    required this.createdAt,
    required this.conversationId,
    required this.category,
  });

  factory ProfileNote.fromJson(Map<String, dynamic> json) => ProfileNote(
        observation: json['observation'],
        createdAt: DateTime.parse(json['created_at']).toLocal(),
        conversationId: json['conversation_id'],
        category: json['category'] ?? 'personal',
      );

  Map<String, dynamic> toJson() => {
        'observation': observation,
        'created_at': createdAt.toUtc().toIso8601String(),
        'conversation_id': conversationId,
        'category': category,
      };
}

class Profile {
  final int profileId;
  final String name;
  final List<String> categories;
  final DateTime lastSeen;
  final List<ProfileNote> notes;

  Profile({
    required this.profileId,
    required this.name,
    required this.categories,
    required this.lastSeen,
    required this.notes,
  });

  factory Profile.fromJson(String name, Map<String, dynamic> json) => Profile(
        profileId: json['profile_id'],
        name: name,
        categories: List<String>.from(json['categories'] ?? const []),
        lastSeen: DateTime.parse(json['last_seen']).toLocal(),
        notes: (json['notes'] as List<dynamic>? ?? const [])
            .map((n) => ProfileNote.fromJson(n))
            .toList(),
      );

  static Map<String, Profile> mapFromJson(Map<String, dynamic> json) =>
      json.map((name, value) => MapEntry(name, Profile.fromJson(name, value)));

  Map<String, dynamic> toJson() => {
        'profile_id': profileId,
        'categories': categories,
        'last_seen': lastSeen.toUtc().toIso8601String(),
        'notes': notes.map((n) => n.toJson()).toList(),
      };

  static Map<String, dynamic> mapToJson(Map<String, Profile> profiles) =>
      profiles.map((name, p) => MapEntry(name, p.toJson()));
}
