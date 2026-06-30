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
}
