import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_jailbreak_detection/flutter_jailbreak_detection.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/colors.dart';
import 'core/theme/theme_provider.dart';
import 'core/providers/tv_fullscreen_provider.dart';
import 'core/services/update_checker.dart';
import 'features/home/home_screen.dart';
import 'features/scores/scores_screen.dart';
import 'features/tv/tv_screen.dart';
import 'features/search/search_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Firebase may not be configured (e.g. CI builds without google-services.json).
  // Gracefully skip so the app still works without Firebase features.
  try {
    await Firebase.initializeApp();
  } catch (_) {
    // no-op
  }
  // Lock the app to portrait. Video fullscreen fakes landscape with a 90°
  // Transform.rotate, which assumes the underlying app never rotates —
  // without this lock, turning the phone rotated the whole app AND the
  // rotated player, breaking fullscreen completely.
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: AppColors.navSurface,
    systemNavigationBarIconBrightness: Brightness.light,
  ));
  runApp(const ProviderScope(child: CriFOApp()));
}

final jailbreakProvider = FutureProvider<bool>((ref) async {
  try {
    return await FlutterJailbreakDetection.jailbroken;
  } catch (_) {
    return false;
  }
});

class CriFOApp extends ConsumerWidget {
  const CriFOApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    final isDark = themeMode == ThemeMode.dark;
    final jailbreak = ref.watch(jailbreakProvider);

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
      themeAnimationDuration: const Duration(milliseconds: 350),
      themeAnimationCurve: Curves.easeOutCubic,
      home: jailbreak.when(
        data: (isJailbroken) {
          if (isJailbroken) return const SecurityBlockScreen();
          return const MainShell();
        },
        loading: () => const Scaffold(
          backgroundColor: AppColors.bg,
          body: Center(child: CircularProgressIndicator(color: AppColors.accentPrimary)),
        ),
        error: (_, __) => const MainShell(),
      ),
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

  @override
  void initState() {
    super.initState();
    // A moment after first paint, ask the website if a newer build exists.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await Future.delayed(const Duration(seconds: 2));
      final update = await checkForUpdate();
      if (update != null && mounted) _showUpdateDialog(update);
    });
  }

  void _showUpdateDialog(AppUpdate u) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ctx.cBgCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(children: [
          const Icon(Icons.system_update_rounded, color: AppColors.accentPrimary, size: 22),
          const SizedBox(width: 10),
          Text('Update available', style: TextStyle(color: ctx.cTextPrimary, fontSize: 17, fontWeight: FontWeight.w700)),
        ]),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Version ${u.versionName} is ready.',
              style: TextStyle(color: ctx.cTextSecondary, fontSize: 13)),
          if (u.releaseNotes.trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(u.releaseNotes, style: TextStyle(color: ctx.cTextMuted, fontSize: 12, height: 1.4)),
          ],
        ]),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Later', style: TextStyle(color: ctx.cTextMuted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.accentPrimary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () async {
              Navigator.pop(ctx);
              // Security: only launch https:// APK download links.
              // A compromised version.json cannot redirect to dangerous schemes
              // (intent:, javascript:, file:, content:, etc.).
              final rawUrl = u.apkUrl.trim();
              final uri = Uri.tryParse(rawUrl);
              if (uri != null &&
                  uri.scheme == 'https' &&
                  uri.host.isNotEmpty) {
                try { await launchUrl(uri, mode: LaunchMode.externalApplication); } catch (_) {}
              }
            },
            child: const Text('Update', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

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

    // A screen requested TV playback (e.g. match "Where to watch") — jump to TV tab
    ref.listen(tvPlayRequestProvider, (prev, next) {
      if (next != null && _index != 2) {
        // Pop pushed routes (match detail etc.) so the TV tab is visible
        Navigator.of(context).popUntil((r) => r.isFirst);
        setState(() => _index = 2);
      }
    });

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

class SecurityBlockScreen extends StatelessWidget {
  const SecurityBlockScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF06060E),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: const Color(0xFFEF4444).withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xFFEF4444).withValues(alpha: 0.3), width: 2),
                ),
                child: const Icon(
                  Icons.security_rounded,
                  color: Color(0xFFEF4444),
                  size: 48,
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'Security Violation',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  fontFamily: 'Inter',
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'This device appears to be rooted or jailbroken. For security and proxy integrity reasons, CriFO cannot run on modified operating systems.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: const Color(0xFF7A7A9A),
                  fontSize: 13,
                  fontFamily: 'Inter',
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 32),
              GestureDetector(
                onTap: () => SystemNavigator.pop(),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEF4444),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFEF4444).withValues(alpha: 0.3),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      )
                    ],
                  ),
                  child: const Text(
                    'Exit Application',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      fontFamily: 'Inter',
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
