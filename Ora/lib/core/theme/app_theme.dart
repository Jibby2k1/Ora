import 'package:flutter/material.dart';

class AppTheme {
  static ThemeData dark({bool highContrastSnackbars = true}) {
    const base = Color(0xFF070A10);
    const surface = Color(0xFF10161F);
    const surfaceAlt = Color(0xFF182230);
    const surfaceElevated = Color(0xFF223044);
    const accent = Color(0xFF9BE7FF);
    const secondary = Color(0xFFD1D9FF);
    const tertiary = Color(0xFF8EF4D1);

    final scheme = const ColorScheme.dark().copyWith(
      primary: accent,
      onPrimary: const Color(0xFF041019),
      secondary: secondary,
      onSecondary: const Color(0xFF0C1322),
      tertiary: tertiary,
      onTertiary: const Color(0xFF07160F),
      surface: surface,
      onSurface: const Color(0xFFF3F8FF),
      surfaceContainerHighest: surfaceAlt,
      outline: const Color(0xFF314154),
      shadow: Colors.black,
    );

    final textTheme = const TextTheme(
      headlineLarge: TextStyle(
        fontSize: 28,
        fontWeight: FontWeight.w700,
        height: 1.05,
      ),
      headlineMedium: TextStyle(
        fontSize: 22,
        fontWeight: FontWeight.w700,
        height: 1.1,
      ),
      titleLarge: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w700,
        height: 1.15,
      ),
      titleMedium: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w700,
        height: 1.15,
      ),
      titleSmall: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w700,
        height: 1.15,
      ),
      bodyLarge: TextStyle(fontSize: 15, height: 1.42),
      bodyMedium: TextStyle(fontSize: 14, height: 1.42),
      bodySmall: TextStyle(fontSize: 12, height: 1.32),
      labelLarge: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
      labelMedium: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
    ).apply(
      bodyColor: scheme.onSurface,
      displayColor: scheme.onSurface,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: base,
      fontFamily: 'SpaceGrotesk',
      textTheme: textTheme,
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
        toolbarHeight: 72,
        titleTextStyle: textTheme.titleLarge,
        iconTheme: IconThemeData(color: scheme.onSurface),
      ),
      cardTheme: CardThemeData(
        color: surface.withValues(alpha: 0.72),
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface.withValues(alpha: 0.92),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: highContrastSnackbars
            ? const Color(0xFFF3F7FF)
            : surfaceAlt.withValues(alpha: 0.95),
        contentTextStyle: TextStyle(
          color: highContrastSnackbars
              ? const Color(0xFF081426)
              : const Color(0xFFF7FAFF),
          fontWeight: FontWeight.w700,
        ),
        actionTextColor:
            highContrastSnackbars ? const Color(0xFF0A58FF) : accent,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: surface.withValues(alpha: 0.84),
        selectedItemColor: accent,
        unselectedItemColor: const Color(0xFF93A2B8),
        showSelectedLabels: true,
        showUnselectedLabels: true,
        type: BottomNavigationBarType.fixed,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceAlt.withValues(alpha: 0.44),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: scheme.outline.withValues(alpha: 0.24)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: scheme.outline.withValues(alpha: 0.24)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide:
              BorderSide(color: accent.withValues(alpha: 0.86), width: 1.4),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: accent.withValues(alpha: 0.96),
          foregroundColor: scheme.onPrimary,
          minimumSize: const Size(0, 48),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          textStyle: textTheme.labelLarge,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: accent.withValues(alpha: 0.96),
          foregroundColor: scheme.onPrimary,
          elevation: 0,
          minimumSize: const Size(0, 48),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          textStyle: textTheme.labelLarge,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: scheme.onSurface,
          backgroundColor: surfaceElevated.withValues(alpha: 0.18),
          side: BorderSide(color: scheme.outline.withValues(alpha: 0.24)),
          minimumSize: const Size(0, 48),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          textStyle: textTheme.labelLarge,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: accent,
          minimumSize: const Size(0, 44),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          textStyle: textTheme.labelLarge,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: accent.withValues(alpha: 0.96),
        foregroundColor: scheme.onPrimary,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: scheme.onSurface,
          backgroundColor: surfaceAlt.withValues(alpha: 0.24),
          minimumSize: const Size(42, 42),
          padding: const EdgeInsets.all(10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: surfaceAlt.withValues(alpha: 0.28),
        selectedColor: accent.withValues(alpha: 0.20),
        secondarySelectedColor: accent.withValues(alpha: 0.20),
        disabledColor: surface.withValues(alpha: 0.24),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        side: BorderSide(color: scheme.outline.withValues(alpha: 0.16)),
        labelStyle: textTheme.bodySmall,
        secondaryLabelStyle: textTheme.bodySmall,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outline.withValues(alpha: 0.16),
        thickness: 1,
      ),
    );
  }
}
