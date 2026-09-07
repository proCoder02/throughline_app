import 'package:flutter/material.dart';

import '../theme.dart';

/// Curated (not raw-random) palette so per-person colors stay pleasant and
/// on-brand instead of landing on something muddy/clashing -- same idea as
/// WhatsApp/Slack's own contact-color palettes.
const _avatarPalette = [
  Color(0xFF00A884), // brand accent, kept as one option so it doesn't disappear
  Color(0xFFE17055),
  Color(0xFF6C5CE7),
  Color(0xFF0984E3),
  Color(0xFFD63384),
  Color(0xFFE1B12C),
  Color(0xFF20BF6B),
  Color(0xFFFF6B6B),
  Color(0xFF00B8D9),
  Color(0xFF8854D0),
];

/// Deterministic per-name color -- the same name always lands on the same
/// palette entry (a stable hash, not String.hashCode, which Dart doesn't
/// guarantee is stable across app runs/versions).
Color colorForName(String name) {
  final trimmed = name.trim();
  if (trimmed.isEmpty) return AppColors.accent;
  var hash = 0;
  for (final codeUnit in trimmed.toLowerCase().codeUnits) {
    hash = (hash * 31 + codeUnit) & 0x7fffffff;
  }
  return _avatarPalette[hash % _avatarPalette.length];
}

/// Solid circle (color varies per-person, see colorForName), white uppercase
/// first letter -- unless `imageUrl` is set (a real R2-hosted profile
/// picture, see MEDIA_STORAGE_PLAN.md), in which case that's shown instead.
/// This is the single render point for every avatar in the app, same
/// reasoning as the web client's Avatar.jsx: extend the one shared widget
/// so a profile picture appears everywhere at once, not one screen at a time.
class InitialAvatar extends StatelessWidget {
  final String name;
  final double size;
  final String? imageUrl;

  const InitialAvatar({super.key, required this.name, this.size = 44, this.imageUrl});

  @override
  Widget build(BuildContext context) {
    if (imageUrl != null && imageUrl!.isNotEmpty) {
      return CircleAvatar(
        radius: size / 2,
        backgroundColor: colorForName(name),
        backgroundImage: NetworkImage(imageUrl!),
        // If the image 404s (e.g. deleted from R2) this callback just
        // leaves the colored background showing behind it rather than
        // crashing or showing Flutter's default broken-image error widget.
        onBackgroundImageError: (_, __) {},
      );
    }
    final letter = name.trim().isNotEmpty ? name.trim()[0].toUpperCase() : '?';
    return CircleAvatar(
      radius: size / 2,
      backgroundColor: colorForName(name),
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
