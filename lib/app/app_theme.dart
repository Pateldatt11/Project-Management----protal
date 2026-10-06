import 'package:flutter/material.dart';

class AppTheme {
  static const Color navy = Color(0xFF0F172A);
  static const Color ink = Color(0xFF1E293B);
  static const Color blue = Color(0xFF2563EB);
  static const Color blueSoft = Color(0xFFEFF6FF);
  static const Color violet = Color(0xFF7C3AED);
  static const Color cyan = Color(0xFF0891B2);
  static const Color bg = Color(0xFFF4F7FB);
  static const Color card = Color(0xFFFFFFFF);
  static const Color cardAlt = Color(0xFFF8FAFC);
  static const Color border = Color(0xFFE2E8F0);
  static const Color muted = Color(0xFF64748B);
  static const Color success = Color(0xFF16A34A);
  static const Color warning = Color(0xFFF59E0B);
  static const Color danger = Color(0xFFDC2626);
  static const Color slate100 = Color(0xFFF1F5F9);
  static const Color slate200 = Color(0xFFE2E8F0);
  static const Color slate700 = Color(0xFF334155);

  static ThemeData get light {
    final scheme = ColorScheme.fromSeed(seedColor: blue, brightness: Brightness.light).copyWith(
      primary: blue,
      secondary: violet,
      surface: card,
      error: danger,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: bg,
      fontFamily: 'Roboto',
      visualDensity: VisualDensity.adaptivePlatformDensity,
      appBarTheme: const AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        backgroundColor: card,
        foregroundColor: navy,
        surfaceTintColor: Colors.transparent,
      ),
      cardTheme: CardThemeData(
        color: card,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: const BorderSide(color: border),
        ),
      ),
      dividerTheme: const DividerThemeData(color: border, thickness: 1),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: blue, width: 1.4),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: blue,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      ),
      textTheme: const TextTheme(
        headlineSmall: TextStyle(color: navy, fontWeight: FontWeight.w900, letterSpacing: -0.5),
        titleLarge: TextStyle(color: navy, fontWeight: FontWeight.w900, letterSpacing: -0.35),
        titleMedium: TextStyle(color: navy, fontWeight: FontWeight.w800),
        bodyMedium: TextStyle(color: slate700),
        bodySmall: TextStyle(color: muted),
        labelMedium: TextStyle(color: muted, fontWeight: FontWeight.w700),
      ),
    );
  }

  static ThemeData get dark => ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: blue, brightness: Brightness.dark),
      );
}
