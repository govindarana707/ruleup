import 'package:flutter/material.dart';

abstract final class AppTheme {
  static ThemeData get light => _theme(Brightness.light);

  static ThemeData get dark => _theme(Brightness.dark);

  static ThemeData _theme(Brightness brightness) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: Colors.blue,
      brightness: brightness,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: colorScheme.surface,
      appBarTheme: const AppBarTheme(centerTitle: false, elevation: 0),
      cardTheme: const CardThemeData(margin: EdgeInsets.zero),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(minimumSize: const Size(64, 48)),
      ),
    );
  }
}
