import 'package:flutter/material.dart';

class AppColors {
  static const bgApp = Color(0xFFF0F2F5);
  static const panel = Color(0xFFFFFFFF);
  static const chatBg = Color(0xFFEFEAE2);
  static const bubbleOut = Color(0xFFD9FDD3);
  static const bubbleIn = Color(0xFFFFFFFF);
  static const text = Color(0xFF111B21);
  static const textSoft = Color(0xFF667781);
  static const accent = Color(0xFF00A884);
  static const accentDark = Color(0xFF008069);
  static const border = Color(0xFFE9EDEF);
  static const danger = Color(0xFFDC3545);
  static const railIcon = Color(0xFF54656F);
  static const railIconActive = Color(0xFF00A884);
  static const unreadBadge = Color(0xFFEA0038);
}

ThemeData buildAppTheme() {
  final inputBorder = OutlineInputBorder(borderRadius: BorderRadius.circular(8));
  return ThemeData(
    useMaterial3: true,
    scaffoldBackgroundColor: AppColors.bgApp,
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.accent,
      primary: AppColors.accent,
      error: AppColors.danger,
      surface: AppColors.panel,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.panel,
      foregroundColor: AppColors.text,
      elevation: 0.5,
      surfaceTintColor: AppColors.panel,
    ),
    dividerColor: AppColors.border,
    textTheme: const TextTheme(
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
      enabledBorder: inputBorder.copyWith(borderSide: const BorderSide(color: AppColors.border)),
      focusedBorder: inputBorder.copyWith(borderSide: const BorderSide(color: AppColors.accent, width: 2)),
      labelStyle: const TextStyle(color: AppColors.textSoft),
    ),
    cardTheme: const CardThemeData(color: AppColors.panel, elevation: 1),
    dialogTheme: const DialogThemeData(backgroundColor: AppColors.panel),
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
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: AppColors.panel,
      selectedItemColor: AppColors.railIconActive,
      unselectedItemColor: AppColors.railIcon,
    ),
  );
}
