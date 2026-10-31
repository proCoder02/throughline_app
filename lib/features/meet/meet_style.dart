import 'package:flutter/material.dart';

/// Card colours -- the names match the server's COLORS list. Each is a mid
/// shade that carries white text and reads on both light and dark screens.
const meetColors = <String, Color>{
  'amber': Color(0xFFD98E4A),
  'coral': Color(0xFFE0705A),
  'teal': Color(0xFF2E9C8F),
  'indigo': Color(0xFF5B6CD6),
  'plum': Color(0xFF9A5BB5),
  'forest': Color(0xFF4F8A4B),
};

/// The card's colour: the one the person picked, else a stable one from
/// their name (so the same person always gets the same colour).
Color meetColorFor(String? chosen, String name) {
  final c = meetColors[chosen];
  if (c != null) return c;
  final values = meetColors.values.toList();
  return values[name.codeUnits.fold<int>(0, (a, b) => (a * 31 + b) & 0x7fffffff) % values.length];
}
