import 'package:dio/dio.dart';
import '../models/espn_match.dart';

const _BASE = 'https://site.api.espn.com/apis/site/v2/sports/soccer';

final _dio = Dio(BaseOptions(
  connectTimeout: const Duration(seconds: 10),
  receiveTimeout: const Duration(seconds: 15),
));

class EspnClient {
  static Future<List<ESPNMatch>> getScoreboard({String? date}) async {
    final dateParam = date != null ? '?dates=${date.replaceAll('-', '')}' : '';
    final futures = ESPNLeagueInfo.all.map((lg) async {
      try {
        final res = await _dio.get('$_BASE/${lg.slug}/scoreboard$dateParam');
        final events = (res.data['events'] as List?) ?? [];
        return events.map((ev) {
          try {
            return ESPNMatch.fromJson(ev as Map<String, dynamic>,
                leagueSlug: lg.slug, leagueName: lg.name, leagueLogo: lg.logo);
          } catch (_) {
            return null;
          }
        }).whereType<ESPNMatch>().toList();
      } catch (_) {
        return <ESPNMatch>[];
      }
    });
    final results = await Future.wait(futures);
    return results.expand((x) => x).toList();
  }

  static Future<Map<String, dynamic>> getMatchSummary(String leagueSlug, String eventId) async {
    final res = await _dio.get('$_BASE/$leagueSlug/summary?event=$eventId');
    return res.data as Map<String, dynamic>;
  }

  static Future<List<Map<String, dynamic>>> getNews({List<String> slugs = const ['eng.1', 'esp.1', 'uefa.champions', 'fifa.world', 'ita.1', 'ger.1']}) async {
    final futures = slugs.map((slug) async {
      try {
        final res = await _dio.get('$_BASE/$slug/news');
        return (res.data['articles'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      } catch (_) {
        return <Map<String, dynamic>>[];
      }
    });
    final results = await Future.wait(futures);
    final seen = <String>{};
    final articles = <Map<String, dynamic>>[];
    for (final list in results) {
      for (final art in list) {
        final title = art['headline']?.toString() ?? art['title']?.toString() ?? '';
        if (title.isEmpty || seen.contains(title)) continue;
        seen.add(title);
        final images = art['images'] as List?;
        final imageUrl = images != null && images.isNotEmpty
            ? (images[0]['url']?.toString() ?? images[0]['href']?.toString() ?? '')
            : '';
        final links = art['links'] as Map?;
        final url = links != null
            ? (links['web']?['href']?.toString() ?? links['api']?['self']?.toString() ?? '')
            : '';
        articles.add({
          'title': title,
          'imageUrl': imageUrl,
          'url': url,
          'source': art['source']?.toString() ?? art['provider']?['name']?.toString() ?? 'ESPN',
        });
      }
    }
    return articles;
  }

  static Future<Map<String, dynamic>> getTeamDetails(String leagueSlug, String teamId) async {
    final res = await _dio.get('$_BASE/$leagueSlug/teams/$teamId');
    return res.data as Map<String, dynamic>;
  }

  // FotMob primaryId → ESPN league slug mapping
  static String? fotmobToEspnSlug(String fotmobId) {
    const map = {
      '47': 'eng.1',    // Premier League
      '87': 'esp.1',    // La Liga
      '54': 'ger.1',    // Bundesliga
      '55': 'ita.1',    // Serie A
      '53': 'fra.1',    // Ligue 1
      '42': 'uefa.champions', // Champions League
      '73': 'eng.2',    // Championship
      '108': 'por.1',   // Primeira Liga
      '67': 'ned.1',    // Eredivisie
      '130': 'tur.1',   // Süper Lig
      '168': 'esp.2',   // La Liga 2
      '77': 'fifa.world', // World Cup
      '489': 'fifa.friendly', // Friendlies
      '263': 'blr.1',   // Belarus PL
      '169': 'swe.2',   // Sweden Ettan
    };
    return map[fotmobId];
  }

  static Future<List<Map<String, dynamic>>> getStandings(String leagueSlug) async {
    try {
      final res = await _dio.get('$_BASE/$leagueSlug/standings');
      final data = res.data as Map<String, dynamic>;

      // ESPN standings structure: {standings: {entries: [{team, stats, note}]}}
      final children = data['children'] as List?;
      if (children != null && children.isNotEmpty) {
        // Conference/group format
        final allRows = <Map<String, dynamic>>[];
        for (final child in children) {
          final entries = (child as Map)['standings']?['entries'] as List? ?? [];
          for (final e in entries) {
            allRows.add(_parseStandingEntry(e as Map<String, dynamic>));
          }
        }
        return allRows;
      }

      final entries = data['standings']?['entries'] as List? ?? [];
      return entries.map((e) => _parseStandingEntry(e as Map<String, dynamic>)).toList();
    } catch (_) {
      return [];
    }
  }

  static Map<String, dynamic> _parseStandingEntry(Map<String, dynamic> e) {
    final team = e['team'] as Map? ?? {};
    final stats = e['stats'] as List? ?? [];
    Map<String, dynamic> statMap = {};
    for (final s in stats) {
      statMap[s['name']?.toString() ?? ''] = s['value'];
    }
    return {
      'id': team['id']?.toString() ?? '',
      'name': team['displayName']?.toString() ?? team['name']?.toString() ?? '',
      'logo': team['logos'] != null && (team['logos'] as List).isNotEmpty
          ? (team['logos'] as List)[0]['href']?.toString() ?? ''
          : '',
      'played': (statMap['gamesPlayed'] ?? 0).toInt(),
      'wins': (statMap['wins'] ?? 0).toInt(),
      'draws': (statMap['ties'] ?? 0).toInt(),
      'losses': (statMap['losses'] ?? 0).toInt(),
      'goalsFor': (statMap['pointsFor'] ?? statMap['goalsFor'] ?? 0).toInt(),
      'goalsAgainst': (statMap['pointsAgainst'] ?? statMap['goalsAgainst'] ?? 0).toInt(),
      'gd': (statMap['pointDifferential'] ?? 0).toInt(),
      'pts': (statMap['points'] ?? 0).toInt(),
      'rank': e['stats']?.isEmpty == false ? (e['stats'] as List).firstWhere((s) => s['name'] == 'rank', orElse: () => {'value': 0})['value']?.toInt() ?? 0 : 0,
    };
  }
}
