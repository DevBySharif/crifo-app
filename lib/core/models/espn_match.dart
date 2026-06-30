class ESPNMatch {
  final String id;
  final String leagueSlug;
  final String leagueName;
  final String leagueLogo;
  final String teamA;
  final String teamB;
  final String teamAId;
  final String teamBId;
  final String logoA;
  final String logoB;
  final String scoreA;
  final String scoreB;
  final String homeAbbr;
  final String awayAbbr;
  final String state;
  final String statusDetail;
  final String? displayClock;
  final String date;
  final String venue;
  final String venueCity;
  final String groupName;
  final String attendance;
  final List<String> broadcasts;
  final String homeColor;
  final String awayColor;
  final String recordA;
  final String recordB;
  final List<ESPNScorer> scorers;

  ESPNMatch({
    required this.id,
    required this.leagueSlug,
    required this.leagueName,
    required this.leagueLogo,
    required this.teamA,
    required this.teamB,
    required this.teamAId,
    required this.teamBId,
    required this.logoA,
    required this.logoB,
    required this.scoreA,
    required this.scoreB,
    required this.homeAbbr,
    required this.awayAbbr,
    required this.state,
    required this.statusDetail,
    this.displayClock,
    required this.date,
    required this.venue,
    required this.venueCity,
    required this.groupName,
    required this.attendance,
    this.broadcasts = const [],
    this.homeColor = '',
    this.awayColor = '',
    this.recordA = '',
    this.recordB = '',
    this.scorers = const [],
  });

  bool get isLive => state == 'in';
  bool get isPre => state == 'pre';
  bool get isPost => state == 'post';

  String get displayTime {
    if (isLive) return displayClock ?? statusDetail;
    if (isPost) return 'FT';
    return statusDetail;
  }

  factory ESPNMatch.fromJson(Map<String, dynamic> json, {String? leagueSlug, String? leagueName, String? leagueLogo}) {
    final comps = json['competitions'];
    final comp = (comps is List && comps.isNotEmpty) ? comps[0] as Map<String, dynamic>? : null;

    Map<String, dynamic> home = {};
    Map<String, dynamic> away = {};
    if (comp != null) {
      final competitors = comp['competitors'];
      if (competitors is List) {
        for (final c in competitors) {
          if (c is Map) {
            if (c['homeAway'] == 'home') home = c.cast<String, dynamic>();
            if (c['homeAway'] == 'away') away = c.cast<String, dynamic>();
          }
        }
      }
    }

    final status = json['status'];
    final statusType = (status is Map) ? (status['type'] as Map<String, dynamic>? ?? <String, dynamic>{}) : <String, dynamic>{};
    final broadcasts = <String>[];
    if (comp != null) {
      final rawBroadcasts = comp['broadcasts'];
      if (rawBroadcasts is List) {
        for (final b in rawBroadcasts) {
          if (b is Map) {
            final names = b['names'];
            if (names is List) {
              for (final n in names) broadcasts.add(n.toString());
            } else if (b['name'] != null) {
              broadcasts.add(b['name'].toString());
            }
          }
        }
      }
    }

    final scorers = <ESPNScorer>[];
    if (comp != null) {
      final competitors = comp['competitors'];
      if (competitors is List) {
        for (final c in competitors) {
          if (c is Map) {
            final cScorers = c['scorers'];
            if (cScorers is List) {
              for (final s in cScorers) {
                if (s is Map) {
                  final athlete = s['athlete'];
                  scorers.add(ESPNScorer(
                    name: (athlete is Map) ? (athlete['displayName']?.toString() ?? '') : '',
                    value: s['value']?.toString() ?? '1',
                  ));
                }
              }
            }
          }
        }
      }
    }

    final homeTeam = home['team'];
    final awayTeam = away['team'];
    final homeTeamMap = homeTeam is Map ? homeTeam.cast<String, dynamic>() : <String, dynamic>{};
    final awayTeamMap = awayTeam is Map ? awayTeam.cast<String, dynamic>() : <String, dynamic>{};

    final homeRecords = home['records'];
    final awayRecords = away['records'];
    final homeRecs = homeRecords is List ? homeRecords : <dynamic>[];
    final awayRecs = awayRecords is List ? awayRecords : <dynamic>[];

    String venue = '';
    String venueCity = '';
    String groupName = '';
    String attendance = '';
    String date = '';
    if (comp != null) {
      final v = comp['venue'];
      venue = (v is Map) ? (v['displayName']?.toString() ?? v['fullName']?.toString() ?? '') : '';
      venueCity = (v is Map && v['address'] is Map) ? (v['address']['city']?.toString() ?? '') : '';
      groupName = (comp['groups'] is Map) ? (comp['groups']['name']?.toString() ?? '') : '';
      attendance = comp['attendance']?.toString() ?? '';
      date = comp['date']?.toString() ?? '';
    }
    if (date.isEmpty && json['date'] != null) {
      date = json['date'].toString();
    }

    return ESPNMatch(
      id: json['id']?.toString() ?? '',
      leagueSlug: leagueSlug ?? '',
      leagueName: leagueName ?? '',
      leagueLogo: leagueLogo ?? '',
      teamA: homeTeamMap['displayName']?.toString() ?? '',
      teamB: awayTeamMap['displayName']?.toString() ?? '',
      teamAId: homeTeamMap['id']?.toString() ?? '',
      teamBId: awayTeamMap['id']?.toString() ?? '',
      logoA: homeTeamMap['logo']?.toString() ?? '',
      logoB: awayTeamMap['logo']?.toString() ?? '',
      scoreA: home['score']?.toString() ?? '0',
      scoreB: away['score']?.toString() ?? '0',
      homeAbbr: homeTeamMap['abbreviation']?.toString() ?? '',
      awayAbbr: awayTeamMap['abbreviation']?.toString() ?? '',
      state: statusType['state']?.toString() ?? 'pre',
      statusDetail: statusType['detail']?.toString() ?? '',
      displayClock: (status is Map) ? status['displayClock']?.toString() : null,
      date: date,
      venue: venue,
      venueCity: venueCity,
      groupName: groupName,
      attendance: attendance,
      broadcasts: broadcasts,
      homeColor: homeTeamMap['color']?.toString() ?? '',
      awayColor: awayTeamMap['color']?.toString() ?? '',
      recordA: homeRecs.isNotEmpty ? (homeRecs[0]['summary']?.toString() ?? '') : '',
      recordB: awayRecs.isNotEmpty ? (awayRecs[0]['summary']?.toString() ?? '') : '',
      scorers: scorers,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id, 'leagueSlug': leagueSlug, 'leagueName': leagueName,
    'leagueLogo': leagueLogo, 'teamA': teamA, 'teamB': teamB,
    'teamAId': teamAId, 'teamBId': teamBId, 'logoA': logoA, 'logoB': logoB,
    'scoreA': scoreA, 'scoreB': scoreB, 'homeAbbr': homeAbbr, 'awayAbbr': awayAbbr,
    'state': state, 'statusDetail': statusDetail, 'displayClock': displayClock,
    'date': date, 'venue': venue, 'venueCity': venueCity, 'groupName': groupName,
    'attendance': attendance, 'broadcasts': broadcasts,
    'homeColor': homeColor, 'awayColor': awayColor,
    'recordA': recordA, 'recordB': recordB,
  };
}

class ESPNScorer {
  final String name;
  final String value;
  ESPNScorer({required this.name, this.value = '1'});
}

class ESPNLeagueInfo {
  final String slug;
  final String name;
  final String logo;
  const ESPNLeagueInfo({required this.slug, required this.name, required this.logo});

  static const List<ESPNLeagueInfo> all = [
    ESPNLeagueInfo(slug: 'eng.1', name: 'Premier League', logo: 'https://a.espncdn.com/i/leaguelogos/soccer/500/23.png'),
    ESPNLeagueInfo(slug: 'esp.1', name: 'La Liga', logo: 'https://a.espncdn.com/i/leaguelogos/soccer/500/15.png'),
    ESPNLeagueInfo(slug: 'ger.1', name: 'Bundesliga', logo: 'https://a.espncdn.com/i/leaguelogos/soccer/500/10.png'),
    ESPNLeagueInfo(slug: 'ita.1', name: 'Serie A', logo: 'https://a.espncdn.com/i/leaguelogos/soccer/500/12.png'),
    ESPNLeagueInfo(slug: 'fra.1', name: 'Ligue 1', logo: 'https://a.espncdn.com/i/leaguelogos/soccer/500/9.png'),
    ESPNLeagueInfo(slug: 'uefa.champions', name: 'Champions League', logo: 'https://a.espncdn.com/i/leaguelogos/soccer/500/2.png'),
    ESPNLeagueInfo(slug: 'uefa.europa', name: 'Europa League', logo: 'https://a.espncdn.com/i/leaguelogos/soccer/500/600.png'),
    ESPNLeagueInfo(slug: 'fifa.world', name: 'World Cup', logo: 'https://a.espncdn.com/i/leaguelogos/soccer/500/4.png'),
    ESPNLeagueInfo(slug: 'usa.1', name: 'MLS', logo: 'https://a.espncdn.com/i/leaguelogos/soccer/500/19.png'),
    ESPNLeagueInfo(slug: 'ned.1', name: 'Eredivisie', logo: 'https://a.espncdn.com/i/leaguelogos/soccer/500/11.png'),
    ESPNLeagueInfo(slug: 'por.1', name: 'Primeira Liga', logo: 'https://a.espncdn.com/i/leaguelogos/soccer/500/17.png'),
    ESPNLeagueInfo(slug: 'tur.1', name: 'Süper Lig', logo: 'https://a.espncdn.com/i/leaguelogos/soccer/500/18.png'),
    ESPNLeagueInfo(slug: 'bra.1', name: 'Brasileirão', logo: 'https://a.espncdn.com/i/leaguelogos/soccer/500/8.png'),
  ];
}
