import 'package:flutter/material.dart';
import 'app_colors.dart';

class AppTheme {
  static ThemeData get lightTheme {
    return ThemeData(
      brightness: Brightness.light,
      primaryColor: AppColors.lightPrimary,
      scaffoldBackgroundColor: AppColors.lightBackground,
      cardColor: AppColors.lightCard,
      dividerColor: AppColors.lightDivider,
      fontFamily: 'Inter',
      textTheme: const TextTheme(
        titleLarge: TextStyle(color: AppColors.lightTitleText, fontSize: 24, fontWeight: FontWeight.bold),
        bodyLarge: TextStyle(color: AppColors.lightBodyText, fontSize: 16),
        bodyMedium: TextStyle(color: AppColors.lightDescriptionText, fontSize: 14),
      ),
      colorScheme: const ColorScheme.light(
        primary: AppColors.lightPrimary,
        secondary: AppColors.lightSecondary,
        surface: AppColors.lightSurface,
        error: AppColors.lightError,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.lightSurface,
        foregroundColor: AppColors.lightTitleText,
        elevation: 0,
      ),
    );
  }

  static ThemeData get darkTheme {
    return ThemeData(
      brightness: Brightness.dark,
      primaryColor: AppColors.darkPrimary,
      scaffoldBackgroundColor: AppColors.darkBackground,
      cardColor: AppColors.darkCard,
      dividerColor: AppColors.darkDivider,
      fontFamily: 'Inter',
      textTheme: const TextTheme(
        titleLarge: TextStyle(color: AppColors.darkTitleText, fontSize: 24, fontWeight: FontWeight.bold),
        bodyLarge: TextStyle(color: AppColors.darkBodyText, fontSize: 16),
        bodyMedium: TextStyle(color: AppColors.darkDescriptionText, fontSize: 14),
      ),
      colorScheme: const ColorScheme.dark(
        primary: AppColors.darkPrimary,
        secondary: AppColors.darkSecondary,
        surface: AppColors.darkSurface,
        error: AppColors.darkError,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.darkSurface,
        foregroundColor: AppColors.darkTitleText,
        elevation: 0,
      ),
    );
  }
}
