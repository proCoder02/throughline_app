import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// Flipped by ThemeProvider whenever the effective brightness changes.
/// AppColors' mode-dependent fields below read this instead of the app
/// needing two separate color-constant sets wired through every screen --
/// dozens of files already reference AppColors.X directly as a static
/// field, and this lets dark mode work without touching any of them.
bool isAppDarkMode = false;

class AppColors {
  // Mode-dependent -- computed, not const, so they can actually change when
  // isAppDarkMode flips. Any const usage of these was a compile-time
  // constant before dark mode existed; each one needed its surrounding
  // `const` dropped (mechanical, verified via `flutter analyze` catching
  // every single one as a compile error -- nothing here is a silent risk).
  static Color get bgApp => isAppDarkMode ? const Color(0xFF0B141A) : const Color(0xFFF0F2F5);
  static Color get panel => isAppDarkMode ? const Color(0xFF1F2C34) : const Color(0xFFFFFFFF);
  static Color get chatBg => isAppDarkMode ? const Color(0xFF0B141A) : const Color(0xFFEFEAE2);
  static Color get bubbleOut => isAppDarkMode ? const Color(0xFF005C4B) : const Color(0xFFD9FDD3);
  static Color get bubbleIn => isAppDarkMode ? const Color(0xFF1F2C34) : const Color(0xFFFFFFFF);
  static Color get text => isAppDarkMode ? const Color(0xFFE9EDEF) : const Color(0xFF111B21);
  static Color get textSoft => isAppDarkMode ? const Color(0xFF8696A0) : const Color(0xFF667781);
  static Color get border => isAppDarkMode ? const Color(0xFF2A3942) : const Color(0xFFE9EDEF);
  static Color get railIcon => isAppDarkMode ? const Color(0xFF8696A0) : const Color(0xFF54656F);

  // Brand/semantic colors -- legible and on-brand in both modes as-is, kept
  // as real compile-time constants (no need to touch their call sites).
  static const accent = Color(0xFF00A884);
  static const accentDark = Color(0xFF008069);
  static const danger = Color(0xFFDC3545);
  static const railIconActive = Color(0xFF00A884);
  static const unreadBadge = Color(0xFFEA0038);
}

/// Builds a ThemeData reflecting whatever isAppDarkMode currently is --
/// callers (main.dart) resolve ThemeMode.system/light/dark + platform
/// brightness into that flag BEFORE calling this, so this stays a pure
/// function of the already-decided mode rather than a second place that
/// independently decides light vs dark.
ThemeData buildAppTheme() {
  final dark = isAppDarkMode;
  final inputBorder = OutlineInputBorder(borderRadius: BorderRadius.circular(8));
  return ThemeData(
    useMaterial3: true,
    brightness: dark ? Brightness.dark : Brightness.light,
    scaffoldBackgroundColor: AppColors.bgApp,
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.accent,
      brightness: dark ? Brightness.dark : Brightness.light,
      primary: AppColors.accent,
      error: AppColors.danger,
      surface: AppColors.panel,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: AppColors.panel,
      foregroundColor: AppColors.text,
      elevation: 0.5,
      surfaceTintColor: AppColors.panel,
    ),
    dividerColor: AppColors.border,
    textTheme: TextTheme(
      titleLarge: TextStyle(color: AppColors.text, fontWeight: FontWeight.w600),
      titleMedium: TextStyle(color: AppColors.text, fontWeight: FontWeight.w600),
      labelLarge: TextStyle(color: AppColors.text),
      bodyMedium: TextStyle(color: AppColors.text),
      bodySmall: TextStyle(color: AppColors.textSoft),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.panel,
      border: inputBorder,
      enabledBorder: inputBorder.copyWith(borderSide: BorderSide(color: AppColors.border)),
      focusedBorder: inputBorder.copyWith(borderSide: const BorderSide(color: AppColors.accent, width: 2)),
      labelStyle: TextStyle(color: AppColors.textSoft),
    ),
    cardTheme: CardThemeData(color: AppColors.panel, elevation: 1),
    dialogTheme: DialogThemeData(backgroundColor: AppColors.panel),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: AppColors.accent,
      foregroundColor: Colors.white,
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.accent,
        foregroundColor: Colors.white,
      ),
    ),
    bottomNavigationBarTheme: BottomNavigationBarThemeData(
      backgroundColor: AppColors.panel,
      selectedItemColor: AppColors.railIconActive,
      unselectedItemColor: AppColors.railIcon,
    ),
    // Material 3's Android default (ZoomPageTransitionsBuilder) composites
    // both the outgoing and incoming page through a simultaneous fade+scale
    // -- noticeably heavier than a plain slide, and the "zoom" a couple of
    // screens visibly do on push. CupertinoPageTransitionsBuilder for every
    // platform gives one cheap, GPU-friendly slide everywhere in the app --
    // every plain MaterialPageRoute push (opening a conversation, opening
    // the live thread from Listen, etc.) automatically gets it, so they all
    // stay visually consistent with each other for free.
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: CupertinoPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
      },
    ),
  );
}
