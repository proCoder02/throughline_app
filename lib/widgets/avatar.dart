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
/// first letter — no photos, per spec.
class InitialAvatar extends StatelessWidget {
  final String name;
  final double size;

  const InitialAvatar({super.key, required this.name, this.size = 44});

  @override
  Widget build(BuildContext context) {
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
