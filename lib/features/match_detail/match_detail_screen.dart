import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../core/api/fotmob_client.dart';
import '../../core/theme/colors.dart';
import '../player/player_screen.dart';
import '../team/team_screen.dart';

// ─── Helpers ──────────────────────────────────────────────────────────────────
Map<String, dynamic> _m(dynamic v) {
  if (v is Map<String, dynamic>) return v;
  if (v is Map) return v.cast<String, dynamic>();
  return {};
}
List _l(dynamic v) => v is List ? v : [];
String _s(dynamic v) => v?.toString() ?? '';

String _playerName(dynamic raw) {
  if (raw == null) return '';
  if (raw is String) return raw;
  if (raw is Map) {
    final m = raw is Map<String, dynamic> ? raw : raw.cast<String, dynamic>();
    final first = _s(m['firstName']);
    final last  = _s(m['lastName']);
    if (last.isNotEmpty) return first.isNotEmpty ? '$first $last' : last;
    return _s(m['name']);
  }
  return raw.toString();
}

double? _rating(dynamic raw) {
  if (raw == null) return null;
  if (raw is num) return raw.toDouble();
  if (raw is Map) {
    final m = raw is Map<String, dynamic> ? raw : raw.cast<String, dynamic>();
    return double.tryParse(_s(m['num']));
  }
  return null;
}

String _lastName(String name) {
  final p = name.trim().split(' ');
  return p.length > 1 ? p.last : name;
}

Color _ratingColor(double r) {
  if (r >= 8) return AppColors.accentGold;
  if (r >= 7) return AppColors.accentGreen;
  if (r >= 6) return AppColors.accentOrange;
  return AppColors.accentRed;
}

const _posMap = {
  1: 'GK', 2: 'RB', 3: 'CB', 4: 'LB', 5: 'DM',
  6: 'CM', 7: 'AM', 8: 'RW', 9: 'LW', 10: 'ST', 11: 'GK',
};

// ─── Provider ─────────────────────────────────────────────────────────────────
final _matchDetailProvider = FutureProvider.family<Map<String, dynamic>, String>((ref, id) async {
  ref.keepAlive();
  return FotmobClient.getMatchDetails(id);
});

// ─── Glass Card ───────────────────────────────────────────────────────────────
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

// ─── Section Title ────────────────────────────────────────────────────────────
class _SecTitle extends StatelessWidget {
  final String title;
  const _SecTitle(this.title);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 14),
    child: Row(children: [
      Container(width: 3, height: 16, decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [AppColors.accentBlue, AppColors.accentPurple]),
        borderRadius: BorderRadius.circular(2),
      )),
      const SizedBox(width: 10),
      Text(title, style: const TextStyle(fontFamily: 'Inter', fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimary, letterSpacing: 0.5)),
    ]),
  );
}

// ─── Screen ───────────────────────────────────────────────────────────────────
class MatchDetailScreen extends ConsumerStatefulWidget {
  final String matchId;
  const MatchDetailScreen({super.key, required this.matchId});

  @override
  ConsumerState<MatchDetailScreen> createState() => _MatchDetailScreenState();
}

class _MatchDetailScreenState extends ConsumerState<MatchDetailScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;
  final _tabLabels = ['PREVIEW', 'EVENTS', 'STATS', 'LINEUP', 'H2H', 'COMMENTARY', 'PLAYERS'];

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: _tabLabels.length, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(_matchDetailProvider(widget.matchId));
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: data.when(
        data: (d) => _buildBody(d),
        loading: () => const Center(child: CircularProgressIndicator(color: AppColors.accentBlue)),
        error: (e, _) => Scaffold(
          appBar: AppBar(backgroundColor: AppColors.bg, leading: const BackButton(color: AppColors.textPrimary)),
          backgroundColor: AppColors.bg,
          body: Center(child: Text('Could not load match: $e', style: const TextStyle(color: AppColors.textMuted))),
        ),
      ),
    );
  }

  Widget _buildBody(Map<String, dynamic> data) {
    final header   = _m(data['header']);
    final general  = _m(data['general']);
    final teams    = _l(header['teams']);
    final home     = teams.isNotEmpty ? _m(teams[0]) : <String, dynamic>{};
    final away     = teams.length > 1 ? _m(teams[1]) : <String, dynamic>{};
    final status   = _m(header['status']);
    final topPad   = MediaQuery.of(context).padding.top;
    final league   = _s(general['leagueName']).isNotEmpty ? _s(general['leagueName'])
                   : _s(general['parentLeagueName']).isNotEmpty ? _s(general['parentLeagueName'])
                   : _s(_m(header['tournament'])['name']);

    return Column(
      children: [
        Container(
          height: 238 + topPad,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter, end: Alignment.bottomCenter,
              colors: [Color(0xFF152030), Color(0xFF0F0F0F)],
              stops: [0.0, 1.0],
            ),
          ),
          child: Stack(
            children: [
              Positioned.fill(
                child: Padding(
                  padding: EdgeInsets.only(top: topPad),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (league.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text(league,
                            style: const TextStyle(color: AppColors.textMuted, fontSize: 11, fontWeight: FontWeight.w500, letterSpacing: 0.5),
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                        ),
                      _MatchHeader(home: home, away: away, status: status),
                    ],
                  ),
                ),
              ),
              Positioned(
                left: 0, top: topPad,
                child: IconButton(
                  icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
            ],
          ),
        ),
        Container(
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
            labelStyle: const TextStyle(fontFamily: 'Inter', fontSize: 11, fontWeight: FontWeight.w700),
            tabs: _tabLabels.map((l) => Tab(text: l)).toList(),
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabs,
            children: [
              _PreviewTab(data: data),
              _EventsTab(data: data),
              _StatsTab(data: data),
              _LineupTab(data: data),
              _H2HTab(data: data, header: header),
              _CommentaryTab(matchId: widget.matchId),
              _PlayersTab(data: data, header: header),
            ],
          ),
        ),
      ],
    );
  }
}

// ─── Match Header Content ────────────────────────────────────────────────────
class _MatchHeader extends StatelessWidget {
  final Map<String, dynamic> home, away, status;
  const _MatchHeader({required this.home, required this.away, required this.status});

  @override
  Widget build(BuildContext context) {
    final isLive   = status['started'] == true && status['finished'] == false;
    final finished = status['finished'] == true;
    final score    = _s(status['scoreStr']).isNotEmpty ? _s(status['scoreStr']) : 'vs';
    final minute   = _s(_m(status['liveTime'])['short']);
    final utcTime  = _s(status['utcTime']);

    String timeLabel = '';
    if (finished) timeLabel = 'FT';
    else if (!isLive && utcTime.isNotEmpty) {
      try {
        final dt = DateTime.parse(utcTime).toLocal();
        timeLabel = '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
      } catch (_) {}
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
      children: [
        Expanded(child: _TeamBlock(team: home)),
        const SizedBox(width: 12),
        SizedBox(
          width: 96,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (isLive) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [AppColors.live, AppColors.accentRed]),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text('LIVE${minute.isNotEmpty ? ' $minute\'' : ''}',
                    style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700)),
              ),
              const SizedBox(height: 4),
            ] else if (timeLabel.isNotEmpty) ...[
              Text(timeLabel, style: TextStyle(
                color: finished ? AppColors.textMuted : AppColors.textSecondary, fontSize: 11, fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
            ],
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(score, style: TextStyle(fontFamily: 'Oswald', fontSize: 38, fontWeight: FontWeight.w800, color: AppColors.textPrimary,
                shadows: [Shadow(blurRadius: 10, color: Colors.black.withOpacity(0.3))])),
            ),
          ]),
        ),
        const SizedBox(width: 12),
        Expanded(child: _TeamBlock(team: away)),
      ],
    ),
    );
  }
}

class _TeamBlock extends StatelessWidget {
  final Map<String, dynamic> team;
  const _TeamBlock({required this.team});

  @override
  Widget build(BuildContext context) {
    final id   = team['id'];
    final name = _s(team['name']);
    return GestureDetector(
      onTap: () {
        if (id != null) {
          Navigator.push(context, MaterialPageRoute(builder: (_) => TeamScreen(teamId: _s(id), teamName: name)));
        }
      },
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 52, height: 52,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [BoxShadow(color: Colors.white.withOpacity(0.05), blurRadius: 15, spreadRadius: 2)],
            ),
            child: ClipOval(
              child: id != null
                ? CachedNetworkImage(imageUrl: FotmobClient.teamLogoUrl(id), width: 52, height: 52, fit: BoxFit.cover,
                    errorWidget: (_, __, ___) => Container(
                      color: AppColors.bgElevated,
                      child: const Icon(Icons.sports_soccer, size: 24, color: AppColors.textMuted)))
                : Container(
                  color: AppColors.bgElevated,
                  child: const Icon(Icons.sports_soccer, size: 24, color: AppColors.textMuted)),
            ),
          ),
          const SizedBox(height: 6),
          Text(name, style: const TextStyle(fontFamily: 'Inter', fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
            textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis),
        ]),
    );
  }
}

// ─── Info Line ────────────────────────────────────────────────────────────────
class _InfoLine extends StatelessWidget {
  final IconData icon;
  final String text;
  final Widget? trailing;
  const _InfoLine({required this.icon, required this.text, this.trailing});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Row(children: [
      Container(
        width: 32, height: 32,
        decoration: BoxDecoration(
          color: AppColors.accentBlue.withOpacity(0.08),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, size: 14, color: AppColors.accentBlue),
      ),
      const SizedBox(width: 10),
      Expanded(child: Text(text, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13))),
      if (trailing != null) trailing!,
    ]),
  );
}

// ─── PREVIEW TAB ──────────────────────────────────────────────────────────────
class _PreviewTab extends StatelessWidget {
  final Map<String, dynamic> data;
  const _PreviewTab({required this.data});

  @override
  Widget build(BuildContext context) {
    final content    = _m(data['content']);
    final matchFacts = _m(content['matchFacts']);
    final general    = _m(data['general']);
    final header     = _m(data['header']);
    final teams      = _l(header['teams']);
    final home       = teams.isNotEmpty ? _m(teams[0]) : <String, dynamic>{};
    final away       = teams.length > 1 ? _m(teams[1]) : <String, dynamic>{};

    final infoBox  = _m(matchFacts['infoBox']);
    final stadium  = _m(infoBox['Stadium']);
    final venue    = _s(stadium['name']).isNotEmpty ? _s(stadium['name']) : _s(_m(_m(_m(matchFacts['matchInfo'])['venue'])['shortName']));
    final city     = _s(stadium['city']);
    final referee  = _s(_m(infoBox['Referee'])['name']);
    final capacity = _s(stadium['capacity']);
    final surface  = _s(_m(infoBox['Surface'])['value']);
    final round    = _s(_m(infoBox['Match round'])['value']).isNotEmpty
        ? _s(_m(infoBox['Match round'])['value']) : _s(general['matchRound']);
    final utcTime  = _s(general['matchTimeUTC']).isNotEmpty ? _s(general['matchTimeUTC']) : _s(_m(header['status'])['utcTime']);

    String dateStr = '';
    if (utcTime.isNotEmpty) {
      try {
        final dt = DateTime.parse(utcTime).toLocal();
        dateStr = '${_weekday(dt.weekday)}, ${dt.day} ${_month(dt.month)} ${dt.year}  ${dt.hour.toString().padLeft(2,'0')}:${dt.minute.toString().padLeft(2,'0')}';
      } catch (_) {}
    }

    final tvChannels = _l(matchFacts['tvChannels']).isNotEmpty
        ? _l(matchFacts['tvChannels']) : _l(matchFacts['broadcasts']).isNotEmpty
            ? _l(matchFacts['broadcasts']) : _l(data['broadcasts']).isNotEmpty ? _l(data['broadcasts']) : _l(data['tvChannels']);

    final formObj = _m(matchFacts['teamFormData']).isNotEmpty
        ? _m(matchFacts['teamFormData']) : _m(matchFacts['teamForm']).isNotEmpty
            ? _m(matchFacts['teamForm']) : _m(matchFacts['form']);
    final homeForm = _l(formObj['homeTeam']).isNotEmpty ? _l(formObj['homeTeam'])
        : _l(formObj['home']).isNotEmpty ? _l(formObj['home'])
            : _l(formObj['homeTeamForm']).isNotEmpty ? _l(formObj['homeTeamForm']) : _l(_m(general['homeTeam'])['form']);
    final awayForm = _l(formObj['awayTeam']).isNotEmpty ? _l(formObj['awayTeam'])
        : _l(formObj['away']).isNotEmpty ? _l(formObj['away'])
            : _l(formObj['awayTeamForm']).isNotEmpty ? _l(formObj['awayTeamForm']) : _l(_m(general['awayTeam'])['form']);

    final rawInsights = _l(_m(matchFacts['matchInsights'])['texts']).isNotEmpty
        ? _l(_m(matchFacts['matchInsights'])['texts']) : _l(matchFacts['matchInsights']).isNotEmpty
            ? _l(matchFacts['matchInsights']) : _l(_m(matchFacts['insights'])['texts']).isNotEmpty
                ? _l(_m(matchFacts['insights'])['texts']) : _l(matchFacts['insights']);
    final insights = rawInsights.map((e) => e is String ? e : _s(_m(e)['text'])).where((s) => s.isNotEmpty).toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        if (dateStr.isNotEmpty || venue.isNotEmpty || round.isNotEmpty || referee.isNotEmpty || capacity.isNotEmpty || surface.isNotEmpty) ...[
          const _SecTitle('MATCH INFO'),
          _GlassCard(
            child: Column(children: [
              if (dateStr.isNotEmpty)     _InfoLine(icon: Icons.calendar_today, text: dateStr),
              if (venue.isNotEmpty)       _InfoLine(icon: Icons.location_on, text: [venue, city].where((s) => s.isNotEmpty).join(', ')),
              if (round.isNotEmpty)       _InfoLine(icon: Icons.emoji_events, text: round),
              if (referee.isNotEmpty)     _InfoLine(icon: Icons.person, text: 'Referee: $referee'),
              if (capacity.isNotEmpty)    _InfoLine(icon: Icons.people, text: 'Capacity: ${int.tryParse(capacity) != null ? _fmtNum(int.parse(capacity)) : capacity}'),
              if (surface.isNotEmpty)     _InfoLine(icon: Icons.layers, text: 'Surface: $surface'),
            ]),
          ),
        ],

        if (tvChannels.isNotEmpty) ...[
          const _SecTitle('WHERE TO WATCH'),
          _GlassCard(
            child: Wrap(spacing: 8, runSpacing: 8,
              children: tvChannels.take(8).map((ch) => _TvChip(ch: _m(ch))).toList()),
          ),
        ],

        if (homeForm.isNotEmpty || awayForm.isNotEmpty) ...[
          const _SecTitle('TEAM FORM'),
          _GlassCard(
            child: Column(children: [
              _FormRow(label: _s(home['name']), form: homeForm),
              const Divider(height: 16, color: AppColors.border),
              _FormRow(label: _s(away['name']), form: awayForm),
            ]),
          ),
        ],

        if (insights.isNotEmpty) ...[
          const _SecTitle('MATCH INSIGHTS'),
          _GlassCard(
            child: Column(children: [
              ...insights.take(10).map((txt) => _InsightRow(text: txt)),
            ]),
          ),
        ],

        if (dateStr.isEmpty && tvChannels.isEmpty && homeForm.isEmpty && insights.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 48),
            child: Center(child: Text('Preview not available yet', style: TextStyle(color: AppColors.textMuted))),
          ),
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
  String _weekday(int d) => ['Mon','Tue','Wed','Thu','Fri','Sat','Sun'][d - 1];
  String _month(int m) => ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'][m - 1];
}

class _TvChip extends StatelessWidget {
  final Map<String, dynamic> ch;
  const _TvChip({required this.ch});
  @override
  Widget build(BuildContext context) {
    final name = _s(ch['name']).isNotEmpty ? _s(ch['name']) : _s(ch['channelName']);
    final logo = _s(ch['logoUrl']).isNotEmpty ? _s(ch['logoUrl']) : _s(ch['logoSmallUrl']);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (logo.isNotEmpty) ...[
          CachedNetworkImage(imageUrl: logo, width: 20, height: 20,
            errorWidget: (_, __, ___) => const SizedBox()),
          const SizedBox(width: 6),
        ],
        Text(name, style: const TextStyle(color: AppColors.textPrimary, fontSize: 12, fontWeight: FontWeight.w600)),
      ]),
    );
  }
}

class _FormRow extends StatelessWidget {
  final String label;
  final List form;
  const _FormRow({required this.label, required this.form});
  static const _colors = {'W': AppColors.accentGreen, 'D': AppColors.accentOrange, 'L': AppColors.accentRed};
  @override
  Widget build(BuildContext context) {
    if (form.isEmpty) return const SizedBox();
    return Row(children: [
      SizedBox(width: 100, child: Text(label, style: const TextStyle(color: AppColors.textPrimary, fontSize: 12, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis)),
      const Spacer(),
      ...form.reversed.take(6).toList().reversed.map((f) {
        final r = _s(_m(f)['result']).isNotEmpty ? _s(_m(f)['result']) : _s(_m(f)['resultString']);
        final c = _colors[r] ?? AppColors.textMuted;
        return Container(
          width: 28, height: 28,
          margin: const EdgeInsets.only(left: 6),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [c, c.withOpacity(0.7)]),
          ),
          child: Center(child: Text(r, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800))),
        );
      }),
    ]);
  }
}

class _InsightRow extends StatelessWidget {
  final String text;
  const _InsightRow({required this.text});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        margin: const EdgeInsets.only(top: 4),
        width: 8, height: 8,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const LinearGradient(colors: [AppColors.accentBlue, AppColors.accentPurple]),
        ),
      ),
      const SizedBox(width: 10),
      Expanded(child: Text(text, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.4))),
    ]),
  );
}

// ─── EVENTS TAB ───────────────────────────────────────────────────────────────
class _EventsTab extends StatelessWidget {
  final Map<String, dynamic> data;
  const _EventsTab({required this.data});

  @override
  Widget build(BuildContext context) {
    final content = _m(data['content']);
    List events = _l(_m(_m(content['matchFacts'])['events'])['events']);
    if (events.isEmpty) events = _l(_m(content['events'])['events']);
    if (events.isEmpty) events = _l(_m(content['matchFacts'])['events']);

    final goals = events.where((e) => _s(_m(e)['type']).toLowerCase().contains('goal')).toList();
    final cards = events.where((e) => _s(_m(e)['type']).toLowerCase().contains('card')).toList();
    final subs  = events.where((e) {
      final t = _s(_m(e)['type']).toLowerCase();
      return t.contains('subst') || t == 'substitutionin';
    }).toList();

    if (events.isEmpty) {
      return const Center(child: Text('No events yet', style: TextStyle(color: AppColors.textMuted)));
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        if (goals.isNotEmpty) ...[
          const _SecTitle('GOALS'),
          const SizedBox(height: 4),
          _GlassCard(child: Column(children: goals.map((e) => _EventRow(event: _m(e), type: 'goal')).toList())),
        ],
        if (cards.isNotEmpty) ...[
          const _SecTitle('CARDS'),
          const SizedBox(height: 4),
          _GlassCard(child: Column(children: cards.map((e) => _EventRow(event: _m(e), type: 'card')).toList())),
        ],
        if (subs.isNotEmpty) ...[
          const _SecTitle('SUBSTITUTIONS'),
          const SizedBox(height: 4),
          _GlassCard(child: Column(children: subs.map((e) => _EventRow(event: _m(e), type: 'sub')).toList())),
        ],
      ],
    );
  }
}

String _playerId(dynamic raw) {
  if (raw == null) return '';
  if (raw is Map) return _s(raw['id'] ?? raw['playerId']);
  return '';
}

class _EventRow extends StatelessWidget {
  final Map<String, dynamic> event;
  final String type;
  const _EventRow({required this.event, required this.type});

  @override
  Widget build(BuildContext context) {
    final isHome = event['isHome'] == true || event['isHomeTeam'] == true;
    final min    = _s(event['time']).isNotEmpty ? _s(event['time']) : _s(event['timeStr']);
    final over   = _s(event['overloadTime']).isNotEmpty ? '+${event['overloadTime']}' : '';
    final timeStr = "$min$over'";

    final playerRaw = event['player'];
    String player = _playerName(playerRaw);
    if (player.isEmpty) player = _s(event['playerName']);
    final playerId = _playerId(playerRaw).isNotEmpty ? _playerId(playerRaw) : _s(event['playerId']);

    String playerIn  = '';
    String playerOut = '';
    String playerInId = '', playerOutId = '';
    if (type == 'sub') {
      final swap = _m(event['swap']);
      if (swap.isNotEmpty) {
        playerIn  = _playerName(_m(swap['playerIn'])['name']).isNotEmpty ? _playerName(_m(swap['playerIn'])['name']) : _playerName(swap['playerIn']);
        playerOut = _playerName(_m(swap['playerOut'])['name']).isNotEmpty ? _playerName(_m(swap['playerOut'])['name']) : _playerName(swap['playerOut']);
        playerInId = _playerId(swap['playerIn']);
        playerOutId = _playerId(swap['playerOut']);
      }
      if (playerIn.isEmpty) {
        playerIn  = _playerName(event['playerIn']);
        playerOut = _playerName(event['playerOut']);
        playerInId = _playerId(event['playerIn']);
        playerOutId = _playerId(event['playerOut']);
      }
      if (playerIn.isEmpty) { playerIn = player; playerInId = playerId; }
    }

    final assistRaw = event['assistPlayer'];
    final assist = _playerName(assistRaw).isNotEmpty ? _playerName(assistRaw) : _playerName(_m(assistRaw)['name']);
    final assistId = _playerId(assistRaw).isNotEmpty ? _playerId(assistRaw) : _s(_m(assistRaw)['id']);

    Color iconColor = AppColors.accentGreen;
    IconData icon   = Icons.sports_soccer;
    if (type == 'card') {
      icon = Icons.square_rounded;
      final c = _s(event['card']).toLowerCase();
      iconColor = (c.contains('red') || c.contains('yellowred')) ? AppColors.accentRed : AppColors.accentOrange;
    } else if (type == 'sub') {
      icon = Icons.swap_horiz;
      iconColor = AppColors.accentBlue;
    }

    final clockBox = Container(
      constraints: const BoxConstraints(minWidth: 36),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.bgElevated,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(timeStr, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12, fontFamily: 'Oswald', fontWeight: FontWeight.w600), textAlign: TextAlign.center),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(children: [
        if (!isHome) ...[clockBox, const SizedBox(width: 10)],
        Icon(icon, color: iconColor, size: 18),
        const SizedBox(width: 8),
        Expanded(child: Column(
          crossAxisAlignment: isHome ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            if (type == 'sub' && playerIn.isNotEmpty) ...[
              GestureDetector(
                onTap: () { if (playerInId.isNotEmpty) Navigator.push(context, MaterialPageRoute(builder: (_) => PlayerScreen(playerId: playerInId, playerName: playerIn))); },
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.arrow_upward, size: 12, color: AppColors.accentGreen),
                  const SizedBox(width: 2),
                  Text(playerIn, style: const TextStyle(color: AppColors.accentGreen, fontSize: 13, fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
                ]),
              ),
              if (playerOut.isNotEmpty)
                GestureDetector(
                  onTap: () { if (playerOutId.isNotEmpty) Navigator.push(context, MaterialPageRoute(builder: (_) => PlayerScreen(playerId: playerOutId, playerName: playerOut))); },
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.arrow_downward, size: 12, color: AppColors.accentRed),
                    const SizedBox(width: 2),
                      Text(playerOut, style: const TextStyle(color: AppColors.accentRed, fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
                  ]),
                ),
            ] else ...[
              if (player.isNotEmpty)
                GestureDetector(
                  onTap: () { if (playerId.isNotEmpty) Navigator.push(context, MaterialPageRoute(builder: (_) => PlayerScreen(playerId: playerId, playerName: player))); },
                  child: Text(player, style: const TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
              if (assist.isNotEmpty)
                GestureDetector(
                  onTap: () { if (assistId.isNotEmpty) Navigator.push(context, MaterialPageRoute(builder: (_) => PlayerScreen(playerId: assistId, playerName: assist))); },
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.remove_red_eye, size: 10, color: AppColors.textMuted),
                    const SizedBox(width: 2),
                      Text(assist, style: const TextStyle(color: AppColors.textMuted, fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis),
                  ]),
                ),
            ],
          ],
        )),
        if (isHome) ...[const SizedBox(width: 10), clockBox],
      ]),
    );
  }
}

// ─── STATS TAB ────────────────────────────────────────────────────────────────
class _StatsTab extends StatelessWidget {
  final Map<String, dynamic> data;
  const _StatsTab({required this.data});

  @override
  Widget build(BuildContext context) {
    final content  = _m(data['content']);
    final header   = _m(data['header']);
    final teams    = _l(header['teams']);
    final homeName = teams.isNotEmpty ? _s(_m(teams[0])['name']) : '';
    final awayName = teams.length > 1 ? _s(_m(teams[1])['name']) : '';
    final statsRoot = _m(content['stats']);

    List groups = [];
    final periods = _m(statsRoot['Periods']);
    if (periods.containsKey('All'))       groups = _l(_m(periods['All'])['stats']);
    if (groups.isEmpty && periods.containsKey('1H')) groups = _l(_m(periods['1H'])['stats']);
    if (groups.isEmpty)                   groups = _l(statsRoot['stats']);

    if (groups.isEmpty) {
      return const Center(child: Text('Stats not available yet', style: TextStyle(color: AppColors.textMuted)));
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        Row(children: [
          Expanded(child: Text(homeName, style: const TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w700))),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.06),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text('STATS', style: TextStyle(color: AppColors.textMuted, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1)),
          ),
          Expanded(child: Text(awayName, style: const TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w700), textAlign: TextAlign.right)),
        ]),
        const SizedBox(height: 8),
        for (int gi = 0; gi < groups.length; gi++) ...[
          const SizedBox(height: 8),
          _GlassCard(
            child: Column(children: [
              Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.04),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(_s(_m(groups[gi])['title']).toUpperCase(),
                    style: const TextStyle(color: AppColors.textMuted, fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: 1)),
                ),
              ),
              const SizedBox(height: 8),
              ...(_l(_m(groups[gi])['stats'])).asMap().entries.map((e) =>
                _StatRow(key: ValueKey('$gi-${e.key}'), stat: _m(e.value))),
            ]),
          ),
        ],
      ],
    );
  }
}

class _StatRow extends StatelessWidget {
  final Map<String, dynamic> stat;
  const _StatRow({super.key, required this.stat});

  @override
  Widget build(BuildContext context) {
    final title = _s(stat['title']).isNotEmpty ? _s(stat['title']) : _s(stat['name']);

    String home = '', away = '';
    final vals = _l(stat['stats']).isNotEmpty ? _l(stat['stats']) : _l(stat['values']);
    if (vals.length >= 2) {
      home = _s(vals[0]);
      away = _s(vals[1]);
    } else {
      home = _s(stat['home']).isNotEmpty ? _s(stat['home']) : _s(stat['homeValue']);
      away = _s(stat['away']).isNotEmpty ? _s(stat['away']) : _s(stat['awayValue']);
    }

    final hVal  = double.tryParse(home.replaceAll('%', '').replaceAll(',', '').trim()) ?? 0;
    final aVal  = double.tryParse(away.replaceAll('%', '').replaceAll(',', '').trim()) ?? 0;
    final total = hVal + aVal;
    final hFrac = total > 0 ? (hVal / total).clamp(0.0, 1.0) : 0.5;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(children: [
        Row(children: [
          SizedBox(width: 40, child: Text(home, style: TextStyle(fontFamily: 'Oswald', fontSize: 16,
            color: hFrac > 0.5 ? AppColors.accentBlue : AppColors.textPrimary, fontWeight: FontWeight.w700), textAlign: TextAlign.center)),
          const SizedBox(width: 8),
          Expanded(child: Text(title, style: const TextStyle(fontSize: 12, color: AppColors.textMuted), textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis)),
          const SizedBox(width: 8),
          SizedBox(width: 40, child: Text(away, style: TextStyle(fontFamily: 'Oswald', fontSize: 16,
            color: hFrac < 0.5 ? AppColors.accentBlue : AppColors.textPrimary, fontWeight: FontWeight.w700), textAlign: TextAlign.center)),
        ]),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: Row(children: [
            Flexible(
              flex: (hFrac * 1000).round().clamp(1, 999),
              child: Container(
                height: 6,
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [AppColors.accentBlue, AppColors.accentBlue.withOpacity(0.7)]),
                ),
              ),
            ),
            Flexible(
              flex: ((1 - hFrac) * 1000).round().clamp(1, 999),
              child: Container(
                height: 6,
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [AppColors.accentRed.withOpacity(0.7), AppColors.accentRed]),
                ),
              ),
            ),
          ]),
        ),
      ]),
    );
  }
}

// ─── LINEUP TAB ───────────────────────────────────────────────────────────────
class _LineupTab extends StatefulWidget {
  final Map<String, dynamic> data;
  const _LineupTab({required this.data});
  @override
  State<_LineupTab> createState() => _LineupTabState();
}

class _LineupTabState extends State<_LineupTab> {
  bool _pitchView = true;

  @override
  Widget build(BuildContext context) {
    final content  = _m(widget.data['content']);
    final lineup   = _m(content['lineup']).isNotEmpty ? _m(content['lineup']) : _m(widget.data['lineup']);
    if (lineup['homeTeam'] == null && lineup['awayTeam'] == null) {
      return const Center(child: Text('Lineup not announced yet', style: TextStyle(color: AppColors.textMuted)));
    }

    final homeTeam = _m(lineup['homeTeam']);
    final awayTeam = _m(lineup['awayTeam']);
    final coaches  = _l(lineup['coaches']);

    final homeP = _getPlayers(homeTeam);
    final awayP = _getPlayers(awayTeam);
    final homeCoach = coaches.firstWhere((c) => _m(c)['teamId'] == homeTeam['id'], orElse: () => null);
    final awayCoach = coaches.firstWhere((c) => _m(c)['teamId'] == awayTeam['id'], orElse: () => null);

    return SingleChildScrollView(
      child: Column(children: [
        const SizedBox(height: 8),
        // Toggle
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.04),
            borderRadius: BorderRadius.circular(24),
          ),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, mainAxisSize: MainAxisSize.min, children: [
            _ToggleBtn(label: 'Pitch', icon: Icons.grid_view, active: _pitchView, onTap: () => setState(() => _pitchView = true)),
            const SizedBox(width: 4),
            _ToggleBtn(label: 'List', icon: Icons.list, active: !_pitchView, onTap: () => setState(() => _pitchView = false)),
          ]),
        ),
        const SizedBox(height: 12),

        // Formation labels
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Column(children: [
              Text(_s(homeTeam['formation']), style: const TextStyle(fontFamily: 'Oswald', fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.accentBlue)),
              Text(_s(homeTeam['name']), style: const TextStyle(color: AppColors.textMuted, fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis),
            ]),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.06),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text('vs', style: TextStyle(color: AppColors.textMuted, fontSize: 11, fontWeight: FontWeight.w600)),
            ),
            Column(children: [
              Text(_s(awayTeam['formation']), style: const TextStyle(fontFamily: 'Oswald', fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.accentRed)),
              Text(_s(awayTeam['name']), style: const TextStyle(color: AppColors.textMuted, fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis),
            ]),
          ]),
        ),
        const SizedBox(height: 12),

        if (_pitchView)
          _PitchView(homeTeam: homeTeam, awayTeam: awayTeam, homePlayers: homeP, awayPlayers: awayP)
        else
          _LineupListView(homeStarters: homeP['starters'] ?? [], awayStarters: awayP['starters'] ?? []),

        // Substitutes
        if ((homeP['bench'] ?? []).isNotEmpty || (awayP['bench'] ?? []).isNotEmpty) ...[
          const Padding(padding: EdgeInsets.fromLTRB(16, 16, 16, 8), child: _SecTitle('SUBSTITUTES')),
          _BenchList(home: homeP['bench']!, away: awayP['bench']!),
        ],

        // Coach
        if (homeCoach != null || awayCoach != null) ...[
          const Padding(padding: EdgeInsets.fromLTRB(16, 16, 16, 8), child: _SecTitle('COACH')),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(children: [
              Expanded(child: homeCoach != null ? _CoachRow(coach: _m(homeCoach)) : const SizedBox()),
              const SizedBox(width: 8),
              Expanded(child: awayCoach != null ? _CoachRow(coach: _m(awayCoach), isAway: true) : const SizedBox()),
            ]),
          ),
        ],
        const SizedBox(height: 24),
      ]),
    );
  }

  Map<String, List<Map<String, dynamic>>> _getPlayers(Map<String, dynamic> team) {
    final starters = <Map<String, dynamic>>[];
    final bench    = <Map<String, dynamic>>[];
    final starterList = _l(team['starters']);
    final subsList    = _l(team['subs']);
    if (starterList.isNotEmpty || subsList.isNotEmpty) {
      for (final p in starterList) starters.add(_m(p));
      for (final p in subsList) bench.add(_m(p));
      return {'starters': starters, 'bench': bench};
    }
    final players  = _l(team['players']);
    final benchList = _l(team['bench']);
    if (players.isNotEmpty || benchList.isNotEmpty) {
      for (final p in players) starters.add(_m(p));
      for (final p in benchList) bench.add(_m(p));
      return {'starters': starters, 'bench': bench};
    }
    return {'starters': starters, 'bench': bench};
  }
}

class _ToggleBtn extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool active;
  final VoidCallback onTap;
  const _ToggleBtn({required this.label, required this.icon, required this.active, required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(
        color: active ? AppColors.accentBlue : Colors.transparent,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 14, color: active ? Colors.white : AppColors.textMuted),
        const SizedBox(width: 5),
        Text(label, style: TextStyle(color: active ? Colors.white : AppColors.textMuted, fontSize: 12, fontWeight: FontWeight.w600)),
      ]),
    ),
  );
}

class _LineupListView extends StatelessWidget {
  final List<Map<String, dynamic>> homeStarters, awayStarters;
  const _LineupListView({required this.homeStarters, required this.awayStarters});

  @override
  Widget build(BuildContext context) {
    final max = homeStarters.length > awayStarters.length ? homeStarters.length : awayStarters.length;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: _GlassCard(
        child: Column(
          children: List.generate(max, (i) {
            final h = i < homeStarters.length ? homeStarters[i] : null;
            final a = i < awayStarters.length ? awayStarters[i] : null;
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(children: [
                Expanded(child: h != null ? _ListPlayer(player: h) : const SizedBox()),
                Container(width: 1, height: 36, color: AppColors.border, margin: const EdgeInsets.symmetric(horizontal: 8)),
                Expanded(child: a != null ? _ListPlayer(player: a, isAway: true) : const SizedBox()),
              ]),
            );
          }),
        ),
      ),
    );
  }
}

class _ListPlayer extends StatelessWidget {
  final Map<String, dynamic> player;
  final bool isAway;
  const _ListPlayer({required this.player, this.isAway = false});
  @override
  Widget build(BuildContext context) {
    final id    = player['id'] ?? player['playerId'];
    final name  = _s(player['name']).isNotEmpty ? _s(player['name']) : '${_s(player['firstName'])} ${_s(player['lastName'])}'.trim();
    final shirt = _s(player['shirtNumber']).isNotEmpty ? _s(player['shirtNumber']) : _s(player['shirt']);
    final posId = player['positionId'];
    final pos   = posId != null ? (_posMap[(posId is int ? posId : (posId as num).toInt())] ?? '') : '';
    final r     = _rating(player['rating']);

    return GestureDetector(
      onTap: () { if (id != null) Navigator.push(context, MaterialPageRoute(builder: (_) => PlayerScreen(playerId: _s(id), playerName: name))); },
      child: Row(
        textDirection: isAway ? TextDirection.rtl : TextDirection.ltr,
        children: [
          Container(
            width: 26, height: 26,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.bgElevated,
              border: Border.all(color: Colors.white.withOpacity(0.08)),
            ),
            child: Center(child: Text(shirt, style: const TextStyle(color: AppColors.textSecondary, fontSize: 10, fontWeight: FontWeight.w700))),
          ),
          const SizedBox(width: 8),
          Expanded(child: Column(crossAxisAlignment: isAway ? CrossAxisAlignment.end : CrossAxisAlignment.start, children: [
            Text(name, style: const TextStyle(color: AppColors.textPrimary, fontSize: 12, fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
            SizedBox(height: 2),
            Row(mainAxisSize: MainAxisSize.min, mainAxisAlignment: isAway ? MainAxisAlignment.end : MainAxisAlignment.start, children: [
              Text(pos, style: const TextStyle(color: AppColors.textMuted, fontSize: 9)),
              if (r != null) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  decoration: BoxDecoration(
                    color: _ratingColor(r).withOpacity(0.15),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Text(r.toStringAsFixed(1), style: TextStyle(color: _ratingColor(r), fontSize: 8, fontWeight: FontWeight.w700)),
                ),
              ],
            ]),
          ])),
        ],
      ),
    );
  }
}

class _PitchView extends StatelessWidget {
  final Map<String, dynamic> homeTeam, awayTeam;
  final Map<String, List<Map<String, dynamic>>> homePlayers, awayPlayers;
  const _PitchView({required this.homeTeam, required this.awayTeam, required this.homePlayers, required this.awayPlayers});

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width - 28;
    final h = MediaQuery.of(context).size.height * 0.75;
    final homeStarters  = homePlayers['starters']!;
    final awayStarters  = awayPlayers['starters']!;
    final homeFormation = _s(homeTeam['formation']).isNotEmpty ? _s(homeTeam['formation']) : '4-4-2';
    final awayFormation = _s(awayTeam['formation']).isNotEmpty ? _s(awayTeam['formation']) : '4-4-2';
    final homeRows = _buildRows(homeFormation, homeStarters);
    final awayRows = _buildRows(awayFormation, awayStarters);
    final pad = 28.0;
    final halfH = h / 2;

    return SizedBox(
      width: w + 28, height: h,
      child: Stack(children: [
        Positioned.fill(child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter, end: Alignment.bottomCenter,
              colors: [Color(0xFF1A5A3A), Color(0xFF0D3018)]),
          ),
        )),
        Positioned.fill(child: CustomPaint(painter: _FieldPainter(w: w, h: h, pad: pad))),
        ..._renderTeam2(homeRows, w, halfH, pad, isHome: true),
        ..._renderTeam2(awayRows, w, halfH, pad, isHome: false),
      ]),
    );
  }

  List<List<Map<String, dynamic>>> _buildRows(String formation, List<Map<String, dynamic>> starters) {
    if (starters.isEmpty) return [];
    final parts  = formation.split('-').map((s) => int.tryParse(s) ?? 0).toList();
    final counts = [1, ...parts];
    final rows   = <List<Map<String, dynamic>>>[];
    int idx = 0;
    for (final c in counts) {
      if (idx >= starters.length) break;
      rows.add(starters.sublist(idx, (idx + c).clamp(0, starters.length)));
      idx += c;
    }
    if (idx < starters.length) rows.add(starters.sublist(idx));
    return rows;
  }

  List<Widget> _renderTeam2(List<List<Map<String, dynamic>>> rows, double w, double halfH, double pad, {required bool isHome}) {
    const size = 38.0;
    final available = halfH - pad * 2 - size;
    final list = isHome ? rows : rows.reversed.toList();
    final count = list.length;
    final widgets = <Widget>[];
    for (int ri = 0; ri < count; ri++) {
      final row  = list[ri];
      final frac = count > 1 ? ri / (count - 1) : 0.5;
      final y    = isHome
          ? pad + frac * available
          : halfH + pad + frac * available;
      for (int ci = 0; ci < row.length; ci++) {
        final x = (w / (row.length + 1)) * (ci + 1) + 14 - size / 2;
        widgets.add(Positioned(left: x, top: y, child: _PitchPlayer(player: row[ci], isHome: isHome)));
      }
    }
    return widgets;
  }
}

class _FieldPainter extends CustomPainter {
  final double w, h, pad;
  const _FieldPainter({required this.w, required this.h, this.pad = 4});

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = Colors.white.withOpacity(0.3)..strokeWidth = 1.5..style = PaintingStyle.stroke;
    final ox = (size.width - w) / 2;
    canvas.drawRect(Rect.fromLTWH(ox, pad, w, h - pad * 2), p);
    canvas.drawLine(Offset(ox, h / 2), Offset(ox + w, h / 2), p);
    canvas.drawCircle(Offset(size.width / 2, h / 2), 44, p);
    final pbW = w * 0.5; final pbH = (h - pad * 2) * 0.13;
    canvas.drawRect(Rect.fromLTWH(ox + (w - pbW) / 2, pad, pbW, pbH), p);
    canvas.drawRect(Rect.fromLTWH(ox + (w - pbW) / 2, h - pad - pbH, pbW, pbH), p);
  }

  @override bool shouldRepaint(_) => false;
}

class _PitchPlayer extends StatelessWidget {
  final Map<String, dynamic> player;
  final bool isHome;
  const _PitchPlayer({required this.player, required this.isHome});
  static const _size = 38.0;

  @override
  Widget build(BuildContext context) {
    final id    = player['id'] ?? player['playerId'];
    final name  = _s(player['name']).isNotEmpty ? _s(player['name']) : '${_s(player['firstName'])} ${_s(player['lastName'])}'.trim();
    final shirt = _s(player['shirtNumber']).isNotEmpty ? _s(player['shirtNumber']) : _s(player['shirt']);
    final r     = _rating(player['rating']);

    return GestureDetector(
      onTap: () { if (id != null) Navigator.push(context, MaterialPageRoute(builder: (_) => PlayerScreen(playerId: _s(id), playerName: name))); },
      child: SizedBox(
        width: _size,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: _size, height: _size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: isHome ? AppColors.accentBlue : AppColors.accentRed, width: 2.5),
              color: Colors.white.withOpacity(0.1),
              boxShadow: [BoxShadow(color: (isHome ? AppColors.accentBlue : AppColors.accentRed).withOpacity(0.2), blurRadius: 8)],
            ),
            child: ClipOval(child: id != null
              ? CachedNetworkImage(imageUrl: FotmobClient.playerImageUrl(id), fit: BoxFit.cover,
                  errorWidget: (_, __, ___) => Center(child: Text(shirt, style: const TextStyle(color: Colors.white, fontFamily: 'Oswald', fontWeight: FontWeight.w700, fontSize: 14))))
              : Center(child: Text(shirt, style: const TextStyle(color: Colors.white, fontFamily: 'Oswald', fontWeight: FontWeight.w700, fontSize: 14)))),
          ),
          if (r != null)
            Container(
              margin: const EdgeInsets.only(top: 2),
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(color: _ratingColor(r), borderRadius: BorderRadius.circular(4)),
              child: Text(r.toStringAsFixed(1), style: const TextStyle(fontSize: 8, fontWeight: FontWeight.w800, color: Colors.white)),
            ),
          Text(_lastName(name), style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w600,
            shadows: [Shadow(blurRadius: 3, color: Colors.black.withOpacity(0.8))]),
            textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis),
        ]),
      ),
    );
  }
}

class _BenchList extends StatelessWidget {
  final List<Map<String, dynamic>> home, away;
  const _BenchList({required this.home, required this.away});

  @override
  Widget build(BuildContext context) {
    final max = home.length > away.length ? home.length : away.length;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: List.generate(max, (i) {
          final h = i < home.length ? home[i] : null;
          final a = i < away.length ? away[i] : null;
          return Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: _GlassCard(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Row(children: [
                Expanded(child: h != null ? _BenchPlayer(player: h) : const SizedBox()),
                if (h != null && a != null) const SizedBox(width: 8),
                Expanded(child: a != null ? _BenchPlayer(player: a, isAway: true) : const SizedBox()),
              ]),
            ),
          );
        }),
      ),
    );
  }
}

class _BenchPlayer extends StatelessWidget {
  final Map<String, dynamic> player;
  final bool isAway;
  const _BenchPlayer({required this.player, this.isAway = false});

  @override
  Widget build(BuildContext context) {
    final id    = player['id'] ?? player['playerId'];
    final name  = _s(player['name']).isNotEmpty ? _s(player['name']) : '${_s(player['firstName'])} ${_s(player['lastName'])}'.trim();
    final shirt = _s(player['shirtNumber']).isNotEmpty ? _s(player['shirtNumber']) : _s(player['shirt']);
    return GestureDetector(
      onTap: () { if (id != null) Navigator.push(context, MaterialPageRoute(builder: (_) => PlayerScreen(playerId: _s(id), playerName: name))); },
      child: Row(
        textDirection: isAway ? TextDirection.rtl : TextDirection.ltr,
        children: [
          Container(
            width: 30, height: 30,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withOpacity(0.06),
              border: Border.all(color: (isAway ? AppColors.accentRed : AppColors.accentBlue).withOpacity(0.4)),
            ),
            child: ClipOval(child: id != null
              ? CachedNetworkImage(imageUrl: FotmobClient.playerImageUrl(id), fit: BoxFit.cover,
                  errorWidget: (_, __, ___) => Center(child: Text(shirt, style: const TextStyle(fontSize: 10, color: AppColors.textPrimary, fontFamily: 'Oswald'))))
              : Center(child: Text(shirt, style: const TextStyle(fontSize: 10, color: AppColors.textPrimary, fontFamily: 'Oswald')))),
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(name, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12), overflow: TextOverflow.ellipsis)),
        ],
      ),
    );
  }
}

class _CoachRow extends StatelessWidget {
  final Map<String, dynamic> coach;
  final bool isAway;
  const _CoachRow({required this.coach, this.isAway = false});
  @override
  Widget build(BuildContext context) {
    final id   = coach['id'];
    final name = _s(coach['name']);
    return GestureDetector(
      onTap: () { if (id != null) Navigator.push(context, MaterialPageRoute(builder: (_) => PlayerScreen(playerId: _s(id), playerName: name))); },
      child: _GlassCard(
        padding: const EdgeInsets.all(10),
        child: Row(
          textDirection: isAway ? TextDirection.rtl : TextDirection.ltr,
          children: [
            Container(
              width: 32, height: 32,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withOpacity(0.06),
              ),
              child: ClipOval(child: id != null
                ? CachedNetworkImage(imageUrl: FotmobClient.playerImageUrl(id), fit: BoxFit.cover,
                    errorWidget: (_, __, ___) => const Icon(Icons.person, size: 18, color: AppColors.textMuted))
                : const Icon(Icons.person, size: 18, color: AppColors.textMuted)),
            ),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: isAway ? CrossAxisAlignment.end : CrossAxisAlignment.start, children: [
              Text(name, style: const TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis),
              const Text('Coach', style: TextStyle(color: AppColors.textMuted, fontSize: 10)),
            ])),
          ],
        ),
      ),
    );
  }
}

// ─── H2H TAB ──────────────────────────────────────────────────────────────────
class _H2HTab extends StatelessWidget {
  final Map<String, dynamic> data, header;
  const _H2HTab({required this.data, required this.header});

  @override
  Widget build(BuildContext context) {
    final h2h = _m(_m(data['content'])['h2h']);
    if (h2h.isEmpty) return const Center(child: Text('H2H not available', style: TextStyle(color: AppColors.textMuted)));

    final teams    = _l(header['teams']);
    final homeName = teams.isNotEmpty ? _s(_m(teams[0])['name']) : '';
    final awayName = teams.length > 1 ? _s(_m(teams[1])['name']) : '';
    final summary  = _l(h2h['summary']);
    final matches  = _l(h2h['matches']);

    int toInt(dynamic v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;
    final hw   = summary.isNotEmpty ? toInt(summary[0]) : 0;
    final draws = summary.length > 1 ? toInt(summary[1]) : 0;
    final aw   = summary.length > 2 ? toInt(summary[2]) : 0;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        const _SecTitle('HEAD TO HEAD'),
        _GlassCard(
          child: Column(children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
              Column(children: [
                Text('$hw', style: const TextStyle(fontFamily: 'Oswald', fontSize: 32, fontWeight: FontWeight.w800, color: AppColors.accentBlue)),
                Text(homeName.split(' ').last, style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
              ]),
              Column(children: [
                Text('$draws', style: const TextStyle(fontFamily: 'Oswald', fontSize: 32, fontWeight: FontWeight.w800, color: AppColors.textMuted)),
                const Text('Draw', style: TextStyle(color: AppColors.textMuted, fontSize: 11)),
              ]),
              Column(children: [
                Text('$aw', style: const TextStyle(fontFamily: 'Oswald', fontSize: 32, fontWeight: FontWeight.w800, color: AppColors.accentRed)),
                Text(awayName.split(' ').last, style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
              ]),
            ]),
            const SizedBox(height: 14),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: Row(children: [
                Flexible(flex: hw > 0 ? hw : 1, child: Container(
                  height: 8,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: [AppColors.accentBlue, AppColors.accentBlue.withOpacity(0.7)]),
                  ),
                )),
                const SizedBox(width: 2),
                Flexible(flex: draws > 0 ? draws : 1, child: Container(height: 8, color: AppColors.textMuted)),
                const SizedBox(width: 2),
                Flexible(flex: aw > 0 ? aw : 1, child: Container(
                  height: 8,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: [AppColors.accentRed, AppColors.accentRed.withOpacity(0.7)]),
                  ),
                )),
              ]),
            ),
          ]),
        ),

        if (matches.isNotEmpty) ...[
          const _SecTitle('PREVIOUS MEETINGS'),
          ...matches.take(10).map((m) => _H2HMatchRow(match: _m(m))),
        ],
      ],
    );
  }
}

class _H2HMatchRow extends StatelessWidget {
  final Map<String, dynamic> match;
  const _H2HMatchRow({required this.match});

  @override
  Widget build(BuildContext context) {
    final home  = _m(match['home']);
    final away  = _m(match['away']);
    final score = _s(_m(match['status'])['scoreStr']).isNotEmpty
        ? _s(_m(match['status'])['scoreStr']) : _s(match['score']);
    final utc   = _s(_m(match['status'])['utcTime']).isNotEmpty
        ? _s(_m(match['status'])['utcTime']) : _s(match['date']);
    String dateStr = '';
    if (utc.isNotEmpty) {
      try {
        final dt = DateTime.parse(utc).toLocal();
        dateStr = '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year.toString().substring(2)}';
      } catch (_) { dateStr = utc.length > 10 ? utc.substring(0, 10) : utc; }
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: GestureDetector(
        onTap: () {
          final id = _s(match['id']);
          if (id.isNotEmpty) Navigator.push(context, MaterialPageRoute(builder: (_) => MatchDetailScreen(matchId: id)));
        },
        child: _GlassCard(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(children: [
            SizedBox(width: 44, child: Text(dateStr, style: const TextStyle(color: AppColors.textMuted, fontSize: 10))),
            Expanded(child: Text(_s(home['name']), style: const TextStyle(color: AppColors.textPrimary, fontSize: 12), textAlign: TextAlign.right, overflow: TextOverflow.ellipsis)),
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 10),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.bgElevated,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(score.isNotEmpty ? score : '-', style: const TextStyle(fontFamily: 'Oswald', fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
            ),
            Expanded(child: Text(_s(away['name']), style: const TextStyle(color: AppColors.textPrimary, fontSize: 12), overflow: TextOverflow.ellipsis)),
          ]),
        ),
      ),
    );
  }
}

// ─── PLAYERS TAB ──────────────────────────────────────────────────────────────
class _PlayersTab extends StatelessWidget {
  final Map<String, dynamic> data, header;
  const _PlayersTab({required this.data, required this.header});

  @override
  Widget build(BuildContext context) {
    final content   = _m(data['content']);
    final psRaw     = content['playerStats'];
    final teams     = _l(header['teams']);
    final homeId    = teams.isNotEmpty ? _m(teams[0])['id'] : null;
    final awayId    = teams.length > 1 ? _m(teams[1])['id'] : null;
    final homeName  = teams.isNotEmpty ? _s(_m(teams[0])['name']) : '';
    final awayName  = teams.length > 1 ? _s(_m(teams[1])['name']) : '';

    if (psRaw == null) {
      return const Center(child: Text('Player stats not available', style: TextStyle(color: AppColors.textMuted)));
    }

    final psMap = psRaw is Map ? psRaw : <String, dynamic>{};
    final players = psMap.values.map((p) {
      final pm = _m(p);
      final topGroup = _l(pm['stats']).whereType<Map>().firstWhere(
        (g) => _s(g['key']) == 'top_stats', orElse: () => <String, dynamic>{});
      final topMap = _m(topGroup['stats']);
      final rating = _m(_m(topMap['FotMob rating'])['stat'])['value'];
      final minutes = _m(_m(topMap['Minutes played'])['stat'])['value'];
      final goals   = _m(_m(topMap['Goals'])['stat'])['value'];
      final assists = _m(_m(topMap['Assists'])['stat'])['value'];
      return {
        'id': pm['id'], 'name': pm['name'], 'teamId': pm['teamId'],
        'shirt': pm['shirtNumber'],
        'rating': rating != null ? double.tryParse(_s(rating)) : null,
        'minutes': minutes,
        'goals': goals,
        'assists': assists,
      };
    }).where((p) => p['rating'] != null)
      .toList()
      ..sort((a, b) => (b['rating'] as double? ?? 0).compareTo(a['rating'] as double? ?? 0));

    if (players.isEmpty) {
      return const Center(child: Text('Player stats not available', style: TextStyle(color: AppColors.textMuted)));
    }

    final homePlayers = players.where((p) => p['teamId'] == homeId).toList();
    final awayPlayers = players.where((p) => p['teamId'] == awayId).toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        if (homePlayers.isNotEmpty) ...[
          const SizedBox(height: 4),
          _GlassCard(child: Column(children: [
            _SecTitle(homeName.toUpperCase()),
            _PlayerStatsHeader(),
            ...homePlayers.map((p) => _PlayerStatRow(player: p)),
          ])),
        ],
        if (awayPlayers.isNotEmpty) ...[
          const SizedBox(height: 12),
          _GlassCard(child: Column(children: [
            _SecTitle(awayName.toUpperCase()),
            _PlayerStatsHeader(),
            ...awayPlayers.map((p) => _PlayerStatRow(player: p)),
          ])),
        ],
      ],
    );
  }
}

class _PlayerStatsHeader extends StatelessWidget {
  const _PlayerStatsHeader();
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(vertical: 6),
    decoration: BoxDecoration(
      border: Border(bottom: BorderSide(color: Colors.white.withOpacity(0.06))),
    ),
    child: const Row(children: [
      Expanded(flex: 3, child: Row(children: [
        SizedBox(width: 36),
        Text('Player', style: TextStyle(color: AppColors.textMuted, fontSize: 10, fontWeight: FontWeight.w700)),
      ])),
      SizedBox(width: 36, child: Text('Rat', style: TextStyle(color: AppColors.textMuted, fontSize: 10, fontWeight: FontWeight.w700), textAlign: TextAlign.center)),
      SizedBox(width: 36, child: Text('Min', style: TextStyle(color: AppColors.textMuted, fontSize: 10, fontWeight: FontWeight.w700), textAlign: TextAlign.center)),
      SizedBox(width: 28, child: Text('G', style: TextStyle(color: AppColors.textMuted, fontSize: 10, fontWeight: FontWeight.w700), textAlign: TextAlign.center)),
      SizedBox(width: 28, child: Text('A', style: TextStyle(color: AppColors.textMuted, fontSize: 10, fontWeight: FontWeight.w700), textAlign: TextAlign.center)),
    ]),
  );
}

class _PlayerStatRow extends StatelessWidget {
  final Map<String, dynamic> player;
  const _PlayerStatRow({required this.player});
  @override
  Widget build(BuildContext context) {
    final id   = player['id'];
    final name = _s(player['name']);
    final r    = player['rating'] as double?;
    final g    = _s(player['goals']);
    final a    = _s(player['assists']);
    final min  = _s(player['minutes']);

    return GestureDetector(
      onTap: () { if (id != null) Navigator.push(context, MaterialPageRoute(builder: (_) => PlayerScreen(playerId: _s(id), playerName: name))); },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: Colors.white.withOpacity(0.04))),
        ),
        child: Row(children: [
          Expanded(flex: 3, child: Row(children: [
            ClipOval(
              child: id != null
                ? CachedNetworkImage(imageUrl: FotmobClient.playerImageUrl(id), width: 28, height: 28, fit: BoxFit.cover,
                    errorWidget: (_, __, ___) => Container(
                      color: AppColors.bgElevated,
                      child: const Icon(Icons.person, size: 16, color: AppColors.textMuted)))
                : Container(
                  color: AppColors.bgElevated,
                  child: const Icon(Icons.person, size: 16, color: AppColors.textMuted)),
            ),
            const SizedBox(width: 8),
            Expanded(child: Text(name, style: const TextStyle(color: AppColors.textPrimary, fontSize: 12), overflow: TextOverflow.ellipsis)),
          ])),
          SizedBox(width: 36, child: Text(r != null ? r.toStringAsFixed(1) : '-',
            style: TextStyle(color: r != null ? _ratingColor(r) : AppColors.textMuted, fontSize: 12, fontWeight: FontWeight.w700),
            textAlign: TextAlign.center)),
          SizedBox(width: 36, child: Text(min.isNotEmpty ? min : '-', style: const TextStyle(color: AppColors.textSecondary, fontSize: 12), textAlign: TextAlign.center)),
          SizedBox(width: 28, child: Text(g.isNotEmpty && g != '0' ? g : '-', style: const TextStyle(color: AppColors.textSecondary, fontSize: 12), textAlign: TextAlign.center)),
          SizedBox(width: 28, child: Text(a.isNotEmpty && a != '0' ? a : '-', style: const TextStyle(color: AppColors.textSecondary, fontSize: 12), textAlign: TextAlign.center)),
        ]),
      ),
    );
  }
}
// ─── COMMENTARY TAB ───────────────────────────────────────────────────────────
final _commentaryProvider = FutureProvider.family<List<Map<String, dynamic>>, String>((ref, matchId) async {
  return FotmobClient.getMatchCommentary(matchId);
});

class _CommentaryTab extends ConsumerWidget {
  final String matchId;
  const _CommentaryTab({required this.matchId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(_commentaryProvider(matchId));
    return data.when(
      data: (entries) {
        if (entries.isEmpty) {
          return const Center(child: Text('Commentary not available', style: TextStyle(color: AppColors.textMuted, fontFamily: 'Inter')));
        }
        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: entries.length,
          itemBuilder: (ctx, i) {
            final e = entries[i];
            // FotMob events: {minute, minuteExtra, type, description, player, team}
            // Commentary: {minute, text, type}
            final minNum = _s(e['minute'] ?? e['min'] ?? e['time'] ?? '');
            final minExtra = _s(e['minuteExtra'] ?? e['minuteAddedTime'] ?? '');
            final min = minExtra.isNotEmpty && minExtra != '0' ? '$minNum+$minExtra' : minNum;
            final text = _s(e['text'] ?? e['comment'] ?? e['message'] ?? e['description'] ?? '');
            final type = _s(e['type'] ?? e['eventType'] ?? e['typeId'] ?? '').toLowerCase();
            // Skip empty entries
            if (text.isEmpty && min.isEmpty) return const SizedBox.shrink();

            final isGoal = type.contains('goal') || text.toLowerCase().contains('goal');
            final isCard = type.contains('card') || text.toLowerCase().contains('yellow') || text.toLowerCase().contains('red');

            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                // Minute
                Container(
                  width: 44,
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  alignment: Alignment.topCenter,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                    decoration: BoxDecoration(
                      color: isGoal ? AppColors.accentGreen.withOpacity(0.15)
                          : isCard ? AppColors.accentRed.withOpacity(0.12)
                          : AppColors.bgElevated,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(min.isNotEmpty ? "$min'" : '•',
                      style: TextStyle(
                        fontSize: 10, fontWeight: FontWeight.w700, fontFamily: 'Inter',
                        color: isGoal ? AppColors.accentGreen
                            : isCard ? AppColors.accentRed
                            : AppColors.textMuted,
                      )),
                  ),
                ),
                const SizedBox(width: 10),
                // Text
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: isGoal ? AppColors.accentGreen.withOpacity(0.06)
                          : AppColors.bgCard,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isGoal ? AppColors.accentGreen.withOpacity(0.2)
                            : AppColors.border,
                      ),
                    ),
                    child: Text(text,
                      style: TextStyle(
                        color: isGoal ? AppColors.textPrimary : AppColors.textSecondary,
                        fontSize: 12, fontFamily: 'Inter',
                        fontWeight: isGoal ? FontWeight.w600 : FontWeight.w400,
                      )),
                  ),
                ),
              ]),
            );
          },
        );
      },
      loading: () => const Center(child: CircularProgressIndicator(color: AppColors.accentBlue, strokeWidth: 2)),
      error: (e, _) => const Center(child: Text('Could not load commentary', style: TextStyle(color: AppColors.textMuted, fontFamily: 'Inter'))),
    );
  }
}
