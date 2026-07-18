import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../core/api/fotmob_client.dart';
import '../../core/api/espn_client.dart';
import '../../core/theme/colors.dart';
import '../match_detail/match_detail_screen.dart';
import '../league/league_screen.dart';

Map<String, dynamic> _m(dynamic v) {
  if (v is Map<String, dynamic>) return v;
  if (v is Map) return v.cast<String, dynamic>();
  return {};
}
List _l(dynamic v) => v is List ? v : [];
String _s(dynamic v) => v?.toString() ?? '';

final _scoresProvider = FutureProvider.family<Map<String, dynamic>, String>((ref, date) async {
  ref.keepAlive();
  final data = await FotmobClient.getMatchesByDate(date);
  final leagues = data['leagues'];
  if (leagues is List && leagues.isNotEmpty) return data;
  // FotMob returned nothing (e.g. blocked carrier IP) → fall back to ESPN.
  try {
    final espn = await EspnClient.getScoreboardAsLeagues(date: date);
    if ((espn['leagues'] as List?)?.isNotEmpty == true) return espn;
  } catch (_) {}
  return data;
});

String _fmtDate(DateTime dt) => '${dt.year}${dt.month.toString().padLeft(2, '0')}${dt.day.toString().padLeft(2, '0')}';

enum Filter { all, live, ft, upcoming }

extension FilterLabel on Filter {
  String get label {
    switch (this) {
      case Filter.all: return 'ALL';
      case Filter.live: return 'LIVE';
      case Filter.ft: return 'FT';
      case Filter.upcoming: return 'TODAY';
    }
  }
}

class ScoresScreen extends ConsumerStatefulWidget {
  const ScoresScreen({super.key});

  @override
  ConsumerState<ScoresScreen> createState() => _ScoresScreenState();
}

class _ScoresScreenState extends ConsumerState<ScoresScreen> {
  DateTime _selectedDate = DateTime.now();
  Filter _filter = Filter.all;
  Timer? _poll;
  late ScrollController _dateScrollCtrl;

  @override
  void initState() {
    super.initState();
    _dateScrollCtrl = ScrollController();
    _poll = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) ref.invalidate(_scoresProvider(_fmtDate(_selectedDate)));
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollDateToCenter();
    });
  }

  void _scrollDateToCenter() {
    if (!_dateScrollCtrl.hasClients) return;
    // Item extent = width 46 + horizontal margin 3*2; today sits at index 7
    // (built as now + (i-7) days). Center it in the viewport.
    const itemExtent = 52.0;
    const todayIndex = 7;
    const leftPad = 12.0;
    final viewport = _dateScrollCtrl.position.viewportDimension;
    final target = (todayIndex * itemExtent) + leftPad + (itemExtent / 2) - (viewport / 2);
    _dateScrollCtrl.animateTo(
      target.clamp(0.0, _dateScrollCtrl.position.maxScrollExtent),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  @override
  void dispose() {
    _poll?.cancel();
    _dateScrollCtrl.dispose();
    super.dispose();
  }

  void _selectDate(DateTime dt) => setState(() => _selectedDate = dt);

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: ColorScheme.dark(
            primary: AppColors.accentPrimary,
            onPrimary: Colors.white,
            surface: context.cBgCard,
            onSurface: context.cTextPrimary,
          ),
          dialogTheme: DialogThemeData(backgroundColor: context.cBg),
        ),
        child: child!,
      ),
    );
    if (picked != null) _selectDate(picked);
  }

  @override
  Widget build(BuildContext context) {
    final dateKey = _fmtDate(_selectedDate);
    final data = ref.watch(_scoresProvider(dateKey));

    return Scaffold(
      backgroundColor: context.cBg,
      body: SafeArea(
        child: Column(children: [
          // ── Header ──
          Container(
            decoration: BoxDecoration(
              color: context.cBg,
              border: Border(bottom: BorderSide(color: context.cBorder, width: 0.5)),
            ),
            child: Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 16, 10),
                child: Row(children: [
                  ShaderMask(
                    shaderCallback: (b) => AppColors.primaryGradient.createShader(b),
                    child: const Text('SCORES',
                      style: TextStyle(fontFamily: 'Oswald', fontSize: 24,
                          fontWeight: FontWeight.w700, color: Colors.white, letterSpacing: 1.5)),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: _pickDate,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                      decoration: BoxDecoration(
                        color: context.cBgElevated,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: context.cBorder),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.calendar_today_rounded, color: context.cTextSecondary, size: 14),
                        const SizedBox(width: 6),
                        Text(_formatHeaderDate(_selectedDate),
                          style: TextStyle(color: context.cTextSecondary, fontSize: 12,
                              fontWeight: FontWeight.w600, fontFamily: 'Inter')),
                      ]),
                    ),
                  ),
                ]),
              ),

              // ── Date Strip ──
              SizedBox(
                height: 60,
                child: ListView.builder(
                  controller: _dateScrollCtrl,
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  itemCount: 15,
                  itemBuilder: (ctx, i) {
                    final dt = DateTime.now().add(Duration(days: i - 7));
                    final key = _fmtDate(dt);
                    final isToday = key == _fmtDate(DateTime.now());
                    final isSelected = key == dateKey;
                    final dayName = ['M', 'T', 'W', 'T', 'F', 'S', 'S'][dt.weekday - 1];

                    return GestureDetector(
                      onTap: () => _selectDate(dt),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        curve: Curves.easeOutCubic,
                        width: 46,
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        decoration: BoxDecoration(
                          gradient: isSelected ? AppColors.primaryGradient : null,
                          color: isSelected ? null : (isToday ? context.cBgElevated : context.cBgCard),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isSelected ? Colors.transparent
                                : (isToday ? context.cBorderL : context.cBorder),
                          ),
                          boxShadow: isSelected ? [
                            BoxShadow(color: AppColors.accentPrimary.withValues(alpha: 0.3), blurRadius: 8),
                          ] : null,
                        ),
                        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                          Text(isToday ? '•' : dayName,
                            style: TextStyle(fontSize: isToday ? 14 : 9, fontWeight: FontWeight.w700,
                              color: isSelected ? Colors.white
                                  : (isToday ? AppColors.accentPrimary : context.cTextMuted),
                              fontFamily: 'Inter')),
                          Text('${dt.day}',
                            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, fontFamily: 'Inter',
                              color: isSelected ? Colors.white : context.cTextPrimary)),
                        ]),
                      ),
                    );
                  },
                ),
              ),

              // ── Filter Chips ──
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                child: Row(children: Filter.values.map((f) {
                  final active = _filter == f;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: GestureDetector(
                      onTap: () => setState(() => _filter = f),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                        decoration: BoxDecoration(
                          gradient: active ? (f == Filter.live ? AppColors.liveGradient : AppColors.primaryGradient) : null,
                          color: active ? null : context.cBgCard,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: active ? Colors.transparent : context.cBorder,
                          ),
                        ),
                        child: Text(f.label,
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, fontFamily: 'Inter',
                            color: active ? Colors.white : context.cTextSecondary)),
                      ),
                    ),
                  );
                }).toList()),
              ),
            ]),
          ),

          // ── Content ──
          Expanded(
            child: data.when(
              data: (d) => _buildContent(d, dateKey),
              loading: () => const Center(child: CircularProgressIndicator(
                color: AppColors.accentPrimary, strokeWidth: 2.5)),
              error: (e, _) => Center(child: Text('Failed to load scores',
                style: TextStyle(color: context.cTextMuted, fontFamily: 'Inter'))),
            ),
          ),
        ]),
      ),
    );
  }

  String _formatHeaderDate(DateTime dt) {
    final months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    final days = ['Mon','Tue','Wed','Thu','Fri','Sat','Sun'];
    if (_fmtDate(dt) == _fmtDate(DateTime.now())) return 'Today';
    return '${days[dt.weekday - 1]}, ${months[dt.month - 1]} ${dt.day}';
  }

  Widget _buildContent(Map<String, dynamic> data, String dateKey) {
    final leagues = _l(data['leagues']);
    final allMatches = <Map<String, dynamic>>[];
    for (final lg in leagues) {
      final league = _m(lg);
      for (final m in _l(league['matches'])) {
        allMatches.add({..._m(m), '_league': league});
      }
    }

    List<Map<String, dynamic>> filtered;
    switch (_filter) {
      case Filter.live:
        filtered = allMatches.where((m) => _m(m['status'])['started'] == true && _m(m['status'])['finished'] == false).toList();
        break;
      case Filter.ft:
        filtered = allMatches.where((m) => _m(m['status'])['finished'] == true).toList();
        break;
      case Filter.upcoming:
        filtered = allMatches.where((m) => _m(m['status'])['started'] != true).toList();
        break;
      case Filter.all:
        filtered = allMatches;
        break;
    }

    if (filtered.isEmpty) {
      return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 64, height: 64,
          decoration: BoxDecoration(color: context.cBgElevated, borderRadius: BorderRadius.circular(20), border: Border.all(color: context.cBorder)),
          child: Icon(Icons.sports_soccer_rounded, color: context.cTextMuted, size: 30)),
        const SizedBox(height: 16),
        Text('No matches found', style: TextStyle(color: context.cTextPrimary, fontSize: 15, fontWeight: FontWeight.w600, fontFamily: 'Inter')),
        const SizedBox(height: 6),
        Text('Try a different date or filter', style: TextStyle(color: context.cTextMuted, fontSize: 12, fontFamily: 'Inter')),
      ]));
    }

    // Group by league
    final grouped = <String, List<Map<String, dynamic>>>{};
    final leagueMap = <String, Map<String, dynamic>>{};
    for (final m in filtered) {
      final lg = _m(m['_league']);
      final lk = _s(lg['id']);
      grouped.putIfAbsent(lk, () => []);
      grouped[lk]!.add(m);
      leagueMap[lk] = lg;
    }

    return ListView(
      padding: const EdgeInsets.only(bottom: 90),
      children: [
        for (final entry in grouped.entries)
          _LeagueBlock(league: leagueMap[entry.key]!, matches: entry.value),
      ],
    );
  }
}

class _LeagueBlock extends StatefulWidget {
  final Map<String, dynamic> league;
  final List<Map<String, dynamic>> matches;
  const _LeagueBlock({required this.league, required this.matches});

  @override
  State<_LeagueBlock> createState() => _LeagueBlockState();
}

class _LeagueBlockState extends State<_LeagueBlock> {
  bool _expanded = true;

  @override
  Widget build(BuildContext context) {
    final name = _s(widget.league['name']);
    final id = widget.league['primaryId'] ?? widget.league['parentLeagueId'] ?? widget.league['id'];
    final flagUrl = id != null
        ? FotmobClient.leagueLogoUrl(id)
        : null;

    return Column(children: [
      // League header — tap to expand/collapse, long press to open league screen
      GestureDetector(
        behavior: HitTestBehavior.opaque,
        onLongPress: () {
          if (id != null) {
            HapticFeedback.mediumImpact();
            Navigator.push(context, MaterialPageRoute(
              builder: (_) => LeagueScreen(leagueId: _s(id), leagueName: name, existingMatches: _l(widget.league['matches']))));
          }
        },
        onTap: () => setState(() => _expanded = !_expanded),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
          decoration: BoxDecoration(
            color: context.cBgCard,
            border: Border(
              bottom: BorderSide(color: context.cBorder.withValues(alpha: 0.6), width: 0.5),
            ),
          ),
          child: Row(children: [
            // Left accent
            Container(width: 2, height: 16,
              decoration: BoxDecoration(gradient: AppColors.primaryGradient, borderRadius: BorderRadius.circular(1))),
            const SizedBox(width: 10),
            // League logo — tap to open league screen
            GestureDetector(
              onTap: () {
                final lid = id;
                if (lid != null) Navigator.push(context, MaterialPageRoute(
                  builder: (_) => LeagueScreen(leagueId: _s(lid), leagueName: name, existingMatches: _l(widget.league['matches']))));
              },
              child: flagUrl != null
                ? CachedNetworkImage(imageUrl: flagUrl, width: 20, height: 20,
                    errorWidget: (_, __, ___) => Icon(Icons.sports_soccer_rounded, size: 16, color: context.cTextMuted))
                : Icon(Icons.sports_soccer_rounded, size: 16, color: context.cTextMuted),
            ),
            const SizedBox(width: 10),
            Expanded(child: GestureDetector(
              onTap: () {
                final lid = id;
                if (lid != null) Navigator.push(context, MaterialPageRoute(
                  builder: (_) => LeagueScreen(leagueId: _s(lid), leagueName: name, existingMatches: _l(widget.league['matches']))));
              },
              child: Text(name,
              style: TextStyle(color: context.cTextPrimary, fontSize: 13,
                  fontWeight: FontWeight.w700, fontFamily: 'Inter')),
            )),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: context.cBgElevated,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text('${widget.matches.length}',
                style: TextStyle(fontSize: 10, color: context.cTextSecondary,
                    fontWeight: FontWeight.w600, fontFamily: 'Inter')),
            ),
            const SizedBox(width: 6),
            AnimatedRotation(
              turns: _expanded ? 0 : -0.25,
              duration: const Duration(milliseconds: 200),
              child: Icon(Icons.keyboard_arrow_down, color: context.cTextMuted, size: 18),
            ),
          ]),
        ),
      ),
      AnimatedSize(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
        child: _expanded
            ? Column(children: widget.matches.map((m) => _MatchItem(match: m)).toList())
            : const SizedBox.shrink(),
      ),
    ]);
  }
}

class _MatchItem extends StatelessWidget {
  final Map<String, dynamic> match;
  const _MatchItem({required this.match});

  @override
  Widget build(BuildContext context) {
    final status   = _m(match['status']);
    final home     = _m(match['home']);
    final away     = _m(match['away']);
    final isLive   = status['started'] == true && status['finished'] == false;
    final finished = status['finished'] == true;
    final score    = _s(status['scoreStr']);
    // liveTime can be a map {short, long} or a string directly
    final liveTime = status['liveTime'];
    final minute = liveTime is Map
        ? _s((liveTime is Map<String,dynamic> ? liveTime : Map<String,dynamic>.from(liveTime))['short'])
        : _s(liveTime);
    final parts    = score.split('-');
    final hG       = parts.isNotEmpty ? int.tryParse(parts.first.trim()) ?? -1 : -1;
    final aG       = parts.length > 1 ? int.tryParse(parts.last.trim()) ?? -1 : -1;

    final mid = _s(match['id']);
    return GestureDetector(
      onTap: () {
        if (mid.isNotEmpty) Navigator.push(context, MaterialPageRoute(builder: (_) => MatchDetailScreen(matchId: mid)));
      },
      child: Hero(
        tag: 'match_$mid',
        child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: isLive ? AppColors.live.withValues(alpha: 0.03) : null,
          border: Border(bottom: BorderSide(color: context.cBorder.withValues(alpha: 0.5), width: 0.5)),
        ),
        child: Row(children: [
          // Status
          SizedBox(width: 46, child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            if (isLive)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.live.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: AppColors.live.withValues(alpha: 0.3)),
                ),
                child: Text(minute.isNotEmpty ? minute : 'LIVE',
                  style: const TextStyle(color: AppColors.live, fontSize: 9,
                      fontWeight: FontWeight.w800, fontFamily: 'Inter')),
              )
            else
              Text(finished ? 'FT' : _formatTime(status['utcTime']),
                style: TextStyle(fontSize: 11, fontFamily: 'Inter',
                  color: finished ? context.cTextMuted : context.cTextSecondary,
                  fontWeight: finished ? FontWeight.w400 : FontWeight.w600),
                textAlign: TextAlign.center),
          ])),
          const SizedBox(width: 8),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _MiniRow(team: home, score: parts.isNotEmpty ? parts.first.trim() : '',
                win: finished && hG > aG),
            const SizedBox(height: 5),
            _MiniRow(team: away, score: parts.length > 1 ? parts.last.trim() : '',
                win: finished && aG > hG),
          ])),
          Icon(Icons.chevron_right, color: context.cTextMuted, size: 14),
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

class _MiniRow extends StatelessWidget {
  final Map<String, dynamic> team;
  final String score;
  final bool win;
  const _MiniRow({required this.team, required this.score, required this.win});

  @override
  Widget build(BuildContext context) {
    final id = team['id'];
    return Row(children: [
      if (id != null)
        CachedNetworkImage(imageUrl: FotmobClient.teamLogoUrl(id), width: 18, height: 18,
          errorWidget: (_, __, ___) => const SizedBox(width: 18))
      else
        const SizedBox(width: 18),
      const SizedBox(width: 8),
      Expanded(child: Text(_s(team['name']),
        style: TextStyle(fontSize: 12, fontWeight: win ? FontWeight.w700 : FontWeight.w400,
          color: win ? context.cTextPrimary : context.cTextSecondary, fontFamily: 'Inter'),
        overflow: TextOverflow.ellipsis)),
      if (score.isNotEmpty)
        Text(score, style: TextStyle(fontFamily: 'Oswald', fontSize: 14,
          fontWeight: win ? FontWeight.w700 : FontWeight.w400,
          color: win ? context.cTextPrimary : context.cTextMuted)),
    ]);
  }
}
