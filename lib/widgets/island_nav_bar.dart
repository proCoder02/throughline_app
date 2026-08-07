import 'package:flutter/material.dart';

import '../theme.dart';

class IslandNavItem {
  final IconData icon;
  final IconData? activeIcon;
  final String label;
  final int badgeCount;

  const IslandNavItem({
    required this.icon,
    this.activeIcon,
    required this.label,
    this.badgeCount = 0,
  });
}

/// Floating "island" bottom nav: every tab keeps its icon + label visible at
/// all times (matching WhatsApp/Telegram's iOS tab bars -- this deliberately
/// is NOT the icon-only Instagram/Messenger style tried earlier), stacked
/// vertically rather than side-by-side. Vertical stacking only needs the
/// width of whichever of icon/label is wider, not their sum, which is what
/// made an earlier side-by-side version overflow/clip its label into
/// illegibility on a normal 5-tab phone-width slot. All five tabs stay the
/// same fixed width at all times; only a small pill highlight slides behind
/// the selected icon (AnimatedPositioned in a Stack), so there's no per-tab
/// reflow for anything to overflow. Page content still swaps instantly via
/// HomeShell's IndexedStack, so per-tab scroll position/state is preserved
/// exactly as before.
class IslandNavBar extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;
  final List<IslandNavItem> items;

  const IslandNavBar({
    super.key,
    required this.currentIndex,
    required this.onTap,
    required this.items,
  });

  static const _pillWidth = 44.0;
  static const _pillHeight = 30.0;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      minimum: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Container(
        height: 68,
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.panel,
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isAppDarkMode ? 0.4 : 0.12),
              blurRadius: 18,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final slotWidth = constraints.maxWidth / items.length;
            return Stack(
              children: [
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 320),
                  curve: Curves.easeOutCubic,
                  top: 2,
                  left: slotWidth * currentIndex + (slotWidth - _pillWidth) / 2,
                  width: _pillWidth,
                  height: _pillHeight,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: AppColors.railIconActive.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
                Row(
                  children: [
                    for (var i = 0; i < items.length; i++)
                      Expanded(
                        child: _IslandNavItemWidget(
                          item: items[i],
                          selected: i == currentIndex,
                          onTap: () => onTap(i),
                        ),
                      ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _IslandNavItemWidget extends StatelessWidget {
  final IslandNavItem item;
  final bool selected;
  final VoidCallback onTap;

  const _IslandNavItemWidget({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.railIconActive : AppColors.railIcon;
    final icon = Icon(selected ? (item.activeIcon ?? item.icon) : item.icon, color: color, size: 22);

    return Semantics(
      selected: selected,
      button: true,
      label: item.label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: IslandNavBar._pillHeight,
              child: Center(
                child: TweenAnimationBuilder<double>(
                  duration: const Duration(milliseconds: 320),
                  curve: selected ? Curves.easeOutBack : Curves.easeOut,
                  tween: Tween(begin: 1.0, end: selected ? 1.12 : 1.0),
                  builder: (context, scale, child) => Transform.scale(scale: scale, child: child),
                  child: item.badgeCount > 0
                      ? Badge(label: Text('${item.badgeCount}'), child: icon)
                      : icon,
                ),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              item.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
