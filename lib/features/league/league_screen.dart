import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/api/fotmob_client.dart';
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

final _leagueProvider = FutureProvider.family<Map<String, dynamic>, String>((ref, id) async {
  Map<String, dynamic> raw = {};
  String fetchError = '';
  try {
    raw = await FotmobClient.getLeagueDetails(id);
  } catch (e) {
    fetchError = e.toString();
  }
  // FotMob returns: {table:[{data:{table:{all:[rows]}}}], stats:{...}, fixtures:{...}, overview:{...}}
  // Pass the raw response directly — tabs extract their own data
  List<Map<String, dynamic>> news = [];
  try { news = await FotmobClient.getLeagueNews(id); } catch (_) {}
  return {'raw': raw, 'news': news, 'fetchError': fetchError};
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
            Tab(text: 'TABLE'), Tab(text: 'FIXTURES'), Tab(text: 'STATS'), Tab(text: 'NEWS'),
          ],
        ),
      ),
      body: data.when(
        data: (d) {
          final raw = _m(d['raw']);
          return TabBarView(controller: _tabs, children: [
            _TableTab(raw: raw, fetchError: _s(d['fetchError'])),
            _FixturesTab(raw: raw),
            _StatsTab(raw: raw),
            _LeagueNewsTab(news: (d['news'] as List?)?.cast<Map<String, dynamic>>() ?? []),
          ]);
        },
        loading: () => const Center(child: CircularProgressIndicator(color: AppColors.accentBlue)),
        error: (e, _) => Center(child: Text('Error: $e', style: const TextStyle(color: AppColors.textMuted))),
      ),
    );
  }
}

class _TableTab extends StatelessWidget {
  final Map<String, dynamic> raw;
  final String fetchError;
  const _TableTab({required this.raw, this.fetchError = ''});

  @override
  Widget build(BuildContext context) {
    // Confirmed path from logs: raw['table'][0]['data']['table']['all']
    final tables = _l(raw['table']);
    List rows = [];
    for (final t in tables) {
      final tm = _m(t);
      // Path: {data: {table: {all: [...]}}}
      final data = _m(tm['data']);
      final tableInData = _m(data['table']);
      if (tableInData['all'] != null) { rows = _l(tableInData['all']); break; }
      if (tableInData['data'] != null) { rows = _l(tableInData['data']); break; }
      // Fallback paths
      if (data['all'] != null) { rows = _l(data['all']); break; }
      if (tm['all'] != null) { rows = _l(tm['all']); break; }
      if (t is List && (t as List).isNotEmpty) { rows = t; break; }
    }

    if (rows.isEmpty) {
      return const Center(child: Text('No standings available', style: TextStyle(color: AppColors.textMuted, fontFamily: 'Inter')));
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

        return GestureDetector(
          onTap: () {
            if (teamId.isNotEmpty) Navigator.push(context, MaterialPageRoute(
              builder: (_) => TeamScreen(teamId: teamId, teamName: name)));
          },
          child: Container(
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
        ));
      },
    );
  }
}

class _FixturesTab extends StatelessWidget {
  final Map<String, dynamic> raw;
  const _FixturesTab({required this.raw});

  @override
  Widget build(BuildContext context) {
    // raw['fixtures'] has the fixtures data
    // raw['fixtures'] → {allFixtures: {fixtures: [...]}, previousFixtures: [...], nextMatch: [...]}
    final fixturesObj = _m(raw['fixtures']);
    List fixtures = _l(_m(fixturesObj['allFixtures'])['fixtures']);
    if (fixtures.isEmpty) fixtures = _l(fixturesObj['previousFixtures']);
    if (fixtures.isEmpty) fixtures = _l(fixturesObj['nextMatch']);
    if (fixtures.isEmpty) {
      for (final v in fixturesObj.values) {
        if (v is List && (v as List).isNotEmpty) { fixtures = v; break; }
        if (v is Map) {
          final inner = _l(_m(v)['fixtures'] ?? _m(v)['matches'] ?? []);
          if (inner.isNotEmpty) { fixtures = inner; break; }
        }
      }
    }

    if (fixtures.isEmpty) {
      return const Center(child: Text('No fixtures available', style: TextStyle(color: AppColors.textMuted, fontFamily: 'Inter')));
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
            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.border, width: 0.5))),
            child: Row(children: [
              SizedBox(width: 56, child: Text(timeStr, style: const TextStyle(color: AppColors.textMuted, fontSize: 10, fontFamily: 'Inter'))),
              Expanded(child: Text(_s(home['name']), style: const TextStyle(color: AppColors.textPrimary, fontSize: 12, fontWeight: FontWeight.w500), overflow: TextOverflow.ellipsis)),
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 8),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: isLive ? AppColors.live.withOpacity(0.12) : AppColors.bgElevated,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  score.isNotEmpty ? score : 'vs',
                  style: TextStyle(fontFamily: 'Oswald', fontSize: 13, fontWeight: FontWeight.w700,
                    color: isLive ? AppColors.live : finished ? AppColors.textSecondary : AppColors.textMuted),
                ),
              ),
              Expanded(child: Text(_s(away['name']), style: const TextStyle(color: AppColors.textPrimary, fontSize: 12, fontWeight: FontWeight.w500), textAlign: TextAlign.right, overflow: TextOverflow.ellipsis)),
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
    // raw['stats'] has topLists / topScorers
    final statsData = _m(raw['stats']);
    List topListSections = _l(statsData['topLists'] ?? statsData['playerStats'] ?? []);
    if (topListSections.isNotEmpty) return _buildTopList(context, topListSections);

    // Fallback: topScorers from overview
    final overview = _m(raw['overview']);
    List topScorers = _l(statsData['topScorers'] ?? overview['topScorers'] ?? []);
    if (topScorers.isEmpty) {
      return const Center(child: Text('Stats not available for this league', style: TextStyle(color: AppColors.textMuted, fontFamily: 'Inter')));
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

  Widget _buildTopList(BuildContext context, List sections) {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: sections.map((section) {
        final sec = _m(section);
        final title = _s(sec['header'] ?? sec['title'] ?? sec['name'] ?? '');
        final players = _l(sec['topList'] ?? sec['players'] ?? sec['items'] ?? []);
        if (players.isEmpty) return const SizedBox.shrink();
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 16, 4, 10),
            child: Row(children: [
              Container(width: 3, height: 14, decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [AppColors.accentBlue, AppColors.accentPurple]),
                borderRadius: BorderRadius.circular(2),
              )),
              const SizedBox(width: 8),
              Text(title.toUpperCase(), style: const TextStyle(
                fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textMuted, letterSpacing: 1.5)),
            ]),
          ),
          ...players.take(10).toList().asMap().entries.map((e) {
            final idx = e.key;
            final p = _m(e.value);
            final name = _s(p['name'] ?? p['playerName'] ?? '');
            final pid = _s(p['id'] ?? p['playerId'] ?? '');
            final val = _s(p['value'] ?? p['statValue'] ?? p['goals'] ?? p['assists'] ?? '');
            final teamName = _s(p['teamName'] ?? _m(p['team'])['name'] ?? '');
            return GestureDetector(
              onTap: () { if (pid.isNotEmpty) Navigator.push(context, MaterialPageRoute(builder: (_) => PlayerScreen(playerId: pid, playerName: name))); },
              child: Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.bgCard,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(children: [
                  SizedBox(width: 22, child: Text('${idx + 1}', style: const TextStyle(color: AppColors.textMuted, fontSize: 11, fontWeight: FontWeight.w600))),
                  if (pid.isNotEmpty)
                    ClipOval(child: CachedNetworkImage(imageUrl: FotmobClient.playerImageUrl(pid), width: 32, height: 32, fit: BoxFit.cover,
                      errorWidget: (_, __, ___) => Container(width: 32, height: 32, color: AppColors.bgElevated, child: const Icon(Icons.person, size: 18, color: AppColors.textMuted))))
                  else
                    Container(width: 32, height: 32, decoration: const BoxDecoration(color: AppColors.bgElevated, shape: BoxShape.circle),
                      child: const Icon(Icons.person, size: 18, color: AppColors.textMuted)),
                  const SizedBox(width: 10),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(name, style: const TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w500), maxLines: 1, overflow: TextOverflow.ellipsis),
                    if (teamName.isNotEmpty) Text(teamName, style: const TextStyle(color: AppColors.textMuted, fontSize: 10)),
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
      return const Center(child: Text('No news available', style: TextStyle(color: AppColors.textMuted, fontFamily: 'Inter')));
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
            if (url.isNotEmpty) {
              try {
                final uri = Uri.parse(url.startsWith('http') ? url : 'https://www.fotmob.com$url');
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              } catch (_) {}
            }
          },
          child: Container(
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: AppColors.bgCard,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (imageUrl.isNotEmpty)
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                  child: CachedNetworkImage(
                    imageUrl: imageUrl, height: 160, width: double.infinity, fit: BoxFit.cover,
                    errorWidget: (_, __, ___) => Container(height: 80, color: AppColors.bgElevated,
                      child: const Icon(Icons.image_not_supported_outlined, color: AppColors.textMuted)),
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
                        color: AppColors.accentPrimary.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(source.toUpperCase(), style: const TextStyle(
                        color: AppColors.accentPrimary, fontSize: 9,
                        fontWeight: FontWeight.w700, letterSpacing: 0.8)),
                    ),
                  Text(title, style: const TextStyle(
                    color: AppColors.textPrimary, fontSize: 14,
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
