import 'package:flutter/material.dart';

import '../theme.dart';

/// Friendlier empty-list placeholder -- icon + short title + softer
/// supporting line, instead of one plain gray sentence. Purely a display
/// widget, no behavior of its own.
class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;

  const EmptyState({super.key, required this.icon, required this.title, this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(color: AppColors.accent.withValues(alpha: 0.10), shape: BoxShape.circle),
              child: Icon(icon, size: 34, color: AppColors.accent),
            ),
            const SizedBox(height: 16),
            Text(title,
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.text),
                textAlign: TextAlign.center),
            if (subtitle != null) ...[
              const SizedBox(height: 6),
              Text(subtitle!,
                  style: TextStyle(fontSize: 13.5, color: AppColors.textSoft), textAlign: TextAlign.center),
            ],
          ],
        ),
      ),
    );
  }
}
