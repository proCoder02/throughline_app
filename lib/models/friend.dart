class Friend {
  final int id;
  final String username;

  Friend({required this.id, required this.username});

  factory Friend.fromJson(Map<String, dynamic> json) =>
      Friend(id: json['id'], username: json['username']);
}

class MoodEntry {
  final String moodLabel;
  final double moodScore;
  final DateTime createdAt;

  MoodEntry({required this.moodLabel, required this.moodScore, required this.createdAt});

  factory MoodEntry.fromJson(Map<String, dynamic> json) => MoodEntry(
        moodLabel: json['mood_label'],
        moodScore: (json['mood_score'] as num).toDouble(),
        createdAt: DateTime.parse(json['created_at']).toLocal(),
      );
}
