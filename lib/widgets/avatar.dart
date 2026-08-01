import 'package:flutter/material.dart';

import '../theme.dart';

/// Solid green circle, white uppercase first letter — no photos, per spec.
class InitialAvatar extends StatelessWidget {
  final String name;
  final double size;

  const InitialAvatar({super.key, required this.name, this.size = 44});

  @override
  Widget build(BuildContext context) {
    final letter = name.trim().isNotEmpty ? name.trim()[0].toUpperCase() : '?';
    return CircleAvatar(
      radius: size / 2,
      backgroundColor: AppColors.accent,
      child: Text(
        letter,
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w600,
          fontSize: size * 0.42,
        ),
      ),
    );
  }
}
