import 'package:flutter/material.dart';

abstract final class HomeDashboardTheme {
  static const background = Color(0xFF081015);
  static const surface = Color(0xFF111A20);
  static const surfaceRaised = Color(0xFF19232B);
  static const outline = Color(0xFF2A3942);
  static const mint = Color(0xFF65EDC1);
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
      fontFamily: 'RuleUpSans',
      fontFamilyFallback: const ['Roboto', 'sans-serif'],
    );
    return base.copyWith(
      scaffoldBackgroundColor: background,
      textTheme: base.textTheme.copyWith(
        headlineMedium: base.textTheme.headlineMedium?.copyWith(
          color: text,
          fontSize: 31,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.7,
        ),
        headlineSmall: base.textTheme.headlineSmall?.copyWith(
          color: text,
          fontSize: 27,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.4,
        ),
        titleLarge: base.textTheme.titleLarge?.copyWith(
          color: text,
          fontSize: 21,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.25,
        ),
        titleMedium: base.textTheme.titleMedium?.copyWith(
          color: text,
          fontSize: 17,
          fontWeight: FontWeight.w600,
        ),
        titleSmall: base.textTheme.titleSmall?.copyWith(
          color: text,
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
        bodyLarge: base.textTheme.bodyLarge?.copyWith(fontSize: 16),
        bodyMedium: base.textTheme.bodyMedium?.copyWith(
          color: mutedText,
          fontSize: 15,
        ),
        bodySmall: base.textTheme.bodySmall?.copyWith(
          color: mutedText,
          fontSize: 13,
        ),
        labelLarge: base.textTheme.labelLarge?.copyWith(fontSize: 14),
        labelMedium: base.textTheme.labelMedium?.copyWith(fontSize: 13),
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
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: outline),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 78,
        elevation: 0,
        backgroundColor: surface,
        indicatorColor: Colors.transparent,
        iconTheme: WidgetStateProperty.resolveWith((states) {
          return IconThemeData(
            color: states.contains(WidgetState.selected) ? mint : mutedText,
            size: 24,
          );
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          return TextStyle(
            color: states.contains(WidgetState.selected) ? mint : mutedText,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          );
        }),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: mint,
          foregroundColor: const Color(0xFF052019),
          minimumSize: const Size(64, 66),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
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
