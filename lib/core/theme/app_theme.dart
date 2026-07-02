import 'package:flutter/material.dart';
import 'colors.dart';

class AppTheme {
  static ThemeData get dark => ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: AppColors.bg,
    colorScheme: const ColorScheme.dark(
      primary: AppColors.accentPrimary,
      secondary: AppColors.accentIndigo,
      surface: AppColors.bgCard,
      error: AppColors.accentRed,
      onPrimary: Colors.white,
      onSurface: AppColors.textPrimary,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      foregroundColor: AppColors.textPrimary,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
    ),
    cardTheme: CardThemeData(
      color: AppColors.bgCard,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: const BorderRadius.all(Radius.circular(14)),
        side: BorderSide(color: AppColors.border, width: 0.8),
      ),
    ),
    dividerTheme: const DividerThemeData(color: AppColors.border, thickness: 0.5, space: 0),
    splashFactory: InkSparkle.splashFactory,
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: CupertinoPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
      },
    ),
    textTheme: const TextTheme(
      displayLarge:  TextStyle(fontFamily: 'Oswald', color: AppColors.textPrimary, fontWeight: FontWeight.w700),
      displayMedium: TextStyle(fontFamily: 'Oswald', color: AppColors.textPrimary, fontWeight: FontWeight.w700),
      titleLarge:    TextStyle(fontFamily: 'Inter', color: AppColors.textPrimary, fontWeight: FontWeight.w700, fontSize: 18),
      titleMedium:   TextStyle(fontFamily: 'Inter', color: AppColors.textPrimary, fontWeight: FontWeight.w600, fontSize: 15),
      titleSmall:    TextStyle(fontFamily: 'Inter', color: AppColors.textPrimary, fontWeight: FontWeight.w600, fontSize: 13),
      bodyLarge:     TextStyle(fontFamily: 'Inter', color: AppColors.textPrimary, fontSize: 14),
      bodyMedium:    TextStyle(fontFamily: 'Inter', color: AppColors.textSecondary, fontSize: 13),
      bodySmall:     TextStyle(fontFamily: 'Inter', color: AppColors.textMuted, fontSize: 11),
      labelLarge:    TextStyle(fontFamily: 'Inter', color: AppColors.textMuted, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1.5),
    ),
  );

  static ThemeData get light => ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    scaffoldBackgroundColor: AppColors.bgLight,
    colorScheme: const ColorScheme.light(
      primary: AppColors.accentPrimary,
      secondary: AppColors.accentIndigo,
      surface: AppColors.bgCardLight,
      error: AppColors.accentRed,
      onPrimary: Colors.white,
      onSurface: AppColors.textPrimaryLight,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      foregroundColor: AppColors.textPrimaryLight,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
    ),
    cardTheme: CardThemeData(
      color: AppColors.bgCardLight,
      elevation: 0,
      shadowColor: Color(0x1200B4FF),
      shape: RoundedRectangleBorder(
        borderRadius: const BorderRadius.all(Radius.circular(14)),
        side: BorderSide(color: AppColors.borderLightMode, width: 0.8),
      ),
    ),
    dividerTheme: const DividerThemeData(color: AppColors.borderLightMode, thickness: 0.5, space: 0),
    splashFactory: InkSparkle.splashFactory,
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: CupertinoPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
      },
    ),
    textTheme: const TextTheme(
      displayLarge:  TextStyle(fontFamily: 'Oswald', color: AppColors.textPrimaryLight, fontWeight: FontWeight.w700),
      displayMedium: TextStyle(fontFamily: 'Oswald', color: AppColors.textPrimaryLight, fontWeight: FontWeight.w700),
      titleLarge:    TextStyle(fontFamily: 'Inter', color: AppColors.textPrimaryLight, fontWeight: FontWeight.w700, fontSize: 18),
      titleMedium:   TextStyle(fontFamily: 'Inter', color: AppColors.textPrimaryLight, fontWeight: FontWeight.w600, fontSize: 15),
      titleSmall:    TextStyle(fontFamily: 'Inter', color: AppColors.textPrimaryLight, fontWeight: FontWeight.w600, fontSize: 13),
      bodyLarge:     TextStyle(fontFamily: 'Inter', color: AppColors.textPrimaryLight, fontSize: 14),
      bodyMedium:    TextStyle(fontFamily: 'Inter', color: AppColors.textSecondaryLight, fontSize: 13),
      bodySmall:     TextStyle(fontFamily: 'Inter', color: AppColors.textMutedLight, fontSize: 11),
      labelLarge:    TextStyle(fontFamily: 'Inter', color: AppColors.textMutedLight, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1.5),
    ),
  );
}
