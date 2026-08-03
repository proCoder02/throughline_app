/// One match from GET /search -- a conversation whose title/transcript or
/// one of its chat messages matched the query, with a highlighted snippet
/// (backend wraps the matched term in <b>...</b> via Postgres ts_headline).
class SearchResult {
  final int id;
  final DateTime createdAt;
  final String? title;
  final String category;
  final String snippet;

  SearchResult({
    required this.id,
    required this.createdAt,
    required this.title,
    required this.category,
    required this.snippet,
  });

  String get displayTitle => title ?? 'Untitled conversation';

  factory SearchResult.fromJson(Map<String, dynamic> json) => SearchResult(
        id: json['id'],
        createdAt: DateTime.parse(json['created_at']).toLocal(),
        title: json['title'],
        category: json['category'] ?? 'personal',
        snippet: json['snippet'] ?? '',
      );
}
