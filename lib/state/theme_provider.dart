import 'package:flutter/material.dart';

import '../services/local_cache.dart';

/// User's explicit light/dark/system choice, persisted on-device (not
/// server-side -- purely a per-device display preference, same reasoning as
/// LocalCache's persona_completed flag). ThroughlineApp resolves this (plus
/// platform brightness for ThemeMode.system) into theme.dart's isAppDarkMode
/// flag on every build.
class ThemeProvider extends ChangeNotifier {
  ThemeMode mode = ThemeMode.system;

  void load() {
    final stored = LocalCache.instance.getThemeMode();
    if (stored != null) {
      mode = ThemeMode.values.firstWhere((m) => m.name == stored, orElse: () => ThemeMode.system);
      notifyListeners();
    }
  }

  void setMode(ThemeMode newMode) {
    if (mode == newMode) return;
    mode = newMode;
    notifyListeners();
    LocalCache.instance.setThemeMode(newMode.name);
  }
}
