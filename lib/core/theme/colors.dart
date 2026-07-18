import 'package:flutter/material.dart';

class AppColors {
  // ── Dark Backgrounds — deep navy-black ────────────────────────────────────────
  static const bg          = Color(0xFF06060E);
  static const bgCard      = Color(0xFF0D0D22);
  static const bgElevated  = Color(0xFF181840);
  static const bgInput     = Color(0xFF0B0B18);
  static const bgGlass     = Color(0x0DFFFFFF);
  static const bgSurface   = Color(0xFF090918);

  // ── Light Mode Backgrounds ────────────────────────────────────────────────────
  static const bgLight         = Color(0xFFF2F2F8);
  static const bgCardLight     = Color(0xFFFFFFFF);
  static const bgElevatedLight = Color(0xFFEAEAF5);
  static const bgInputLight    = Color(0xFFEEEEF8);
  static const bgSurfaceLight  = Color(0xFFF8F8FF);

  // ── Borders ───────────────────────────────────────────────────────────────────
  static const border           = Color(0xFF1E1E40);
  static const borderGlow       = Color(0x336366F1);
  static const borderLight      = Color(0xFF2A2A50);
  static const borderLightMode  = Color(0xFFE0E0EE);

  // ── Primary Accent — electric blue ────────────────────────────────────────────
  static const accentBlue    = Color(0xFF00C2FF);
  static const accentIndigo  = Color(0xFF0099FF);
  static const accentPrimary = Color(0xFF00B4FF);
  static const accentViolet  = Color(0xFF0077FF);

  // ── Secondary Accents ─────────────────────────────────────────────────────────
  static const accentGold    = Color(0xFFE8B84B);
  static const accentGreen   = Color(0xFF10B981);
  static const accentRed     = Color(0xFFEF4444);
  static const accentOrange  = Color(0xFFF59E0B);
  static const accentCyan    = Color(0xFF22D3EE);
  static const accentPurple  = Color(0xFF8B5CF6);
  static const accentCoral   = Color(0xFFFF6B35);
  static const accentEmerald = Color(0xFF059669);

  // ── TV Category Colors ────────────────────────────────────────────────────────
  static const tvSports        = Color(0xFF00B4FF);
  static const tvCricket       = Color(0xFF22C55E);
  static const tvFootball      = Color(0xFF22D3EE);
  static const tvBangla        = Color(0xFFE8B84B);
  static const tvNews          = Color(0xFFEF4444);
  static const tvEntertainment = Color(0xFF8B5CF6);

  static Color tvCategoryColor(String category) {
    switch (category.toLowerCase()) {
      case 'cricket':       return tvCricket;
      case 'football':      return tvFootball;
      case 'bangla':        return tvBangla;
      case 'news':          return tvNews;
      case 'entertainment': return tvEntertainment;
      default:              return tvSports;
    }
  }

  static LinearGradient tvCategoryGradient(String category) {
    final c = tvCategoryColor(category);
    return LinearGradient(
      colors: [c, c.withValues(alpha: 0.6)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    );
  }

  // ── Live / Status ─────────────────────────────────────────────────────────────
  static const live     = Color(0xFFFF2D55);
  static const liveGlow = Color(0x30FF2D55);
  static const livePulse = Color(0x60FF2D55);

  // ── Text ──────────────────────────────────────────────────────────────────────
  static const textPrimary         = Color(0xFFF0F0FF);
  static const textSecondary       = Color(0xFF7A7A9A);
  static const textMuted           = Color(0xFF55558A);
  static const textPrimaryLight    = Color(0xFF0A0A1A);
  static const textSecondaryLight  = Color(0xFF5A5A7A);
  static const textMutedLight      = Color(0xFFAAAAAA);

  // ── Nav ───────────────────────────────────────────────────────────────────────
  static const navSurface      = Color(0xFF0A0A16);
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
    colors: [Color(0xFF12122E), Color(0xFF0D0D22)],
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
    colors: [Color(0xFF06060E), Color(0xFF0D0D22), Color(0xFF06060E)],
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

  Color get cBgSurface => isDark ? AppColors.bgSurface : AppColors.bgSurfaceLight;

  Color get cTvColor => AppColors.tvCategoryColor('');

  Color tvCatColor(String cat) => AppColors.tvCategoryColor(cat);
  LinearGradient tvCatGradient(String cat) => AppColors.tvCategoryGradient(cat);

  LinearGradient get cCardGradient =>
      isDark ? AppColors.cardGradient : AppColors.cardGradientLight;
}
