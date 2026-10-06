import 'package:flutter/material.dart';

/// Employee APK-only visual theme.
///
/// This intentionally does not replace the admin/web dashboard theme. The
/// palette follows the soft neutral green/gray direction from the requested
/// Dribbble reference, while all labels/content remain project-management only.
class EmployeeMobileTheme {
  static const Color ink = Color(0xFF0A0D0A);
  static const Color deepGreen = Color(0xFF344D50);
  static const Color moss = Color(0xFF405446);
  static const Color sage = Color(0xFF8F9168);
  static const Color canvas = Color(0xFFF3F4F1);
  static const Color canvasAlt = Color(0xFFECEFEC);
  static const Color muted = Color(0xFF687269);
  static const Color border = Color(0xFFD9DFDA);
  static const Color card = Color(0xFFFFFFFF);
  static const Color success = Color(0xFF405446);
  static const Color warning = Color(0xFF8F9168);
  static const Color danger = Color(0xFFD87465);

  static ThemeData get light {
    final scheme = ColorScheme.fromSeed(
      seedColor: deepGreen,
      brightness: Brightness.light,
    ).copyWith(
      primary: deepGreen,
      secondary: moss,
      tertiary: sage,
      surface: card,
      onSurface: ink,
      surfaceContainerHighest: canvasAlt,
      outline: border,
      error: danger,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: canvas,
      fontFamily: 'Roboto',
      visualDensity: VisualDensity.adaptivePlatformDensity,
      splashFactory: InkSparkle.splashFactory,
      appBarTheme: const AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        backgroundColor: canvas,
        foregroundColor: ink,
        surfaceTintColor: Colors.transparent,
        systemOverlayStyle: null,
      ),
      cardTheme: CardThemeData(
        color: card,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(28),
          side: const BorderSide(color: border),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: ink,
        indicatorColor: Colors.white.withOpacity(.12),
        surfaceTintColor: Colors.transparent,
        labelBehavior: NavigationDestinationLabelBehavior.onlyShowSelected,
        iconTheme: MaterialStateProperty.resolveWith((states) {
          final selected = states.contains(MaterialState.selected);
          return IconThemeData(color: selected ? Colors.white : const Color(0xFFA7AEA8));
        }),
        labelTextStyle: MaterialStateProperty.resolveWith((states) {
          final selected = states.contains(MaterialState.selected);
          return TextStyle(
            color: selected ? Colors.white : const Color(0xFFA7AEA8),
            fontSize: 11,
            fontWeight: FontWeight.w800,
          );
        }),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: canvasAlt,
        selectedColor: deepGreen.withOpacity(.12),
        disabledColor: canvasAlt,
        labelStyle: const TextStyle(color: ink, fontWeight: FontWeight.w800, fontSize: 12),
        secondaryLabelStyle: const TextStyle(color: ink, fontWeight: FontWeight.w800, fontSize: 12),
        side: const BorderSide(color: border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      ),
      dividerTheme: const DividerThemeData(color: border, thickness: 1),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(22)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(22),
          borderSide: const BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(22),
          borderSide: const BorderSide(color: deepGreen, width: 1.4),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: ink,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: ink,
          side: const BorderSide(color: border),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        ),
      ),
      textTheme: const TextTheme(
        headlineSmall: TextStyle(color: ink, fontWeight: FontWeight.w900, letterSpacing: -0.7),
        titleLarge: TextStyle(color: ink, fontWeight: FontWeight.w900, letterSpacing: -0.5),
        titleMedium: TextStyle(color: ink, fontWeight: FontWeight.w900, letterSpacing: -0.2),
        titleSmall: TextStyle(color: ink, fontWeight: FontWeight.w800),
        bodyMedium: TextStyle(color: muted, fontWeight: FontWeight.w600),
        bodySmall: TextStyle(color: muted, fontWeight: FontWeight.w700),
        labelMedium: TextStyle(color: muted, fontWeight: FontWeight.w800),
      ),
    );
  }
}
