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
                    color: AppColors.bgInput,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: _focused ? AppColors.accentPrimary : AppColors.border,
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
                        color: _focused ? AppColors.accentPrimary : AppColors.textMuted, size: 22),
                    ),
                    Expanded(
                      child: TextField(
                        controller: _ctrl,
                        focusNode: _focusNode,
                        onChanged: (v) => setState(() => _query = v),
                        style: const TextStyle(color: AppColors.textPrimary, fontSize: 15, fontFamily: 'Inter'),
                        decoration: InputDecoration(
                          hintText: 'Teams, players, leagues...',
                          hintStyle: const TextStyle(color: AppColors.textMuted, fontSize: 14, fontFamily: 'Inter'),
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                          suffixIcon: _query.isNotEmpty
                              ? GestureDetector(
                                  onTap: () { _ctrl.clear(); setState(() => _query = ''); },
                                  child: Container(
                                    margin: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(color: AppColors.bgElevated, shape: BoxShape.circle),
                                    child: const Icon(Icons.close, color: AppColors.textSecondary, size: 16),
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
                ? _SearchPlaceholder()
                : results.when(
                    data: (d) => _SearchResults(hits: d, query: _query),
                    loading: () => const Center(child: CircularProgressIndicator(
                      color: AppColors.accentPrimary, strokeWidth: 2.5)),
                    error: (e, _) => const Center(child: Text('Search failed',
                      style: TextStyle(color: AppColors.textMuted, fontFamily: 'Inter'))),
                  ),
          ),
        ]),
      ),
    );
  }
}

class _SearchPlaceholder extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 80, height: 80,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [AppColors.bgElevated, AppColors.bgCard],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: AppColors.border),
          ),
          child: ShaderMask(
            shaderCallback: (b) => AppColors.primaryGradient.createShader(b),
            child: const Icon(Icons.manage_search_rounded, size: 40, color: Colors.white),
          ),
        ),
        const SizedBox(height: 20),
        const Text('Find anything', style: TextStyle(
          color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.w700, fontFamily: 'Inter')),
        const SizedBox(height: 8),
        const Text('Search teams, players or leagues', style: TextStyle(
          color: AppColors.textMuted, fontSize: 13, fontFamily: 'Inter')),
        const SizedBox(height: 24),
        // Quick suggestions
        Wrap(spacing: 8, runSpacing: 8, children: [
          _SuggestionPill(label: '⚽ Premier League'),
          _SuggestionPill(label: '🏆 Champions League'),
          _SuggestionPill(label: '🦁 Arsenal'),
          _SuggestionPill(label: '🌟 Ronaldo'),
        ]),
      ]),
    );
  }
}

class _SuggestionPill extends StatelessWidget {
  final String label;
  const _SuggestionPill({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(
        color: AppColors.bgElevated,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
      ),
      child: Text(label, style: const TextStyle(
        color: AppColors.textSecondary, fontSize: 12, fontFamily: 'Inter', fontWeight: FontWeight.w500)),
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
        const Icon(Icons.search_off_rounded, size: 48, color: AppColors.textMuted),
        const SizedBox(height: 12),
        Text('No results for "$query"',
          style: const TextStyle(color: AppColors.textPrimary, fontSize: 15,
              fontWeight: FontWeight.w600, fontFamily: 'Inter')),
        const SizedBox(height: 6),
        const Text('Try a different search term', style: TextStyle(color: AppColors.textMuted, fontSize: 12, fontFamily: 'Inter')),
      ]));
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
      itemCount: hits.length,
      itemBuilder: (ctx, i) {
        final hit  = hits[i];
        final type = _s(hit['type']).toLowerCase();
        final id   = _s(hit['id']);
        final name = _s(hit['name']).isNotEmpty ? _s(hit['name']) : _s(hit['teamName']);

        return GestureDetector(
          onTap: () {
            if (type == 'match') {
              Navigator.push(context, MaterialPageRoute(builder: (_) => MatchDetailScreen(matchId: id)));
            } else if (type == 'team') {
              Navigator.push(context, MaterialPageRoute(builder: (_) => TeamScreen(teamId: id, teamName: name)));
            } else if (type == 'player') {
              Navigator.push(context, MaterialPageRoute(builder: (_) => PlayerScreen(playerId: id, playerName: name)));
            } else if (type == 'league' || type == 'tournament') {
              Navigator.push(context, MaterialPageRoute(builder: (_) => LeagueScreen(leagueId: id, leagueName: name)));
            }
          },
          child: Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.bgCard,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(children: [
              _ResultAvatar(type: type, id: id),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(name, style: const TextStyle(color: AppColors.textPrimary, fontSize: 14,
                    fontWeight: FontWeight.w600, fontFamily: 'Inter')),
                const SizedBox(height: 3),
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
              ])),
              const Icon(Icons.chevron_right, color: AppColors.textMuted, size: 18),
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
      default: return AppColors.textMuted;
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

    return Container(
      width: 46, height: 46,
      decoration: BoxDecoration(
        color: AppColors.bgElevated,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(13),
        child: url != null
            ? CachedNetworkImage(imageUrl: url, fit: BoxFit.cover,
                errorWidget: (_, __, ___) => Icon(_icon(type), color: AppColors.textMuted, size: 22))
            : Icon(_icon(type), color: AppColors.textMuted, size: 22),
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
