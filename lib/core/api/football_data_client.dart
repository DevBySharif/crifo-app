import 'package:dio/dio.dart';

const _BASE = 'https://api.football-data.org/v4';
const _TOKEN = '5bfc00e6b7f04977b89a454666d9c4fa';

final _dio = Dio(BaseOptions(
  connectTimeout: const Duration(seconds: 10),
  receiveTimeout: const Duration(seconds: 15),
  headers: {'X-Auth-Token': _TOKEN},
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
      final res = await _dio.get('$_BASE/competitions/$code/standings');
      final data = res.data as Map<String, dynamic>;
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
          'played': (m['playedGames'] ?? 0) as int,
          'wins': (m['won'] ?? 0) as int,
          'draws': (m['draw'] ?? 0) as int,
          'losses': (m['lost'] ?? 0) as int,
          'goalsFor': (m['goalsFor'] ?? 0) as int,
          'goalsAgainst': (m['goalsAgainst'] ?? 0) as int,
          'gd': (m['goalDifference'] ?? 0) as int,
          'pts': (m['points'] ?? 0) as int,
          'pos': (m['position'] ?? 0) as int,
        };
      }).toList();
    } catch (_) {
      return [];
    }
  }

  // For competitions with groups (World Cup, UCL group stage)
  static Future<List<Map<String, dynamic>>> getAllGroupStandings(String code) async {
    try {
      final res = await _dio.get('$_BASE/competitions/$code/standings');
      final data = res.data as Map<String, dynamic>;
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
            'played': (m['playedGames'] ?? 0) as int,
            'wins': (m['won'] ?? 0) as int,
            'draws': (m['draw'] ?? 0) as int,
            'losses': (m['lost'] ?? 0) as int,
            'goalsFor': (m['goalsFor'] ?? 0) as int,
            'goalsAgainst': (m['goalsAgainst'] ?? 0) as int,
            'gd': (m['goalDifference'] ?? 0) as int,
            'pts': (m['points'] ?? 0) as int,
            'pos': (m['position'] ?? 0) as int,
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
