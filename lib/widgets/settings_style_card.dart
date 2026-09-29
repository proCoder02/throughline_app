import 'package:flutter/material.dart';

import '../theme.dart';

/// The bordered dmBubbleIn card look used by Settings' own sections --
/// pulled out into a shared widget instead of being duplicated (Settings
/// had its own private _SettingsCard, FriendProfile had a second,
/// hand-copied _ProfileCard with the exact same chrome, kept in sync only
/// by whoever remembered to copy changes across both -- see this session's
/// UX audit). Both now use this one.
class SettingsStyleCard extends StatelessWidget {
  final String? title;
  final String? subtitle;
  final List<Widget> children;

  const SettingsStyleCard({super.key, this.title, this.subtitle, required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.dmBubbleIn,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.dmBubbleBorder),
      ),
      // Material ancestor required -- any ListTile/InkWell child (radio
      // rows, toggle switches, action rows) paints its own background/ink
      // via Ink, which is otherwise invisible (and throws a debug warning)
      // inside a plain, non-Material Container.
      child: Material(
        type: MaterialType.transparency,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (title != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child:
                      Text(title!, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.dmText)),
                ),
              if (subtitle != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Text(subtitle!, style: TextStyle(fontSize: 13, color: AppColors.dmTextSoft)),
                ),
              ...children,
            ],
          ),
        ),
      ),
    );
  }
}
