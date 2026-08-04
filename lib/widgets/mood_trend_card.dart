import 'package:flutter/material.dart';

import '../models/mood_day.dart';
import '../services/mood_service.dart';
import '../theme.dart';

/// Valence-mapped, not just presence/absence -- lets the grid actually read
/// as a mood trend (green = good stretch, warm = a rough one) rather than
/// just "logged or not logged".
const _moodColors = {
  'happy': Color(0xFF20BF6B),
  'excited': Color(0xFF00B894),
  'calm': Color(0xFF00A884),
  'neutral': Color(0xFFB2BEC3),
  'stressed': Color(0xFFE17055),
  'frustrated': Color(0xFFD63031),
  'anxious': Color(0xFFE1B12C),
  'sad': Color(0xFF636E72),
};

Color _colorForMood(String label) => _moodColors[label.toLowerCase()] ?? AppColors.accent;

/// GitHub-contribution-graph-style calendar heatmap of the last 28 days'
/// dominant mood, plus a simple check-in streak -- the highest-leverage
/// "give people a reason to open the app" surface available, since the
/// underlying mood_logs data has been captured all along with nothing ever
/// showing it back to the user. Self-contained: fetches its own data, fails
/// silently to nothing (not an error banner) so a slow/offline mood fetch
/// never blocks or clutters whatever screen embeds this.
class MoodTrendCard extends StatefulWidget {
  const MoodTrendCard({super.key});

  @override
  State<MoodTrendCard> createState() => _MoodTrendCardState();
}

class _MoodTrendCardState extends State<MoodTrendCard> {
  final _service = MoodService();
  MoodHistory? _history;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final history = await _service.history(days: 28);
      if (mounted) setState(() => _history = history);
    } catch (_) {
      // Best-effort -- no mood data yet (brand-new account) or a transient
      // network error both just mean this card quietly doesn't render.
    }
  }

  @override
  Widget build(BuildContext context) {
    final history = _history;
    if (history == null || history.days.isEmpty) return const SizedBox.shrink();

    final byDate = {for (final d in history.days) _dateKey(d.date): d};
    final today = DateTime.now();
    final cells = List.generate(28, (i) {
      final day = today.subtract(Duration(days: 27 - i));
      return byDate[_dateKey(day)];
    });

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Mood trend', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.text)),
              const Spacer(),
              if (history.streak > 1)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: AppColors.accent.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
                  child: Text('🔥 ${history.streak}-day streak',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.accentDark)),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 5,
            runSpacing: 5,
            children: cells.map((d) => _DayCell(day: d)).toList(),
          ),
        ],
      ),
    );
  }

  String _dateKey(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

class _DayCell extends StatelessWidget {
  final MoodDay? day;
  const _DayCell({this.day});

  @override
  Widget build(BuildContext context) {
    final color = day != null ? _colorForMood(day!.moodLabel) : AppColors.bgApp;
    return Tooltip(
      message: day != null
          ? '${day!.date.month}/${day!.date.day}: ${day!.moodLabel} ${day!.emoji}'
          : '',
      child: Container(
        width: 16,
        height: 16,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(4),
          border: day == null ? Border.all(color: AppColors.border) : null,
        ),
      ),
    );
  }
}
