import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/colors.dart';
import 'core/theme/theme_provider.dart';
import 'core/providers/tv_fullscreen_provider.dart';
import 'features/home/home_screen.dart';
import 'features/scores/scores_screen.dart';
import 'features/tv/tv_screen.dart';
import 'features/search/search_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: AppColors.navSurface,
    systemNavigationBarIconBrightness: Brightness.light,
  ));
  runApp(const ProviderScope(child: CriFOApp()));
}

class CriFOApp extends ConsumerWidget {
  const CriFOApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    final isDark = themeMode == ThemeMode.dark;

    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
      systemNavigationBarColor: isDark ? AppColors.navSurface : AppColors.navSurfaceLight,
      systemNavigationBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
    ));

    return MaterialApp(
      title: 'CriFO',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: themeMode,
      home: const MainShell(),
    );
  }
}

// ── Main Shell ────────────────────────────────────────────────────────────────
class MainShell extends ConsumerStatefulWidget {
  const MainShell({super.key});

  @override
  ConsumerState<MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<MainShell> {
  int _index = 0;

  static const _screens = [
    HomeScreen(),
    ScoresScreen(),
    TVScreen(),
    SearchScreen(),
  ];

  void _onTap(int i) {
    if (i == _index) return;
    HapticFeedback.selectionClick();
    setState(() => _index = i);
    if (i != 2) {
      ref.read(tvFullscreenProvider.notifier).state = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = ref.watch(themeModeProvider) == ThemeMode.dark;
    final fsWidget = ref.watch(tvFullscreenProvider);

    return Stack(
      children: [
        Scaffold(
          backgroundColor: context.cBg,
          body: IndexedStack(
            index: _index,
            children: _screens.map((s) => RepaintBoundary(child: s)).toList(),
          ),
          bottomNavigationBar: fsWidget == null
              ? _PremiumNavBar(currentIndex: _index, onTap: _onTap, isDark: isDark)
              : null,
        ),
        if (fsWidget != null) Positioned.fill(child: fsWidget),
      ],
    );
  }
}

// ── Premium Nav Bar ───────────────────────────────────────────────────────────
class _PremiumNavBar extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;
  final bool isDark;

  const _PremiumNavBar({
    required this.currentIndex,
    required this.onTap,
    required this.isDark,
  });

  static const _items = [
    _NavItem(label: 'HOME',   icon: Icons.home_outlined,          activeIcon: Icons.home_rounded),
    _NavItem(label: 'SCORES', icon: Icons.sports_soccer_outlined,  activeIcon: Icons.sports_soccer_rounded),
    _NavItem(label: 'TV',     icon: Icons.live_tv_outlined,        activeIcon: Icons.live_tv_rounded),
    _NavItem(label: 'SEARCH', icon: Icons.search_rounded,          activeIcon: Icons.manage_search_rounded),
  ];

  @override
  Widget build(BuildContext context) {
    final navBg  = isDark ? AppColors.navSurface : AppColors.navSurfaceLight;
    final borderC = isDark ? AppColors.border    : AppColors.borderLightMode;

    return Container(
      decoration: BoxDecoration(
        color: navBg,
        border: Border(top: BorderSide(color: borderC, width: 0.5)),
        boxShadow: [
          BoxShadow(
            color: isDark
                ? AppColors.accentPrimary.withValues(alpha: 0.04)
                : Colors.black.withValues(alpha: 0.06),
            blurRadius: 24,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 64,
          child: Row(
            children: List.generate(_items.length, (i) {
              final item   = _items[i];
              final active = currentIndex == i;
              return Expanded(
                child: GestureDetector(
                  onTap: () => onTap(i),
                  behavior: HitTestBehavior.opaque,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Icon with pill background
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 220),
                          curve: Curves.easeOutCubic,
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 5),
                          decoration: BoxDecoration(
                            color: active
                                ? AppColors.accentPrimary.withValues(alpha: 0.14)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(24),
                            border: active
                                ? Border.all(color: AppColors.accentPrimary.withValues(alpha: 0.25), width: 0.5)
                                : null,
                          ),
                          child: Icon(
                            active ? item.activeIcon : item.icon,
                            color: active
                                ? AppColors.accentPrimary
                                : context.cTextMuted,
                            size: 22,
                          ),
                        ),
                        const SizedBox(height: 3),
                        AnimatedDefaultTextStyle(
                          duration: const Duration(milliseconds: 200),
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            color: active ? AppColors.accentPrimary : context.cTextMuted,
                            letterSpacing: 0.8,
                          ),
                          child: Text(item.label),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}

class _NavItem {
  final String label;
  final IconData icon;
  final IconData activeIcon;
  const _NavItem({required this.label, required this.icon, required this.activeIcon});
}
