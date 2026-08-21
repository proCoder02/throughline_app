import 'package:flutter/material.dart';

import '../theme.dart';

/// A master switch row -- icon badge + bold title makes it read as the
/// header for a [ToggleGroup] below rather than just another switch.
/// Shared by SettingsScreen's "Smart features" card and
/// FriendProfileScreen's "Cognitive Sharing" card so both use the exact
/// same toggle-switch look (per explicit request to match settings' style)
/// instead of each screen growing its own slightly-different version.
class ToggleParentTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const ToggleParentTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      activeThumbColor: AppColors.accent,
      secondary: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: AppColors.accent.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: AppColors.accent, size: 20),
      ),
      title: Text(title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.text)),
      subtitle: Text(subtitle, style: TextStyle(fontSize: 13, color: AppColors.textSoft)),
      value: value,
      onChanged: onChanged,
    );
  }
}

/// Visually nests its children under the parent switch above: indented,
/// with a left "rail" connecting them back to it -- the same tree
/// convention used in Notion/Linear-style settings for "this group is
/// governed by that switch."
class ToggleGroup extends StatelessWidget {
  final List<Widget> children;

  const ToggleGroup({super.key, required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(left: 18, top: 2),
      padding: const EdgeInsets.only(left: 14),
      decoration: BoxDecoration(border: Border(left: BorderSide(color: AppColors.border, width: 2))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
    );
  }
}

/// One row inside a [ToggleGroup] -- deliberately smaller/lighter than
/// [ToggleParentTile] (dense layout, regular weight, smaller type) so the
/// typographic hierarchy alone signals "child of the switch above."
///
/// `enabled: false` passes `onChanged: null` to SwitchListTile, which
/// Flutter renders as a non-interactive, greyed-out row on its own -- no
/// extra disabled-state styling needed.
class ToggleChildTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool value;
  final bool enabled;
  final ValueChanged<bool> onChanged;
  final bool isLast;

  const ToggleChildTile({
    super.key,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
    this.enabled = true,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : 2),
      child: SwitchListTile(
        dense: true,
        contentPadding: EdgeInsets.zero,
        activeThumbColor: AppColors.accent,
        title: Text(title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: AppColors.text)),
        subtitle: Text(subtitle, style: TextStyle(fontSize: 12, color: AppColors.textSoft)),
        value: value,
        onChanged: enabled ? onChanged : null,
      ),
    );
  }
}
