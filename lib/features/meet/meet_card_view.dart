import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../theme.dart';
import '../../widgets/avatar.dart';
import 'meet_models.dart';

/// One personality card -- mine (preview) or the person I just met. Reads
/// top to bottom like an introduction: who they are, what they're like,
/// what they're into, how to stay in touch.
class MeetCardView extends StatelessWidget {
  final MeetCard card;
  final MeetPerson person;

  const MeetCardView({super.key, required this.card, required this.person});

  @override
  Widget build(BuildContext context) {
    final where = [card.organization, card.city].where((s) => s.isNotEmpty).join(' · ');
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
          // ---- who I am ----
          Row(
            children: [
              InitialAvatar(name: person.name, imageUrl: person.photo, size: 60),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(person.name, style: appHeadlineFont(color: AppColors.text, fontSize: 20)),
                    if (card.headline.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(card.headline, style: TextStyle(color: AppColors.text, fontSize: 14, fontWeight: FontWeight.w600)),
                    ],
                    if (where.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(where, style: TextStyle(color: AppColors.textSoft, fontSize: 13)),
                    ],
                  ],
                ),
              ),
            ],
          ),
          if (card.education.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Row(
                children: [
                  Icon(Icons.school_outlined, size: 16, color: AppColors.textSoft),
                  const SizedBox(width: 6),
                  Expanded(child: Text(card.education, style: TextStyle(color: AppColors.textSoft, fontSize: 13))),
                ],
              ),
            ),

          // ---- personality ----
          if (card.traits.isNotEmpty || card.style.isNotEmpty) ...[
            const SizedBox(height: 16),
            const _Label('Personality'),
            if (card.traits.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children: [for (final t in card.traits) _Chip(t, strong: true)]),
            ],
            if (card.style.isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                decoration: const BoxDecoration(
                  border: Border(left: BorderSide(color: AppColors.accent, width: 3)),
                ),
                child: Text('“${card.style}”',
                    style: TextStyle(color: AppColors.text, fontSize: 14, fontStyle: FontStyle.italic, height: 1.4)),
              ),
            ],
          ],
          if (card.about.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(card.about, style: TextStyle(color: AppColors.text, fontSize: 15, height: 1.4)),
          ],

          // ---- into ----
          if (card.interests.isNotEmpty) _ChipGroup(title: 'Into', items: card.interests),
          if (card.likes.isNotEmpty) _ChipGroup(title: 'Likes', items: card.likes),

          // ---- stay in touch ----
          if (card.links.isNotEmpty) ...[
            const SizedBox(height: 16),
            const _Label('Stay in touch'),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [for (final l in card.links) _LinkButton(l)]),
          ],
          if (card.isEmpty) ...[
            const SizedBox(height: 16),
            Text('No details on this card yet.', style: TextStyle(color: AppColors.textSoft)),
          ],
        ],
      ),
    );
  }
}

class _Label extends StatelessWidget {
  final String text;

  const _Label(this.text);

  @override
  Widget build(BuildContext context) => Text(text.toUpperCase(),
      style: TextStyle(color: AppColors.textSoft, fontSize: 11, letterSpacing: 0.8, fontWeight: FontWeight.w600));
}

class _Chip extends StatelessWidget {
  final String text;
  final bool strong;

  const _Chip(this.text, {this.strong = false});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.accent.withValues(alpha: strong ? 0.22 : 0.12),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(text,
            style: TextStyle(color: AppColors.text, fontSize: 13, fontWeight: strong ? FontWeight.w600 : FontWeight.normal)),
      );
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
          _Label(title),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [for (final item in items) _Chip(item)]),
        ],
      ),
    );
  }
}

/// A profile link, labelled by site ("LinkedIn", "Instagram", ...).
class _LinkButton extends StatelessWidget {
  final String url;

  const _LinkButton(this.url);

  static (IconData, String) describe(String url) {
    final host = (Uri.tryParse(url)?.host ?? url).toLowerCase().replaceFirst('www.', '');
    if (host.contains('linkedin.')) return (Icons.work_outline, 'LinkedIn');
    if (host.contains('instagram.')) return (Icons.camera_alt_outlined, 'Instagram');
    if (host == 'x.com' || host.contains('twitter.')) return (Icons.alternate_email, 'X');
    if (host.contains('github.')) return (Icons.code, 'GitHub');
    return (Icons.link, host.isEmpty ? 'Link' : host);
  }

  @override
  Widget build(BuildContext context) {
    final (icon, label) = describe(url);
    return OutlinedButton.icon(
      onPressed: () async {
        final uri = Uri.tryParse(url);
        if (uri == null || !await launchUrl(uri, mode: LaunchMode.externalApplication)) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Couldn't open that link.")));
          }
        }
      },
      icon: Icon(icon, size: 16),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.text,
        side: BorderSide(color: AppColors.border),
        shape: const StadiumBorder(),
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}
