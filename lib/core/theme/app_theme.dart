import 'package:flutter/material.dart';

class AppTheme {
  static const background = Color(0xFF101414);
  static const surface = Color(0xFF1C2020);
  static const card = Color(0xFF272B2B);
  static const gold = Color(0xFFF2CA50);
  static const cream = Color(0xFFD0C5AF);
  static const text = Color(0xFFE0E3E2);
  static const border = Color(0xFF4D4635);

  static final darkTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    fontFamily: 'IBM Plex Sans Arabic',
    scaffoldBackgroundColor: background,
    colorScheme: const ColorScheme.dark(
      primary: gold,
      onPrimary: Color(0xFF3C2F00),
      secondary: Color(0xFFFFB4A5),
      surface: surface,
      onSurface: text,
    ),
    textTheme: const TextTheme(
      headlineLarge: TextStyle(fontSize: 28, fontWeight: FontWeight.w700),
      headlineMedium: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
      titleLarge: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
      bodyLarge: TextStyle(fontSize: 18, height: 1.5),
      bodyMedium: TextStyle(fontSize: 16, height: 1.5),
      labelLarge: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
    ),
    appBarTheme: const AppBarTheme(backgroundColor: background, elevation: 0),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: gold,
        foregroundColor: const Color(0xFF241A00),
        minimumSize: const Size(48, 48),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        textStyle: const TextStyle(
          fontFamily: 'IBM Plex Sans Arabic',
          fontSize: 16,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
  );
}
