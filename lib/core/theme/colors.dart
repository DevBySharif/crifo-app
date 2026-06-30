import 'package:flutter/material.dart';

class AppColors {
  // ── Dark Mode Backgrounds ─────────────────────────────────────────────────────
  static const bg          = Color(0xFF0A0A0F);
  static const bgCard      = Color(0xFF13131A);
  static const bgElevated  = Color(0xFF1C1C28);
  static const bgInput     = Color(0xFF16161F);

  // ── Light Mode Backgrounds ────────────────────────────────────────────────────
  static const bgLight         = Color(0xFFF5F5FA);
  static const bgCardLight     = Color(0xFFFFFFFF);
  static const bgElevatedLight = Color(0xFFEEEEF8);
  static const bgInputLight    = Color(0xFFF0F0F8);

  // ── Borders ───────────────────────────────────────────────────────────────────
  static const border       = Color(0xFF1E1E2E);
  static const borderLight  = Color(0xFF2A2A3E);
  static const borderLightMode = Color(0xFFDDDDEE);

  // ── Primary Accent (Blue-Indigo gradient) ────────────────────────────────────
  static const accentBlue    = Color(0xFF4F81F1);
  static const accentIndigo  = Color(0xFF6366F1);
  static const accentPrimary = Color(0xFF5B6EF5);

  // ── Secondary Accents ────────────────────────────────────────────────────────
  static const accentGreen  = Color(0xFF10B981);
  static const accentRed    = Color(0xFFEF4444);
  static const accentOrange = Color(0xFFF59E0B);
  static const accentGold   = Color(0xFFEAB308);
  static const accentPurple = Color(0xFF8B5CF6);
  static const accentCyan   = Color(0xFF06B6D4);

  // ── Live / Status ─────────────────────────────────────────────────────────────
  static const live     = Color(0xFFFF3B5C);
  static const liveGlow = Color(0x40FF3B5C);

  // ── Dark Text ─────────────────────────────────────────────────────────────────
  static const textPrimary   = Color(0xFFF0F0FF);
  static const textSecondary = Color(0xFF8888AA);
  static const textMuted     = Color(0xFF44445A);

  // ── Light Text ────────────────────────────────────────────────────────────────
  static const textPrimaryLight   = Color(0xFF0D0D1A);
  static const textSecondaryLight = Color(0xFF55557A);
  static const textMutedLight     = Color(0xFFAAAAAC);

  // ── Nav / Chrome ──────────────────────────────────────────────────────────────
  static const tabBar     = Color(0xFF0D0D14);
  static const navSurface = Color(0xFF111118);
  static const navSurfaceLight = Color(0xFFFFFFFF);

  // ── Gradients ─────────────────────────────────────────────────────────────────
  static const primaryGradient = LinearGradient(
    colors: [Color(0xFF4F81F1), Color(0xFF7C3AED)],
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
  );

  static const liveGradient = LinearGradient(
    colors: [Color(0xFFFF3B5C), Color(0xFFFF6B35)],
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
  );

  static const cardGradient = LinearGradient(
    colors: [Color(0xFF1C1C28), Color(0xFF13131A)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const cardGradientLight = LinearGradient(
    colors: [Color(0xFFFFFFFF), Color(0xFFF5F5FA)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const heroGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Colors.transparent, Color(0xCC000000), Color(0xF5000000)],
    stops: [0.0, 0.55, 1.0],
  );
}

// ── Context Extension for Theme-Aware Colors ─────────────────────────────────
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
