class Conversation {
  final int id;
  final DateTime createdAt;
  final String? title;
  final String category;
  final String? rawTranscript;

  Conversation({
    required this.id,
    required this.createdAt,
    required this.title,
    required this.category,
    this.rawTranscript,
  });

  String get displayTitle => title ?? 'Untitled conversation';

  factory Conversation.fromJson(Map<String, dynamic> json) => Conversation(
        id: json['id'],
        createdAt: DateTime.parse(json['created_at']).toLocal(),
        title: json['title'],
        category: json['category'] ?? 'personal',
        rawTranscript: json['raw_transcript'],
      );
}
