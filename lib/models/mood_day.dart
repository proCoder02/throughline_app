/// One calendar day's dominant mood -- see GET /mood/history.
class MoodDay {
  final DateTime date;
  final String moodLabel;
  final String emoji;

  MoodDay({required this.date, required this.moodLabel, required this.emoji});

  factory MoodDay.fromJson(Map<String, dynamic> json) => MoodDay(
        date: DateTime.parse(json['date']),
        moodLabel: json['mood_label'] ?? '',
        emoji: json['emoji'] ?? '',
      );
}

class MoodHistory {
  final List<MoodDay> days;
  final int streak;

  MoodHistory({required this.days, required this.streak});

  factory MoodHistory.fromJson(Map<String, dynamic> json) => MoodHistory(
        days: (json['days'] as List? ?? []).map((j) => MoodDay.fromJson(j)).toList(),
        streak: json['streak'] ?? 0,
      );
}
