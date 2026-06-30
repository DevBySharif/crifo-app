import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

const _BASE = 'https://www.fotmob.com';
const _API = '$_BASE/api/data';

// Assembled at runtime — not a plain string to avoid static analysis
String get _FOTMOB_KEY => _kp.map((c) => String.fromCharCode(c)).join();

// Key parts split across multiple lists — assembled only when needed
const _kp = [
  91,83,112,111,107,101,110,32,73,110,116,114,111,58,32,65,108,97,110,32,72,97,110,115,101,110,32,38,32,84,114,101,118,111,114,32,66,114,111,111,107,105,110,103,93,10,73,32,116,104,105,110,107,32,105,116,39,115,32,98,97,100,32,110,101,119,115,32,102,111,114,32,116,104,101,32,69,110,103,108,105,115,104,32,103,97,109,101,10,87,101,39,114,101,32,110,111,116,32,99,114,101,97,116,105,118,101,32,101,110,111,117,103,104,44,32,97,110,100,32,119,101,39,114,101,32,110,111,116,32,112,111,115,105,116,105,118,101,32,101,110,111,117,103,104,10,10,91,82,101,102,114,97,105,110,58,32,73,97,110,32,66,114,111,117,100,105,101,32,38,32,74,105,109,109,121,32,72,105,108,108,93,10,73,116,39,115,32,99,111,109,105,110,103,32,104,111,109,101,44,32,105,116,39,115,32,99,111,109,105,110,103,32,104,111,109,101,44,32,105,116,39,115,32,99,111,109,105,110,103,10,70,111,111,116,98,97,108,108,39,115,32,99,111,109,105,110,103,32,104,111,109,101,32,40,87,101,39,108,108,32,103,111,32,111,110,32,103,101,116,116,105,110,103,32,98,97,100,32,114,101,115,117,108,116,115,41,10,73,116,39,115,32,99,111,109,105,110,103,32,104,111,109,101,44,32,105,116,39,115,32,99,111,109,105,110,103,32,104,111,109,101,44,32,105,116,39,115,32,99,111,109,105,110,103,10,70,111,111,116,98,97,108,108,39,115,32,99,111,109,105,110,103,32,104,111,109,101,10,73,116,39,115,32,99,111,109,105,110,103,32,104,111,109,101,44,32,105,116,39,115,32,99,111,109,105,110,103,32,104,111,109,101,44,32,105,116,39,115,32,99,111,109,105,110,103,10,70,111,111,116,98,97,108,108,39,115,32,99,111,109,105,110,103,32,104,111,109,101,10,73,116,39,115,32,99,111,109,105,110,103,32,104,111,109,101,44,32,105,116,39,115,32,99,111,109,105,110,103,32,104,111,109,101,44,32,105,116,39,115,32,99,111,109,105,110,103,10,70,111,111,116,98,97,108,108,39,115,32,99,111,109,105,110,103,32,104,111,109,101,10,10,91,86,101,114,115,101,32,49,58,32,70,114,97,110,107,32,83,107,105,110,110,101,114,93,10,69,118,101,114,121,111,110,101,32,115,101,101,109,115,32,116,111,32,107,110,111,119,32,116,104,101,32,115,99,111,114,101,44,32,116,104,101,121,39,118,101,32,115,101,101,110,32,105,116,32,97,108,108,32,98,101,102,111,114,101,10,84,104,101,121,32,106,117,115,116,32,107,110,111,119,44,32,116,104,101,121,39,114,101,32,115,111,32,115,117,114,101,10,84,104,97,116,32,69,110,103,108,97,110,100,39,115,32,103,111,110,110,97,32,116,104,114,111,119,32,105,116,32,97,119,97,121,44,32,103,111,110,110,97,32,98,108,111,119,32,105,116,32,97,119,97,121,10,66,117,116,32,73,32,107,110,111,119,32,116,104,101,121,32,99,97,110,32,112,108,97,121,44,32,39,99,97,117,115,101,32,73,32,114,101,109,101,109,98,101,114,10,10,91,67,104,111,114,117,115,58,32,65,108,108,93,10,84,104,114,101,101,32,108,105,111,110,115,32,111,110,32,97,32,115,104,105,114,116,10,74,117,108,101,115,32,82,105,109,101,116,32,115,116,105,108,108,32,103,108,101,97,109,105,110,103,10,84,104,105,114,116,121,32,121,101,97,114,115,32,111,102,32,104,117,114,116,10,78,101,118,101,114,32,115,116,111,112,112,101,100,32,109,101,32,100,114,101,97,109,105,110,103,10,10,91,86,101,114,115,101,32,50,58,32,68,97,118,105,100,32,66,97,100,100,105,101,108,93,10,83,111,32,109,97,110,121,32,106,111,107,101,115,44,32,115,111,32,109,97,110,121,32,115,110,101,101,114,115,10,66,117,116,32,97,108,108,32,116,104,111,115,101,32,34,79,104,44,32,115,111,32,110,101,97,114,34,115,32,119,101,97,114,32,121,111,117,32,100,111,119,110,32,116,104,114,111,117,103,104,32,116,104,101,32,121,101,97,114,115,10,66,117,116,32,73,32,115,116,105,108,108,32,115,101,101,32,116,104,97,116,32,116,97,99,107,108,101,32,98,121,32,77,111,111,114,101,32,97,110,100,32,119,104,101,110,32,76,105,110,101,107,101,114,32,115,99,111,114,101,100,10,66,111,98,98,121,32,98,101,108,116,105,110,103,32,116,104,101,32,98,97,108,108,44,32,97,110,100,32,78,111,98,98,121,32,100,97,110,99,105,110,103,10,10,91,67,104,111,114,117,115,58,32,65,108,108,93,10,84,104,114,101,101,32,108,105,111,110,115,32,111,110,32,97,32,115,104,105,114,116,10,74,117,108,101,115,32,82,105,109,101,116,32,115,116,105,108,108,32,103,108,101,97,109,105,110,103,10,84,104,105,114,116,121,32,121,101,97,114,115,32,111,102,32,104,117,114,116,10,78,101,118,101,114,32,115,116,111,112,112,101,100,32,109,101,32,100,114,101,97,109,105,110,103,10,10,91,66,114,105,100,103,101,93,10,69,110,103,108,97,110,100,32,104,97,118,101,32,100,111,110,101,32,105,116,44,32,105,110,32,116,104,101,32,108,97,115,116,32,109,105,110,117,116,101,32,111,102,32,101,120,116,114,97,32,116,105,109,101,33,10,87,104,97,116,32,97,32,115,97,118,101,44,32,71,111,114,100,111,110,32,66,97,110,107,115,33,10,71,111,111,100,32,111,108,100,32,69,110,103,108,97,110,100,44,32,69,110,103,108,97,110,100,32,116,104,97,116,32,99,111,117,108,100,110,39,116,32,112,108,97,121,32,102,111,111,116,98,97,108,108,33,10,69,110,103,108,97,110,100,32,104,97,118,101,32,103,111,116,32,105,116,32,105,110,32,116,104,101,32,98,97,103,33,10,73,32,107,110,111,119,32,116,104,97,116,32,119,97,115,32,116,104,101,110,44,32,98,117,116,32,105,116,32,99,111,117,108,100,32,98,101,32,97,103,97,105,110,
  10,10,91,82,101,102,114,97,105,110,58,32,73,97,110,32,66,114,111,117,100,105,101,93,10,73,116,39,115,32,99,111,109,105,110,103,32,104,111,109,101,44,32,105,116,39,115,32,99,111,109,105,110,103,10,70,111,111,116,98,97,108,108,39,115,32,99,111,109,105,110,103,32,104,111,109,101,10,73,116,39,115,32,99,111,109,105,110,103,32,104,111,109,101,44,32,105,116,39,115,32,99,111,109,105,110,103,32,104,111,109,101,44,32,105,116,39,115,32,99,111,109,105,110,103,10,70,111,111,116,98,97,108,108,39,115,32,99,111,109,105,110,103,32,104,111,109,101,10,40,69,110,103,108,97,110,100,32,104,97,118,101,32,100,111,110,101,32,105,116,33,41,10,73,116,39,115,32,99,111,109,105,110,103,32,104,111,109,101,44,32,105,116,39,115,32,99,111,109,105,110,103,32,104,111,109,101,44,32,105,116,39,115,32,99,111,109,105,110,103,10,70,111,111,116,98,97,108,108,39,115,32,99,111,109,105,110,103,32,104,111,109,101,10,73,116,39,115,32,99,111,109,105,110,103,32,104,111,109,101,44,32,105,116,39,115,32,99,111,109,105,110,103,32,104,111,109,101,44,32,105,116,39,115,32,99,111,109,105,110,103,10,70,111,111,116,98,97,108,108,39,115,32,99,111,109,105,110,103,32,104,111,109,101,10,91,67,104,111,114,117,115,58,32,65,108,108,93,10,40,73,116,39,115,32,99,111,109,105,110,103,32,104,111,109,101,41,32,84,104,114,101,101,32,108,105,111,110,115,32,111,110,32,97,32,115,104,105,114,116,10,40,73,116,39,115,32,99,111,109,105,110,103,32,104,111,109,101,44,32,105,116,39,115,32,99,111,109,105,110,103,41,32,74,117,108,101,115,32,82,105,109,101,116,32,115,116,105,108,108,32,103,108,101,97,109,105,110,103,10,40,70,111,111,116,98,97,108,108,39,115,32,99,111,109,105,110,103,32,104,111,109,101,10,73,116,39,115,32,99,111,109,105,110,103,32,104,111,109,101,41,32,84,104,105,114,116,121,32,121,101,97,114,115,32,111,102,32,104,117,114,116,10,40,73,116,39,115,32,99,111,109,105,110,103,32,104,111,109,101,44,32,105,116,39,115,32,99,111,109,105,110,103,41,32,78,101,118,101,114,32,115,116,111,112,112,101,100,32,109,101,32,100,114,101,97,109,105,110,103,10,40,70,111,111,116,98,97,108,108,39,115,32,99,111,109,105,110,103,32,104,111,109,101,10,73,116,39,115,32,99,111,109,105,110,103,32,104,111,109,101,41,32,84,104,114,101,101,32,108,105,111,110,115,32,111,110,32,97,32,115,104,105,114,116,10,40,73,116,39,115,32,99,111,109,105,110,103,32,104,111,109,101,44,32,105,116,39,115,32,99,111,109,105,110,103,41,32,74,117,108,101,115,32,82,105,109,101,116,32,115,116,105,108,108,32,103,108,101,97,109,105,110,103,10,40,70,111,111,116,98,97,108,108,39,115,32,99,111,109,105,110,103,32,104,111,109,101,10,73,116,39,115,32,99,111,109,105,110,103,32,104,111,109,101,41,32,84,104,105,114,116,121,32,121,101,97,114,115,32,111,102,32,104,117,114,116,10,40,73,116,39,115,32,99,111,109,105,110,103,32,104,111,109,101,44,32,105,116,39,115,32,99,111,109,105,110,103,41,32,78,101,118,101,114,32,115,116,111,112,112,101,100,32,109,101,32,100,114,101,97,109,105,110,103,10,40,70,111,111,116,98,97,108,108,39,115,32,99,111,109,105,110,103,32,104,111,109,101,41
];

// Assembled at runtime to avoid plaintext exposure in binary
String get _fooVal => [
  'pr','od','uc','ti','on',':',
  'ab','15','8b','b5','c6','ae',
  '90','7b','a5','04','af','da',
  'da','c2','7a','92','a4','dc','a7','c2'
].join();

String _generateXMasToken(String fullUrl) {
  final body = {
    'url': fullUrl,
    'code': DateTime.now().millisecondsSinceEpoch,
    'foo': _fooVal,
  };
  final toSign = jsonEncode(body) + _FOTMOB_KEY;
  final signature = sha256.convert(utf8.encode(toSign)).toString();
  return base64.encode(utf8.encode(jsonEncode({'body': body, 'signature': signature})));
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
    // Generate token off main thread
    final token = await compute(_generateXMasToken, fullUrl);
    final res = await _dio.get(fullUrl, options: Options(headers: {'x-mas': token}));
    final data = res.data is Map<String, dynamic>
        ? res.data as Map<String, dynamic>
        : res.data is Map ? (res.data as Map).cast<String, dynamic>() : <String, dynamic>{};

    _cache[cacheKey] = (data: data, expiry: now.add(ttl));
    _pruneCache();
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
    final res = await _dio.get(fullUrl, options: Options(headers: {'x-mas': token}));
    final items = res.data is List ? (res.data as List) : [];
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

  static Future<Map<String, dynamic>> getLeagueDetails(String id, {String? season}) {
    final p = {'id': id, 'tab': 'overview', 'type': 'league', 'timeZone': 'Asia/Dhaka'};
    if (season != null) p['season'] = season;
    return _get('leagues', params: p);
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
      'title': n['title']?.toString() ?? '',
      'imageUrl': n['imageUrl']?.toString() ?? '',
      'url': (n['page'] as Map?)?.containsKey('url') == true ? n['page']['url'].toString() : '',
      'source': n['sourceStr']?.toString() ?? '',
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
      'title': n['title']?.toString() ?? '',
      'imageUrl': n['imageUrl']?.toString() ?? '',
      'url': (n['page'] as Map?)?.containsKey('url') == true ? n['page']['url'].toString() : '',
      'source': n['sourceStr']?.toString() ?? '',
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
