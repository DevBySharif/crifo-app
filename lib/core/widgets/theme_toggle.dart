import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../theme/colors.dart';
import '../theme/theme_provider.dart';

/// Premium forui-inspired animated dark/light mode toggle switch.
class ThemeToggle extends ConsumerWidget {
  const ThemeToggle({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = ref.watch(themeModeProvider) == ThemeMode.dark;

    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        ref.read(themeModeProvider.notifier).toggle();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutCubic,
        width: 58,
        height: 30,
        decoration: BoxDecoration(
          gradient: isDark
              ? const LinearGradient(
                  colors: [Color(0xFF1C1C28), Color(0xFF2A2A40)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
              : const LinearGradient(
                  colors: [Color(0xFFE8E8F8), Color(0xFFD8D8F0)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: AppColors.accentPrimary.withValues(alpha: isDark ? 0.4 : 0.3),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: AppColors.accentPrimary.withValues(alpha: isDark ? 0.2 : 0.1),
              blurRadius: 8,
            ),
          ],
        ),
        child: Stack(
          children: [
            // Moon icon (left side, visible in dark mode)
            Positioned(
              left: 7, top: 0, bottom: 0,
              child: Center(
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 200),
                  opacity: isDark ? 1.0 : 0.0,
                  child: const Text('🌙', style: TextStyle(fontSize: 11)),
                ),
              ),
            ),
            // Sun icon (right side, visible in light mode)
            Positioned(
              right: 7, top: 0, bottom: 0,
              child: Center(
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 200),
                  opacity: isDark ? 0.0 : 1.0,
                  child: const Text('☀️', style: TextStyle(fontSize: 11)),
                ),
              ),
            ),
            // Sliding gradient thumb
            AnimatedPositioned(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOutCubic,
              top: 3, bottom: 3,
              left: isDark ? 3 : 27,
              child: Container(
                width: 24,
                decoration: BoxDecoration(
                  gradient: AppColors.primaryGradient,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.accentPrimary.withValues(alpha: 0.5),
                      blurRadius: 6,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
