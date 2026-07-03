import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../core/utils/safe_url.dart';
import '../../core/api/fotmob_client.dart';
import '../../core/api/espn_client.dart';
import '../../core/api/football_data_client.dart';
import '../../core/theme/colors.dart';
import '../match_detail/match_detail_screen.dart';
import '../team/team_screen.dart';
import '../player/player_screen.dart';

Map<String, dynamic> _m(dynamic v) {
  if (v is Map<String, dynamic>) return v;
  if (v is Map) return v.cast<String, dynamic>();
  return {};
}
List _l(dynamic v) => v is List ? v : [];
String _s(dynamic v) => v?.toString() ?? '';
int _i(dynamic v) => int.tryParse(_s(v)) ?? 0;

final _leagueProvider = AutoDisposeFutureProvider.family<Map<String, dynamic>, String>((ref, id) async {
  Map<String, dynamic> raw = {};
  String fetchError = '';
  try {
    raw = await FotmobClient.getLeagueDetails(id);
  } catch (e) {
    fetchError = e.toString();
  }

  // football-data.org → ESPN → FotMob fallback chain
  List<Map<String, dynamic>> espnStandings = [];

  // 1. football-data.org (best, always works for major leagues)
  final fdCode = FootballDataClient.getCode(id);
  if (fdCode != null) {
    try {
      // Try grouped first (World Cup, UCL), then simple
      final grouped = await FootballDataClient.getAllGroupStandings(fdCode);
      if (grouped.isNotEmpty) {
        espnStandings = grouped;
      } else {
        espnStandings = await FootballDataClient.getStandings(fdCode);
      }
    } catch (_) {}
  }

  // 2. ESPN fallback
  if (espnStandings.isEmpty) {
    final espnSlug = EspnClient.fotmobToEspnSlug(id);
    if (espnSlug != null) {
      try { espnStandings = await EspnClient.getStandings(espnSlug); } catch (_) {}
    }
  }

  // 3. TheSportsDB fallback (minor leagues not on football-data.org / ESPN)
  if (espnStandings.isEmpty) {
    final sdbId = EspnClient.fotmobToSportsDbId(id);
    if (sdbId != null) {
      try { espnStandings = await EspnClient.getStandingsFromSportsDb(sdbId); } catch (_) {}
    }
  }

  // If FotMob worked, also try individual tabs
  if (raw.isEmpty || raw['table'] == null) {
    try { final r = await FotmobClient.getLeagueTable(id); if (r.isNotEmpty) raw['table'] = r['table']; } catch (_) {}
  }
  if (raw['fixtures'] == null) {
    try { final r = await FotmobClient.getLeagueFixtures(id); if (r.isNotEmpty) raw['fixtures'] = r['fixtures'] ?? r; } catch (_) {}
  }
  // Dedicated stats + toplist endpoints — overview rarely includes them
  if (raw['stats'] == null) {
    try { final r = await FotmobClient.getLeagueStats(id); if (r.isNotEmpty) raw['stats'] = r['stats'] ?? r; } catch (_) {}
  }
  if (raw['stats'] == null) {
    try {
      final r = await FotmobClient.getLeagueTopList(id);
      final top = r['topLists'] ?? r['toplist'] ?? r['stats'];
      if (top != null) raw['stats'] = {'players': top is List ? top : [top]};
    } catch (_) {}
  }

  List<Map<String, dynamic>> news = [];
  try { news = await FotmobClient.getLeagueNews(id); } catch (_) {}
  return {'raw': raw, 'espnStandings': espnStandings, 'news': news, 'fetchError': fetchError};
});

class LeagueScreen extends ConsumerStatefulWidget {
  final String leagueId;
  final String? leagueName;
  final List existingMatches;
  const LeagueScreen({super.key, required this.leagueId, this.leagueName, this.existingMatches = const []});

  @override
  ConsumerState<LeagueScreen> createState() => _LeagueScreenState();
}

class _LeagueScreenState extends ConsumerState<LeagueScreen>
    with SingleTickerProviderStateMixin {
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

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(_leagueProvider(widget.leagueId));
    return Scaffold(
      backgroundColor: context.cBg,
      appBar: AppBar(
        backgroundColor: context.cBg,
        leading: BackButton(color: context.cTextPrimary),
        title: Text(widget.leagueName ?? 'League', style: TextStyle(color: context.cTextPrimary, fontSize: 16, fontWeight: FontWeight.w600)),
        bottom: TabBar(
          controller: _tabs,
          indicatorColor: AppColors.accentBlue,
          labelColor: AppColors.accentBlue,
          unselectedLabelColor: context.cTextMuted,
          tabs: const [
            Tab(text: 'TABLE'), Tab(text: 'FIXTURES'), Tab(text: 'STATS'), Tab(text: 'NEWS'),
          ],
        ),
      ),
      body: data.when(
        data: (d) {
          final raw = _m(d['raw']);
          final espnRows = (d['espnStandings'] as List?)?.cast<Map<String,dynamic>>() ?? [];
          return TabBarView(controller: _tabs, children: [
            _TableTab(raw: raw, espnRows: espnRows),
            _FixturesTab(raw: raw, existingMatches: widget.existingMatches),
            _StatsTab(raw: raw),
            _LeagueNewsTab(news: (d['news'] as List?)?.cast<Map<String, dynamic>>() ?? []),
          ]);
        },
        loading: () => const Center(child: CircularProgressIndicator(color: AppColors.accentBlue)),
        error: (e, _) => Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Failed to load', style: TextStyle(color: context.cTextMuted)),
          const SizedBox(height: 12),
          GestureDetector(
            onTap: () => ref.invalidate(_leagueProvider(widget.leagueId)),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              decoration: BoxDecoration(color: AppColors.accentPrimary, borderRadius: BorderRadius.circular(20)),
              child: const Text('Retry', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
            ),
          ),
        ])),
      ),
    );
  }
}

class _TableTab extends StatelessWidget {
  final Map<String, dynamic> raw;
  final String fetchError;
  final List<Map<String, dynamic>> espnRows;
  const _TableTab({required this.raw, this.fetchError = '', this.espnRows = const []});

  @override
  Widget build(BuildContext context) {
    final tableRaw = raw['table'];
    final tables = _l(tableRaw);

    if (tables.isEmpty) {
      if (espnRows.isNotEmpty) return _buildEspnTable(context, espnRows);
      // Show what was attempted
      return Center(child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.table_chart_outlined, color: context.cTextMuted, size: 40),
          const SizedBox(height: 12),
          Text('Table not available', style: TextStyle(color: context.cTextMuted, fontFamily: 'Inter', fontSize: 14)),
        ]),
      ));
    }

    // Dig into first element
    final first = tables.first;
    final firstMap = _m(first);
    final firstData = _m(firstMap['data']);
    final firstTableInData = _m(firstData['table']);
    final allRows = firstTableInData['all'];

    if (allRows == null) {
      if (espnRows.isNotEmpty) return _buildEspnTable(context, espnRows);
      return Center(child: Text('Table not available', style: TextStyle(color: context.cTextMuted, fontFamily: 'Inter')));
    }

    List rows = _l(allRows);

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

        return GestureDetector(
          onTap: () {
            if (teamId.isNotEmpty) Navigator.push(context, MaterialPageRoute(
              builder: (_) => TeamScreen(teamId: teamId, teamName: name)));
          },
          child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: context.cBorder, width: 0.5)),
          ),
          child: Row(children: [
            SizedBox(width: 28, child: Text(pos,
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700,
                color: _i(pos) <= 4 ? AppColors.accentBlue : context.cTextSecondary))),
            if (teamId.isNotEmpty)
              CachedNetworkImage(imageUrl: FotmobClient.teamLogoUrl(teamId), width: 18, height: 18,
                errorWidget: (_, __, ___) => SizedBox(width: 18))
            else
              SizedBox(width: 18),
            SizedBox(width: 8),
            Expanded(child: Text(name, style: TextStyle(color: context.cTextPrimary, fontSize: 12), overflow: TextOverflow.ellipsis)),
            SizedBox(width: 24, child: Text(p, style: TextStyle(color: context.cTextSecondary, fontSize: 11), textAlign: TextAlign.center)),
            SizedBox(width: 24, child: Text(w, style: TextStyle(color: context.cTextSecondary, fontSize: 11), textAlign: TextAlign.center)),
            SizedBox(width: 24, child: Text(d, style: TextStyle(color: context.cTextSecondary, fontSize: 11), textAlign: TextAlign.center)),
            SizedBox(width: 24, child: Text(l, style: TextStyle(color: context.cTextSecondary, fontSize: 11), textAlign: TextAlign.center)),
            SizedBox(width: 28, child: Text(gd, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
              color: _i(gd) > 0 ? AppColors.accentGreen : _i(gd) < 0 ? AppColors.accentRed : context.cTextSecondary), textAlign: TextAlign.center)),
            SizedBox(width: 28, child: Text(pts, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: context.cTextPrimary), textAlign: TextAlign.center)),
          ]),
        ));
      },
    );
  }

  Widget _buildEspnTable(BuildContext context, List<Map<String, dynamic>> rows) {
    // Build items list with group headers
    final items = <dynamic>[];
    String lastGroup = '';
    for (final r in rows) {
      final g = _s(r['group']);
      if (g.isNotEmpty && g != lastGroup) {
        items.add(g); // group header
        lastGroup = g;
      }
      items.add(r);
    }

    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: items.isEmpty ? rows.length : items.length,
      itemBuilder: (ctx, i) {
        final item = items.isEmpty ? rows[i] : items[i];

        // Group header
        if (item is String) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(4, 12, 4, 6),
            child: Text(item, style: const TextStyle(
              color: AppColors.accentPrimary, fontSize: 12,
              fontWeight: FontWeight.w800, fontFamily: 'Inter', letterSpacing: 1)),
          );
        }

        final r = item as Map<String, dynamic>;
        final pos = (r['pos'] as int?) ?? (i + 1);
        final name = _s(r['name']);
        final logo = _s(r['logo']);
        final pts = r['pts']?.toString() ?? '0';
        final p = r['played']?.toString() ?? '0';
        final w = r['wins']?.toString() ?? '0';
        final d = r['draws']?.toString() ?? '0';
        final l = r['losses']?.toString() ?? '0';
        final gd = r['gd'] ?? 0;

        return GestureDetector(
          onTap: () {
            final id = _s(r['id']);
            if (id.isNotEmpty) Navigator.push(context, MaterialPageRoute(
              builder: (_) => TeamScreen(teamId: id, teamName: name)));
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: context.cBorder, width: 0.5))),
            child: Row(children: [
              SizedBox(width: 28, child: Text('$pos', style: TextStyle(fontSize: 12,
                fontWeight: FontWeight.w700,
                color: pos <= 4 ? AppColors.accentPrimary : context.cTextSecondary))),
              if (logo.isNotEmpty)
                CachedNetworkImage(imageUrl: logo, width: 18, height: 18,
                  errorWidget: (_, __, ___) => SizedBox(width: 18))
              else
                SizedBox(width: 18),
              SizedBox(width: 8),
              Expanded(child: Text(name, style: TextStyle(color: context.cTextPrimary, fontSize: 12), overflow: TextOverflow.ellipsis)),
              SizedBox(width: 24, child: Text(p, style: TextStyle(color: context.cTextSecondary, fontSize: 11), textAlign: TextAlign.center)),
              SizedBox(width: 24, child: Text(w, style: TextStyle(color: context.cTextSecondary, fontSize: 11), textAlign: TextAlign.center)),
              SizedBox(width: 24, child: Text(d, style: TextStyle(color: context.cTextSecondary, fontSize: 11), textAlign: TextAlign.center)),
              SizedBox(width: 24, child: Text(l, style: TextStyle(color: context.cTextSecondary, fontSize: 11), textAlign: TextAlign.center)),
              SizedBox(width: 28, child: Text('$gd', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                color: gd > 0 ? AppColors.accentGreen : gd < 0 ? AppColors.accentRed : context.cTextSecondary), textAlign: TextAlign.center)),
              SizedBox(width: 28, child: Text(pts, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: context.cTextPrimary), textAlign: TextAlign.center)),
            ]),
          ),
        );
      },
    );
  }
}

class _FixturesTab extends StatelessWidget {
  final Map<String, dynamic> raw;
  final List existingMatches;
  const _FixturesTab({required this.raw, this.existingMatches = const []});

  @override
  Widget build(BuildContext context) {
    // raw['fixtures'] has the fixtures data
    // raw['fixtures'] structure — try multiple paths
    final fixturesVal = raw['fixtures'];
    List fixtures = [];
    if (fixturesVal is List) {
      fixtures = fixturesVal;
    } else if (fixturesVal is Map) {
      final fixturesObj = _m(fixturesVal);
      fixtures = _l(_m(fixturesObj['allFixtures'])['fixtures']);
      if (fixtures.isEmpty) fixtures = _l(fixturesObj['fixtures']);
      if (fixtures.isEmpty) fixtures = _l(fixturesObj['previousFixtures']);
      if (fixtures.isEmpty) fixtures = _l(fixturesObj['nextMatch']);
      if (fixtures.isEmpty) {
        for (final v in fixturesObj.values) {
          if (v is List && v.isNotEmpty) { fixtures = v; break; }
          if (v is Map) {
            final inner = _l(_m(v)['fixtures'] ?? _m(v)['matches'] ?? []);
            if (inner.isNotEmpty) { fixtures = inner; break; }
          }
        }
      }
    }
    // Also try overview.matches
    if (fixtures.isEmpty) {
      fixtures = _l(_m(raw['overview'])['matches'] ?? _m(raw['overview'])['leagueOverviewMatches'] ?? []);
    }

    // Fallback: use matches data passed from scores screen
    if (fixtures.isEmpty && existingMatches.isNotEmpty) {
      fixtures = existingMatches;
    }
    if (fixtures.isEmpty) {
      return Center(child: Text('No fixtures available', style: TextStyle(color: context.cTextMuted, fontFamily: 'Inter')));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: fixtures.length,
      itemBuilder: (ctx, i) {
        final m = _m(fixtures[i]);
        final home = _m(m['home']);
        final away = _m(m['away']);
        final status = _m(m['status']);
        final score = _s(status['scoreStr']);
        final finished = status['finished'] == true;
        final isLive = status['started'] == true && !finished;
        final utc = _s(status['utcTime'] ?? m['time'] ?? '');
        String timeStr = utc.length >= 10 ? utc.substring(0, 10) : utc;
        if (utc.length >= 16) {
          try {
            final dt = DateTime.parse(utc).toLocal();
            timeStr = '${dt.month}/${dt.day} ${dt.hour.toString().padLeft(2,'0')}:${dt.minute.toString().padLeft(2,'0')}';
          } catch (_) {}
        }

        return GestureDetector(
          onTap: () { final mid = _s(m['id']); if (mid.isNotEmpty) Navigator.push(context, MaterialPageRoute(builder: (_) => MatchDetailScreen(matchId: mid))); },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: context.cBorder, width: 0.5))),
            child: Row(children: [
              SizedBox(width: 56, child: Text(timeStr, style: TextStyle(color: context.cTextMuted, fontSize: 10, fontFamily: 'Inter'))),
              Expanded(child: Text(_s(home['name']), style: TextStyle(color: context.cTextPrimary, fontSize: 12, fontWeight: FontWeight.w500), overflow: TextOverflow.ellipsis)),
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 8),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: isLive ? AppColors.live.withValues(alpha: 0.12) : context.cBgElevated,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  score.isNotEmpty ? score : 'vs',
                  style: TextStyle(fontFamily: 'Oswald', fontSize: 13, fontWeight: FontWeight.w700,
                    color: isLive ? AppColors.live : finished ? context.cTextSecondary : context.cTextMuted),
                ),
              ),
              Expanded(child: Text(_s(away['name']), style: TextStyle(color: context.cTextPrimary, fontSize: 12, fontWeight: FontWeight.w500), textAlign: TextAlign.right, overflow: TextOverflow.ellipsis)),
            ]),
          ),
        );
      },
    );
  }
}

class _StatsTab extends StatelessWidget {
  final Map<String, dynamic> raw;
  const _StatsTab({required this.raw});

  @override
  Widget build(BuildContext context) {
    final statsData = _m(raw['stats']);
    final overview = _m(raw['overview']);


    // stats: {players: [...sections], teams: [...sections]}
    final playerSections = _l(statsData['players']);
    final teamSections = _l(statsData['teams']);
    final overviewTopPlayers = _l(overview['topPlayers']);

    // Keep only sections that actually contain players
    bool hasPlayers(dynamic section) {
      final sec = _m(section);
      return _l(sec['topList'] ?? sec['topThree'] ?? sec['players'] ?? sec['items'] ?? []).isNotEmpty;
    }
    final allSections = [...playerSections, ...teamSections].where(hasPlayers).toList();
    final validOverview = overviewTopPlayers.where(hasPlayers).toList();
    if (allSections.isEmpty && validOverview.isNotEmpty) {
      return _buildTopList(context, validOverview);
    }
    if (allSections.isNotEmpty) return _buildTopList(context, allSections);

    // Nothing available
    if (statsData.isEmpty) {
      return Center(child: Text('Stats not available', style: TextStyle(color: context.cTextMuted, fontFamily: 'Inter')));
    }
    List topScorers = [];
    if (topScorers.isEmpty) {
      return Center(child: Text('Stats not available for this league', style: TextStyle(color: context.cTextMuted, fontFamily: 'Inter')));
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
            border: Border(bottom: BorderSide(color: context.cBorder, width: 0.5)),
          ),
          child: Row(children: [
            SizedBox(width: 24, child: Text('${i + 1}', style: TextStyle(color: context.cTextMuted, fontSize: 11))),
            if (pid.isNotEmpty)
              CachedNetworkImage(imageUrl: FotmobClient.playerImageUrl(pid), width: 28, height: 28,
                imageBuilder: (c, img) => CircleAvatar(backgroundImage: img, radius: 14),
                errorWidget: (_, __, ___) => CircleAvatar(radius: 14, child: Icon(Icons.person, size: 16, color: context.cTextMuted)))
            else
              CircleAvatar(radius: 14, child: Icon(Icons.person, size: 16, color: context.cTextMuted)),
            SizedBox(width: 8),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name, style: TextStyle(color: context.cTextPrimary, fontSize: 13)),
              if (teamName.isNotEmpty)
                Text(teamName, style: TextStyle(color: context.cTextMuted, fontSize: 10)),
            ])),
            Text('$played apps', style: TextStyle(color: context.cTextMuted, fontSize: 10)),
            const SizedBox(width: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.accentBlue.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(goals, style: const TextStyle(color: AppColors.accentBlue, fontSize: 13, fontWeight: FontWeight.w700)),
            ),
          ]),
        );
      },
    );
  }

  Widget _buildTopList(BuildContext context, List sections) {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: sections.map((section) {
        final sec = _m(section);
        final title = _s(sec['header'] ?? sec['title'] ?? sec['name'] ?? '');
        final players = _l(sec['topList'] ?? sec['topThree'] ?? sec['players'] ?? sec['items'] ?? []);
        if (players.isEmpty) return const SizedBox.shrink();
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 16, 4, 10),
            child: Row(children: [
              Container(width: 3, height: 14, decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [AppColors.accentBlue, AppColors.accentPurple]),
                borderRadius: BorderRadius.circular(2),
              )),
              SizedBox(width: 8),
              Text(title.toUpperCase(), style: TextStyle(
                fontSize: 11, fontWeight: FontWeight.w700, color: context.cTextMuted, letterSpacing: 1.5)),
            ]),
          ),
          ...players.take(10).toList().asMap().entries.map((e) {
            final idx = e.key;
            final p = _m(e.value);
            final name = _s(p['name'] ?? p['playerName'] ?? '');
            final pid = _s(p['id'] ?? p['playerId'] ?? '');
            final val = _s(p['value'] ?? p['statValue'] ?? p['goals'] ?? p['assists'] ?? '');
            String teamName = _s(p['teamName'] ?? _m(p['team'])['name'] ?? '');
            if (teamName == name) teamName = ''; // team rows: don't repeat name as subtitle
            return GestureDetector(
              onTap: () { if (pid.isNotEmpty) Navigator.push(context, MaterialPageRoute(builder: (_) => PlayerScreen(playerId: pid, playerName: name))); },
              child: Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: context.cBgCard,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: context.cBorder),
                ),
                child: Row(children: [
                  SizedBox(width: 22, child: Text('${idx + 1}', style: TextStyle(color: context.cTextMuted, fontSize: 11, fontWeight: FontWeight.w600))),
                  if (pid.isNotEmpty)
                    ClipOval(child: CachedNetworkImage(imageUrl: FotmobClient.playerImageUrl(pid), width: 32, height: 32, fit: BoxFit.cover,
                      errorWidget: (_, __, ___) => Container(width: 32, height: 32, color: context.cBgElevated, child: Icon(Icons.person, size: 18, color: context.cTextMuted))))
                  else
                    Container(width: 32, height: 32, decoration: BoxDecoration(color: context.cBgElevated, shape: BoxShape.circle),
                      child: Icon(Icons.person, size: 18, color: context.cTextMuted)),
                  SizedBox(width: 10),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(name, style: TextStyle(color: context.cTextPrimary, fontSize: 13, fontWeight: FontWeight.w500), maxLines: 1, overflow: TextOverflow.ellipsis),
                    if (teamName.isNotEmpty) Text(teamName, style: TextStyle(color: context.cTextMuted, fontSize: 10)),
                  ])),
                  Container(
                    width: 36, height: 36,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(gradient: AppColors.primaryGradient, borderRadius: BorderRadius.circular(10)),
                    child: Text(val, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w800, fontFamily: 'Oswald')),
                  ),
                ]),
              ),
            );
          }),
        ]);
      }).toList(),
    );
  }
}

// ─── LEAGUE NEWS TAB ──────────────────────────────────────────────────────────
class _LeagueNewsTab extends StatelessWidget {
  final List<Map<String, dynamic>> news;
  const _LeagueNewsTab({required this.news});

  @override
  Widget build(BuildContext context) {
    if (news.isEmpty) {
      return Center(child: Text('No news available', style: TextStyle(color: context.cTextMuted, fontFamily: 'Inter')));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: news.length,
      itemBuilder: (ctx, i) {
        final n = news[i];
        final title = _s(n['title']);
        final imageUrl = _s(n['imageUrl']);
        final url = _s(n['url']);
        final source = _s(n['source']);

        return GestureDetector(
          onTap: () async {
            await openExternalLink(url);
          },
          child: Container(
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: context.cBgCard,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: context.cBorder),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (imageUrl.isNotEmpty)
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                  child: CachedNetworkImage(
                    imageUrl: imageUrl, height: 160, width: double.infinity, fit: BoxFit.cover,
                    errorWidget: (_, __, ___) => Container(height: 80, color: context.cBgElevated,
                      child: Icon(Icons.image_not_supported_outlined, color: context.cTextMuted)),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  if (source.isNotEmpty)
                    Container(
                      margin: const EdgeInsets.only(bottom: 6),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppColors.accentPrimary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(source.toUpperCase(), style: const TextStyle(
                        color: AppColors.accentPrimary, fontSize: 9,
                        fontWeight: FontWeight.w700, letterSpacing: 0.8)),
                    ),
                  Text(title, style: TextStyle(
                    color: context.cTextPrimary, fontSize: 14,
                    fontWeight: FontWeight.w600, fontFamily: 'Inter', height: 1.3)),
                ]),
              ),
            ]),
          ),
        );
      },
    );
  }
}
