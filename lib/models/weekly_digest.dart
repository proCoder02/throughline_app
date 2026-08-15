/// One "here's what I've noticed about you" card -- see
/// emotional_intelligence/weekly_digest.py for how these get generated.
/// No "world" (real-world news/trend suggestion) section yet -- deferred,
/// see WEEKLY_DIGEST_BRAINSTORM.md -- so this model only carries the
/// insight half for now.
class DigestCard {
  final String category; // "preference" | "fact" | "mood" | "personality" | "relationship"
  final String label;
  final String headline;
  final String body;

  DigestCard({
    required this.category,
    required this.label,
    required this.headline,
    required this.body,
  });

  factory DigestCard.fromJson(Map<String, dynamic> json) => DigestCard(
        category: json['category'] ?? '',
        label: json['label'] ?? '',
        headline: json['headline'] ?? '',
        body: json['body'] ?? '',
      );
}

class WeeklyDigest {
  final List<DigestCard> cards;
  final DateTime generatedAt;

  WeeklyDigest({required this.cards, required this.generatedAt});

  factory WeeklyDigest.fromJson(Map<String, dynamic> json) => WeeklyDigest(
        cards: (json['cards'] as List? ?? [])
            .map((c) => DigestCard.fromJson(c as Map<String, dynamic>))
            .toList(),
        generatedAt: DateTime.parse(json['generated_at']).toLocal(),
      );
}
