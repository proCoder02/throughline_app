import 'package:flutter/material.dart';

import '../theme.dart';

/// Slim banner shown when a screen's background refresh couldn't reach the
/// backend -- makes the cache-first fallback (silently keep showing cached
/// data) visible instead of looking like nothing happened.
class OfflineBanner extends StatelessWidget {
  const OfflineBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: AppColors.danger.withValues(alpha: 0.12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.cloud_off, size: 14, color: AppColors.danger),
          SizedBox(width: 6),
          Text(
            "You're offline — showing saved messages",
            style: TextStyle(fontSize: 12, color: AppColors.danger),
          ),
        ],
      ),
    );
  }
}
