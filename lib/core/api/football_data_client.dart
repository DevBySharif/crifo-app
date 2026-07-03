import 'dart:convert';
import 'package:dio/dio.dart';

// ─── Proxy-based football-data.org client ─────────────────────────────────────
//
// SECURITY: The football-data.org API token is stored as a Cloudflare Worker
// secret (env.FD_TOKEN) and injected server-side by the proxy. The token is
// NOT present in this source file or the compiled APK.
//
// To activate:
//   1. Deploy the updated proxy/worker.js to Cloudflare
//   2. Run: wrangler secret put FD_TOKEN  (paste your token)
//   3. Verify: curl https://crifo-proxy.crifo-bd.workers.dev/fd/competitions/PL/standings
//
// When the proxy is unavailable, requests fallback to direct (which will
// 401 without a token — acceptable for dev; production must use the proxy).

const _FD_ORIGIN = 'https://api.football-data.org/v4';

// Same Cloudflare Worker as FotMob proxy, different route (/fd/*).
// Token injected server-side from env.FD_TOKEN Cloudflare secret.
const _PROXY = 'https://crifo-proxy.crifo-bd.workers.dev';

// Proxy base for /fd/* route — falls back to direct if proxy is empty.
String get _fdBase {
  if (_PROXY.isNotEmpty) return '$_PROXY/fd';
  return _FD_ORIGIN;
}

final _dio = Dio(BaseOptions(
  connectTimeout: const Duration(seconds: 10),
  receiveTimeout: const Duration(seconds: 15),
  // No X-Auth-Token header here — the Worker injects it from env.FD_TOKEN
));

// FotMob primaryId → football-data.org competition code
const _codeMap = {
  '47': 'PL',    // Premier League
  '87': 'PD',    // La Liga
  '54': 'BL1',   // Bundesliga
  '55': 'SA',    // Serie A
  '53': 'FL1',   // Ligue 1
  '42': 'CL',    // Champions League
  '73': 'ELC',   // Championship
  '108': 'PPL',  // Primeira Liga
  '67': 'DED',   // Eredivisie
  '130': 'TR1',  // Süper Lig (if available)
  '77': 'WC',    // World Cup
  '65': 'EC',    // European Championship
};

class FootballDataClient {
  static String? getCode(String fotmobPrimaryId) => _codeMap[fotmobPrimaryId];

  static Future<List<Map<String, dynamic>>> getStandings(String code) async {
    try {
      final res = await _dio.get('$_fdBase/competitions/$code/standings');
      final rawData = res.data;
      final Map<String, dynamic> data = rawData is String
          ? jsonDecode(rawData) as Map<String, dynamic>
          : rawData as Map<String, dynamic>;
      final standings = data['standings'] as List? ?? [];

      // Find TOTAL standings (not HOME/AWAY)
      Map<String, dynamic>? total;
      for (final s in standings) {
        if ((s as Map)['type'] == 'TOTAL') { total = s.cast<String, dynamic>(); break; }
      }
      total ??= standings.isNotEmpty ? (standings.first as Map).cast<String, dynamic>() : null;
      if (total == null) return [];

      final table = total['table'] as List? ?? [];
      return table.map((e) {
        final m = e as Map<String, dynamic>;
        final team = m['team'] as Map<String, dynamic>? ?? {};
        return {
          'id': team['id']?.toString() ?? '',
          'name': team['shortName']?.toString() ?? team['name']?.toString() ?? '',
          'logo': team['crest']?.toString() ?? '',
          'played': (m['playedGames'] as num? ?? 0).toInt(),
          'wins': (m['won'] as num? ?? 0).toInt(),
          'draws': (m['draw'] as num? ?? 0).toInt(),
          'losses': (m['lost'] as num? ?? 0).toInt(),
          'goalsFor': (m['goalsFor'] as num? ?? 0).toInt(),
          'goalsAgainst': (m['goalsAgainst'] as num? ?? 0).toInt(),
          'gd': (m['goalDifference'] as num? ?? 0).toInt(),
          'pts': (m['points'] as num? ?? 0).toInt(),
          'pos': (m['position'] as num? ?? 0).toInt(),
        };
      }).toList();
    } catch (_) {
      return [];
    }
  }

  // For competitions with groups (World Cup, UCL group stage)
  static Future<List<Map<String, dynamic>>> getAllGroupStandings(String code) async {
    try {
      final res = await _dio.get('$_fdBase/competitions/$code/standings');
      final rawData = res.data;
      final Map<String, dynamic> data = rawData is String
          ? jsonDecode(rawData) as Map<String, dynamic>
          : rawData as Map<String, dynamic>;
      final standings = data['standings'] as List? ?? [];

      final allRows = <Map<String, dynamic>>[];
      for (final s in standings) {
        final sm = s as Map<String, dynamic>;
        final groupName = sm['group']?.toString() ?? sm['stage']?.toString() ?? '';
        final table = sm['table'] as List? ?? [];
        for (final e in table) {
          final m = e as Map<String, dynamic>;
          final team = m['team'] as Map<String, dynamic>? ?? {};
          allRows.add({
            'id': team['id']?.toString() ?? '',
            'name': team['shortName']?.toString() ?? team['name']?.toString() ?? '',
            'logo': team['crest']?.toString() ?? '',
            'played': (m['playedGames'] as num? ?? 0).toInt(),
            'wins': (m['won'] as num? ?? 0).toInt(),
            'draws': (m['draw'] as num? ?? 0).toInt(),
            'losses': (m['lost'] as num? ?? 0).toInt(),
            'goalsFor': (m['goalsFor'] as num? ?? 0).toInt(),
            'goalsAgainst': (m['goalsAgainst'] as num? ?? 0).toInt(),
            'gd': (m['goalDifference'] as num? ?? 0).toInt(),
            'pts': (m['points'] as num? ?? 0).toInt(),
            'pos': (m['position'] as num? ?? 0).toInt(),
            'group': groupName,
          });
        }
      }
      return allRows;
    } catch (_) {
      return [];
    }
  }
}
