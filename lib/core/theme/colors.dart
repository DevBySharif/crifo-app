import 'package:flutter/material.dart';

class AppColors {
  // ── Dark Backgrounds — deep luxury black ──────────────────────────────────────
  static const bg          = Color(0xFF06060E);
  static const bgCard      = Color(0xFF0E0E1C);
  static const bgElevated  = Color(0xFF161628);
  static const bgInput     = Color(0xFF0B0B18);
  static const bgGlass     = Color(0x0DFFFFFF); // glassmorphism overlay

  // ── Light Mode Backgrounds ────────────────────────────────────────────────────
  static const bgLight         = Color(0xFFF2F2F8);
  static const bgCardLight     = Color(0xFFFFFFFF);
  static const bgElevatedLight = Color(0xFFEAEAF5);
  static const bgInputLight    = Color(0xFFEEEEF8);

  // ── Borders ───────────────────────────────────────────────────────────────────
  static const border           = Color(0xFF1A1A30);
  static const borderGlow       = Color(0x336366F1);
  static const borderLight      = Color(0xFF22223A);
  static const borderLightMode  = Color(0xFFE0E0EE);

  // ── Primary Accent — electric indigo ─────────────────────────────────────────
  static const accentBlue    = Color(0xFF00C2FF);
  static const accentIndigo  = Color(0xFF0099FF);
  static const accentPrimary = Color(0xFF00B4FF);
  static const accentViolet  = Color(0xFF0077FF);

  // ── Secondary Accents ────────────────────────────────────────────────────────
  static const accentGold   = Color(0xFFE8B84B);
  static const accentGreen  = Color(0xFF10B981);
  static const accentRed    = Color(0xFFEF4444);
  static const accentOrange = Color(0xFFF59E0B);
  static const accentCyan   = Color(0xFF22D3EE);
  static const accentPurple = Color(0xFF8B5CF6);

  // ── Live / Status ─────────────────────────────────────────────────────────────
  static const live     = Color(0xFFFF2D55);
  static const liveGlow = Color(0x50FF2D55);

  // ── Text ──────────────────────────────────────────────────────────────────────
  static const textPrimary         = Color(0xFFF0F0FF);
  static const textSecondary       = Color(0xFF7A7A9A);
  static const textMuted           = Color(0xFF3A3A55);
  static const textPrimaryLight    = Color(0xFF0A0A1A);
  static const textSecondaryLight  = Color(0xFF5A5A7A);
  static const textMutedLight      = Color(0xFFAAAAAA);

  // ── Nav ───────────────────────────────────────────────────────────────────────
  static const navSurface      = Color(0xFF09090F);
  static const navSurfaceLight = Color(0xFFFFFFFF);

  // ── Gradients ─────────────────────────────────────────────────────────────────
  static const primaryGradient = LinearGradient(
    colors: [Color(0xFF00B4FF), Color(0xFF0077FF)],
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
  );

  static const brandGradient = LinearGradient(
    colors: [Color(0xFF00C2FF), Color(0xFF00B4FF), Color(0xFF0077FF)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const goldGradient = LinearGradient(
    colors: [Color(0xFFE8B84B), Color(0xFFF5D78E)],
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
  );

  static const liveGradient = LinearGradient(
    colors: [Color(0xFFFF2D55), Color(0xFFFF6B6B)],
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
  );

  static const cardGradient = LinearGradient(
    colors: [Color(0xFF131325), Color(0xFF0E0E1C)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const cardGradientLight = LinearGradient(
    colors: [Color(0xFFFFFFFF), Color(0xFFF5F5FF)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const heroGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Colors.transparent, Color(0xCC000000), Color(0xF5000000)],
    stops: [0.0, 0.5, 1.0],
  );

  static const splashGradient = LinearGradient(
    colors: [Color(0xFF06060E), Color(0xFF0E0E1C), Color(0xFF06060E)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}

extension AppColorsX on BuildContext {
  bool get isDark => Theme.of(this).brightness == Brightness.dark;

  Color get cBg         => isDark ? AppColors.bg         : AppColors.bgLight;
  Color get cBgCard     => isDark ? AppColors.bgCard      : AppColors.bgCardLight;
  Color get cBgElevated => isDark ? AppColors.bgElevated  : AppColors.bgElevatedLight;
  Color get cBgInput    => isDark ? AppColors.bgInput     : AppColors.bgInputLight;
  Color get cBorder     => isDark ? AppColors.border      : AppColors.borderLightMode;
  Color get cBorderL    => isDark ? AppColors.borderLight : AppColors.borderLightMode;
  Color get cNavSurface => isDark ? AppColors.navSurface  : AppColors.navSurfaceLight;

  Color get cTextPrimary   => isDark ? AppColors.textPrimary   : AppColors.textPrimaryLight;
  Color get cTextSecondary => isDark ? AppColors.textSecondary : AppColors.textSecondaryLight;
  Color get cTextMuted     => isDark ? AppColors.textMuted     : AppColors.textMutedLight;

  LinearGradient get cCardGradient =>
      isDark ? AppColors.cardGradient : AppColors.cardGradientLight;
}
