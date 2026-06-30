import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../core/api/fotmob_client.dart';
import '../../core/theme/colors.dart';
import '../match_detail/match_detail_screen.dart';
import '../player/player_screen.dart';

Map<String, dynamic> _m(dynamic v) {
  if (v is Map<String, dynamic>) return v;
  if (v is Map) return v.cast<String, dynamic>();
  return {};
}
List _l(dynamic v) => v is List ? v : [];
String _s(dynamic v) => v?.toString() ?? '';

final _teamProvider = FutureProvider.family<Map<String, dynamic>, String>((ref, id) async {
  return FotmobClient.getTeamDetails(id);
});

final _teamGradient = const LinearGradient(
  begin: Alignment.topCenter, end: Alignment.bottomCenter,
  colors: [Color(0xFF1A2A3A), Color(0xFF0F0F0F)],
  stops: [0.0, 0.5],
);

class TeamScreen extends ConsumerStatefulWidget {
  final String teamId;
  final String? teamName;
  const TeamScreen({super.key, required this.teamId, this.teamName});

  @override
  ConsumerState<TeamScreen> createState() => _TeamScreenState();
}

class _TeamScreenState extends ConsumerState<TeamScreen>
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
    final data = ref.watch(_teamProvider(widget.teamId));
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        leading: const BackButton(color: AppColors.textPrimary),
        title: Row(children: [
          CachedNetworkImage(imageUrl: FotmobClient.teamLogoUrl(widget.teamId), width: 24, height: 24,
            errorWidget: (_, __, ___) => const SizedBox(width: 24)),
          const SizedBox(width: 8),
          Text(widget.teamName ?? 'Team', style: const TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w600)),
        ]),
        bottom: TabBar(
          controller: _tabs,
          indicatorColor: AppColors.accentBlue,
          indicatorWeight: 3,
          labelColor: AppColors.accentBlue,
          unselectedLabelColor: AppColors.textMuted,
          labelStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
          tabs: const [
            Tab(text: 'OVERVIEW'), Tab(text: 'FIXTURES'), Tab(text: 'SQUAD'),
          ],
        ),
      ),
      body: data.when(
        data: (d) => TabBarView(controller: _tabs, children: [
          _OverviewTab(data: d),
          _TeamFixturesTab(data: d),
          _SquadTab(data: d),
        ]),
        loading: () => const Center(child: CircularProgressIndicator(color: AppColors.accentBlue)),
        error: (e, _) => Center(child: Text('Error: $e', style: const TextStyle(color: AppColors.textMuted))),
      ),
    );
  }
}

class _GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  const _GlassCard({required this.child, this.padding});

  @override
  Widget build(BuildContext context) => Container(
    padding: padding ?? const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Colors.white.withOpacity(0.04),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: Colors.white.withOpacity(0.06)),
    ),
    child: child,
  );
}

class _SectionTitle extends StatelessWidget {
  final String title;
  const _SectionTitle(this.title);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 16),
    child: Row(children: [
      Container(width: 3, height: 16, decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [AppColors.accentBlue, AppColors.accentPurple]),
        borderRadius: BorderRadius.circular(2),
      )),
      const SizedBox(width: 10),
      Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary, letterSpacing: 0.3)),
    ]),
  );
}

// ─── OVERVIEW TAB ──────────────────────────────────────────────────────────
class _OverviewTab extends StatelessWidget {
  final Map<String, dynamic> data;
  const _OverviewTab({required this.data});

  @override
  Widget build(BuildContext context) {
    final details = _m(data['details']);
    final overview = _m(data['overview']);
    final venueWidget = _m(overview['venue']);
    final name = _s(details['name']);
    final country = _s(details['country']);
    final venueName = _s(venueWidget['name']);
    final venueCap = _s(venueWidget['capacity']);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Team hero
        Container(
          padding: const EdgeInsets.symmetric(vertical: 32),
          decoration: BoxDecoration(gradient: _teamGradient),
          child: Column(children: [
            Container(
              width: 100, height: 100,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [BoxShadow(color: Colors.white.withOpacity(0.08), blurRadius: 25, spreadRadius: 5)],
              ),
              child: ClipOval(
                child: CachedNetworkImage(imageUrl: FotmobClient.teamLogoUrl(details['id']), width: 100, height: 100, fit: BoxFit.cover,
                  errorWidget: (_, __, ___) => Container(
                    color: AppColors.bgElevated,
                    child: const Icon(Icons.shield, size: 50, color: AppColors.textMuted)),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(name, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: AppColors.textPrimary, letterSpacing: -0.3)),
            if (country.isNotEmpty) ...[
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.public, size: 13, color: AppColors.textSecondary),
                  const SizedBox(width: 4),
                  Text(country, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                ]),
              ),
            ],
          ]),
        ),

        // Stadium card
        if (venueName.isNotEmpty) ...[
          const _SectionTitle('STADIUM'),
          _GlassCard(
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              Container(
                width: 44, height: 44,
                decoration: BoxDecoration(
                  color: AppColors.accentBlue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.stadium_outlined, color: AppColors.accentBlue, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(venueName, style: const TextStyle(color: AppColors.textPrimary, fontSize: 15, fontWeight: FontWeight.w600)),
                if (venueCap.isNotEmpty)
                  Text('Capacity: ${int.tryParse(venueCap) != null ? _fmtNum(int.parse(venueCap)) : venueCap}',
                    style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
              ])),
            ]),
          ),
        ],
      ],
    );
  }

  String _fmtNum(int n) {
    final s = n.toString();
    final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
      buf.write(s[i]);
    }
    return buf.toString();
  }
}

// ─── FIXTURES TAB ──────────────────────────────────────────────────────────
class _TeamFixturesTab extends ConsumerWidget {
  final Map<String, dynamic> data;
  const _TeamFixturesTab({required this.data});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fixturesObj = _m(data['fixtures']);
    final allFixtures = _m(fixturesObj['allFixtures']);
    final fixtures = _l(allFixtures['fixtures']).isNotEmpty ? _l(allFixtures['fixtures']) : _l(data['matches']);
    if (fixtures.isEmpty) {
      return const Center(child: Text('No fixtures', style: TextStyle(color: AppColors.textMuted)));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: fixtures.length,
      itemBuilder: (ctx, i) {
        final m = _m(fixtures[i]);
        final home = _m(m['home']);
        final away = _m(m['away']);
        final status = _m(m['status']);
        final score = _s(status['scoreStr']);
        final isLive = status['started'] == true && status['finished'] == false;
        final finished = status['finished'] == true;
        final utcTime = _s(status['utcTime']);

        String timeStr = '';
        if (utcTime.length >= 16) {
          try {
            final dt = DateTime.parse(utcTime).toLocal();
            timeStr = '${dt.hour.toString().padLeft(2,'0')}:${dt.minute.toString().padLeft(2,'0')}';
          } catch (_) { timeStr = utcTime.length > 10 ? utcTime.substring(11, 16) : ''; }
        }

        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: GestureDetector(
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => MatchDetailScreen(matchId: _s(m['id'])))),
            child: _GlassCard(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(children: [
                 // Home team
                Expanded(child: Row(children: [
                  ClipOval(
                    child: CachedNetworkImage(
                      imageUrl: FotmobClient.teamLogoUrl(home['id']), width: 22, height: 22, fit: BoxFit.cover,
                      errorWidget: (_, __, ___) => const Icon(Icons.sports_soccer, size: 16, color: AppColors.textMuted)),
                  ),
                  const SizedBox(width: 6),
                  Expanded(child: Text(_s(home['name']), style: const TextStyle(color: AppColors.textPrimary, fontSize: 12, fontWeight: FontWeight.w600),
                    maxLines: 1, overflow: TextOverflow.ellipsis)),
                ])),
                const SizedBox(width: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: isLive ? AppColors.live.withOpacity(0.12) : AppColors.bgElevated,
                    borderRadius: BorderRadius.circular(8),
                    border: isLive ? Border.all(color: AppColors.live.withOpacity(0.3)) : null,
                  ),
                  child: Text(
                    score.isNotEmpty ? score : timeStr,
                    style: TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w700, fontFamily: 'Oswald',
                      color: isLive ? AppColors.live : finished ? AppColors.textSecondary : AppColors.textPrimary),
                  ),
                ),
                const SizedBox(width: 10),
                // Away team
                Expanded(child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                  Expanded(child: Text(_s(away['name']), style: const TextStyle(color: AppColors.textPrimary, fontSize: 12, fontWeight: FontWeight.w600),
                    textAlign: TextAlign.right, maxLines: 1, overflow: TextOverflow.ellipsis)),
                  const SizedBox(width: 6),
                  ClipOval(
                    child: CachedNetworkImage(
                      imageUrl: FotmobClient.teamLogoUrl(away['id']), width: 22, height: 22, fit: BoxFit.cover,
                      errorWidget: (_, __, ___) => const Icon(Icons.sports_soccer, size: 16, color: AppColors.textMuted)),
                  ),
                ])),
              ]),
            ),
          ),
        );
      },
    );
  }
}

// ─── SQUAD TAB ─────────────────────────────────────────────────────────────
class _SquadTab extends StatelessWidget {
  final Map<String, dynamic> data;
  const _SquadTab({required this.data});

  @override
  Widget build(BuildContext context) {
    final squadObj = _m(data['squad']);
    final groups = _l(squadObj['squad']);
    if (groups.isEmpty) {
      return const Center(child: Text('No squad data', style: TextStyle(color: AppColors.textMuted)));
    }

    return ListView(
      padding: const EdgeInsets.all(12),
      children: groups.map((g) {
        final group = _m(g);
        final title = _s(group['title']).toUpperCase();
        final members = _l(group['members']);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 12, 0, 8),
              child: Row(children: [
                Container(width: 3, height: 14, decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [AppColors.accentBlue, AppColors.accentPurple]),
                  borderRadius: BorderRadius.circular(2),
                )),
                const SizedBox(width: 8),
                Text(title, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textMuted, letterSpacing: 1.5)),
                const Spacer(),
                Text('${members.length}', style: const TextStyle(color: AppColors.textMuted, fontSize: 10)),
              ]),
            ),
            ...members.map((m) {
              final p = _m(m);
              final pid = _s(p['id'] ?? p['playerId']);
              final name = _s(p['name']);
              final pos = _s(p['position'] ?? p['pos'] ?? p['role'] ?? '');
              final shirt = _s(p['shirt'] ?? p['jerseyNumber'] ?? p['shirtNumber'] ?? '');

              return Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: GestureDetector(
                  onTap: () {
                    if (pid.isNotEmpty) {
                      Navigator.push(context, MaterialPageRoute(builder: (_) => PlayerScreen(playerId: pid, playerName: name)));
                    }
                  },
                  child: _GlassCard(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: Row(children: [
                      ClipOval(
                        child: pid.isNotEmpty
                          ? CachedNetworkImage(imageUrl: FotmobClient.playerImageUrl(pid), width: 36, height: 36, fit: BoxFit.cover,
                              errorWidget: (_, __, ___) => Container(
                                color: AppColors.bgElevated,
                                child: const Icon(Icons.person, size: 20, color: AppColors.textMuted)))
                          : Container(
                            color: AppColors.bgElevated,
                            child: const Icon(Icons.person, size: 20, color: AppColors.textMuted)),
                      ),
                      const SizedBox(width: 10),
                      if (shirt.isNotEmpty)
                        Container(
                          width: 26, height: 26,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: AppColors.bgElevated,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(shirt, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textSecondary, fontFamily: 'Oswald')),
                        ),
                      if (shirt.isNotEmpty) const SizedBox(width: 8),
                      Expanded(child: Text(name, style: const TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w500), maxLines: 1, overflow: TextOverflow.ellipsis)),
                      if (pos.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: AppColors.accentBlue.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(pos, style: TextStyle(color: AppColors.accentBlue.withOpacity(0.7), fontSize: 10, fontWeight: FontWeight.w600)),
                        ),
                    ]),
                  ),
                ),
              );
            }),
          ],
        );
      }).toList(),
    );
  }
}