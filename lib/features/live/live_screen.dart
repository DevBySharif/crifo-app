import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../core/api/espn_client.dart';
import '../../core/models/espn_match.dart';
import '../../core/theme/colors.dart';


final _liveProvider = FutureProvider<List<ESPNMatch>>((ref) async {
  return EspnClient.getScoreboard();
});

class LiveScreen extends ConsumerStatefulWidget {
  const LiveScreen({super.key});

  @override
  ConsumerState<LiveScreen> createState() => _LiveScreenState();
}

class _LiveScreenState extends ConsumerState<LiveScreen> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) ref.invalidate(_liveProvider);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(_liveProvider);
    return Scaffold(
      backgroundColor: context.cBg,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(children: [
                Text('LIVE', style: TextStyle(fontFamily: 'Oswald', fontSize: 22, fontWeight: FontWeight.w700, color: context.cTextPrimary)),
                const Spacer(),
                Container(
                  width: 6, height: 6,
                  decoration: const BoxDecoration(color: AppColors.live, shape: BoxShape.circle),
                ),
                const SizedBox(width: 6),
                Text('AUTO REFRESH 30s', style: TextStyle(color: context.cTextMuted, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1)),
              ]),
            ),
            Divider(height: 1, color: context.cBorder),
            Expanded(
              child: data.when(
                data: (matches) => _LiveBody(matches: matches),
                loading: () => const Center(child: CircularProgressIndicator(color: AppColors.accentBlue)),
                error: (e, _) => Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.wifi_off, color: context.cTextMuted, size: 48),
                  const SizedBox(height: 12),
                  Text('Failed to load live scores', style: TextStyle(color: context.cTextPrimary, fontSize: 15)),
                  const SizedBox(height: 16),
                  TextButton(
                    onPressed: () => ref.invalidate(_liveProvider),
                    child: const Text('Retry', style: TextStyle(color: AppColors.accentBlue)),
                  ),
                ])),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LiveBody extends StatelessWidget {
  final List<ESPNMatch> matches;
  const _LiveBody({required this.matches});

  @override
  Widget build(BuildContext context) {
    final live = matches.where((m) => m.isLive).toList();
    final upcoming = matches.where((m) => m.isPre).toList();
    final finished = matches.where((m) => m.isPost).toList();

    final leagues = <String, List<ESPNMatch>>{};
    for (final m in matches) {
      leagues.putIfAbsent(m.leagueSlug, () => []);
      leagues[m.leagueSlug]!.add(m);
    }

    return RefreshIndicator(
      color: AppColors.accentBlue,
      backgroundColor: context.cBgCard,
      onRefresh: () async {
        // will be handled by riverpod
      },
      child: ListView(
        padding: const EdgeInsets.only(bottom: 100),
        children: [
          if (live.isNotEmpty) ...[
            _SectionHeader(title: 'LIVE NOW', count: live.length),
            const SizedBox(height: 4),
            ...live.map((m) => _ESPNMatchCard(match: m)),
          ],
          if (upcoming.isNotEmpty) ...[
            _SectionHeader(title: 'UPCOMING', count: upcoming.length),
            const SizedBox(height: 4),
            ...upcoming.map((m) => _ESPNMatchCard(match: m)),
          ],
          if (finished.isNotEmpty) ...[
            _SectionHeader(title: 'RESULTS', count: finished.length),
            const SizedBox(height: 4),
            ...finished.take(10).map((m) => _ESPNMatchCard(match: m)),
          ],
          if (live.isEmpty && upcoming.isEmpty && finished.isEmpty)
            Padding(
              padding: EdgeInsets.only(top: 80),
              child: Center(child: Column(children: [
                Icon(Icons.sports_soccer, color: context.cTextMuted, size: 64),
                SizedBox(height: 16),
                Text('No matches available', style: TextStyle(color: context.cTextMuted, fontSize: 15)),
                SizedBox(height: 8),
                Text('Pull down to refresh', style: TextStyle(color: context.cTextMuted, fontSize: 12)),
              ])),
            ),
          // League-wise breakdown
          if (matches.length > 10) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
              child: Text('ALL LEAGUES', style: TextStyle(color: context.cTextMuted, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.5)),
            ),
            ...leagues.entries.map((e) => _LeagueGroup(
              slug: e.key,
              name: e.value.first.leagueName,
              logo: e.value.first.leagueLogo,
              matches: e.value,
            )),
          ],
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final int count;
  const _SectionHeader({required this.title, this.count = 0});

  @override
  Widget build(BuildContext context) {
    final isLive = title == 'LIVE NOW';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Row(children: [
        if (isLive) ...[
          Container(
            width: 8, height: 8,
            decoration: const BoxDecoration(color: AppColors.live, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
        ],
        Text(title, style: TextStyle(
          fontFamily: 'Inter', fontSize: 11, fontWeight: FontWeight.w700,
          color: isLive ? AppColors.live : context.cTextMuted,
          letterSpacing: 1.5,
        )),
        const Spacer(),
        Text('$count', style: TextStyle(color: context.cTextMuted, fontSize: 11, fontWeight: FontWeight.w600)),
      ]),
    );
  }
}

class _ESPNMatchCard extends StatelessWidget {
  final ESPNMatch match;
  const _ESPNMatchCard({required this.match});

  @override
  Widget build(BuildContext context) {
    return Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: context.cBgCard,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: match.isLive ? AppColors.live.withValues(alpha: 0.3) : context.cBorder,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (match.leagueName.isNotEmpty) ...[
              Row(children: [
                if (match.leagueLogo.isNotEmpty)
                  CachedNetworkImage(imageUrl: match.leagueLogo, width: 14, height: 14,
                    errorWidget: (_, __, ___) => const SizedBox(width: 14))
                else
                  const SizedBox(width: 14),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(match.leagueName,
                    style: TextStyle(color: context.cTextMuted, fontSize: 10, fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis),
                ),
                if (match.isLive)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.live.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Container(width: 5, height: 5, decoration: const BoxDecoration(color: AppColors.live, shape: BoxShape.circle)),
                      const SizedBox(width: 4),
                      Text(match.displayTime, style: const TextStyle(color: AppColors.live, fontSize: 10, fontWeight: FontWeight.w700)),
                    ]),
                  )
                else if (match.isPre)
                  Text(match.statusDetail, style: TextStyle(color: context.cTextMuted, fontSize: 10))
                else
                  Text('FT', style: TextStyle(color: context.cTextMuted, fontSize: 10)),
              ]),
              const SizedBox(height: 10),
            ],
            Row(children: [
              Expanded(child: _TeamLogoRow(
                logo: match.logoA,
                name: match.teamA,
                abbr: match.homeAbbr,
                score: match.scoreA,
                isWinner: match.isPost && int.tryParse(match.scoreA) != null && int.tryParse(match.scoreB) != null && int.parse(match.scoreA) > int.parse(match.scoreB),
              )),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  match.isPre ? 'vs' : '${match.scoreA} - ${match.scoreB}',
                  style: TextStyle(
                    fontFamily: 'Oswald', fontSize: match.isPre ? 14 : 20,
                    fontWeight: FontWeight.w700,
                    color: match.isPre ? context.cTextMuted : context.cTextPrimary,
                  ),
                ),
              ),
              Expanded(child: _TeamLogoRow(
                logo: match.logoB,
                name: match.teamB,
                abbr: match.awayAbbr,
                score: match.scoreB,
                isAway: true,
                isWinner: match.isPost && int.tryParse(match.scoreA) != null && int.tryParse(match.scoreB) != null && int.parse(match.scoreB) > int.parse(match.scoreA),
              )),
            ]),
            if (match.scorers.isNotEmpty) ...[
              const SizedBox(height: 8),
              ...match.scorers.map((s) => Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text('⚽ ${s.name}', style: TextStyle(color: context.cTextSecondary, fontSize: 11)),
              )),
            ],
          ],
        ),
    );
  }
}

class _TeamLogoRow extends StatelessWidget {
  final String logo;
  final String name;
  final String abbr;
  final String score;
  final bool isAway;
  final bool isWinner;
  const _TeamLogoRow({
    required this.logo, required this.name, required this.abbr,
    this.score = '', this.isAway = false, this.isWinner = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      textDirection: isAway ? TextDirection.rtl : TextDirection.ltr,
      children: [
        if (logo.startsWith('http'))
          CachedNetworkImage(imageUrl: logo, width: 24, height: 24,
            errorWidget: (_, __, ___) => Icon(Icons.sports_soccer, size: 20, color: context.cTextMuted))
        else
          Icon(Icons.sports_soccer, size: 20, color: context.cTextMuted),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            abbr.isNotEmpty ? abbr : (name.length > 12 ? '${name.substring(0, 10)}.' : name),
            style: TextStyle(
              fontFamily: 'Inter', fontSize: 12,
              fontWeight: isWinner ? FontWeight.w700 : FontWeight.w400,
              color: isWinner ? context.cTextPrimary : context.cTextSecondary,
            ),
            textAlign: isAway ? TextAlign.right : TextAlign.left,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

class _LeagueGroup extends StatelessWidget {
  final String slug;
  final String name;
  final String logo;
  final List<ESPNMatch> matches;
  const _LeagueGroup({required this.slug, required this.name, required this.logo, required this.matches});

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        color: context.cBgCard,
        child: Row(children: [
          if (logo.isNotEmpty)
            CachedNetworkImage(imageUrl: logo, width: 18, height: 18,
              errorWidget: (_, __, ___) => Icon(Icons.sports_soccer, size: 16, color: context.cTextMuted)),
          const SizedBox(width: 10),
          Expanded(child: Text(name, style: TextStyle(color: context.cTextPrimary, fontSize: 12, fontWeight: FontWeight.w600))),
          Text('${matches.length}', style: TextStyle(color: context.cTextMuted, fontSize: 11)),
        ]),
      ),
      Divider(height: 1, color: context.cBorder),
    ]);
  }
}
