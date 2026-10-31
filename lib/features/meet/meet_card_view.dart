import 'package:flutter/material.dart';

import '../../theme.dart';
import '../../widgets/avatar.dart';
import 'meet_models.dart';

/// One personality card -- mine (preview) or the person I just met.
class MeetCardView extends StatelessWidget {
  final MeetCard card;
  final MeetPerson person;

  const MeetCardView({super.key, required this.card, required this.person});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              InitialAvatar(name: person.name, imageUrl: person.photo, size: 56),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(person.name, style: appHeadlineFont(color: AppColors.text, fontSize: 20)),
                    if (card.headline.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(card.headline, style: TextStyle(color: AppColors.textSoft, fontSize: 14)),
                    ],
                  ],
                ),
              ),
            ],
          ),
          if (card.about.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(card.about, style: TextStyle(color: AppColors.text, fontSize: 15, height: 1.4)),
          ],
          if (card.interests.isNotEmpty) _ChipGroup(title: 'Into', items: card.interests),
          if (card.likes.isNotEmpty) _ChipGroup(title: 'Likes', items: card.likes),
          if (card.isEmpty) ...[
            const SizedBox(height: 16),
            Text('No details on this card yet.', style: TextStyle(color: AppColors.textSoft)),
          ],
        ],
      ),
    );
  }
}

class _ChipGroup extends StatelessWidget {
  final String title;
  final List<String> items;

  const _ChipGroup({required this.title, required this.items});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title.toUpperCase(),
              style: TextStyle(color: AppColors.textSoft, fontSize: 11, letterSpacing: 0.8, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final item in items)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(item, style: TextStyle(color: AppColors.text, fontSize: 13)),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
