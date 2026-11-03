import 'package:flutter/material.dart';

abstract final class AppColors {
  static const background = Color(0xFF031310);
  static const surface = Color(0xFF0B2420);
  static const glass = Color(0xFF214039);
  static const primary = Color(0xFF65F4C8);
  static const primaryInk = Color(0xFF031310);
  static const text = Color(0xFFF4FAF7);
  static const muted = Color(0xFFB7CCC4);
  static const outline = Color(0xFF55736A);
  static const information = Color(0xFF83C6FA);
  static const danger = Color(0xFFFF8279);
}

abstract final class AppTheme {
  static ThemeData get dark => ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: AppColors.background,
    colorScheme: const ColorScheme.dark(
      primary: AppColors.primary,
      onPrimary: AppColors.primaryInk,
      surface: AppColors.surface,
      onSurface: AppColors.text,
      error: AppColors.danger,
    ),
    fontFamily: 'Manrope',
    textTheme: const TextTheme(
      bodyLarge: TextStyle(fontSize: 16, height: 1.5, color: AppColors.text),
      bodyMedium: TextStyle(fontSize: 14, height: 1.5, color: AppColors.muted),
      labelLarge: TextStyle(
        fontSize: 16,
        height: 1.5,
        fontWeight: FontWeight.w700,
      ),
    ),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: AppColors.glass,
      contentTextStyle: TextStyle(color: AppColors.text, fontFamily: 'Manrope'),
      behavior: SnackBarBehavior.floating,
    ),
  );
}
