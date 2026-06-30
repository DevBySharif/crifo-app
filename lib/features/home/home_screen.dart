import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/api/fotmob_client.dart';
import '../../core/api/espn_client.dart';
import '../../core/theme/colors.dart';
import '../match_detail/match_detail_screen.dart';

// ── Providers ──────────────────────────────────────────────────────────────────
final _matchesProvider = FutureProvider.family<Map<String, dynamic>, String>((ref, date) async {
  ref.keepAlive();
  return FotmobClient.getMatchesByDate(date);
});

final _newsProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  ref.keepAlive();
  try {
    return await FotmobClient.getWorldNews();
  } catch (_) {
    return EspnClient.getNews();
  }
});

// ── Safe helpers ───────────────────────────────────────────────────────────────
Map<String, dynamic> _m(dynamic v) {
  if (v is Map<String, dynamic>) return v;
  if (v is Map) return v.cast<String, dynamic>();
  return {};
}
List _l(dynamic v) => v is List ? v : [];
String _s(dynamic v) => v?.toString() ?? '';

String _todayKey() {
  final now = DateTime.now().toUtc();
  return '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
}

// ── HomeScreen ─────────────────────────────────────────────────────────────────
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final today = _todayKey();
    final matchData = ref.watch(_matchesProvider(today));

    return Scaffold(
      backgroundColor: context.cBg,
      body: CustomScrollView(
        slivers: [
          // Premium SliverAppBar
          SliverToBoxAdapter(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    AppColors.accentPrimary.withValues(alpha: 0.08),
                    Colors.transparent,
                  ],
                ),
              ),
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 16, 12),
                  child: Row(children: [
                    // Premium CriFO wordmark
                    ShaderMask(
                      shaderCallback: (b) => AppColors.primaryGradient.createShader(b),
                      child: const Text(
                        'CriFO',
                        style: TextStyle(
                          fontFamily: 'Oswald',
                          fontSize: 28,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                          letterSpacing: 1.0,
                        ),
                      ),
                    ),
                    const Spacer(),
                    // Live indicator chip
                    _LiveChip(),
                    const SizedBox(width: 10),
                    // Notification bell
                    Container(
                      width: 36, height: 36,
                      decoration: BoxDecoration(
                        color: context.cBgElevated,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: context.cBorder),
                      ),
                      child: Icon(Icons.notifications_outlined, color: context.cTextSecondary, size: 20),
                    ),
                  ]),
                ),
              ),
            ),
          ),

          // Content
          SliverToBoxAdapter(
            child: matchData.when(
              data: (d) => _MatchBody(data: d),
              loading: () => SizedBox(
                height: 400,
                child: const Center(child: _PremiumLoader()),
              ),
              error: (e, _) => SizedBox(
                height: 400,
                child: _ErrorState(onRetry: () => ref.invalidate(_matchesProvider(today))),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LiveChip extends StatefulWidget {
  @override
  State<_LiveChip> createState() => _LiveChipState();
}

class _LiveChipState extends State<_LiveChip> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _pulse;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(seconds: 1))
      ..repeat(reverse: true);
    _pulse = Tween<double>(begin: 0.4, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _pulse,
      builder: (_, __) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: AppColors.live.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.live.withValues(alpha: _pulse.value * 0.6)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 6, height: 6,
            decoration: BoxDecoration(
              color: AppColors.live.withValues(alpha: _pulse.value),
              shape: BoxShape.circle,
              boxShadow: [BoxShadow(color: AppColors.live.withValues(alpha: 0.5), blurRadius: 4)],
            ),
          ),
          const SizedBox(width: 5),
          const Text('LIVE', style: TextStyle(
            fontFamily: 'Inter', fontSize: 9, fontWeight: FontWeight.w800,
            color: AppColors.live, letterSpacing: 1.2,
          )),
        ]),
      ),
    );
  }
}

class _PremiumLoader extends StatelessWidget {
  const _PremiumLoader();

  @override
  Widget build(BuildContext context) {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      SizedBox(
        width: 36, height: 36,
        child: CircularProgressIndicator(
          color: AppColors.accentPrimary,
          backgroundColor: AppColors.accentPrimary.withValues(alpha: 0.1),
          strokeWidth: 2.5,
        ),
      ),
      const SizedBox(height: 12),
      const Text('Loading matches...', style: TextStyle(color: AppColors.textMuted, fontSize: 12, fontFamily: 'Inter')),
    ]);
  }
}

class _ErrorState extends StatelessWidget {
  final VoidCallback onRetry;
  const _ErrorState({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Column(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children: [
      Container(
        width: 64, height: 64,
        decoration: BoxDecoration(
          color: AppColors.bgElevated,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.border),
        ),
        child: const Icon(Icons.wifi_off_rounded, color: AppColors.textMuted, size: 30),
      ),
      const SizedBox(height: 16),
      const Text('Connection failed', style: TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w600, fontFamily: 'Inter')),
      const SizedBox(height: 6),
      const Text('Check your internet connection', style: TextStyle(color: AppColors.textMuted, fontSize: 12, fontFamily: 'Inter')),
      const SizedBox(height: 20),
      GestureDetector(
        onTap: onRetry,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
          decoration: BoxDecoration(
            gradient: AppColors.primaryGradient,
            borderRadius: BorderRadius.circular(20),
          ),
          child: const Text('Retry', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700, fontFamily: 'Inter')),
        ),
      ),
    ]);
  }
}

// ── Match body with news + sections ───────────────────────────────────────────
class _MatchBody extends ConsumerWidget {
  final Map<String, dynamic> data;
  const _MatchBody({required this.data});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final allMatches = _buildAllMatches(data);
    final live      = allMatches.where((m) => _isLive(m)).toList();
    final upcoming  = allMatches.where((m) => _isUpcoming(m)).toList();
    final finished  = allMatches.where((m) => _isFinished(m)).toList();

    return Column(children: [
      // News Hero Banner
      const _NewsBanner(),
      const SizedBox(height: 4),

      // Live
      if (live.isNotEmpty) ...[
        _SectionHdr(title: 'LIVE NOW', isLive: true, count: live.length),
        SizedBox(
          height: 120,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: live.length,
            itemBuilder: (ctx, i) => _LiveCard(match: live[i]),
          ),
        ),
        const SizedBox(height: 4),
      ],

      // Upcoming
      if (upcoming.isNotEmpty) ...[
        _SectionHdr(title: 'UPCOMING', count: upcoming.length),
        ...upcoming.map((m) => _MatchRow(match: m)),
      ],

      // Finished
      if (finished.isNotEmpty) ...[
        _SectionHdr(title: 'RESULTS', count: finished.length),
        ...finished.map((m) => _MatchRow(match: m)),
      ],

      if (live.isEmpty && upcoming.isEmpty && finished.isEmpty)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 60),
          child: Column(children: [
            Icon(Icons.sports_soccer_outlined, color: AppColors.textMuted, size: 48),
            SizedBox(height: 12),
            Text('No matches today', style: TextStyle(color: AppColors.textMuted, fontSize: 14, fontFamily: 'Inter')),
          ]),
        ),

      const SizedBox(height: 100),
    ]);
  }

  List<Map<String, dynamic>> _buildAllMatches(Map<String, dynamic> data) {
    final leagues = _l(data['leagues']);
    final result = <Map<String, dynamic>>[];
    for (final lg in leagues) {
      final league = _m(lg);
      for (final m in _l(league['matches'])) {
        result.add({..._m(m), '_league': league});
      }
    }
    return result;
  }

  bool _isLive(Map<String, dynamic> m) {
    final s = _m(m['status']);
    return s['started'] == true && s['finished'] == false;
  }
  bool _isUpcoming(Map<String, dynamic> m) => _m(m['status'])['started'] != true;
  bool _isFinished(Map<String, dynamic> m) => _m(m['status'])['finished'] == true;
}

// ── News Banner ────────────────────────────────────────────────────────────────
class _NewsBanner extends ConsumerStatefulWidget {
  const _NewsBanner();

  @override
  ConsumerState<_NewsBanner> createState() => _NewsBannerState();
}

class _NewsBannerState extends ConsumerState<_NewsBanner> {
  int _index = 0;
  Timer? _timer;
  final _controller = PageController();

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted) return;
      final items = ref.read(_newsProvider).valueOrNull ?? [];
      final count = items.length > 5 ? 5 : items.length;
      if (count <= 1) return;
      setState(() { _index = (_index + 1) % count; });
      _controller.animateToPage(_index,
          duration: const Duration(milliseconds: 500), curve: Curves.easeInOutCubic);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final news = ref.watch(_newsProvider);
    return news.when(
      data: (articles) {
        if (articles.isEmpty) return const SizedBox.shrink();
        final items = articles.take(5).toList();
        return Column(children: [
          SizedBox(
            height: 220,
            child: Stack(children: [
              PageView.builder(
                controller: _controller,
                itemCount: items.length,
                onPageChanged: (i) => setState(() => _index = i),
                itemBuilder: (ctx, i) => _NewsSlide(article: items[i]),
              ),
              // Gradient page indicators
              Positioned(
                bottom: 14, left: 0, right: 0,
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  for (int i = 0; i < items.length; i++)
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 350),
                      curve: Curves.easeOutCubic,
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      width: i == _index ? 22 : 6,
                      height: 4,
                      decoration: BoxDecoration(
                        gradient: i == _index ? AppColors.primaryGradient : null,
                        color: i == _index ? null : AppColors.textMuted.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                ]),
              ),
            ]),
          ),
        ]);
      },
      loading: () => Container(
        height: 220,
        margin: const EdgeInsets.only(bottom: 2),
        color: AppColors.bgCard,
        child: const Center(child: _PremiumLoader()),
      ),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}

class _NewsSlide extends StatelessWidget {
  final Map<String, dynamic> article;
  const _NewsSlide({required this.article});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () async {
        final url = _s(article['url']);
        if (url.isNotEmpty) await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      },
      child: Stack(children: [
        CachedNetworkImage(
          imageUrl: _s(article['imageUrl']),
          width: double.infinity, height: 220,
          fit: BoxFit.cover,
          errorWidget: (_, __, ___) => Container(height: 220, color: AppColors.bgCard,
            child: const Icon(Icons.image_not_supported_outlined, color: AppColors.textMuted, size: 40)),
        ),
        // Deep gradient overlay
        Positioned.fill(
          child: DecoratedBox(decoration: BoxDecoration(gradient: AppColors.heroGradient)),
        ),
        // Source badge + title
        Positioned(
          bottom: 0, left: 0, right: 0,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 30),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (_s(article['source']).isNotEmpty)
                Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    gradient: AppColors.primaryGradient,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(_s(article['source']).toUpperCase(),
                    style: const TextStyle(color: Colors.white, fontSize: 9,
                        fontWeight: FontWeight.w800, letterSpacing: 0.8, fontFamily: 'Inter')),
                ),
              Text(_s(article['title']),
                style: const TextStyle(
                  fontFamily: 'Oswald', fontSize: 19, fontWeight: FontWeight.w700,
                  color: Colors.white, letterSpacing: 0.3, height: 1.25,
                ),
                maxLines: 2, overflow: TextOverflow.ellipsis),
            ]),
          ),
        ),
      ]),
    );
  }
}

// ── Section header ─────────────────────────────────────────────────────────────
class _SectionHdr extends StatelessWidget {
  final String title;
  final bool isLive;
  final int count;
  const _SectionHdr({required this.title, this.isLive = false, this.count = 0});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 10),
      child: Row(children: [
        // Accent line
        Container(
          width: 3, height: 14,
          decoration: BoxDecoration(
            gradient: isLive ? AppColors.liveGradient : AppColors.primaryGradient,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        Text(title, style: TextStyle(
          fontFamily: 'Inter', fontSize: 11, fontWeight: FontWeight.w800,
          color: isLive ? AppColors.live : AppColors.textSecondary, letterSpacing: 1.8,
        )),
        if (count > 0) ...[
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: isLive ? AppColors.live.withValues(alpha: 0.12) : AppColors.bgElevated,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text('$count', style: TextStyle(
              fontSize: 10, fontWeight: FontWeight.w700, fontFamily: 'Inter',
              color: isLive ? AppColors.live : AppColors.textMuted,
            )),
          ),
        ],
        const Spacer(),
        if (!isLive)
          const Icon(Icons.chevron_right, color: AppColors.textMuted, size: 16),
      ]),
    );
  }
}

// ── Live Card (horizontal scroll) ─────────────────────────────────────────────
class _LiveCard extends StatelessWidget {
  final Map<String, dynamic> match;
  const _LiveCard({required this.match});

  @override
  Widget build(BuildContext context) {
    final status = _m(match['status']);
    final home   = _m(match['home']);
    final away   = _m(match['away']);
    final score  = _s(status['scoreStr']);
    final minute = _s(_m(status['liveTime'])['short']);

    return GestureDetector(
      onTap: () {
        final mid = _s(match['id']);
        if (mid.isNotEmpty) Navigator.push(context, MaterialPageRoute(builder: (_) => MatchDetailScreen(matchId: mid)));
      },
      child: Container(
        width: 200,
        margin: const EdgeInsets.only(right: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          gradient: AppColors.cardGradient,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.live.withValues(alpha: 0.3), width: 1),
          boxShadow: [
            BoxShadow(color: AppColors.live.withValues(alpha: 0.08), blurRadius: 12, spreadRadius: 0),
          ],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Minute badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              gradient: AppColors.liveGradient,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(minute.isNotEmpty ? minute : 'LIVE',
              style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800, fontFamily: 'Inter')),
          ),
          const SizedBox(height: 10),
          Row(children: [
            _MiniTeam(team: home),
            Expanded(child: Center(child: Text(score.isNotEmpty ? score : '- -',
              style: const TextStyle(fontFamily: 'Oswald', fontSize: 22,
                  fontWeight: FontWeight.w700, color: AppColors.textPrimary)))),
            _MiniTeam(team: away, align: TextAlign.right),
          ]),
        ]),
      ),
    );
  }
}

class _MiniTeam extends StatelessWidget {
  final Map<String, dynamic> team;
  final TextAlign align;
  const _MiniTeam({required this.team, this.align = TextAlign.left});

  @override
  Widget build(BuildContext context) {
    final id   = team['id'];
    final name = _s(team['name']);
    return SizedBox(
      width: 60,
      child: Column(children: [
        if (id != null)
          CachedNetworkImage(imageUrl: FotmobClient.teamLogoUrl(id), width: 30, height: 30,
            errorWidget: (_, __, ___) => Container(width: 30, height: 30,
              decoration: BoxDecoration(color: AppColors.bgElevated, borderRadius: BorderRadius.circular(6))))
        else
          Container(width: 30, height: 30,
            decoration: BoxDecoration(color: AppColors.bgElevated, borderRadius: BorderRadius.circular(6))),
        const SizedBox(height: 5),
        Text(name, style: const TextStyle(color: AppColors.textSecondary, fontSize: 10,
            fontWeight: FontWeight.w500, fontFamily: 'Inter'),
            textAlign: align, maxLines: 1, overflow: TextOverflow.ellipsis),
      ]),
    );
  }
}

// ── Match Row ──────────────────────────────────────────────────────────────────
class _MatchRow extends StatelessWidget {
  final Map<String, dynamic> match;
  const _MatchRow({required this.match});

  @override
  Widget build(BuildContext context) {
    final status   = _m(match['status']);
    final home     = _m(match['home']);
    final away     = _m(match['away']);
    final isLive   = status['started'] == true && status['finished'] == false;
    final finished = status['finished'] == true;
    final score    = _s(status['scoreStr']);
    final minute   = _s(_m(status['liveTime'])['short']);

    final parts   = score.split('-');
    final hG      = parts.isNotEmpty ? int.tryParse(parts.first.trim()) ?? -1 : -1;
    final aG      = parts.length > 1 ? int.tryParse(parts.last.trim()) ?? -1 : -1;
    final homeWin = finished && hG > aG;
    final awayWin = finished && aG > hG;

    return GestureDetector(
      onTap: () {
        final id = _s(match['id']);
        if (id.isNotEmpty) Navigator.push(context, MaterialPageRoute(builder: (_) => MatchDetailScreen(matchId: id)));
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: AppColors.border.withValues(alpha: 0.6), width: 0.5)),
        ),
        child: Row(children: [
          // Time / status column
          SizedBox(
            width: 46,
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              if (isLive) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.live.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: AppColors.live.withValues(alpha: 0.3)),
                  ),
                  child: Text(minute.isNotEmpty ? minute : 'LIVE',
                    style: const TextStyle(color: AppColors.live, fontSize: 9, fontWeight: FontWeight.w800, fontFamily: 'Inter')),
                ),
              ] else
                Text(finished ? 'FT' : _formatTime(status['utcTime']),
                  style: TextStyle(fontSize: 11, fontFamily: 'Inter',
                    color: finished ? AppColors.textMuted : AppColors.textSecondary,
                    fontWeight: finished ? FontWeight.w400 : FontWeight.w600),
                  textAlign: TextAlign.center),
            ]),
          ),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _TeamLine(team: home, score: parts.isNotEmpty ? parts.first.trim() : '', isWinner: homeWin),
            const SizedBox(height: 7),
            _TeamLine(team: away, score: parts.length > 1 ? parts.last.trim() : '', isWinner: awayWin),
          ])),
          // Chevron
          const Icon(Icons.chevron_right, color: AppColors.textMuted, size: 16),
        ]),
      ),
    );
  }

  String _formatTime(dynamic utc) {
    if (utc == null) return '';
    try {
      final dt = DateTime.parse(utc.toString()).toLocal();
      return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) { return ''; }
  }
}

class _TeamLine extends StatelessWidget {
  final Map<String, dynamic> team;
  final String score;
  final bool isWinner;
  const _TeamLine({required this.team, required this.score, required this.isWinner});

  @override
  Widget build(BuildContext context) {
    final id   = team['id'];
    final name = _s(team['longName']).isNotEmpty ? _s(team['longName']) : _s(team['name']);
    return Row(children: [
      if (id != null)
        CachedNetworkImage(imageUrl: FotmobClient.teamLogoUrl(id), width: 20, height: 20,
          errorWidget: (_, __, ___) => const SizedBox(width: 20, height: 20))
      else
        const SizedBox(width: 20, height: 20),
      const SizedBox(width: 10),
      Expanded(child: Text(name,
        style: TextStyle(fontFamily: 'Inter', fontSize: 13,
          fontWeight: isWinner ? FontWeight.w700 : FontWeight.w400,
          color: isWinner ? AppColors.textPrimary : AppColors.textSecondary),
        overflow: TextOverflow.ellipsis)),
      if (score.isNotEmpty)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
          decoration: isWinner ? BoxDecoration(
            color: AppColors.accentPrimary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(4),
          ) : null,
          child: Text(score, style: TextStyle(fontFamily: 'Oswald', fontSize: 15,
            fontWeight: isWinner ? FontWeight.w700 : FontWeight.w400,
            color: isWinner ? AppColors.accentPrimary : AppColors.textMuted)),
        ),
    ]);
  }
}
