import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../core/api/fotmob_client.dart';
import '../../core/theme/colors.dart';
import '../match_detail/match_detail_screen.dart';

Map<String, dynamic> _m(dynamic v) {
  if (v is Map<String, dynamic>) return v;
  if (v is Map) return v.cast<String, dynamic>();
  return {};
}
List _l(dynamic v) => v is List ? v : [];
String _s(dynamic v) => v?.toString() ?? '';
int _i(dynamic v) => int.tryParse(_s(v)) ?? 0;

final _leagueProvider = FutureProvider.family<Map<String, dynamic>, String>((ref, id) async {
  final details = await FotmobClient.getLeagueDetails(id);
  Map<String, dynamic> stats = {};
  try { stats = await FotmobClient.getLeagueStats(id); } catch (_) {}
  return {'details': details, 'stats': stats};
});

class LeagueScreen extends ConsumerStatefulWidget {
  final String leagueId;
  final String? leagueName;
  const LeagueScreen({super.key, required this.leagueId, this.leagueName});

  @override
  ConsumerState<LeagueScreen> createState() => _LeagueScreenState();
}

class _LeagueScreenState extends ConsumerState<LeagueScreen>
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
    final data = ref.watch(_leagueProvider(widget.leagueId));
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        leading: const BackButton(color: AppColors.textPrimary),
        title: Text(widget.leagueName ?? 'League', style: const TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w600)),
        bottom: TabBar(
          controller: _tabs,
          indicatorColor: AppColors.accentBlue,
          labelColor: AppColors.accentBlue,
          unselectedLabelColor: AppColors.textMuted,
          tabs: const [
            Tab(text: 'TABLE'), Tab(text: 'FIXTURES'), Tab(text: 'STATS'),
          ],
        ),
      ),
      body: data.when(
        data: (d) => TabBarView(controller: _tabs, children: [
          _TableTab(details: _m(d['details'])),
          _FixturesTab(details: _m(d['details'])),
          _StatsTab(stats: _m(d['stats']), details: _m(d['details'])),
        ]),
        loading: () => const Center(child: CircularProgressIndicator(color: AppColors.accentBlue)),
        error: (e, _) => Center(child: Text('Error: $e', style: const TextStyle(color: AppColors.textMuted))),
      ),
    );
  }
}

class _TableTab extends StatelessWidget {
  final Map<String, dynamic> details;
  const _TableTab({required this.details});

  @override
  Widget build(BuildContext context) {
    final tables = _l(details['table']);

    if (tables.isEmpty) {
      return const Center(child: Text('No standings available', style: TextStyle(color: AppColors.textMuted)));
    }

    // Each table entry has: all, home, away, and description
    // `all` contains the actual rows
    final rows = _l(_m(tables.first)['all'] ?? _m(tables.first)['data'] ?? tables.first is List ? tables.first : []);
    if (rows.isEmpty) {
      return const Center(child: Text('No table data', style: TextStyle(color: AppColors.textMuted)));
    }

    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: rows.length,
      itemBuilder: (ctx, i) {
        final r = _m(rows[i]);
        final pos = _s(r['pos'] ?? r['position'] ?? '${i + 1}');
        final name = _s(r['name'] ?? r['teamName']);
        final teamId = _s(r['id'] ?? r['teamId']);
        final pts = _s(r['pts'] ?? r['points'] ?? '0');
        final p = _s(r['played'] ?? r['p'] ?? r['matches'] ?? '0');
        final w = _s(r['wins'] ?? r['w'] ?? r['won'] ?? '0');
        final d = _s(r['draws'] ?? r['d'] ?? r['draw'] ?? '0');
        final l = _s(r['losses'] ?? r['l'] ?? r['lost'] ?? '0');
        final gf = _s(r['goalsFor'] ?? r['gf'] ?? r['scored'] ?? '0');
        final ga = _s(r['goalsAgainst'] ?? r['ga'] ?? r['conceded'] ?? '0');
        final gd = _s(r['gd'] ?? r['goalsDiff'] ?? '${_i(gf) - _i(ga)}');

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: AppColors.border, width: 0.5)),
          ),
          child: Row(children: [
            SizedBox(width: 28, child: Text(pos,
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700,
                color: _i(pos) <= 4 ? AppColors.accentBlue : AppColors.textSecondary))),
            if (teamId.isNotEmpty)
              CachedNetworkImage(imageUrl: FotmobClient.teamLogoUrl(teamId), width: 18, height: 18,
                errorWidget: (_, __, ___) => const SizedBox(width: 18))
            else
              const SizedBox(width: 18),
            const SizedBox(width: 8),
            Expanded(child: Text(name, style: const TextStyle(color: AppColors.textPrimary, fontSize: 12), overflow: TextOverflow.ellipsis)),
            SizedBox(width: 24, child: Text(p, style: const TextStyle(color: AppColors.textSecondary, fontSize: 11), textAlign: TextAlign.center)),
            SizedBox(width: 24, child: Text(w, style: const TextStyle(color: AppColors.textSecondary, fontSize: 11), textAlign: TextAlign.center)),
            SizedBox(width: 24, child: Text(d, style: const TextStyle(color: AppColors.textSecondary, fontSize: 11), textAlign: TextAlign.center)),
            SizedBox(width: 24, child: Text(l, style: const TextStyle(color: AppColors.textSecondary, fontSize: 11), textAlign: TextAlign.center)),
            SizedBox(width: 28, child: Text(gd, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
              color: _i(gd) > 0 ? AppColors.accentGreen : _i(gd) < 0 ? AppColors.accentRed : AppColors.textSecondary), textAlign: TextAlign.center)),
            SizedBox(width: 28, child: Text(pts, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimary), textAlign: TextAlign.center)),
          ]),
        );
      },
    );
  }
}

class _FixturesTab extends ConsumerWidget {
  final Map<String, dynamic> details;
  const _FixturesTab({required this.details});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fixtures = _l(details['fixtures'] ?? details['matches'] ?? []);
    if (fixtures.isEmpty) {
      return const Center(child: Text('No fixtures available', style: TextStyle(color: AppColors.textMuted)));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: fixtures.length,
      itemBuilder: (ctx, i) {
        final m = _m(fixtures[i]);
        final home = _m(m['home']);
        final away = _m(m['away']);
        final time = _s(m['time'] ?? m['status']?['utcTime'] ?? '');
        return ListTile(
          leading: Text(time.length >= 10 ? time.substring(0, 10) : time, style: const TextStyle(color: AppColors.textMuted, fontSize: 10)),
          title: Text('${_s(home['name'])} vs ${_s(away['name'])}', style: const TextStyle(color: AppColors.textPrimary, fontSize: 13)),
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => MatchDetailScreen(matchId: _s(m['id'])))),
        );
      },
    );
  }
}

class _StatsTab extends StatelessWidget {
  final Map<String, dynamic> stats;
  final Map<String, dynamic> details;
  const _StatsTab({required this.stats, required this.details});

  @override
  Widget build(BuildContext context) {
    final topScorers = _l(stats['topScorers'] ?? stats['scorers'] ?? stats['top_players'] ?? []);
    if (topScorers.isEmpty) {
      return const Center(child: Text('No stats available', style: TextStyle(color: AppColors.textMuted)));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: topScorers.length,
      itemBuilder: (ctx, i) {
        final p = _m(topScorers[i]);
        final name = _s(p['name'] ?? p['playerName']);
        final pid = _s(p['id'] ?? p['playerId']);
        final goals = _s(p['goals'] ?? p['goalsScored'] ?? p['stat']?['value'] ?? '0');
        final teamName = _s(p['teamName'] ?? p['team']?['name'] ?? '');
        final played = _s(p['played'] ?? p['matchesPlayed'] ?? '-');

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: AppColors.border, width: 0.5)),
          ),
          child: Row(children: [
            SizedBox(width: 24, child: Text('${i + 1}', style: const TextStyle(color: AppColors.textMuted, fontSize: 11))),
            if (pid.isNotEmpty)
              CachedNetworkImage(imageUrl: FotmobClient.playerImageUrl(pid), width: 28, height: 28,
                imageBuilder: (c, img) => CircleAvatar(backgroundImage: img, radius: 14),
                errorWidget: (_, __, ___) => const CircleAvatar(radius: 14, child: Icon(Icons.person, size: 16, color: AppColors.textMuted)))
            else
              const CircleAvatar(radius: 14, child: Icon(Icons.person, size: 16, color: AppColors.textMuted)),
            const SizedBox(width: 8),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name, style: const TextStyle(color: AppColors.textPrimary, fontSize: 13)),
              if (teamName.isNotEmpty)
                Text(teamName, style: const TextStyle(color: AppColors.textMuted, fontSize: 10)),
            ])),
            Text('$played apps', style: const TextStyle(color: AppColors.textMuted, fontSize: 10)),
            const SizedBox(width: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.accentBlue.withOpacity(0.15),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(goals, style: const TextStyle(color: AppColors.accentBlue, fontSize: 13, fontWeight: FontWeight.w700)),
            ),
          ]),
        );
      },
    );
  }
}
