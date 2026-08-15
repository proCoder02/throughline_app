import 'package:flutter/material.dart';

import '../models/weekly_digest.dart';
import '../screens/insights/digest_screen.dart';
import '../services/digest_service.dart';
import '../theme.dart';

/// Permanent home-screen presence for the weekly digest -- built by
/// directly mirroring mood_trend_card.dart's structure (self-contained,
/// fetches its own data, silently hides when there's nothing to show).
/// Embedded in ChatsScreen next to MoodTrendCard: since the digest is
/// expected to rival global chat in usage, it gets the same "give people a
/// reason to open the app" placement rather than living only behind a
/// notification tap (see home_shell.dart's digest_ready case for that
/// second entry point into the same DigestScreen).
class InsightPreviewCard extends StatefulWidget {
  const InsightPreviewCard({super.key});

  @override
  State<InsightPreviewCard> createState() => _InsightPreviewCardState();
}

class _InsightPreviewCardState extends State<InsightPreviewCard> {
  final _service = DigestService();
  WeeklyDigest? _digest;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final digest = await _service.fetch();
      if (mounted) setState(() => _digest = digest);
    } catch (_) {
      // Best-effort -- no digest yet, or a transient network error, both
      // just mean this card quietly doesn't render.
    }
  }

  @override
  Widget build(BuildContext context) {
    final digest = _digest;
    if (digest == null || digest.cards.isEmpty) return const SizedBox.shrink();

    return GestureDetector(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const DigestScreen()),
      ),
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 4, 12, 4),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.panel,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(color: AppColors.accent, borderRadius: BorderRadius.circular(11)),
              child: const Icon(Icons.auto_awesome, color: Colors.white, size: 17),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Weekly insight', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.text)),
                  const SizedBox(height: 2),
                  Text(
                    digest.cards.first.headline,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12.5, color: AppColors.textSoft),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(Icons.chevron_right, color: AppColors.railIcon, size: 20),
          ],
        ),
      ),
    );
  }
}
