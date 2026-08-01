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
}

class Profile {
  final String name;
  final List<String> categories;
  final DateTime lastSeen;
  final List<ProfileNote> notes;

  Profile({
    required this.name,
    required this.categories,
    required this.lastSeen,
    required this.notes,
  });

  factory Profile.fromJson(String name, Map<String, dynamic> json) => Profile(
        name: name,
        categories: List<String>.from(json['categories'] ?? const []),
        lastSeen: DateTime.parse(json['last_seen']).toLocal(),
        notes: (json['notes'] as List<dynamic>? ?? const [])
            .map((n) => ProfileNote.fromJson(n))
            .toList(),
      );

  static Map<String, Profile> mapFromJson(Map<String, dynamic> json) =>
      json.map((name, value) => MapEntry(name, Profile.fromJson(name, value)));
}
