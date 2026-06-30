import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../core/api/espn_client.dart';
import '../../core/models/espn_match.dart';
import '../../core/theme/colors.dart';

final _summaryProvider = FutureProvider.family<Map<String, dynamic>, String>((ref, arg) async {
  final parts = arg.split(':');
  final slug = parts[0];
  final matchId = parts[1];
  return EspnClient.getMatchSummary(slug, matchId);
});

class ESPNMatchDetailScreen extends ConsumerStatefulWidget {
  final String matchId;
  final String leagueSlug;
  final ESPNMatch match;
  const ESPNMatchDetailScreen({
    super.key,
    required this.matchId,
    required this.leagueSlug,
    required this.match,
  });

  @override
  ConsumerState<ESPNMatchDetailScreen> createState() => _ESPNMatchDetailScreenState();
}

class _ESPNMatchDetailScreenState extends ConsumerState<ESPNMatchDetailScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: NestedScrollView(
        headerSliverBuilder: (ctx, _) => [
          SliverAppBar(
            backgroundColor: AppColors.bg,
            pinned: true,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
              onPressed: () => Navigator.pop(context),
            ),
            flexibleSpace: FlexibleSpaceBar(
              background: _MatchHeader(match: widget.match),
            ),
            expandedHeight: 180,
            bottom: TabBar(
              controller: _tabs,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              indicatorColor: AppColors.accentBlue,
              labelColor: AppColors.accentBlue,
              unselectedLabelColor: AppColors.textMuted,
              labelStyle: const TextStyle(fontFamily: 'Inter', fontSize: 11, fontWeight: FontWeight.w700),
              tabs: const [
                Tab(text: 'DETAILS'),
                Tab(text: 'EVENTS'),
                Tab(text: 'STATS'),
              ],
            ),
          ),
        ],
        body: TabBarView(
          controller: _tabs,
          children: [
            _DetailsTab(match: widget.match),
            _ESPNEventsTab(matchId: widget.matchId, leagueSlug: widget.leagueSlug),
            _ESPNStatsTab(matchId: widget.matchId, leagueSlug: widget.leagueSlug),
          ],
        ),
      ),
    );
  }
}

class _MatchHeader extends StatelessWidget {
  final ESPNMatch match;
  const _MatchHeader({required this.match});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.bg,
      padding: const EdgeInsets.fromLTRB(16, 80, 16, 8),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
        Expanded(child: _HeaderTeam(
          logo: match.logoA,
          name: match.teamA,
          record: match.recordA,
        )),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            if (match.isLive) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.live.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Container(width: 6, height: 6, decoration: const BoxDecoration(color: AppColors.live, shape: BoxShape.circle)),
                  const SizedBox(width: 4),
                  Text('LIVE ${match.displayTime}',
                      style: const TextStyle(color: AppColors.live, fontSize: 11, fontWeight: FontWeight.w700)),
                ]),
              ),
              const SizedBox(height: 4),
            ] else if (match.isPost) ...[
              const Text('FT', style: TextStyle(color: AppColors.textMuted, fontSize: 12, fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
            ] else ...[
              Text(match.statusDetail, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12, fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
            ],
            Text(
              match.isPre ? 'vs' : '${match.scoreA} - ${match.scoreB}',
              style: const TextStyle(fontFamily: 'Oswald', fontSize: 40, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
            ),
          ]),
        ),
        Expanded(child: _HeaderTeam(
          logo: match.logoB,
          name: match.teamB,
          record: match.recordB,
        )),
      ]),
    );
  }
}

class _HeaderTeam extends StatelessWidget {
  final String logo;
  final String name;
  final String record;
  const _HeaderTeam({required this.logo, required this.name, this.record = ''});

  @override
  Widget build(BuildContext context) {
    return Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      if (logo.startsWith('http'))
        CachedNetworkImage(imageUrl: logo, width: 54, height: 54,
          errorWidget: (_, __, ___) => const Icon(Icons.sports_soccer, size: 44, color: AppColors.textMuted))
      else
        const Icon(Icons.sports_soccer, size: 44, color: AppColors.textMuted),
      const SizedBox(height: 6),
      Text(name, style: const TextStyle(fontFamily: 'Inter', fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
        textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis),
      if (record.isNotEmpty)
        Text(record, style: const TextStyle(color: AppColors.textMuted, fontSize: 10)),
    ]);
  }
}

class _DetailsTab extends StatelessWidget {
  final ESPNMatch match;
  const _DetailsTab({required this.match});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        _SecTitle('MATCH INFO'),
        _InfoRow(icon: Icons.calendar_today, text: match.date.replaceAll('T', ' ').substring(0, 16)),
        if (match.venue.isNotEmpty)
          _InfoRow(icon: Icons.location_on, text: [match.venue, match.venueCity].where((s) => s.isNotEmpty).join(', ')),
        if (match.attendance.isNotEmpty)
          _InfoRow(icon: Icons.people, text: 'Attendance: ${match.attendance}'),
        if (match.broadcasts.isNotEmpty)
          _InfoRow(icon: Icons.tv, text: 'TV: ${match.broadcasts.join(', ')}'),
        if (match.groupName.isNotEmpty)
          _InfoRow(icon: Icons.emoji_events, text: match.groupName),

        if (match.scorers.isNotEmpty) ...[
          const _SecTitle('GOALS'),
          ...match.scorers.map((s) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(children: [
              const Text('⚽ ', style: TextStyle(fontSize: 16)),
              Text(s.name, style: const TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w600)),
              if (s.value != '1')
                Text(' ×${s.value}', style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
            ]),
          )),
        ],
      ],
    );
  }
}

class _SecTitle extends StatelessWidget {
  final String title;
  const _SecTitle(this.title);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 20, bottom: 10),
    child: Text(title, style: const TextStyle(fontFamily: 'Inter', fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textMuted, letterSpacing: 1.5)),
  );
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String text;
  const _InfoRow({required this.icon, required this.text});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Row(children: [
      Icon(icon, size: 15, color: AppColors.textMuted),
      const SizedBox(width: 10),
      Expanded(child: Text(text, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13))),
    ]),
  );
}

class _ESPNEventsTab extends ConsumerWidget {
  final String matchId;
  final String leagueSlug;
  const _ESPNEventsTab({required this.matchId, required this.leagueSlug});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(_summaryProvider('$leagueSlug:$matchId'));
    return data.when(
      data: (d) {
        final events = (d['events'] as List?)?.cast<Map<String, dynamic>>() ?? [];
        if (events.isEmpty) {
          return const Center(child: Text('No events available', style: TextStyle(color: AppColors.textMuted)));
        }
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: events.map((e) {
            final type = e['type']?.toString() ?? '';
            final text = e['text']?.toString() ?? '';
            final clock = e['clock']?.toString() ?? '';
            final isHome = e['team']?['homeAway'] == 'home';
            final isGoal = type.toLowerCase().contains('goal');
            final isCard = type.toLowerCase().contains('card');
            final isSub = type.toLowerCase().contains('substitution');
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                textDirection: isHome ? TextDirection.ltr : TextDirection.rtl,
                children: [
                  SizedBox(
                    width: 36,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      decoration: BoxDecoration(
                        color: AppColors.bgCard, borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(clock, style: const TextStyle(fontFamily: 'Oswald', fontSize: 11, color: AppColors.textSecondary), textAlign: TextAlign.center),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    isGoal ? Icons.sports_soccer : (isCard ? Icons.square_rounded : (isSub ? Icons.swap_horiz : Icons.info_outline)),
                    color: isGoal ? AppColors.accentGreen : (isCard ? AppColors.accentOrange : AppColors.textMuted),
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: Text(text, style: const TextStyle(color: AppColors.textPrimary, fontSize: 12), overflow: TextOverflow.ellipsis)),
                ],
              ),
            );
          }).toList(),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator(color: AppColors.accentBlue)),
      error: (_, __) => const Center(child: Text('Events unavailable', style: TextStyle(color: AppColors.textMuted))),
    );
  }
}

class _ESPNStatsTab extends ConsumerWidget {
  final String matchId;
  final String leagueSlug;
  const _ESPNStatsTab({required this.matchId, required this.leagueSlug});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(_summaryProvider('$leagueSlug:$matchId'));
    return data.when(
      data: (d) {
        final stats = (d['statistics'] as List?)?.cast<Map<String, dynamic>>() ?? [];
        if (stats.isEmpty) {
          return const Center(child: Text('Stats not available', style: TextStyle(color: AppColors.textMuted)));
        }
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: stats.map((s) {
            final name = s['name']?.toString() ?? '';
            final hVal = double.tryParse(s['homeValue']?.toString() ?? '') ?? 0;
            final aVal = double.tryParse(s['awayValue']?.toString() ?? '') ?? 0;
            final total = hVal + aVal;
            final hFrac = total > 0 ? hVal / total : 0.5;
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(children: [
                Row(children: [
                  SizedBox(width: 60, child: Text(s['homeValue']?.toString() ?? '0',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontFamily: 'Oswald', fontSize: 15, color: hFrac > 0.5 ? AppColors.accentBlue : AppColors.textPrimary))),
                  Expanded(child: Text(name, textAlign: TextAlign.center,
                    style: const TextStyle(fontFamily: 'Inter', fontSize: 11, color: AppColors.textMuted))),
                  SizedBox(width: 60, child: Text(s['awayValue']?.toString() ?? '0',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontFamily: 'Oswald', fontSize: 15, color: hFrac < 0.5 ? AppColors.accentRed : AppColors.textPrimary))),
                ]),
                const SizedBox(height: 4),
                Row(children: [
                  Expanded(child: FractionallySizedBox(
                    alignment: Alignment.centerRight,
                    widthFactor: hFrac,
                    child: Container(height: 4, decoration: BoxDecoration(
                      color: AppColors.accentBlue, borderRadius: BorderRadius.only(
                        topLeft: Radius.circular(2), bottomLeft: Radius.circular(2),
                      ),
                    )),
                  )),
                  Expanded(child: FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: 1 - hFrac,
                    child: Container(height: 4, decoration: BoxDecoration(
                      color: AppColors.accentRed, borderRadius: BorderRadius.only(
                        topRight: Radius.circular(2), bottomRight: Radius.circular(2),
                      ),
                    )),
                  )),
                ]),
              ]),
            );
          }).toList(),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator(color: AppColors.accentBlue)),
      error: (_, __) => const Center(child: Text('Stats unavailable', style: TextStyle(color: AppColors.textMuted))),
    );
  }
}
