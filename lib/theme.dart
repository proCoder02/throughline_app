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
      bodyMedium: TextStyle(color: AppColors.text),
      bodySmall: TextStyle(color: AppColors.textSoft),
    ),
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
