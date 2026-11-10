import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../../theme.dart';

/// Glass look for the Work section, built on Flutter's own BackdropFilter
/// (what the `glassmorphism` package wraps) rather than a dependency.
///
/// Real blur is costly on mid-range phones, so it's used only on fixed
/// chrome (bottom bar, sheets). Scrolling cards use [Frosted]: a see-through
/// fill, a light top edge and a soft shadow, which reads as glass over the
/// [WorkBackdrop] at no blur cost.

bool get _dark => isAppDarkMode;

/// The page behind everything: the app's warm gradient plus a few soft
/// colour glows, so translucent surfaces have something to show through.
/// Painted once (radial gradients, no blur filter) and cached.
class WorkBackdrop extends StatelessWidget {
  final Widget child;
  const WorkBackdrop({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    Widget glow(Alignment at, Color c, double size) => Align(
          alignment: at,
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(colors: [c.withValues(alpha: _dark ? 0.22 : 0.38), c.withValues(alpha: 0)]),
            ),
          ),
        );
    return Stack(children: [
      Positioned.fill(
        child: RepaintBoundary(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: AppColors.dmGradient),
            ),
            child: Stack(children: [
              glow(const Alignment(-1.3, -1.0), const Color(0xFFF2A65A), 420),
              glow(const Alignment(1.4, -0.2), const Color(0xFFB79CF0), 380),
              glow(const Alignment(-0.6, 1.25), const Color(0xFF7FC8B0), 400),
            ]),
          ),
        ),
      ),
      child,
    ]);
  }
}

/// Fill, edge and shadow shared by every glass surface.
BoxDecoration glassDecoration({double radius = 20, double strength = 1}) => BoxDecoration(
      borderRadius: BorderRadius.circular(radius),
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: _dark
            ? [Colors.white.withValues(alpha: 0.09 * strength), Colors.white.withValues(alpha: 0.04 * strength)]
            : [Colors.white.withValues(alpha: 0.78 * strength), Colors.white.withValues(alpha: 0.52 * strength)],
      ),
      border: Border.all(color: Colors.white.withValues(alpha: _dark ? 0.10 : 0.70), width: 1),
      boxShadow: [
        BoxShadow(
          color: (_dark ? Colors.black : const Color(0xFF8A5A2B)).withValues(alpha: _dark ? 0.30 : 0.10),
          blurRadius: 24,
          offset: const Offset(0, 8),
        ),
      ],
    );

/// A frosted card: glass look without a live blur (cheap in long lists).
class Frosted extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsets padding;
  final double radius;
  final Color? accent; // a status colour shown as a slim bar on the left

  const Frosted({super.key, required this.child, this.onTap, this.padding = const EdgeInsets.all(14), this.radius = 20, this.accent});

  @override
  Widget build(BuildContext context) {
    Widget content = Padding(padding: padding, child: child);
    if (accent != null) {
      content = Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 4,
          height: 34,
          margin: EdgeInsets.only(left: padding.left, top: padding.top + 2),
          decoration: BoxDecoration(color: accent, borderRadius: BorderRadius.circular(4)),
        ),
        Expanded(child: Padding(padding: padding.copyWith(left: 12), child: child)),
      ]);
    }
    return Semantics(
      button: onTap != null,
      child: Container(
        decoration: glassDecoration(radius: radius),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(borderRadius: BorderRadius.circular(radius), onTap: onTap, child: content),
        ),
      ),
    );
  }
}

/// A real blurred-glass panel, for fixed chrome only.
class GlassPanel extends StatelessWidget {
  final Widget child;
  final double radius;
  final double blur;
  final EdgeInsets padding;
  const GlassPanel({super.key, required this.child, this.radius = 28, this.blur = 18, this.padding = EdgeInsets.zero});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        boxShadow: glassDecoration(radius: radius).boxShadow,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          child: Container(
            padding: padding,
            decoration: glassDecoration(radius: radius, strength: 0.9).copyWith(boxShadow: const []),
            child: child,
          ),
        ),
      ),
    );
  }
}

class GlassNavItem {
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final int badge;
  const GlassNavItem(this.icon, this.selectedIcon, this.label, {this.badge = 0});
}

/// Floating, blurred bottom bar for the Work tabs.
class GlassNavBar extends StatelessWidget {
  final int index;
  final List<GlassNavItem> items;
  final ValueChanged<int> onTap;
  const GlassNavBar({super.key, required this.index, required this.items, required this.onTap});

  /// Space a scrolling list needs at its end so its last item clears the bar.
  static const clearance = 96.0;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: GlassPanel(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          child: Row(children: [
            for (var i = 0; i < items.length; i++) Expanded(child: _NavButton(item: items[i], selected: i == index, onTap: () => onTap(i))),
          ]),
        ),
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  final GlassNavItem item;
  final bool selected;
  final VoidCallback onTap;
  const _NavButton({required this.item, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.dmAccentDark : AppColors.dmText.withValues(alpha: 0.75);
    final icon = Icon(selected ? item.selectedIcon : item.icon, color: selected ? AppColors.dmAccentDark : color, size: 24);
    return Semantics(
      button: true,
      selected: selected,
      label: item.badge > 0 ? '${item.label}, ${item.badge} unread' : item.label,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 52),
          child: Column(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              decoration: BoxDecoration(
                color: selected ? AppColors.dmAccent.withValues(alpha: 0.22) : Colors.transparent,
                borderRadius: BorderRadius.circular(16),
              ),
              child: item.badge > 0
                  ? Badge(label: Text(item.badge > 99 ? '99+' : '${item.badge}'), backgroundColor: AppColors.unreadBadge, child: icon)
                  : icon,
            ),
            const SizedBox(height: 3),
            // Long labels ("Commitments") shrink to fit narrow phones instead of being cut off.
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(item.label,
                  maxLines: 1, style: TextStyle(fontSize: 12, fontWeight: selected ? FontWeight.w800 : FontWeight.w600, color: color)),
            ),
          ]),
        ),
      ),
    );
  }
}
