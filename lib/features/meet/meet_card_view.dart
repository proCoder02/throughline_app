import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../theme.dart';
import '../../widgets/avatar.dart';
import 'meet_models.dart';
import 'meet_style.dart';

/// One personality card, designed for the first 3 seconds.
///
/// Front: the face (hero), name, role, a one-line hook, top 3 traits, what
/// the two of you have in common, and an "ask me about" opener -- one focal
/// point, then at most three small groups. Everything else (how they
/// communicate, about, education, full interests/likes) sits behind
/// "More about …" so the first look stays calm.
class MeetCardView extends StatefulWidget {
  final MeetCard card;
  final MeetPerson person;

  /// Shared interests/likes/traits/city -- only on a card you've received.
  final List<String> inCommon;
  final bool initiallyExpanded;

  const MeetCardView({
    super.key,
    required this.card,
    required this.person,
    this.inCommon = const [],
    this.initiallyExpanded = false,
  });

  @override
  State<MeetCardView> createState() => _MeetCardViewState();
}

class _MeetCardViewState extends State<MeetCardView> {
  static const _frontTraits = 3;
  late bool _expanded = widget.initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    final card = widget.card;
    final person = widget.person;
    final accent = meetColorFor(card.color, person.name);
    final role = [card.headline, card.organization].where((s) => s.isNotEmpty).join(' · ');
    final firstName = person.name.split(RegExp(r'\s+')).first;
    final extraTraits = card.traits.skip(_frontTraits).toList();
    final hasMore = card.style.isNotEmpty ||
        card.about.isNotEmpty ||
        card.education.isNotEmpty ||
        card.interests.isNotEmpty ||
        card.likes.isNotEmpty ||
        extraTraits.isNotEmpty;

    return Container(
      width: double.infinity,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.border),
        boxShadow: [BoxShadow(color: accent.withValues(alpha: 0.18), blurRadius: 24, offset: const Offset(0, 8))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ---- banner + face (the focal point) ----
          SizedBox(
            height: 128,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  height: 84,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [accent, Color.lerp(accent, Colors.white, 0.35)!],
                    ),
                  ),
                ),
                Positioned(
                  left: 20,
                  top: 36,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(color: AppColors.panel, shape: BoxShape.circle),
                    child: InitialAvatar(name: person.name, imageUrl: person.photo, size: 84),
                  ),
                ),
                if (card.links.isNotEmpty)
                  Positioned(
                    right: 16,
                    top: 94,
                    child: Row(children: [for (final l in card.links) _LinkIcon(l, accent)]),
                  ),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(person.name, style: appHeadlineFont(color: AppColors.text, fontSize: 24)),
                if (role.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(role, style: TextStyle(color: AppColors.text, fontSize: 15, fontWeight: FontWeight.w600)),
                ],
                if (card.city.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Row(children: [
                    Icon(Icons.place_outlined, size: 14, color: AppColors.textSoft),
                    const SizedBox(width: 3),
                    Text(card.city, style: TextStyle(color: AppColors.textSoft, fontSize: 13)),
                  ]),
                ],

                // ---- the hook: the line people remember ----
                if (card.hook.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Text(card.hook, style: TextStyle(color: AppColors.text, fontSize: 17, height: 1.35, fontWeight: FontWeight.w500)),
                ],

                if (card.traits.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [for (final t in card.traits.take(_frontTraits)) _TraitPill(t, accent)],
                  ),
                ],

                // ---- what you share: the best conversation starter ----
                if (widget.inCommon.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.handshake_outlined, size: 18, color: accent),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text.rich(
                            TextSpan(children: [
                              TextSpan(text: 'You both · ', style: TextStyle(color: AppColors.textSoft)),
                              TextSpan(text: widget.inCommon.join(', '), style: TextStyle(color: AppColors.text, fontWeight: FontWeight.w600)),
                            ]),
                            style: const TextStyle(fontSize: 14, height: 1.35),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                if (card.askMe.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.chat_bubble_outline, size: 17, color: accent),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text.rich(
                          TextSpan(children: [
                            TextSpan(text: 'Ask me about ', style: TextStyle(color: AppColors.textSoft)),
                            TextSpan(text: card.askMe, style: TextStyle(color: AppColors.text, fontWeight: FontWeight.w600)),
                          ]),
                          style: const TextStyle(fontSize: 14, height: 1.35),
                        ),
                      ),
                    ],
                  ),
                ],

                // ---- details, one tap away ----
                if (hasMore) ...[
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: () => setState(() => _expanded = !_expanded),
                    style: TextButton.styleFrom(padding: EdgeInsets.zero, foregroundColor: AppColors.textSoft),
                    icon: AnimatedRotation(
                      turns: _expanded ? 0.5 : 0,
                      duration: const Duration(milliseconds: 200),
                      child: const Icon(Icons.expand_more, size: 20),
                    ),
                    label: Text(_expanded ? 'Less' : 'More about $firstName'),
                  ),
                  AnimatedSize(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOut,
                    alignment: Alignment.topCenter,
                    child: _expanded ? _more(card, extraTraits, accent) : const SizedBox(width: double.infinity),
                  ),
                ],
                if (card.isEmpty) ...[
                  const SizedBox(height: 12),
                  Text('No details on this card yet.', style: TextStyle(color: AppColors.textSoft)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _more(MeetCard card, List<String> extraTraits, Color accent) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (card.style.isNotEmpty) ...[
          const SizedBox(height: 4),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
            decoration: BoxDecoration(border: Border(left: BorderSide(color: accent, width: 3))),
            child: Text('“${card.style}”',
                style: TextStyle(color: AppColors.text, fontSize: 14, fontStyle: FontStyle.italic, height: 1.4)),
          ),
        ],
        if (card.about.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(card.about, style: TextStyle(color: AppColors.text, fontSize: 14, height: 1.45)),
        ],
        if (card.education.isNotEmpty) ...[
          const SizedBox(height: 12),
          Row(children: [
            Icon(Icons.school_outlined, size: 16, color: AppColors.textSoft),
            const SizedBox(width: 6),
            Expanded(child: Text(card.education, style: TextStyle(color: AppColors.textSoft, fontSize: 13))),
          ]),
        ],
        if (extraTraits.isNotEmpty) _ChipGroup(title: 'Also', items: extraTraits),
        if (card.interests.isNotEmpty) _ChipGroup(title: 'Into', items: card.interests),
        if (card.likes.isNotEmpty) _ChipGroup(title: 'Likes', items: card.likes),
      ],
    );
  }
}

class _TraitPill extends StatelessWidget {
  final String text;
  final Color accent;

  const _TraitPill(this.text, this.accent);

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: accent.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: accent.withValues(alpha: 0.35)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text('✦ ', style: TextStyle(color: accent, fontSize: 12)),
          Text(text, style: TextStyle(color: AppColors.text, fontSize: 13, fontWeight: FontWeight.w600)),
        ]),
      );
}

class _ChipGroup extends StatelessWidget {
  final String title;
  final List<String> items;

  const _ChipGroup({required this.title, required this.items});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(color: AppColors.textSoft, fontSize: 12, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final item in items)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(color: AppColors.border.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(999)),
                  child: Text(item, style: TextStyle(color: AppColors.text, fontSize: 12.5)),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A profile link as a small round icon (LinkedIn, Instagram, ...).
class _LinkIcon extends StatelessWidget {
  final String url;
  final Color accent;

  const _LinkIcon(this.url, this.accent);

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
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: Tooltip(
        message: label,
        child: Material(
          color: AppColors.panel,
          shape: CircleBorder(side: BorderSide(color: accent.withValues(alpha: 0.4))),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: () async {
              final uri = Uri.tryParse(url);
              if (uri == null || !await launchUrl(uri, mode: LaunchMode.externalApplication)) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Couldn't open that link.")));
                }
              }
            },
            child: Padding(padding: const EdgeInsets.all(8), child: Icon(icon, size: 18, color: accent, semanticLabel: label)),
          ),
        ),
      ),
    );
  }
}
