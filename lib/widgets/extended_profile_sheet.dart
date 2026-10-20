import 'package:flutter/material.dart';

import '../models/friend.dart';
import '../theme.dart';
import 'avatar.dart';

/// Read-only card for someone in the viewer's extended network (a friend of
/// one of their friends, see GET /friends/search) -- tapped from the
/// Friends screen's "In your network" search section. Deliberately no
/// actions: adding a friend still only works via their friend code, same
/// as today, so this is discovery only, not a parallel add-friend path.
void showExtendedProfileSheet(BuildContext context, ExtendedFriend friend) {
  showModalBottomSheet<void>(
    context: context,
    builder: (sheetContext) => Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          InitialAvatar(name: friend.username, imageUrl: friend.profilePictureUrl, size: 64),
          const SizedBox(height: 12),
          Text(friend.username, style: appHeadlineFont(color: AppColors.dmText, fontSize: 17)),
          const SizedBox(height: 6),
          Text(
            friend.mutualVia.isEmpty
                ? 'Not directly connected to you'
                : 'Connected via ${friend.mutualVia.join(', ')}',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: AppColors.dmTextSoft),
          ),
          const SizedBox(height: 16),
          Text(
            "You're not friends with ${friend.username} yet -- ask them for their friend code to add them.",
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: AppColors.dmTextSoft, height: 1.4),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () => Navigator.of(sheetContext).pop(),
              child: const Text('Close'),
            ),
          ),
        ],
      ),
    ),
  );
}
