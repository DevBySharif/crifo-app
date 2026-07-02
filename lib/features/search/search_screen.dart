import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../core/api/fotmob_client.dart';
import '../../core/theme/colors.dart';
import '../match_detail/match_detail_screen.dart';
import '../team/team_screen.dart';
import '../player/player_screen.dart';
import '../league/league_screen.dart';

String _s(dynamic v) => v?.toString() ?? '';

final _searchProvider = FutureProvider.family<List<Map<String, dynamic>>, String>((ref, term) async {
  if (term.isEmpty) return [];
  return FotmobClient.search(term);
});

// All countries + their leagues (FotMob allLeagues endpoint)
final _countriesProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final data = await FotmobClient.getAllCountries();
  final out = <Map<String, dynamic>>[];
  // International competitions first
  for (final section in [data['international'], data['countries']]) {
    if (section is! List) continue;
    for (final c in section) {
      if (c is! Map) continue;
      final cm = c.cast<String, dynamic>();
      final leagues = (cm['leagues'] as List?)
              ?.whereType<Map>()
              .map((l) => l.cast<String, dynamic>())
              .toList() ?? [];
      if (leagues.isEmpty) continue;
      out.add({'name': _s(cm['name'] ?? cm['ccode']), 'ccode': _s(cm['ccode']), 'leagues': leagues});
    }
  }
  return out;
});

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  String _query = '';
  final _ctrl = TextEditingController();
  final _focusNode = FocusNode();
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(() => setState(() => _focused = _focusNode.hasFocus));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final results = _query.length >= 2 ? ref.watch(_searchProvider(_query)) : null;

    return Scaffold(
      backgroundColor: context.cBg,
      body: SafeArea(
        child: Column(children: [
          // ── Header ──
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  AppColors.accentPrimary.withValues(alpha: 0.06),
                  Colors.transparent,
                ],
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                ShaderMask(
                  shaderCallback: (b) => AppColors.primaryGradient.createShader(b),
                  child: const Text('SEARCH',
                    style: TextStyle(fontFamily: 'Oswald', fontSize: 24,
                        fontWeight: FontWeight.w700, color: Colors.white, letterSpacing: 1.5)),
                ),
                const SizedBox(height: 14),
                // Premium search bar
                AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  decoration: BoxDecoration(
                    color: context.cBgInput,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: _focused ? AppColors.accentPrimary : context.cBorder,
                      width: _focused ? 1.5 : 1,
                    ),
                    boxShadow: _focused ? [
                      BoxShadow(color: AppColors.accentPrimary.withValues(alpha: 0.15), blurRadius: 12),
                    ] : null,
                  ),
                  child: Row(children: [
                    Padding(
                      padding: const EdgeInsets.only(left: 14),
                      child: Icon(Icons.search_rounded,
                        color: _focused ? AppColors.accentPrimary : context.cTextMuted, size: 22),
                    ),
                    Expanded(
                      child: TextField(
                        controller: _ctrl,
                        focusNode: _focusNode,
                        onChanged: (v) => setState(() => _query = v),
                        style: TextStyle(color: context.cTextPrimary, fontSize: 15, fontFamily: 'Inter'),
                        decoration: InputDecoration(
                          hintText: 'Teams, players, leagues...',
                          hintStyle: TextStyle(color: context.cTextMuted, fontSize: 14, fontFamily: 'Inter'),
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                          suffixIcon: _query.isNotEmpty
                              ? GestureDetector(
                                  onTap: () { _ctrl.clear(); setState(() => _query = ''); },
                                  child: Container(
                                    margin: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(color: context.cBgElevated, shape: BoxShape.circle),
                                    child: Icon(Icons.close, color: context.cTextSecondary, size: 16),
                                  ),
                                )
                              : null,
                        ),
                      ),
                    ),
                  ]),
                ),
              ]),
            ),
          ),

          // ── Results ──
          Expanded(
            child: results == null
                ? _SearchPlaceholder(onSuggestion: (t) {
                    _ctrl.text = t;
                    setState(() => _query = t);
                  })
                : results.when(
                    data: (d) => _SearchResults(hits: d, query: _query),
                    loading: () => const Center(child: CircularProgressIndicator(
                      color: AppColors.accentPrimary, strokeWidth: 2.5)),
                    error: (e, _) => Center(child: Text('Search failed',
                      style: TextStyle(color: context.cTextMuted, fontFamily: 'Inter'))),
                  ),
          ),
        ]),
      ),
    );
  }
}

class _SearchPlaceholder extends ConsumerWidget {
  final void Function(String) onSuggestion;
  const _SearchPlaceholder({required this.onSuggestion});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final countries = ref.watch(_countriesProvider);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 90),
      children: [
        const SizedBox(height: 8),
        Text('QUICK SEARCH', style: TextStyle(
          color: context.cTextMuted, fontSize: 11, fontWeight: FontWeight.w700,
          fontFamily: 'Inter', letterSpacing: 1.5)),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 8, children: [
          _SuggestionPill(label: '⚽ Premier League', term: 'Premier League', onTap: onSuggestion),
          _SuggestionPill(label: '🏆 Champions League', term: 'Champions League', onTap: onSuggestion),
          _SuggestionPill(label: '🦁 Arsenal', term: 'Arsenal', onTap: onSuggestion),
          _SuggestionPill(label: '🌟 Ronaldo', term: 'Ronaldo', onTap: onSuggestion),
          _SuggestionPill(label: '🐐 Messi', term: 'Messi', onTap: onSuggestion),
          _SuggestionPill(label: '🇧🇩 Bangladesh', term: 'Bangladesh', onTap: onSuggestion),
        ]),
        const SizedBox(height: 24),
        Text('BROWSE LEAGUES', style: TextStyle(
          color: context.cTextMuted, fontSize: 11, fontWeight: FontWeight.w700,
          fontFamily: 'Inter', letterSpacing: 1.5)),
        const SizedBox(height: 10),
        countries.when(
          data: (list) => Column(children: [
            for (final c in list) _CountryTile(country: c),
          ]),
          loading: () => const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator(color: AppColors.accentPrimary, strokeWidth: 2.5)),
          ),
          error: (e, _) => Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: Text('Could not load leagues',
              style: TextStyle(color: context.cTextMuted, fontFamily: 'Inter', fontSize: 12))),
          ),
        ),
      ],
    );
  }
}

class _CountryTile extends StatelessWidget {
  final Map<String, dynamic> country;
  const _CountryTile({required this.country});

  @override
  Widget build(BuildContext context) {
    final name = _s(country['name']);
    final ccode = _s(country['ccode']);
    final leagues = (country['leagues'] as List).cast<Map<String, dynamic>>();
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: context.cBgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.cBorder),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 12),
          childrenPadding: const EdgeInsets.only(bottom: 6),
          iconColor: context.cTextMuted,
          collapsedIconColor: context.cTextMuted,
          leading: ccode.isNotEmpty
              ? ClipOval(child: CachedNetworkImage(
                  imageUrl: 'https://images.fotmob.com/image_resources/logo/teamlogo/${ccode.toLowerCase()}.png',
                  width: 24, height: 24, fit: BoxFit.cover,
                  errorWidget: (_, __, ___) => Icon(Icons.flag_rounded, size: 18, color: context.cTextMuted)))
              : Icon(Icons.public_rounded, size: 18, color: context.cTextMuted),
          title: Text(name, style: TextStyle(
            color: context.cTextPrimary, fontSize: 13, fontWeight: FontWeight.w600, fontFamily: 'Inter')),
          children: [
            for (final l in leagues)
              ListTile(
                dense: true,
                contentPadding: const EdgeInsets.only(left: 48, right: 16),
                leading: CachedNetworkImage(
                  imageUrl: 'https://images.fotmob.com/image_resources/logo/leaguelogo/${_s(l['id'])}_small.png',
                  width: 18, height: 18,
                  errorWidget: (_, __, ___) => Icon(Icons.sports_soccer, size: 14, color: context.cTextMuted)),
                title: Text(_s(l['name']), style: TextStyle(
                  color: context.cTextSecondary, fontSize: 12.5, fontFamily: 'Inter')),
                onTap: () => Navigator.push(context, MaterialPageRoute(
                  builder: (_) => LeagueScreen(leagueId: _s(l['id']), leagueName: _s(l['name'])))),
              ),
          ],
        ),
      ),
    );
  }
}

class _SuggestionPill extends StatelessWidget {
  final String label;
  final String term;
  final void Function(String) onTap;
  const _SuggestionPill({required this.label, required this.term, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onTap(term),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: context.cBgElevated,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: context.cBorder),
        ),
        child: Text(label, style: TextStyle(
          color: context.cTextSecondary, fontSize: 12, fontFamily: 'Inter', fontWeight: FontWeight.w500)),
      ),
    );
  }
}

class _SearchResults extends StatelessWidget {
  final List<Map<String, dynamic>> hits;
  final String query;
  const _SearchResults({required this.hits, required this.query});

  @override
  Widget build(BuildContext context) {
    if (hits.isEmpty) {
      return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.search_off_rounded, size: 48, color: context.cTextMuted),
        const SizedBox(height: 12),
        Text('No results for "$query"',
          style: TextStyle(color: context.cTextPrimary, fontSize: 15,
              fontWeight: FontWeight.w600, fontFamily: 'Inter')),
        const SizedBox(height: 6),
        Text('Try a different search term', style: TextStyle(color: context.cTextMuted, fontSize: 12, fontFamily: 'Inter')),
      ]));
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
      itemCount: hits.length,
      itemBuilder: (ctx, i) {
        final hit  = hits[i];
        final type = _s(hit['type']).toLowerCase();
        final id   = _s(hit['id']);
        String name = _s(hit['name']).isNotEmpty ? _s(hit['name']) : _s(hit['teamName']);
        if (name.isEmpty && type == 'match') {
          final ht = hit['homeTeam'], at = hit['awayTeam'];
          final h = _s(hit['homeName'] ?? hit['homeTeamName'] ?? (ht is Map ? ht['name'] : ''));
          final a = _s(hit['awayName'] ?? hit['awayTeamName'] ?? (at is Map ? at['name'] : ''));
          if (h.isNotEmpty || a.isNotEmpty) name = '$h vs $a';
        }
        // Subtitle: team for player, country for team/league, score for match
        final subtitle = type == 'player'
            ? _s(hit['teamName'] ?? hit['team'] ?? '')
            : type == 'team'
                ? _s(hit['leagueName'] ?? hit['country'] ?? hit['league'] ?? '')
                : type == 'match'
                    ? '${_s(hit['teamName'] ?? '')} ${_s(hit['scoreStr'] ?? '')}'.trim()
                    : _s(hit['country'] ?? hit['parentLeague'] ?? '');

        return GestureDetector(
          onTap: () {
            if (type == 'match') {
              Navigator.push(context, MaterialPageRoute(builder: (_) => MatchDetailScreen(matchId: id)));
            } else if (type == 'team') {
              Navigator.push(context, MaterialPageRoute(builder: (_) => TeamScreen(teamId: id, teamName: name)));
            } else if (type == 'player') {
              Navigator.push(context, MaterialPageRoute(builder: (_) => PlayerScreen(playerId: id, playerName: name)));
            } else if (type == 'league' || type == 'tournament' ||
                       type == 'cup' || type == 'competition' || type == 'international') {
              Navigator.push(context, MaterialPageRoute(builder: (_) => LeagueScreen(leagueId: id, leagueName: name)));
            }
          },
          child: Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: context.cBgCard,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: context.cBorder),
            ),
            child: Row(children: [
              _ResultAvatar(type: type, id: id),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(name, style: TextStyle(color: context.cTextPrimary, fontSize: 14,
                    fontWeight: FontWeight.w600, fontFamily: 'Inter')),
                const SizedBox(height: 3),
                Row(children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: _typeColor(type).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(type.toUpperCase(), style: TextStyle(
                      fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 0.8,
                      color: _typeColor(type), fontFamily: 'Inter')),
                  ),
                  if (subtitle.isNotEmpty) ...[
                    const SizedBox(width: 6),
                    Expanded(child: Text(subtitle, style: TextStyle(
                      color: context.cTextSecondary, fontSize: 11, fontFamily: 'Inter'),
                      maxLines: 1, overflow: TextOverflow.ellipsis)),
                  ],
                ]),
              ])),
              Icon(Icons.chevron_right, color: context.cTextMuted, size: 18),
            ]),
          ),
        );
      },
    );
  }

  Color _typeColor(String t) {
    switch (t) {
      case 'team': return AppColors.accentBlue;
      case 'player': return AppColors.accentGreen;
      case 'match': return AppColors.accentOrange;
      case 'league':
      case 'tournament': return AppColors.accentPurple;
      default: return AppColors.textSecondary;
    }
  }
}

class _ResultAvatar extends StatelessWidget {
  final String type, id;
  const _ResultAvatar({required this.type, required this.id});

  @override
  Widget build(BuildContext context) {
    String? url;
    if (type == 'team') url = FotmobClient.teamLogoUrl(id);
    else if (type == 'player') url = FotmobClient.playerImageUrl(id);
    else if (type == 'league' || type == 'tournament') url = 'https://images.fotmob.com/image_resources/logo/leaguelogo/${id}_small.png';

    return Container(
      width: 46, height: 46,
      decoration: BoxDecoration(
        color: context.cBgElevated,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.cBorder),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(13),
        child: url != null
            ? CachedNetworkImage(imageUrl: url, fit: BoxFit.cover,
                errorWidget: (_, __, ___) => Icon(_icon(type), color: context.cTextMuted, size: 22))
            : Icon(_icon(type), color: context.cTextMuted, size: 22),
      ),
    );
  }

  IconData _icon(String t) {
    switch (t) {
      case 'team': return Icons.shield_rounded;
      case 'player': return Icons.person_rounded;
      case 'match': return Icons.sports_soccer_rounded;
      default: return Icons.emoji_events_rounded;
    }
  }
}
