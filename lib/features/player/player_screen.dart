import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../core/api/fotmob_client.dart';
import '../../core/theme/colors.dart';
import '../team/team_screen.dart';
import '../match_detail/match_detail_screen.dart';

Map<String, dynamic> _m(dynamic v) {
  if (v is Map<String, dynamic>) return v;
  if (v is Map) return v.cast<String, dynamic>();
  return {};
}
List _l(dynamic v) => v is List ? v : [];
String _s(dynamic v) => v?.toString() ?? '';

final _playerProvider = FutureProvider.family<Map<String, dynamic>, String>((ref, id) async {
  return FotmobClient.getPlayerData(id);
});

final _gradient = const LinearGradient(
  begin: Alignment.topCenter, end: Alignment.bottomCenter,
  colors: [Color(0xFF1E2A4A), Color(0xFF0F0F0F)],
  stops: [0.0, 0.6],
);

class PlayerScreen extends ConsumerWidget {
  final String playerId;
  final String? playerName;
  const PlayerScreen({super.key, required this.playerId, this.playerName});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(_playerProvider(playerId));
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: data.when(
        data: (d) => _PlayerBody(data: d),
        loading: () => const Center(child: CircularProgressIndicator(color: AppColors.accentBlue)),
        error: (e, _) => Scaffold(
          appBar: AppBar(backgroundColor: AppColors.bg, leading: const BackButton(color: AppColors.textPrimary)),
          backgroundColor: AppColors.bg,
          body: Center(child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('Could not load player: $e', style: const TextStyle(color: AppColors.textMuted), textAlign: TextAlign.center),
          )),
        ),
      ),
    );
  }
}

class _PlayerBody extends StatefulWidget {
  final Map<String, dynamic> data;
  const _PlayerBody({required this.data});

  @override
  State<_PlayerBody> createState() => _PlayerBodyState();
}

class _PlayerBodyState extends State<_PlayerBody> with SingleTickerProviderStateMixin {
  late TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  String _infoVal(String key) {
    for (final item in _l(widget.data['playerInformation'])) {
      final m = _m(item);
      if (_s(m['translationKey']) == key) return _s(_m(m['value'])['fallback']);
    }
    return '';
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    final name = _s(data['name']);
    final posDesc = _m(data['positionDescription']);
    final position = _s(_m(posDesc['primaryPosition'])['label']);
    final country = _infoVal('country_sentencecase');
    final primTeam = _m(data['primaryTeam']);
    final club = _s(primTeam['teamName']);
    final clubId = _s(primTeam['teamId']);
    final league = _m(data['mainLeague']);
    final seasonStats = _l(league['stats']);
    final recentMatches = _l(data['recentMatches']);
    final careerHist = _m(data['careerHistory']);
    final careerItems = _m(careerHist['careerItems']);
    final senior = _m(careerItems['senior']);
    final career = _l(senior['teamEntries']);
    final trophiesObj = _m(data['trophies']);
    final playerTrophies = _l(trophiesObj['playerTrophies']);

    return NestedScrollView(
      headerSliverBuilder: (ctx, _) => [
        SliverAppBar(
          backgroundColor: AppColors.bg,
          pinned: true,
          leading: const BackButton(color: AppColors.textPrimary),
          expandedHeight: 320,
          flexibleSpace: FlexibleSpaceBar(
            background: Container(
              decoration: BoxDecoration(gradient: _gradient),
              child: SafeArea(
                bottom: false,
                child: Column(children: [
                  const SizedBox(height: 60),
                  // Avatar with glow
                  Container(
                    width: 110, height: 110,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(color: AppColors.accentBlue.withOpacity(0.3), blurRadius: 20, spreadRadius: 2),
                      ],
                    ),
                    child: ClipOval(
                      child: CachedNetworkImage(
                        imageUrl: FotmobClient.playerImageUrl(data['id']), width: 110, height: 110, fit: BoxFit.cover,
                        errorWidget: (_, __, ___) => Container(
                          color: AppColors.bgElevated,
                          child: const Icon(Icons.person, size: 50, color: AppColors.textMuted)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(name, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.textPrimary, letterSpacing: -0.3)),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: [AppColors.accentBlue.withOpacity(0.2), AppColors.accentPurple.withOpacity(0.15)]),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AppColors.accentBlue.withOpacity(0.3)),
                    ),
                    child: Text(position.toUpperCase(), style: const TextStyle(color: AppColors.accentBlue, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.5)),
                  ),
                  const SizedBox(height: 10),
                  // Club & country mini row
                  Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    if (club.isNotEmpty)
                      GestureDetector(
                        onTap: () { if (clubId.isNotEmpty) Navigator.push(context, MaterialPageRoute(builder: (_) => TeamScreen(teamId: clubId, teamName: club))); },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(color: Colors.white.withOpacity(0.06), borderRadius: BorderRadius.circular(12)),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            const Icon(Icons.shield_outlined, size: 12, color: AppColors.textSecondary),
                            const SizedBox(width: 4),
                            Text(club, style: const TextStyle(color: AppColors.textSecondary, fontSize: 11, fontWeight: FontWeight.w500)),
                          ]),
                        ),
                      ),
                    if (club.isNotEmpty && country.isNotEmpty) const SizedBox(width: 8),
                    if (country.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(color: Colors.white.withOpacity(0.06), borderRadius: BorderRadius.circular(12)),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          const Icon(Icons.public, size: 12, color: AppColors.textSecondary),
                          const SizedBox(width: 4),
                          Text(country, style: const TextStyle(color: AppColors.textSecondary, fontSize: 11, fontWeight: FontWeight.w500)),
                        ]),
                      ),
                  ]),
                ]),
              ),
            ),
          ),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(48),
            child: Container(
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: AppColors.border)),
              ),
              child: TabBar(
                controller: _tabs,
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                indicatorColor: AppColors.accentBlue,
                indicatorWeight: 3,
                labelColor: AppColors.accentBlue,
                unselectedLabelColor: AppColors.textMuted,
                labelStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
                tabs: const [
                  Tab(text: 'STATS'), Tab(text: 'MATCHES'), Tab(text: 'CAREER'), Tab(text: 'TROPHIES'),
                ],
              ),
            ),
          ),
        ),
      ],
      body: TabBarView(
        controller: _tabs,
        children: [
          _StatsSection(stats: seasonStats),
          _MatchesSection(matches: recentMatches),
          _CareerSection(career: career),
          _TrophiesSection(trophies: playerTrophies),
        ],
      ),
    );
  }
}

// ─── SHARED GLASS CARD ─────────────────────────────────────────────────────
class _GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final double? height;
  const _GlassCard({required this.child, this.padding, this.height});

  @override
  Widget build(BuildContext context) => Container(
    padding: padding ?? const EdgeInsets.all(12),
    height: height,
    decoration: BoxDecoration(
      color: Colors.white.withOpacity(0.04),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: Colors.white.withOpacity(0.06)),
    ),
    child: child,
  );
}

// ─── SECTION HEADERS ───────────────────────────────────────────────────────
class _SectionTitle extends StatelessWidget {
  final String title;
  final IconData icon;
  const _SectionTitle(this.title, {this.icon = Icons.circle});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 16),
    child: Row(children: [
      Container(width: 3, height: 16, decoration: BoxDecoration(
        gradient: LinearGradient(colors: [AppColors.accentBlue, AppColors.accentPurple]),
        borderRadius: BorderRadius.circular(2),
      )),
      const SizedBox(width: 10),
      Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary, letterSpacing: 0.3)),
    ]),
  );
}

// ─── STATS TAB ─────────────────────────────────────────────────────────────
class _StatsSection extends StatelessWidget {
  final List stats;
  const _StatsSection({required this.stats});

  @override
  Widget build(BuildContext context) {
    if (stats.isEmpty) {
      return const Center(child: Text('No stats available', style: TextStyle(color: AppColors.textMuted)));
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        const _SectionTitle('Season Stats', icon: Icons.bar_chart_rounded),
        const SizedBox(height: 8),
        Wrap(
          spacing: 10, runSpacing: 10,
          children: stats.map((s) {
            final stat = _m(s);
            final title = _s(stat['title']);
            final value = _s(stat['value']);
            return SizedBox(
              width: (MediaQuery.of(context).size.width - 42) / 2,
              child: _GlassCard(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                child: Row(children: [
                  Expanded(
                    child: Text(title, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                  const SizedBox(width: 8),
                  Text(value, style: const TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w800, fontFamily: 'Oswald')),
                ]),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}

// ─── MATCHES TAB ───────────────────────────────────────────────────────────
class _MatchesSection extends StatelessWidget {
  final List matches;
  const _MatchesSection({required this.matches});

  @override
  Widget build(BuildContext context) {
    if (matches.isEmpty) {
      return const Center(child: Text('No recent matches', style: TextStyle(color: AppColors.textMuted)));
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      itemCount: matches.length,
      itemBuilder: (ctx, i) {
        final match = _m(matches[i]);
        final mid = _s(match['id']);
        final home = _s(match['teamName']);
        final away = _s(match['opponentTeamName']);
        final isHome = match['isHomeTeam'] == true;
        final hScore = _s(match['homeScore']);
        final aScore = _s(match['awayScore']);
        final minutes = _s(match['minutesPlayed']);
        final goals = _s(match['goals']);
        final assists = _s(match['assists']);
        final ratingObj = _m(match['ratingProps']);
        final rating = ratingObj['rating'];
        final leagueName = _s(match['leagueName']);
        final onBench = match['onBench'] == true;

        bool won = false;
        if (hScore.isNotEmpty && aScore.isNotEmpty) {
          final h = int.tryParse(hScore) ?? 0;
          final a = int.tryParse(aScore) ?? 0;
          won = isHome ? h > a : a > h;
        }
        final isDraw = hScore.isNotEmpty && aScore.isNotEmpty && hScore == aScore;

        String result = '';
        Color? resultColor;
        if (won) { result = 'W'; resultColor = AppColors.accentGreen; }
        else if (isDraw) { result = 'D'; resultColor = AppColors.accentOrange; }
        else if (hScore.isNotEmpty) { result = 'L'; resultColor = AppColors.accentRed; }

        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: GestureDetector(
            onTap: () { if (mid.isNotEmpty) Navigator.push(context, MaterialPageRoute(builder: (_) => MatchDetailScreen(matchId: mid))); },
            child: _GlassCard(
              padding: const EdgeInsets.all(12),
              child: Row(children: [
                if (resultColor != null)
                  Container(
                    width: 32, height: 32,
                    decoration: BoxDecoration(shape: BoxShape.circle, gradient: LinearGradient(
                      begin: Alignment.topLeft, end: Alignment.bottomRight,
                      colors: [resultColor, resultColor.withOpacity(0.7)])),
                    child: Center(child: Text(result, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w800))),
                  ),
                if (resultColor != null) const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Flexible(child: Text('$home $hScore-$aScore $away',
                        style: const TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w600),
                        overflow: TextOverflow.ellipsis)),
                    ]),
                    if (leagueName.isNotEmpty)
                      Text(leagueName, style: const TextStyle(color: AppColors.textMuted, fontSize: 10)),
                  ]),
                ),
                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  if (onBench)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.accentOrange.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text('SUB', style: TextStyle(color: AppColors.accentOrange, fontSize: 9, fontWeight: FontWeight.w700)),
                    ),
                  if (minutes.isNotEmpty && minutes != '0')
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text("${minutes}'", style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
                    ),
                ]),
                const SizedBox(width: 8),
                // Stats column
                Column(children: [
                  if (goals.isNotEmpty && goals != '0')
                    Container(
                      width: 28, height: 28,
                      decoration: BoxDecoration(
                        color: AppColors.accentGreen.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Center(child: Text(goals, style: const TextStyle(color: AppColors.accentGreen, fontSize: 12, fontWeight: FontWeight.w800))),
                    ),
                  if (assists.isNotEmpty && assists != '0') ...[
                    if (goals.isNotEmpty && goals != '0') const SizedBox(height: 4),
                    Container(
                      width: 28, height: 28,
                      decoration: BoxDecoration(
                        color: AppColors.accentBlue.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Center(child: Text('${assists}A', style: const TextStyle(color: AppColors.accentBlue, fontSize: 11, fontWeight: FontWeight.w800))),
                    ),
                  ],
                  if (rating is num && rating > 0) ...[
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                      decoration: BoxDecoration(
                        color: rating >= 7 ? AppColors.accentGreen.withOpacity(0.12) : AppColors.bgElevated,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(rating.toStringAsFixed(1), style: TextStyle(
                        color: rating >= 7 ? AppColors.accentGreen : AppColors.textMuted,
                        fontSize: 10, fontWeight: FontWeight.w700)),
                    ),
                  ],
                ]),
              ]),
            ),
          ),
        );
      },
    );
  }
}

// ─── CAREER TAB ────────────────────────────────────────────────────────────
class _CareerSection extends StatelessWidget {
  final List career;
  const _CareerSection({required this.career});

  @override
  Widget build(BuildContext context) {
    if (career.isEmpty) {
      return const Center(child: Text('No career data', style: TextStyle(color: AppColors.textMuted)));
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      itemCount: career.length,
      itemBuilder: (ctx, i) {
        final entry = _m(career[i]);
        final team = _s(entry['team']);
        final teamId = _s(entry['teamId']);
        final from = _s(entry['startDate']).length >= 10 ? _s(entry['startDate']).substring(0, 10) : '';
        final to = _s(entry['endDate']).length >= 10 ? _s(entry['endDate']).substring(0, 10) : (_s(entry['endDate']).isEmpty ? 'Present' : '');
        final apps = _s(entry['appearances']);
        final goals = _s(entry['goals']);
        final assists = _s(entry['assists']);
        final transferType = _s(_m(entry['transferType'])['text']);

        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: GestureDetector(
            onTap: () { if (teamId.isNotEmpty) Navigator.push(context, MaterialPageRoute(builder: (_) => TeamScreen(teamId: teamId, teamName: team))); },
            child: _GlassCard(
              padding: const EdgeInsets.all(12),
              child: Row(children: [
                Container(
                  width: 40, height: 40,
                  decoration: BoxDecoration(
                    color: AppColors.bgElevated,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: CachedNetworkImage(
                      imageUrl: FotmobClient.teamLogoUrl(teamId), width: 40, height: 40, fit: BoxFit.cover,
                      errorWidget: (_, __, ___) => const Icon(Icons.shield_outlined, color: AppColors.textMuted, size: 22)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(team, style: const TextStyle(color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 4),
                  Row(children: [
                    Icon(Icons.calendar_today, size: 9, color: AppColors.textMuted),
                    const SizedBox(width: 4),
                    Text(from, style: const TextStyle(color: AppColors.textMuted, fontSize: 10)),
                    if (to.isNotEmpty) Text(' – $to', style: const TextStyle(color: AppColors.textMuted, fontSize: 10)),
                    if (transferType.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                        decoration: BoxDecoration(color: AppColors.accentPurple.withOpacity(0.12), borderRadius: BorderRadius.circular(4)),
                        child: Text(transferType, style: const TextStyle(color: AppColors.accentPurple, fontSize: 8, fontWeight: FontWeight.w600)),
                      ),
                    ],
                  ]),
                ])),
                const SizedBox(width: 8),
                SizedBox(
                  width: 90,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    if (apps.isNotEmpty && apps != '0')
                      Text('$apps apps', style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
                    const SizedBox(height: 3),
                    Wrap(alignment: WrapAlignment.end, spacing: 4, runSpacing: 2, children: [
                      if (goals.isNotEmpty && goals != '0')
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(color: AppColors.accentGreen.withOpacity(0.1), borderRadius: BorderRadius.circular(4)),
                          child: Text('$goals gls', style: const TextStyle(color: AppColors.accentGreen, fontSize: 9, fontWeight: FontWeight.w700)),
                        ),
                      if (assists.isNotEmpty && assists != '0')
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(color: AppColors.accentBlue.withOpacity(0.1), borderRadius: BorderRadius.circular(4)),
                          child: Text('$assists ast', style: const TextStyle(color: AppColors.accentBlue, fontSize: 9, fontWeight: FontWeight.w700)),
                        ),
                    ]),
                  ]),
                ),
              ]),
            ),
          ),
        );
      },
    );
  }
}

// ─── TROPHIES TAB ──────────────────────────────────────────────────────────
class _TrophiesSection extends StatelessWidget {
  final List trophies;
  const _TrophiesSection({required this.trophies});

  @override
  Widget build(BuildContext context) {
    if (trophies.isEmpty) {
      return const Center(child: Text('No trophies', style: TextStyle(color: AppColors.textMuted)));
    }
    final rows = trophies.expand((t) {
      final pt = _m(t);
      final teamName = _s(pt['teamName']);
      return _l(pt['tournaments']).map((tn) {
        final trophy = _m(tn);
        final leagueName = _s(trophy['leagueName']);
        final seasonsWon = _l(trophy['seasonsWon']);
        return _TrophyCard(leagueName: leagueName, teamName: teamName, seasons: seasonsWon);
      });
    }).toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: rows,
    );
  }
}

class _TrophyCard extends StatelessWidget {
  final String leagueName, teamName;
  final List seasons;
  const _TrophyCard({required this.leagueName, required this.teamName, required this.seasons});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: _GlassCard(
      padding: const EdgeInsets.all(12),
      child: Row(children: [
        Container(
          width: 40, height: 40,
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [AppColors.accentGold.withOpacity(0.2), AppColors.accentOrange.withOpacity(0.1)]),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(Icons.emoji_events, color: AppColors.accentGold, size: 22),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(leagueName, style: const TextStyle(color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w600)),
          if (teamName.isNotEmpty)
            Text(teamName, style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
        ])),
        if (seasons.isNotEmpty)
          Flexible(
            child: Container(
              margin: const EdgeInsets.only(left: 8),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.accentGold.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.accentGold.withOpacity(0.2)),
              ),
              child: Text(seasons.join(', '), style: const TextStyle(color: AppColors.accentGold, fontSize: 10, fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          ),
      ]),
    ),
  );
}