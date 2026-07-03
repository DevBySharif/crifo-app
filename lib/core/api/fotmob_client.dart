import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';

const _BASE = 'https://www.fotmob.com';
const _API = '$_BASE/api/data';

// Cloudflare Worker proxy (see proxy/worker.js). Routing FotMob traffic through
// it avoids mobile-carrier IP blocks that make the app look empty on mobile
// data. Leave empty for a direct connection. The x-mas token still signs the
// real fotmob.com URL, so only the request host changes.
const _PROXY = 'https://crifo-proxy.crifo-bd.workers.dev';

// Ordered list of hosts to try for a given fotmob API URL — proxy first (when
// configured), then a direct connection as a fallback.
List<String> _requestUrls(String fotmobUrl) {
  if (_PROXY.isEmpty) return [fotmobUrl];
  return [fotmobUrl.replaceFirst(_BASE, _PROXY), fotmobUrl];
}

// Reverse-engineered from FotMob's app bundle
const _FOTMOB_KEY =
    "[Spoken Intro: Alan Hansen & Trevor Brooking]\nI think it's bad news for the English game\nWe're not creative enough, and we're not positive enough\n\n[Refrain: Ian Broudie & Jimmy Hill]\nIt's coming home, it's coming home, it's coming\nFootball's coming home (We'll go on getting bad results)\nIt's coming home, it's coming home, it's coming\nFootball's coming home\nIt's coming home, it's coming home, it's coming\nFootball's coming home\nIt's coming home, it's coming home, it's coming\nFootball's coming home\n\n[Verse 1: Frank Skinner]\nEveryone seems to know the score, they've seen it all before\nThey just know, they're so sure\nThat England's gonna throw it away, gonna blow it away\nBut I know they can play, 'cause I remember\n\n[Chorus: All]\nThree lions on a shirt\nJules Rimet still gleaming\nThirty years of hurt\nNever stopped me dreaming\n\n[Verse 2: David Baddiel]\nSo many jokes, so many sneers\nBut all those \"Oh, so near\"s wear you down through the years\nBut I still see that tackle by Moore and when Lineker scored\nBobby belting the ball, and Nobby dancing\n\n[Chorus: All]\nThree lions on a shirt\nJules Rimet still gleaming\nThirty years of hurt\nNever stopped me dreaming\n\n[Bridge]\nEngland have done it, in the last minute of extra time!\nWhat a save, Gordon Banks!\nGood old England, England that couldn't play football!\nEngland have got it in the bag!\nI know that was then, but it could be again\n\n[Refrain: Ian Broudie]\nIt's coming home, it's coming\nFootball's coming home\nIt's coming home, it's coming home, it's coming\nFootball's coming home\n(England have done it!)\nIt's coming home, it's coming home, it's coming\nFootball's coming home\nIt's coming home, it's coming home, it's coming\nFootball's coming home\n[Chorus: All]\n(It's coming home) Three lions on a shirt\n(It's coming home, it's coming) Jules Rimet still gleaming\n(Football's coming home\nIt's coming home) Thirty years of hurt\n(It's coming home, it's coming) Never stopped me dreaming\n(Football's coming home\nIt's coming home) Three lions on a shirt\n(It's coming home, it's coming) Jules Rimet still gleaming\n(Football's coming home\nIt's coming home) Thirty years of hurt\n(It's coming home, it's coming) Never stopped me dreaming\n(Football's coming home\nIt's coming home) Three lions on a shirt\n(It's coming home, it's coming) Jules Rimet still gleaming\n(Football's coming home\nIt's coming home) Thirty years of hurt\n(It's coming home, it's coming) Never stopped me dreaming\n(Football's coming home)";

String _generateXMasToken(String fullUrl) {
  final body = {
    'url': fullUrl,
    'code': DateTime.now().millisecondsSinceEpoch,
    'foo': 'production:ab158bb5c6ae907ba504afdadac27a92a4dca7c2',
  };
  final toSign = jsonEncode(body) + _FOTMOB_KEY;
  final signature = sha256.convert(utf8.encode(toSign)).toString();
  return base64.encode(utf8.encode(jsonEncode({'body': body, 'signature': signature})));
}

// Decode common HTML entities in news titles/sources (e.g. &#8211; → –)
String _decodeEntities(String s) {
  if (!s.contains('&')) return s;
  return s
      .replaceAllMapped(RegExp(r'&#(\d+);'), (m) => String.fromCharCode(int.parse(m[1]!)))
      .replaceAllMapped(RegExp(r'&#x([0-9A-Fa-f]+);'), (m) => String.fromCharCode(int.parse(m[1]!, radix: 16)))
      .replaceAll('&amp;', '&')
      .replaceAll('&quot;', '"')
      .replaceAll('&apos;', "'")
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>');
}

// In-memory response cache — max 60 entries, 5-min TTL, LRU eviction
const _kMaxCache = 60;
final _cache = <String, ({Map<String, dynamic> data, DateTime expiry})>{};

void _pruneCache() {
  final now = DateTime.now();
  _cache.removeWhere((_, v) => now.isAfter(v.expiry));
  if (_cache.length > _kMaxCache) {
    final oldest = _cache.keys.take(_cache.length - _kMaxCache).toList();
    oldest.forEach(_cache.remove);
  }
}

final _dio = Dio(BaseOptions(
  connectTimeout: const Duration(seconds: 10),
  receiveTimeout: const Duration(seconds: 15),
  headers: {
    'User-Agent': 'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Mobile Safari/537.36',
    'Accept': 'application/json, text/plain, */*',
    'Accept-Language': 'en-US,en;q=0.9',
    'Referer': 'https://www.fotmob.com/',
    'Origin': 'https://www.fotmob.com',
  },
));

class FotmobClient {
  static Future<Map<String, dynamic>> _get(String endpoint, {Map<String, dynamic>? params, Duration ttl = const Duration(minutes: 5)}) async {
    final query = params != null ? '?' + params.entries.map((e) => '${e.key}=${Uri.encodeComponent(e.value.toString())}').join('&') : '';
    final cacheKey = '$endpoint$query';
    final now = DateTime.now();

    // Return cached response if still valid
    final cached = _cache[cacheKey];
    if (cached != null && now.isBefore(cached.expiry)) return cached.data;

    final fullUrl = '$_API/$endpoint$query';
    final token = _generateXMasToken(fullUrl);
    final urls = _requestUrls(fullUrl); // [proxy, direct] or [direct]

    Map<String, dynamic> data = <String, dynamic>{};

    // Retry up to 4 times — FotMob rate-limits league endpoints. Each attempt
    // alternates between proxy and direct so one bad path can't strand us.
    for (int attempt = 0; attempt < 4; attempt++) {
      if (attempt > 0) await Future.delayed(Duration(milliseconds: 800 * attempt));
      final url = urls[attempt % urls.length];

      try {
        final res = await _dio.get(url, options: Options(headers: {'x-mas': token}));
        if (res.data is Map<String, dynamic>) {
          data = res.data as Map<String, dynamic>;
        } else if (res.data is Map) {
          data = (res.data as Map).cast<String, dynamic>();
        } else if (res.data is List) {
          data = {'items': res.data as List};
        }
        // res.data == null means JSON null response → retry
        if (data.isNotEmpty) break;
      } catch (_) {
        // keep looping — next attempt tries the other host
      }
    }

    // Only cache non-empty successful responses
    if (data.isNotEmpty) {
      _cache[cacheKey] = (data: data, expiry: now.add(ttl));
      _pruneCache();
    }
    return data;
  }

  static void invalidateCache(String endpoint) {
    _cache.removeWhere((k, _) => k.startsWith(endpoint));
  }

  static Future<Map<String, dynamic>> getMatchesByDate(String date) =>
      _get('matches', params: {'date': date, 'timezone': 'Asia/Dhaka', 'ccode3': 'BGD'});

  static Future<Map<String, dynamic>> getMatchDetails(String matchId) =>
      _get('matchDetails', params: {'matchId': matchId}, ttl: const Duration(seconds: 30));

  static Future<Map<String, dynamic>> getMatchH2H(String matchId) =>
      _get('matchDetails', params: {'matchId': matchId, 'tab': 'h2h'}, ttl: const Duration(minutes: 60));

  static Future<List<Map<String, dynamic>>> getMatchCommentary(String matchId) async {
    // Try commentary tab first, fallback to main matchDetails
    Map<String, dynamic> data = {};
    try {
      data = await _get('matchDetails', params: {'matchId': matchId, 'tab': 'commentary'}, ttl: const Duration(seconds: 20));
    } catch (_) {
      data = await _get('matchDetails', params: {'matchId': matchId}, ttl: const Duration(seconds: 30));
    }
    return _extractCommentary(data);
  }

  static List<Map<String, dynamic>> _extractCommentary(Map<String, dynamic> data) {
    // FotMob commentary can be in multiple paths
    final tryPaths = [
      () => data['content']?['commentary'],
      () => data['commentary'],
      () => data['content']?['matchFacts']?['events']?['events'],
      () => data['content']?['events']?['events'],
    ];

    for (final path in tryPaths) {
      try {
        final val = path();
        if (val == null) continue;
        if (val is List && val.isNotEmpty) {
          return val
              .map((e) => e is Map ? (e is Map<String, dynamic> ? e : (e as Map).cast<String, dynamic>()) : <String, dynamic>{})
              .where((e) => e.isNotEmpty)
              .toList()
              .reversed
              .toList(); // newest first
        }
        if (val is Map) {
          final entries = val['entries'] ?? val['comments'] ?? val['items'] ?? val['commentary'] ?? [];
          if (entries is List && entries.isNotEmpty) {
            return (entries as List)
                .map((e) => e is Map ? (e is Map<String, dynamic> ? e : (e as Map).cast<String, dynamic>()) : <String, dynamic>{})
                .where((e) => e.isNotEmpty)
                .toList()
                .reversed
                .toList();
          }
        }
      } catch (_) {}
    }
    return [];
  }

  static Future<Map<String, dynamic>> getMatchOdds(String matchId) =>
      _get('matchDetails', params: {'matchId': matchId, 'tab': 'odds'}, ttl: const Duration(minutes: 30));

  static Future<Map<String, dynamic>> getTeamDetails(String teamId) =>
      _get('teams', params: {'id': teamId, 'tab': 'overview', 'type': 'team', 'timeZone': 'Asia/Dhaka'});

  static Future<Map<String, dynamic>> getTeamSquad(String teamId) =>
      _get('teams', params: {'id': teamId, 'tab': 'squad', 'type': 'team', 'timeZone': 'Asia/Dhaka'});

  static Future<Map<String, dynamic>> getTeamFixtures(String teamId) =>
      _get('teams', params: {'id': teamId, 'tab': 'fixtures', 'type': 'team', 'timeZone': 'Asia/Dhaka'}, ttl: const Duration(minutes: 30));

  static Future<Map<String, dynamic>> getTeamStats(String teamId) =>
      _get('teams', params: {'id': teamId, 'tab': 'stats', 'type': 'team', 'timeZone': 'Asia/Dhaka'});

  static Future<Map<String, dynamic>> getPlayerData(String playerId) =>
      _get('playerData', params: {'id': playerId});

  static Future<List<Map<String, dynamic>>> search(String term) async {
    final query = '?' + {'term': term}.entries.map((e) => '${e.key}=${Uri.encodeComponent(e.value.toString())}').join('&');
    final fullUrl = '$_API/search/suggest$query';
    final token = _generateXMasToken(fullUrl);
    dynamic resData;
    for (final url in _requestUrls(fullUrl)) {
      try {
        final res = await _dio.get(url, options: Options(headers: {'x-mas': token}));
        if (res.data is List && (res.data as List).isNotEmpty) { resData = res.data; break; }
        resData ??= res.data;
      } catch (_) {}
    }
    final items = resData is List ? resData : [];
    final results = <Map<String, dynamic>>[];
    for (final group in items) {
      if (group is Map) {
        final suggestions = (group['suggestions'] as List?) ?? [];
        for (final s in suggestions) {
          if (s is Map) results.add(s.cast<String, dynamic>());
        }
      }
    }
    return results;
  }

  static Future<Map<String, dynamic>> getLeagueDetails(String id, {String? season}) async {
    // Generate token fresh and make direct request — bypass _get retry/cache logic
    final params = {'id': id, 'tab': 'overview', 'type': 'league', 'timeZone': 'Asia/Dhaka'};
    if (season != null) params['season'] = season;
    final query = '?' + params.entries.map((e) => '${e.key}=${Uri.encodeComponent(e.value)}').join('&');
    final url = '$_API/leagues$query';
    final token = _generateXMasToken(url);

    final freshDio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 12),
      receiveTimeout: const Duration(seconds: 15),
      headers: {
        'x-mas': token,
        'User-Agent': 'Mozilla/5.0 (Linux; Android 14; Pixel 7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36',
        'Accept': 'application/json, text/plain, */*',
        'Accept-Language': 'en-US,en;q=0.9',
        'Referer': 'https://www.fotmob.com/leagues/$id',
        'Origin': 'https://www.fotmob.com',
      },
    ));

    final hosts = _requestUrls(url); // [proxy, direct] or [direct]
    for (int i = 0; i < 4; i++) {
      if (i > 0) await Future.delayed(Duration(seconds: i));
      try {
        final token2 = _generateXMasToken(url); // fresh token each attempt
        final res = await freshDio.get(hosts[i % hosts.length], options: Options(headers: {'x-mas': token2}));
        if (res.data is Map<String, dynamic> && (res.data as Map).isNotEmpty) {
          return res.data as Map<String, dynamic>;
        }
        if (res.data is Map && (res.data as Map).isNotEmpty) {
          return (res.data as Map).cast<String, dynamic>();
        }
      } catch (_) {}
    }
    return {};
  }

  static Future<Map<String, dynamic>> getLeagueStats(String id, {String? season}) {
    final p = {'id': id, 'tab': 'stats', 'type': 'league', 'timeZone': 'Asia/Dhaka'};
    if (season != null) p['season'] = season;
    return _get('leagues', params: p);
  }

  static Future<Map<String, dynamic>> getLeagueTable(String id, {String? season}) {
    final p = {'id': id, 'tab': 'table', 'type': 'league', 'timeZone': 'Asia/Dhaka'};
    if (season != null) p['season'] = season;
    return _get('leagues', params: p);
  }

  static Future<Map<String, dynamic>> getLeagueFixtures(String id, {String? season}) {
    final p = {'id': id, 'tab': 'fixtures', 'type': 'league', 'timeZone': 'Asia/Dhaka'};
    if (season != null) p['season'] = season;
    return _get('leagues', params: p, ttl: const Duration(minutes: 30));
  }

  static Future<List<Map<String, dynamic>>> getLeagueNews(String id) async {
    final data = await _get('tlnews', params: {'id': id, 'type': 'league', 'language': 'en-GB', 'startIndex': '0'}, ttl: const Duration(minutes: 30));
    final items = (data['data'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    return items.map((n) => {
      'title': _decodeEntities(n['title']?.toString() ?? ''),
      'imageUrl': n['imageUrl']?.toString() ?? '',
      'url': (n['page'] as Map?)?.containsKey('url') == true ? n['page']['url'].toString() : '',
      'source': _decodeEntities(n['sourceStr']?.toString() ?? ''),
    }).toList();
  }

  static Future<Map<String, dynamic>> getAllCountries() =>
      _get('allLeagues', params: {}, ttl: const Duration(hours: 6));

  static Future<Map<String, dynamic>> getLeagueTopList(String id, {String? season}) {
    final p = {'id': id, 'tab': 'toplist', 'type': 'league', 'timeZone': 'Asia/Dhaka'};
    if (season != null) p['season'] = season;
    return _get('leagues', params: p);
  }

  static Future<Map<String, dynamic>> getAllLeagues() =>
      _get('leagues');

  static Future<List<Map<String, dynamic>>> getWorldNews() async {
    final res = await _get('tlnews', params: {'id': '47', 'type': 'league', 'language': 'en-GB', 'startIndex': '0'});
    final items = (res['data'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    return items.map((n) => {
      'title': _decodeEntities(n['title']?.toString() ?? ''),
      'imageUrl': n['imageUrl']?.toString() ?? '',
      'url': (n['page'] as Map?)?.containsKey('url') == true ? n['page']['url'].toString() : '',
      'source': _decodeEntities(n['sourceStr']?.toString() ?? ''),
    }).toList();
  }

  static Future<List<Map<String, dynamic>>> getTransfers() async {
    final res = await _get('transfers');
    final items = (res['transfers'] as List?)?.cast<Map<String, dynamic>>() ?? (res as List?)?.cast<Map<String, dynamic>>() ?? [];
    return items.map((t) => {
      'playerName': t['name']?.toString() ?? t['playerName']?.toString() ?? '',
      'from': t['fromClub']?.toString() ?? t['from']?.toString() ?? '',
      'to': t['toClub']?.toString() ?? t['to']?.toString() ?? '',
      'fee': (t['fee'] is Map) ? (t['fee']['feeText']?.toString() ?? '-') : (t['fee']?.toString() ?? '-'),
    }).toList();
  }

  static Future<Map<String, dynamic>> getTeamStatsLegacy(String teamId) =>
      _get('teamStats', params: {'teamId': teamId});

  static String teamLogoUrl(dynamic id) =>
      'https://images.fotmob.com/image_resources/logo/teamlogo/${id}_small.png';

  static String playerImageUrl(dynamic id) =>
      'https://images.fotmob.com/image_resources/playerimages/$id.png';
}
