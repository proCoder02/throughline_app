import 'dart:ui';

import 'package:flutter/material.dart';

import '../theme.dart';

/// Rounded pill chip for a single horizontally-scrolling row (see
/// chat_thread_screen.dart's topics/questions/speaker strips) -- single
/// line, ellipsis-truncated rather than wrapping, matching how Gmail/
/// Instagram/Messenger all render this kind of "AI noticed something"
/// suggestion chip. A fixed-height scrolling row only works if every chip
/// in it has a predictable height, which a wrapping label can't guarantee.
class TagChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final VoidCallback onDismiss;
  // Lets callers visually tell apart chips with different meanings (e.g.
  // topic keywords vs. tappable follow-up questions) without a second
  // near-identical widget -- both default to the original plain look.
  final Color? backgroundColor;
  final Color? borderColor;

  const TagChip({
    super.key,
    required this.label,
    required this.onTap,
    required this.onDismiss,
    this.backgroundColor,
    this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    // Genuine glass, not just a low-alpha color -- these now float directly
    // over the scrolling message list (see chat_thread_screen.dart's Stack
    // overlay), and a flat semi-transparent fill still read as fairly
    // opaque. A blur + a much lighter tint (same technique as IslandNavBar/
    // the rename panel) actually lets message text show through legibly.
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: onTap,
            child: Container(
              constraints: const BoxConstraints(maxWidth: 220),
              padding: const EdgeInsets.only(left: 12, right: 6, top: 6, bottom: 6),
              decoration: BoxDecoration(
                color: backgroundColor ?? AppColors.panel.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: borderColor ?? AppColors.border.withValues(alpha: 0.5)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: AppColors.text, fontSize: 13),
                    ),
                  ),
                  InkWell(
                    onTap: onDismiss,
                    child: Padding(
                      padding: const EdgeInsets.only(left: 4),
                      child: Icon(Icons.close, size: 14, color: AppColors.textSoft),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
