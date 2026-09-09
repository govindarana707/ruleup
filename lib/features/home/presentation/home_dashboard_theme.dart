import 'package:flutter/material.dart';

abstract final class HomeDashboardTheme {
  static const background = Color(0xFF0B1014);
  static const surface = Color(0xFF141B20);
  static const surfaceRaised = Color(0xFF1A232A);
  static const outline = Color(0xFF2A363E);
  static const mint = Color(0xFF83E8C5);
  static const text = Color(0xFFF2F6F4);
  static const mutedText = Color(0xFFA3B0AC);

  static ThemeData create() {
    const scheme = ColorScheme.dark(
      primary: mint,
      onPrimary: Color(0xFF052019),
      primaryContainer: Color(0xFF173C32),
      onPrimaryContainer: Color(0xFFB8F6E0),
      secondary: Color(0xFFB8C9C3),
      onSecondary: Color(0xFF14201C),
      error: Color(0xFFFFB4AB),
      onError: Color(0xFF690005),
      errorContainer: Color(0xFF3E1C1D),
      onErrorContainer: Color(0xFFFFDAD6),
      surface: background,
      onSurface: text,
      onSurfaceVariant: mutedText,
      outline: outline,
      outlineVariant: Color(0xFF222D34),
    );
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
    );
    return base.copyWith(
      scaffoldBackgroundColor: background,
      textTheme: base.textTheme.copyWith(
        headlineMedium: base.textTheme.headlineMedium?.copyWith(
          color: text,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.7,
        ),
        titleLarge: base.textTheme.titleLarge?.copyWith(
          color: text,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.25,
        ),
        titleMedium: base.textTheme.titleMedium?.copyWith(
          color: text,
          fontWeight: FontWeight.w600,
        ),
        bodyMedium: base.textTheme.bodyMedium?.copyWith(color: mutedText),
        bodySmall: base.textTheme.bodySmall?.copyWith(color: mutedText),
      ),
      appBarTheme: const AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: background,
        foregroundColor: text,
        surfaceTintColor: Colors.transparent,
      ),
      cardTheme: CardThemeData(
        margin: EdgeInsets.zero,
        elevation: 0,
        color: surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: outline),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 68,
        elevation: 0,
        backgroundColor: surface,
        indicatorColor: const Color(0xFF23463C),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          return IconThemeData(
            color: states.contains(WidgetState.selected) ? mint : mutedText,
          );
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          return TextStyle(
            color: states.contains(WidgetState.selected) ? text : mutedText,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          );
        }),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: mint,
          foregroundColor: const Color(0xFF052019),
          minimumSize: const Size(64, 56),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: mint,
        linearTrackColor: Color(0xFF253139),
      ),
      dividerTheme: const DividerThemeData(color: outline, space: 1),
    );
  }
}
