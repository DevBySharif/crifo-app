import 'dart:convert';
import 'dart:math' as math;
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../core/api/tv_channels.dart';
import '../../core/services/remote_channels.dart';
import '../../core/theme/colors.dart';
import '../../core/providers/tv_fullscreen_provider.dart';

// ─── Name sanitizer ───────────────────────────────────────────────────────────
// Source data contains mojibake (UTF-8 read as Latin-1, emoji bytes, %X junk).
// cp1252 printable chars that appear when UTF-8 bytes 0x80-0x9F get mis-decoded
const _cp1252Rev = {
  0x20AC: 0x80, 0x201A: 0x82, 0x0192: 0x83, 0x201E: 0x84, 0x2026: 0x85,
  0x2020: 0x86, 0x2021: 0x87, 0x02C6: 0x88, 0x2030: 0x89, 0x0160: 0x8A,
  0x2039: 0x8B, 0x0152: 0x8C, 0x017D: 0x8E, 0x2018: 0x91, 0x2019: 0x92,
  0x201C: 0x93, 0x201D: 0x94, 0x2022: 0x95, 0x2013: 0x96, 0x2014: 0x97,
  0x02DC: 0x98, 0x2122: 0x99, 0x0161: 0x9A, 0x203A: 0x9B, 0x0153: 0x9C,
  0x017E: 0x9E, 0x0178: 0x9F,
};

String cleanChannelName(String raw) {
  var s = raw;
  // Repair double-encoded UTF-8 (e.g. "Ã±" → "ñ") when mojibake markers present
  if (s.contains('Ã') || s.contains('â') || s.contains('ï¸')) {
    try {
      final bytes = <int>[];
      var ok = true;
      for (final cu in s.runes) {
        if (cu <= 0xFF) { bytes.add(cu); }
        else if (_cp1252Rev.containsKey(cu)) { bytes.add(_cp1252Rev[cu]!); }
        else { ok = false; break; }
      }
      if (ok) s = utf8.decode(bytes, allowMalformed: true);
    } catch (_) {}
  }
  s = s
      .replaceAll(RegExp(r'[\u{1F000}-\u{1FFFF}\u{2190}-\u{2BFF}\u{FE00}-\u{FE0F}�]', unicode: true), '') // emoji/junk
      .replaceAll(RegExp(r'(%[0-9A-Fa-f])+'), '') // %7%4... garbage
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  return s.isEmpty ? raw.trim() : s;
}

// ─── Sorting helpers ──────────────────────────────────────────────────────────

// Region groups: 0=International (popular global), 1=Bangladeshi, 2=Indian, 3=Pakistani, 4=Other
const _bdKeywords = [
  'btv', 'maasranga', 'somoy', 'jamuna', 'rtv', 'channel 9', 'channel i',
  'desh tv', 'ntv', 'independent', 'ekattor', 'dbc', 'bangla vision',
  'channel 24', 'boishakhi', 'my tv', 'atn bangla', 'atn news', 'sa tv',
  'news24', 'gtv', 'gazi tv', 't sports', 'akash go', 'akash sports',
  'a sports', 'duranto', 'asian tv', 'ananda tv', 'anb news', 'islamic tv',
  'peace tv bangla',
];

const _pakKeywords = [
  'ptv', 'geo tv', 'geo news', 'geo sports', 'ary', 'hum tv', 'hum news',
  'dunya news', 'samaa', 'express news', 'a sports pk', 'ten sports pk',
  'such tv', 'capital tv', 'bol news', '92 news', 'neo news',
];

const _indKeywords = [
  'zee', 'colors', 'star plus', 'star gold', 'set max', 'sony sports',
  'sony ten', 'sony six', 'star sports', 'ndtv', 'aaj tak', 'india tv',
  'republic', 'abp', 'news18', 'sun tv', 'star bharat', 'sab tv',
  'star utsav', 'dd national', 'dd sports', 'zee news', 'times now',
  'cricket gold', 'cricket 24', 'star vijay', 'sony sab',
];

const _intlPopularKeywords = [
  'bein sports', 'sky sports', 'espn', 'ten sports', 'willow',
  'fox sports', 'al jazeera', 'bbc', 'cnn', 'euronews', 'discovery',
  'national geographic', 'nat geo', 'mbc', 'dubai sports', 'abu dhabi sports',
];

int _regionOf(String name) {
  final n = name.toLowerCase();
  for (final k in _bdKeywords) { if (n.contains(k)) return 1; }
  for (final k in _pakKeywords) { if (n.contains(k)) return 3; }
  for (final k in _indKeywords) { if (n.contains(k)) return 2; }
  for (final k in _intlPopularKeywords) { if (n.contains(k)) return 0; }
  return 4;
}

int _popularityRank(String name) {
  final n = name.toLowerCase();
  final all = [..._intlPopularKeywords, ..._bdKeywords, ..._indKeywords, ..._pakKeywords];
  for (var i = 0; i < all.length; i++) {
    if (n.contains(all[i])) return i;
  }
  return 9999;
}

int _cdnScore(String url) {
  final u = url.toLowerCase();
  if (u.contains('gpcdn.net')) return 0;
  if (u.contains('aynaott.com')) return 1;
  if (u.contains('jagobd.com')) return 2;
  if (u.contains('cloudfront.net') || u.contains('akamai')) return 3;
  if (u.contains('amagi.tv') || u.contains('sofast.tv') ||
      u.contains('tubi.video') || u.contains('transmit.live')) return 4;
  if (u.contains('ercdn.net') || u.contains('daioncdn.net')) return 5;
  if (RegExp(r'https?://\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}').hasMatch(u)) return 9;
  return 6;
}

// Region (Intl→BD→India→Pak→Other) is the primary sort key.
// Within a region: working channels first, then popularity, then CDN reliability.
int _channelSortKey(TVChannel ch, {int working = 1}) {
  final region = _regionOf(ch.name);
  final pop = _popularityRank(ch.name);
  final cdn = _cdnScore(ch.streamUrl);
  final popScore = pop < 9999 ? pop : 500;
  return region * 1000000 + working * 100000 + popScore * 100 + cdn * 10;
}

// ─── Channel health check ─────────────────────────────────────────────────────

final _dio = Dio(BaseOptions(
  connectTimeout: const Duration(seconds: 5),
  receiveTimeout: const Duration(seconds: 8),
  headers: {
    'User-Agent': 'Mozilla/5.0 (Linux; Android 14; Pixel 7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36',
    'Accept': '*/*',
  },
));

Future<Set<String>> _checkWorkingChannels(List<TVChannel> channels) async {
  final working = <String>{};
  final toCheck = channels.take(80).toList();
  for (var i = 0; i < toCheck.length; i += 15) {
    final batch = toCheck.sublist(i, math.min(i + 15, toCheck.length));
    await Future.wait(
      batch.map((ch) async {
        if (ch.streamUrl.isEmpty) return;
        try {
          final u = ch.streamUrl.toLowerCase();
          final isHls = u.contains('.m3u8') || u.contains('/master') ||
              u.contains('playlist') || u.contains('chunks') ||
              u.contains('/index') || u.contains('output/index');
          if (isHls) {
            final res = await _dio.get<String>(ch.streamUrl,
                options: Options(responseType: ResponseType.plain));
            final body = res.data ?? '';
            final snippet = body.substring(0, math.min(body.length, 512));
            if (snippet.contains('#EXTM3U') || snippet.contains('#EXT-X-')) {
              working.add(ch.id);
            }
          } else {
            final res = await _dio.head(ch.streamUrl);
            if ((res.statusCode ?? 0) < 400) working.add(ch.id);
          }
        } catch (_) {}
      }),
      eagerError: false,
    );
  }
  return working;
}

// ─── Main screen ──────────────────────────────────────────────────────────────

class TVScreen extends ConsumerStatefulWidget {
  const TVScreen({super.key});
  @override
  ConsumerState<TVScreen> createState() => _TVScreenState();
}

class _TVScreenState extends ConsumerState<TVScreen> {
  TVCategory? _cat;
  final _searchCtrl = TextEditingController();
  String _query = '';

  TVChannel? _playing;
  VideoPlayerController? _vpc;
  bool _playerLoading = false;
  bool _fullscreen = false;

  List<TVChannel> _channels = tvChannels
      .map((c) => TVChannel(id: c.id, name: cleanChannelName(c.name),
          category: c.category, streamUrl: c.streamUrl, logoUrl: c.logoUrl))
      .toList()
    ..sort((a, b) => _channelSortKey(a, working: a.live ? 0 : 1)
        .compareTo(_channelSortKey(b, working: b.live ? 0 : 1)));
  Set<String> _workingIds = {};
  bool _checking = false;

  // --- DUDE TV State ---
  List<DudeCategory> _dudeCategories = [];
  DudeCategory? _selectedDudeCategory;
  List<DudeChannel> _dudeChannels = [];
  bool _dudeLoading = false;
  bool _dudeError = false;
  final Map<String, List<DudeChannel>> _dudeChannelsCache = {};
  List<DudeChannel> _allDudeChannels = []; // all loaded dude channels merged

  // unified category: null = All, TVCategory = crifo cat, String = dude cat id
  Object? _selectedCatKey; // null | TVCategory | String(DudeCategory.id)

  @override
  void initState() {
    super.initState();
    _loadRemoteThenCheck();
    _fetchDudeCategories(); // auto-load DUDE channels on start
  }

  // Pull the latest channel list from the server (so channels can change with
  // no app update), then health-check them. Falls back to the built-in list.
  Future<void> _loadRemoteThenCheck() async {
    try {
      final remote = await loadChannels();
      if (mounted && remote.isNotEmpty) {
        setState(() {
          _channels = remote
              .map((c) => TVChannel(id: c.id, name: cleanChannelName(c.name),
                  category: c.category, streamUrl: c.streamUrl, logoUrl: c.logoUrl,
                  live: c.live))
              .toList()
            ..sort((a, b) => _channelSortKey(a, working: a.live ? 0 : 1)
                .compareTo(_channelSortKey(b, working: b.live ? 0 : 1)));
        });
      }
    } catch (_) {}
    await _runChannelCheck();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _vpc?.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  Future<void> _runChannelCheck() async {
    if (_checking) return;
    setState(() => _checking = true);
    final working = await _checkWorkingChannels(_channels);
    if (!mounted) return;
    final sorted = List<TVChannel>.from(_channels)
      ..sort((a, b) {
        final aW = (working.contains(a.id) || a.live) ? 0 : 1;
        final bW = (working.contains(b.id) || b.live) ? 0 : 1;
        return _channelSortKey(a, working: aW)
            .compareTo(_channelSortKey(b, working: bW));
      });
    setState(() {
      _workingIds = working;
      _channels = sorted;
      _checking = false;
    });
  }

  // ─── Dude TV Backend Systems ────────────────────────────────────────────────

  Future<void> _fetchDudeCategories() async {
    if (!mounted) return;
    setState(() {
      _dudeLoading = true;
      _dudeError = false;
    });
    try {
      final res = await Dio().get(
        'https://mdjamsad9.github.io/dudetvapi/public_decrypted/cats.json',
        options: Options(responseType: ResponseType.json),
      );
      final list = res.data;
      if (list is List) {
        final parsed = list
            .map((e) => DudeCategory.fromJson(e as Map<String, dynamic>))
            .toList();

        parsed.removeWhere((c) => c.title.isEmpty || c.catLink.isEmpty);

        if (mounted) {
          setState(() {
            _dudeCategories = parsed;
            if (parsed.isNotEmpty) {
              _selectedDudeCategory = parsed.first;
            }
          });
          if (_selectedDudeCategory != null) {
            await _fetchDudeChannelsForCategory(_selectedDudeCategory!);
          }
        }

        _preloadCategoryCounts(parsed);
      } else {
        if (mounted) setState(() => _dudeError = true);
      }
    } catch (_) {
      if (mounted) setState(() => _dudeError = true);
    } finally {
      if (mounted) setState(() => _dudeLoading = false);
    }
  }

  Future<void> _fetchDudeChannelsForCategory(DudeCategory cat) async {
    final link = cat.catLink;
    if (_dudeChannelsCache.containsKey(link)) {
      setState(() {
        _dudeChannels = _dudeChannelsCache[link]!;
      });
      return;
    }

    if (!mounted) return;
    setState(() => _dudeLoading = true);
    try {
      List<DudeChannel> parsedChannels = [];

      if (link == 'Sports') {
        final res = await Dio().get(
          'https://mdjamsad9.github.io/dudetvapi/public_decrypted/sports.json',
          options: Options(responseType: ResponseType.json),
        );
        if (res.data is List) {
          parsedChannels = (res.data as List)
              .map((e) => DudeChannel.fromJson(e as Map<String, dynamic>))
              .toList();
        }
      } else if (link.startsWith('http') || link.endsWith('.m3u')) {
        final res = await Dio().get(
          link,
          options: Options(responseType: ResponseType.plain),
        );
        parsedChannels = parseM3U(res.data.toString(), cat.title);
      } else if (link.endsWith('.json')) {
        final res = await Dio().get(
          'https://mdjamsad9.github.io/dudetvapi/public_decrypted/$link',
          options: Options(responseType: ResponseType.json),
        );
        if (res.data is List) {
          parsedChannels = (res.data as List)
              .map((e) => DudeChannel.fromJson(e as Map<String, dynamic>))
              .toList();
        }
      } else {
        final res = await Dio()
            .get(
              'https://mdjamsad9.github.io/dudetvapi/public_decrypted/cats/${link.toLowerCase()}.json',
              options: Options(responseType: ResponseType.json),
            )
            .catchError((_) => Dio().get(
                  'https://mdjamsad9.github.io/dudetvapi/public_decrypted/$link.json',
                  options: Options(responseType: ResponseType.json),
                ));
        if (res.data is List) {
          parsedChannels = (res.data as List)
              .map((e) => DudeChannel.fromJson(e as Map<String, dynamic>))
              .toList();
        }
      }

      if (mounted) {
        setState(() {
          _dudeChannelsCache[link] = parsedChannels;
          _dudeChannels = parsedChannels;
          cat.channelCount = parsedChannels.length;
          // merge into allDudeChannels (avoid duplicates by id)
          final existingIds = _allDudeChannels.map((c) => c.id).toSet();
          final newOnes = parsedChannels.where((c) => !existingIds.contains(c.id)).toList();
          _allDudeChannels = [..._allDudeChannels, ...newOnes];
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _dudeChannels = [];
        });
      }
    } finally {
      if (mounted) setState(() => _dudeLoading = false);
    }
  }

  Future<void> _preloadCategoryCounts(List<DudeCategory> categories) async {
    for (final cat in categories) {
      if (cat.id == _selectedDudeCategory?.id) continue;
      try {
        final link = cat.catLink;
        List<DudeChannel> channels = [];
        if (link == 'Sports') {
          final res = await Dio().get(
            'https://mdjamsad9.github.io/dudetvapi/public_decrypted/sports.json',
            options: Options(responseType: ResponseType.json),
          );
          if (res.data is List) {
            channels = (res.data as List)
                .map((e) => DudeChannel.fromJson(e as Map<String, dynamic>))
                .toList();
          }
        } else if (link.startsWith('http') || link.endsWith('.m3u')) {
          final res = await Dio().get(
            link,
            options: Options(responseType: ResponseType.plain),
          );
          channels = parseM3U(res.data.toString(), cat.title);
        } else if (link.endsWith('.json')) {
          final res = await Dio().get(
            'https://mdjamsad9.github.io/dudetvapi/public_decrypted/$link',
            options: Options(responseType: ResponseType.json),
          );
          if (res.data is List) {
            channels = (res.data as List)
                .map((e) => DudeChannel.fromJson(e as Map<String, dynamic>))
                .toList();
          }
        } else {
          final res = await Dio()
              .get(
                'https://mdjamsad9.github.io/dudetvapi/public_decrypted/cats/${link.toLowerCase()}.json',
                options: Options(responseType: ResponseType.json),
              )
              .catchError((_) => Dio().get(
                    'https://mdjamsad9.github.io/dudetvapi/public_decrypted/$link.json',
                    options: Options(responseType: ResponseType.json),
                  ));
          if (res.data is List) {
            channels = (res.data as List)
                .map((e) => DudeChannel.fromJson(e as Map<String, dynamic>))
                .toList();
          }
        }
        if (mounted) {
          setState(() {
            cat.channelCount = channels.length;
            _dudeChannelsCache[link] = channels;
            // merge into allDudeChannels
            final existingIds = _allDudeChannels.map((c) => c.id).toSet();
            final newOnes = channels.where((c) => !existingIds.contains(c.id)).toList();
            _allDudeChannels = [..._allDudeChannels, ...newOnes];
          });
        }
      } catch (_) {}
    }
  }

  void _showDudeSubChannelsSheet(DudeChannel ch) {
    if (ch.directUrl != null) {
      final tvCh = TVChannel(
        id: ch.id,
        name: ch.title,
        category: categoryFromString(ch.category),
        streamUrl: ch.directUrl!,
        logoUrl: ch.image,
      );
      _play(tvCh);
      return;
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: context.cBgCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Container(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: context.cBorder,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                ch.title.toUpperCase(),
                style: TextStyle(
                  color: context.cTextPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'Inter',
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 14),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: ch.formatsNew.length,
                  itemBuilder: (subCtx, subIdx) {
                    final fmt = ch.formatsNew[subIdx];
                    return Container(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      decoration: BoxDecoration(
                        color: context.cBgElevated,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: context.cBorder, width: 0.8),
                      ),
                      child: ListTile(
                        leading: Container(
                          width: 32,
                          height: 32,
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Center(
                            child: fmt.logo.isNotEmpty
                                ? CachedNetworkImage(
                                    imageUrl: fmt.logo,
                                    fit: BoxFit.contain,
                                    errorWidget: (_, __, ___) => const Icon(
                                        Icons.tv_rounded,
                                        size: 16,
                                        color: Color(0xFF00B4FF)),
                                  )
                                : const Icon(Icons.tv_rounded,
                                    size: 16, color: Color(0xFF00B4FF)),
                          ),
                        ),
                        title: Text(
                          fmt.title,
                          style: TextStyle(
                            color: context.cTextPrimary,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'Inter',
                          ),
                        ),
                        trailing: const Icon(Icons.play_circle_fill_rounded,
                            color: Color(0xFF00B4FF), size: 24),
                        onTap: () {
                          Navigator.pop(ctx);
                          _resolveAndPlayDudeChannel(ch, fmt);
                        },
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _resolveAndPlayDudeChannel(DudeChannel ch, DudeFormat fmt) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (loadingCtx) => Center(
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: context.cBgCard,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: context.cBorder),
          ),
          child: const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: Color(0xFF00B4FF)),
              SizedBox(height: 12),
              Text(
                'Resolving Stream...',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'Inter',
                  decoration: TextDecoration.none,
                ),
              ),
            ],
          ),
        ),
      ),
    );

    try {
      final res = await Dio().get(
        'https://mdjamsad9.github.io/dudetvapi/public_decrypted/channels/${ch.id}.json',
        options: Options(responseType: ResponseType.json),
      );

      if (mounted) {
        Navigator.pop(context);
      }

      if (res.data is List) {
        final streams = (res.data as List)
            .map((e) => DudeStream.fromJson(e as Map<String, dynamic>))
            .toList();

        // Only use type=0 (plain HLS). type=1 requires Widevine DRM key — not supported.
        final playableStreams = streams.where((s) => s.type == '0' && s.link.isNotEmpty).toList();

        if (playableStreams.isEmpty && streams.isNotEmpty) {
          _showErrorSnackBar('This channel uses DRM encryption — not supported.');
          return;
        }

        final matched = playableStreams
            .where((s) => s.title.toLowerCase() == fmt.title.toLowerCase())
            .toList();

        final chosenStream = matched.isNotEmpty ? matched.first : (playableStreams.isNotEmpty ? playableStreams.first : null);

        if (chosenStream != null) {
          final tvCh = TVChannel(
            id: '${ch.id}_${chosenStream.title}',
            name: '${ch.title} - ${chosenStream.title}',
            category: categoryFromString(ch.category),
            streamUrl: chosenStream.link,
            logoUrl: ch.image,
          );
          _play(tvCh);
        } else {
          _showErrorSnackBar('No playable stream found for this channel.');
        }
      } else {
        _showErrorSnackBar('Failed to resolve channel stream.');
      }
    } catch (_) {
      if (mounted) {
        Navigator.pop(context);
      }
      _showErrorSnackBar('Connection failed. Please try again.');
    }
  }

  void _showErrorSnackBar(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          msg,
          style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontFamily: 'Inter',
              fontWeight: FontWeight.w600),
        ),
        backgroundColor: const Color(0xFFEF4444),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  // Handle play requests coming from other screens (match "Where to watch")
  void _handlePlayRequest(String? channelId) {
    if (channelId == null) return;
    ref.read(tvPlayRequestProvider.notifier).state = null;
    final ch = _channels.where((c) => c.id == channelId).toList();
    if (ch.isNotEmpty) _play(ch.first);
  }

  // Live = server-verified reachable this cycle, or confirmed by client check.
  int get _liveCount =>
      _channels.where((c) => c.live || _workingIds.contains(c.id)).length;

  // Unified filtered list: CriFO + DUDE channels based on selected category
  List<TVChannel> get _filteredCrifo {
    return _channels.where((c) {
      if (_selectedCatKey is TVCategory && c.category != _selectedCatKey) return false;
      if (_selectedCatKey is String) return false; // dude-only category
      if (_query.isNotEmpty && !c.name.toLowerCase().contains(_query.toLowerCase())) return false;
      return true;
    }).toList();
  }

  List<DudeChannel> get _filteredDude {
    if (_selectedCatKey is TVCategory) {
      // show dude channels matching the same crifo category name
      final catName = (_selectedCatKey as TVCategory).name.toLowerCase();
      return _allDudeChannels.where((c) => c.category.toLowerCase() == catName).toList();
    }
    if (_selectedCatKey is String) {
      return _dudeChannels; // already filtered to selected DUDE category
    }
    return _allDudeChannels; // All: show everything
  }

  // Legacy getter for backwards compat
  List<TVChannel> get _filtered => _filteredCrifo;

  // ── Playback ───────────────────────────────────────────────────────────────

  int _playToken = 0;
  bool _playerError = false;

  Future<void> _play(TVChannel ch) async {
    final token = ++_playToken;
    final oldCtrl = _vpc;
    setState(() {
      _playing = ch;
      _vpc = null;
      _playerLoading = true;
      _playerError = false;
      _fullscreen = false;
    });
    // Dispose old controller after swapping state so UI doesn't flash old frame
    oldCtrl?.dispose();

    try {
      final uri = Uri.parse(ch.streamUrl);
      final ctrl = VideoPlayerController.networkUrl(
        uri,
        httpHeaders: {
          'User-Agent': 'Mozilla/5.0 (Linux; Android 14; Pixel 7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36',
          'Accept': '*/*',
          'Referer': '${uri.scheme}://${uri.host}/',
        },
        videoPlayerOptions: VideoPlayerOptions(mixWithOthers: false),
      );

      await ctrl.initialize().timeout(const Duration(seconds: 12));

      // A newer _play() call superseded this one — discard.
      if (token != _playToken) { ctrl.dispose(); return; }
      if (!mounted) { ctrl.dispose(); return; }

      ctrl.addListener(() {
        if (!mounted || token != _playToken) return;
        final err = ctrl.value.errorDescription;
        if (err != null) {
          setState(() { _playerLoading = false; _playerError = true; });
        } else if (ctrl.value.isPlaying && _playerLoading) {
          setState(() => _playerLoading = false);
        }
      });

      await ctrl.setLooping(false);
      ctrl.play();
      setState(() {
        _vpc = ctrl;
        _playerLoading = false;
      });
    } catch (e) {
      if (token != _playToken || !mounted) return;
      setState(() { _playerLoading = false; _playerError = true; });
    }
  }

  void _closePlayer() {
    _playToken++;
    _exitFullscreen();
    _vpc?.dispose();
    setState(() {
      _playing = null;
      _vpc = null;
      _playerLoading = false;
      _playerError = false;
      _fullscreen = false;
    });
  }

  void _enterFullscreen() {
    final vpc = _vpc;
    final ch = _playing;
    if (vpc == null || ch == null) return;

    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    setState(() => _fullscreen = true);

    ref.read(tvFullscreenProvider.notifier).state = _FullscreenPage(
      controller: vpc,
      channelName: ch.name,
      onExit: _exitFullscreen,
    );
  }

  void _exitFullscreen() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    ref.read(tvFullscreenProvider.notifier).state = null;
    if (mounted) setState(() => _fullscreen = false);
  }

  // ─── Dude TV UI Elements ────────────────────────────────────────────────────

  Widget _buildDudeCategories() {
    if (_dudeCategories.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 75,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        itemCount: _dudeCategories.length,
        itemBuilder: (ctx, idx) {
          final cat = _dudeCategories[idx];
          final isActive = _selectedDudeCategory?.id == cat.id;
          return GestureDetector(
            onTap: () {
              setState(() {
                _selectedDudeCategory = cat;
              });
              _fetchDudeChannelsForCategory(cat);
            },
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 6),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: isActive ? Colors.transparent : context.cBgCard,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: isActive ? const Color(0xFF00B4FF) : context.cBorder,
                            width: isActive ? 2 : 1.2,
                          ),
                          boxShadow: isActive
                              ? [
                                  BoxShadow(
                                    color: const Color(0xFF00B4FF).withValues(alpha: 0.3),
                                    blurRadius: 8,
                                    spreadRadius: 1,
                                  )
                                ]
                              : null,
                        ),
                        child: ClipOval(
                          child: Padding(
                            padding: const EdgeInsets.all(6.0),
                            child: cat.image.isNotEmpty && cat.image != 'nullbsbbs'
                                ? CachedNetworkImage(
                                    imageUrl: cat.image,
                                    fit: BoxFit.contain,
                                    placeholder: (_, __) => _categoryFallback(cat.title),
                                    errorWidget: (_, __, ___) => _categoryFallback(cat.title),
                                  )
                                : _categoryFallback(cat.title),
                          ),
                        ),
                      ),
                      if (cat.channelCount > 0)
                        Positioned(
                          top: -3,
                          right: -3,
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: const BoxDecoration(
                              color: Color(0xFFFF2D55),
                              shape: BoxShape.circle,
                            ),
                            constraints: const BoxConstraints(
                              minWidth: 16,
                              minHeight: 16,
                            ),
                            child: Center(
                              child: Text(
                                '${cat.channelCount}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 7.5,
                                  fontWeight: FontWeight.w800,
                                  fontFamily: 'Inter',
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  Text(
                    cat.title.toUpperCase(),
                    style: TextStyle(
                      color: isActive ? const Color(0xFF00B4FF) : context.cTextSecondary,
                      fontSize: 8.5,
                      fontWeight: isActive ? FontWeight.w800 : FontWeight.w600,
                      fontFamily: 'Inter',
                      letterSpacing: 0.3,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _categoryFallback(String title) {
    return Center(
      child: Text(
        title.isNotEmpty ? title[0].toUpperCase() : 'T',
        style: const TextStyle(
          color: Color(0xFF00B4FF),
          fontSize: 16,
          fontWeight: FontWeight.bold,
          fontFamily: 'Inter',
        ),
      ),
    );
  }

  Widget _buildDudeGrid() {
    if (_dudeLoading && _dudeChannels.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFF00B4FF)),
      );
    }
    if (_dudeError && _dudeChannels.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.wifi_off_rounded, size: 40, color: context.cTextMuted),
            const SizedBox(height: 8),
            Text(
              'Failed to load channels',
              style: TextStyle(color: context.cTextSecondary, fontSize: 13, fontFamily: 'Inter'),
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: () => _fetchDudeCategories(),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00B4FF),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              child: const Text('Retry', style: TextStyle(color: Colors.white, fontSize: 11)),
            ),
          ],
        ),
      );
    }
    if (_dudeChannels.isEmpty) {
      return Center(
        child: Text(
          'No channels available',
          style: TextStyle(color: context.cTextMuted, fontFamily: 'Inter'),
        ),
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        childAspectRatio: 0.76,
        crossAxisSpacing: 6,
        mainAxisSpacing: 6,
      ),
      itemCount: _dudeChannels.length,
      itemBuilder: (ctx, idx) {
        final ch = _dudeChannels[idx];
        return GestureDetector(
          onTap: () => _showDudeSubChannelsSheet(ch),
          child: Container(
            decoration: BoxDecoration(
              color: context.cBgCard,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: context.cBorder, width: 0.8),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Expanded(
                  child: Container(
                    margin: const EdgeInsets.fromLTRB(6, 6, 6, 4),
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Center(
                      child: ch.image.isNotEmpty
                          ? CachedNetworkImage(
                              imageUrl: ch.image,
                              fit: BoxFit.contain,
                              placeholder: (_, __) => const SizedBox.shrink(),
                              errorWidget: (_, __, ___) => _channelTextLogo(ch.title),
                            )
                          : _channelTextLogo(ch.title),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 0, 4, 6),
                  child: Text(
                    ch.title,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: context.cTextPrimary,
                      fontSize: 8.5,
                      fontWeight: FontWeight.w600,
                      fontFamily: 'Inter',
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _channelTextLogo(String title) {
    return Text(
      title.isNotEmpty ? title[0].toUpperCase() : 'C',
      style: const TextStyle(
        color: Color(0xFF00B4FF),
        fontSize: 22,
        fontWeight: FontWeight.w900,
        fontFamily: 'Inter',
      ),
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    // Play request from match detail "Where to watch"
    ref.listen(tvPlayRequestProvider, (prev, next) => _handlePlayRequest(next));
    final pending = ref.read(tvPlayRequestProvider);
    if (pending != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _handlePlayRequest(pending));
    }
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (_, __) {
        if (_fullscreen) { _exitFullscreen(); return; }
        if (_playing != null) _closePlayer();
      },
      child: Scaffold(
        backgroundColor: context.cBg,
        body: SafeArea(
          child: Column(
            children: [
              if (_playing != null && !_fullscreen) _buildMiniPlayer(),
              _buildHeader(),
              _buildUnifiedCategories(),
              const SizedBox(height: 4),
              Expanded(child: _buildUnifiedGrid()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMiniPlayer() {
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: _PlayerStack(
        controller: _vpc,
        loading: _playerLoading,
        hasError: _playerError,
        channelName: _playing?.name ?? '',
        fullscreen: false,
        onClose: _closePlayer,
        onFullscreen: _enterFullscreen,
        onRetry: () { if (_playing != null) _play(_playing!); },
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
      child: Row(
        children: [
          Text('LIVE TV', style: TextStyle(
            color: context.cTextPrimary, fontSize: 16,
            fontWeight: FontWeight.w800, fontFamily: 'Inter', letterSpacing: 1,
          )),
          const SizedBox(width: 6),
          _checking
              ? const SizedBox(width: 10, height: 10,
                  child: CircularProgressIndicator(strokeWidth: 1.5, color: Color(0xFF00B4FF)))
              : Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFF00B4FF).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFF00B4FF).withValues(alpha: 0.3)),
                  ),
                  child: Text('$_liveCount live', style: const TextStyle(
                    color: Color(0xFF00B4FF), fontSize: 10,
                    fontWeight: FontWeight.w700, fontFamily: 'Inter',
                  )),
                ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _searchCtrl,
              onChanged: (v) => setState(() => _query = v),
              style: TextStyle(color: context.cTextPrimary, fontSize: 12, fontFamily: 'Inter'),
              decoration: InputDecoration(
                hintText: 'Search channels...',
                hintStyle: TextStyle(color: context.cTextMuted, fontSize: 12),
                prefixIcon: Icon(Icons.search_rounded, color: context.cTextMuted, size: 18),
                prefixIconConstraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
                filled: true,
                fillColor: context.cBgInput,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: context.cBorder)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: context.cBorder)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: Color(0xFF00B4FF), width: 1.2)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPills() {
    const items = [
      (null, 'ALL'),
      (TVCategory.Sports, 'SPORTS'),
      (TVCategory.Football, 'FOOTBALL'),
      (TVCategory.Cricket, 'CRICKET'),
      (TVCategory.Bangla, 'BANGLA'),
      (TVCategory.News, 'NEWS'),
      (TVCategory.Entertainment, 'ENTER.'),
    ];
    return SizedBox(
      height: 32,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: items.map((item) {
          final active = _cat == item.$1;
          return GestureDetector(
            onTap: () => setState(() => _cat = item.$1),
            child: Container(
              margin: const EdgeInsets.only(right: 6),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(
                color: active ? const Color(0xFF00B4FF) : context.cBgCard,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: active ? const Color(0xFF00B4FF) : context.cBorder,
                ),
              ),
              child: Text(item.$2, style: TextStyle(
                color: active ? Colors.white : context.cTextSecondary,
                fontSize: 10, fontWeight: FontWeight.w700,
                fontFamily: 'Inter', letterSpacing: 0.5,
              )),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildCategorizedListView() {
    const categories = [
      (TVCategory.Sports, 'SPORTS'),
      (TVCategory.Cricket, 'CRICKET'),
      (TVCategory.Football, 'FOOTBALL'),
      (TVCategory.Bangla, 'BANGLA'),
      (TVCategory.News, 'NEWS'),
      (TVCategory.Entertainment, 'ENTERTAINMENT'),
    ];

    final Map<TVCategory, List<TVChannel>> grouped = {};
    for (final cat in TVCategory.values) {
      grouped[cat] = [];
    }
    for (final ch in _filtered) {
      grouped[ch.category]?.add(ch);
    }

    final activeCategories = categories.where((item) => grouped[item.$1]?.isNotEmpty == true).toList();

    if (activeCategories.isEmpty) {
      return Center(child: Text('No channels match search',
          style: TextStyle(color: context.cTextMuted, fontFamily: 'Inter')));
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: activeCategories.length,
      itemBuilder: (ctx, catIdx) {
        final item = activeCategories[catIdx];
        final catEnum = item.$1;
        final catTitle = item.$2;
        final list = grouped[catEnum]!;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(
                children: [
                  Container(
                    width: 3, height: 12,
                    decoration: BoxDecoration(
                      gradient: AppColors.primaryGradient,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    catTitle,
                    style: TextStyle(
                      color: context.cTextPrimary,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      fontFamily: 'Inter',
                      letterSpacing: 0.8,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                    decoration: BoxDecoration(
                      color: context.cBgElevated,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '${list.length}',
                      style: TextStyle(color: context.cTextSecondary, fontSize: 8, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(
              height: 105,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: list.length,
                itemBuilder: (ctx, i) {
                  final ch = list[i];
                  final isActive = _playing?.id == ch.id;
                  final isWorking = ch.live || _workingIds.contains(ch.id);
                  return GestureDetector(
                    onTap: () => _play(ch),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: 90,
                      margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                      decoration: BoxDecoration(
                        color: isActive
                            ? const Color(0xFF00B4FF).withValues(alpha: 0.12)
                            : context.cBgCard,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: isActive
                              ? const Color(0xFF00B4FF)
                              : isWorking
                                  ? const Color(0xFF22C55E).withValues(alpha: 0.4)
                                  : context.cBorder,
                          width: isActive ? 1.5 : 1,
                        ),
                      ),
                      child: Stack(
                        children: [
                          Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.fromLTRB(6, 8, 6, 2),
                                  child: _ChannelLogo(logoUrl: ch.logoUrl, name: ch.name),
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.fromLTRB(4, 0, 4, 6),
                                child: Text(
                                  ch.name,
                                  textAlign: TextAlign.center,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: isActive ? const Color(0xFF00B4FF) : context.cTextPrimary,
                                    fontSize: 8.5,
                                    fontWeight: FontWeight.w600,
                                    fontFamily: 'Inter',
                                  ),
                                ),
                              ),
                            ],
                          ),
                          if (isWorking && !isActive)
                            const Positioned(top: 4, left: 4, child: _LiveBadge()),
                          if (isWorking && !isActive)
                            Positioned(
                              top: 4, right: 4,
                              child: Container(
                                width: 5, height: 5,
                                decoration: const BoxDecoration(
                                  color: Color(0xFF22C55E),
                                  shape: BoxShape.circle,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildGrid() {
    if (_cat == null) {
      return _buildCategorizedListView();
    }
    final channels = _filtered;
    if (channels.isEmpty) {
      return Center(child: Text('No channels',
          style: TextStyle(color: context.cTextMuted, fontFamily: 'Inter')));
    }
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3, childAspectRatio: 0.82,
        crossAxisSpacing: 8, mainAxisSpacing: 8,
      ),
      itemCount: channels.length,
      itemBuilder: (_, i) {
        final ch = channels[i];
        final isActive = _playing?.id == ch.id;
        final isWorking = ch.live || _workingIds.contains(ch.id);
        return GestureDetector(
          onTap: () => _play(ch),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            decoration: BoxDecoration(
              color: isActive
                  ? const Color(0xFF00B4FF).withValues(alpha: 0.12)
                  : context.cBgCard,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isActive
                    ? const Color(0xFF00B4FF)
                    : isWorking
                        ? const Color(0xFF22C55E).withValues(alpha: 0.4)
                        : context.cBorder,
                width: isActive ? 1.5 : 1,
              ),
            ),
            child: Stack(children: [
              Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(8, 10, 8, 4),
                    child: _ChannelLogo(logoUrl: ch.logoUrl, name: ch.name),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(6, 0, 6, 8),
                  child: Text(ch.name,
                    textAlign: TextAlign.center, maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: isActive ? const Color(0xFF00B4FF) : context.cTextPrimary,
                      fontSize: 9, fontWeight: FontWeight.w600, fontFamily: 'Inter',
                    )),
                ),
              ]),
              if (isWorking && !isActive)
                const Positioned(top: 5, left: 5, child: _LiveBadge()),
              if (isWorking && !isActive)
                Positioned(top: 5, right: 5,
                  child: Container(width: 6, height: 6,
                    decoration: const BoxDecoration(
                      color: Color(0xFF22C55E), shape: BoxShape.circle))),
            ]),
          ),
        );
      },
    );
  }

  // ─── Unified Category Circles (DUDE TV style) ───────────────────────────────

  static const _crifoCats = [
    (null, 'ALL', Icons.tv_rounded),
    (TVCategory.Sports, 'SPORTS', Icons.sports_rounded),
    (TVCategory.Cricket, 'CRICKET', Icons.sports_cricket_rounded),
    (TVCategory.Football, 'FOOTBALL', Icons.sports_soccer_rounded),
    (TVCategory.Bangla, 'BANGLA', Icons.language_rounded),
    (TVCategory.News, 'NEWS', Icons.newspaper_rounded),
    (TVCategory.Entertainment, 'ENTERTAIN', Icons.movie_rounded),
  ];

  Widget _buildUnifiedCategories() {
    return SizedBox(
      height: 88,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        children: [
          // CriFO static categories
          ..._crifoCats.map((item) {
            final isActive = _selectedCatKey == item.$1;
            final count = item.$1 == null
                ? _channels.length + _allDudeChannels.length
                : _channels.where((c) => c.category == item.$1).length;
            return _CategoryCircle(
              label: item.$2,
              icon: item.$3,
              isActive: isActive,
              count: count,
              onTap: () {
                setState(() {
                  _selectedCatKey = item.$1;
                  _dudeChannels = item.$1 == null ? _allDudeChannels : [];
                });
              },
            );
          }),
          // DUDE dynamic categories
          ..._dudeCategories.map((cat) {
            final isActive = _selectedCatKey == cat.id;
            return _CategoryCircle(
              label: cat.title.toUpperCase(),
              imageUrl: cat.image,
              isActive: isActive,
              count: cat.channelCount,
              onTap: () {
                setState(() {
                  _selectedCatKey = cat.id;
                  _selectedDudeCategory = cat;
                });
                _fetchDudeChannelsForCategory(cat);
              },
            );
          }),
          if (_dudeLoading && _dudeCategories.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20, vertical: 28),
              child: SizedBox(width: 20, height: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF00B4FF))),
            ),
        ],
      ),
    );
  }

  // ─── Unified 4-column Grid ────────────────────────────────────────────────

  Widget _buildUnifiedGrid() {
    final crifoChs = _filteredCrifo;
    final dudeChs = _filteredDude;

    final totalCount = crifoChs.length + dudeChs.length;

    if (totalCount == 0) {
      if (_dudeLoading) {
        return const Center(child: CircularProgressIndicator(color: Color(0xFF00B4FF)));
      }
      return Center(child: Text('No channels found',
          style: TextStyle(color: context.cTextMuted, fontFamily: 'Inter')));
    }

    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        childAspectRatio: 0.72,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemCount: totalCount,
      itemBuilder: (_, i) {
        if (i < crifoChs.length) {
          // CriFO channel card
          final ch = crifoChs[i];
          final isActive = _playing?.id == ch.id;
          final isWorking = ch.live || _workingIds.contains(ch.id);
          return GestureDetector(
            onTap: () => _play(ch),
            child: _UnifiedChannelCard(
              name: ch.name,
              imageUrl: ch.logoUrl,
              isActive: isActive,
              isLive: isWorking,
              isDude: false,
            ),
          );
        } else {
          // DUDE channel card
          final ch = dudeChs[i - crifoChs.length];
          final isActive = _playing?.id == '${ch.id}_playing';
          return GestureDetector(
            onTap: () => _showDudeSubChannelsSheet(ch),
            child: _UnifiedChannelCard(
              name: ch.title,
              imageUrl: ch.image,
              isActive: isActive,
              isLive: false,
              isDude: true,
            ),
          );
        }
      },
    );
  }
}


// ─── Fullscreen page ──────────────────────────────────────────────────────────

class _FullscreenPage extends StatelessWidget {
  final VideoPlayerController controller;
  final String channelName;
  final VoidCallback onExit;

  const _FullscreenPage({
    required this.controller,
    required this.channelName,
    required this.onExit,
  });

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final w = size.shortestSide;
    final h = size.longestSide;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (_, __) => onExit(),
      child: Material(
        color: Colors.black,
        child: SizedBox.expand(
          child: Center(
            child: OverflowBox(
              maxWidth: h, maxHeight: w,
              child: Transform.rotate(
                angle: math.pi / 2,
                child: SizedBox(
                  width: h, height: w,
                  child: _PlayerStack(
                    controller: controller,
                    loading: false,
                    hasError: false,
                    channelName: channelName,
                    fullscreen: true,
                    onClose: onExit,
                    onFullscreen: onExit,
                    onRetry: onExit,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Shared player widget ─────────────────────────────────────────────────────

class _PlayerStack extends StatelessWidget {
  final VideoPlayerController? controller;
  final bool loading;
  final bool hasError;
  final String channelName;
  final bool fullscreen;
  final VoidCallback onClose;
  final VoidCallback onFullscreen;
  final VoidCallback onRetry;

  const _PlayerStack({
    required this.controller,
    required this.loading,
    required this.hasError,
    required this.channelName,
    required this.fullscreen,
    required this.onClose,
    required this.onFullscreen,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final ctrl = controller;
    return Container(
      color: Colors.black,
      child: Stack(children: [
        // Video
        if (ctrl != null && ctrl.value.isInitialized)
          Center(
            child: AspectRatio(
              aspectRatio: ctrl.value.aspectRatio,
              child: VideoPlayer(ctrl),
            ),
          )
        else
          const SizedBox.expand(),

        // Loading overlay
        if (loading)
          Container(
            color: Colors.black,
            child: Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const SizedBox(width: 28, height: 28,
                  child: CircularProgressIndicator(color: Color(0xFF00B4FF), strokeWidth: 2.5)),
                const SizedBox(height: 10),
                Text(channelName, style: const TextStyle(
                  color: Color(0xFF8888AA), fontSize: 11,
                  fontFamily: 'Inter', fontWeight: FontWeight.w600)),
              ]),
            ),
          ),

        // Error state
        if (hasError || (ctrl != null && ctrl.value.hasError))
          Container(
            color: Colors.black,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.signal_wifi_off_rounded,
                        color: Color(0xFFFF5555), size: 36),
                  ),
                  const SizedBox(height: 12),
                  const Text('Stream unavailable', style: TextStyle(
                    color: Colors.white, fontSize: 14,
                    fontFamily: 'Inter', fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  const Text('This channel may be offline or geo-restricted.',
                    style: TextStyle(color: Color(0xFF8888AA), fontSize: 11,
                        fontFamily: 'Inter', height: 1.4),
                    textAlign: TextAlign.center),
                  const SizedBox(height: 16),
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    GestureDetector(
                      onTap: onClose,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF333355),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Text('Close', style: TextStyle(
                          color: Color(0xFF8888CC), fontSize: 12,
                          fontWeight: FontWeight.w600, fontFamily: 'Inter')),
                      ),
                    ),
                    const SizedBox(width: 10),
                    GestureDetector(
                      onTap: onRetry,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF00B4FF),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.refresh_rounded, color: Colors.white, size: 14),
                          SizedBox(width: 4),
                          Text('Retry', style: TextStyle(
                            color: Colors.white, fontSize: 12,
                            fontWeight: FontWeight.w700, fontFamily: 'Inter')),
                        ]),
                      ),
                    ),
                  ]),
                ]),
              ),
            ),
          ),

        // Controls bar
        Positioned(top: 8, left: 8, right: 8,
          child: Row(children: [
            _CtrlBtn(icon: Icons.close_rounded, onTap: onClose),
            const Spacer(),
            if (channelName.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFF00B4FF).withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Container(width: 5, height: 5,
                    decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle)),
                  const SizedBox(width: 5),
                  Text(channelName, style: const TextStyle(
                    color: Colors.white, fontSize: 10,
                    fontWeight: FontWeight.w700, fontFamily: 'Inter')),
                ]),
              ),
            const Spacer(),
            _CtrlBtn(
              icon: fullscreen ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded,
              onTap: onFullscreen,
            ),
          ]),
        ),
      ]),
    );
  }
}

// Compact red "● LIVE" badge shown on channels confirmed reachable.
class _LiveBadge extends StatelessWidget {
  const _LiveBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1.5),
      decoration: BoxDecoration(
        color: const Color(0xFFE21B22),
        borderRadius: BorderRadius.circular(4),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFE21B22).withValues(alpha: 0.5),
            blurRadius: 4,
          ),
        ],
      ),
      child: const Row(mainAxisSize: MainAxisSize.min, children: [
        SizedBox(
          width: 3.5, height: 3.5,
          child: DecoratedBox(
            decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle),
          ),
        ),
        SizedBox(width: 3),
        Text('LIVE', style: TextStyle(
          color: Colors.white, fontSize: 6.5, height: 1,
          fontWeight: FontWeight.w800, fontFamily: 'Inter', letterSpacing: 0.3,
        )),
      ]),
    );
  }
}

class _CtrlBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _CtrlBtn({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 30, height: 30,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.65),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
        ),
        child: Icon(icon, color: Colors.white, size: 17),
      ),
    );
  }
}

// ─── Channel logo ─────────────────────────────────────────────────────────────

class _ChannelLogo extends StatelessWidget {
  final String logoUrl;
  final String name;
  const _ChannelLogo({required this.logoUrl, required this.name});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Container(
        color: context.cBgElevated,
        child: logoUrl.isNotEmpty
            ? Image.network(logoUrl, fit: BoxFit.contain,
                width: double.infinity, height: double.infinity,
                loadingBuilder: (_, child, p) => p == null ? child : _initial(),
                errorBuilder: (_, __, ___) => _initial())
            : _initial(),
      ),
    );
  }

  Widget _initial() {
    return Center(child: Text(
      name.isNotEmpty ? name[0].toUpperCase() : 'T',
      style: const TextStyle(color: Color(0xFF00B4FF), fontSize: 24,
          fontWeight: FontWeight.w800, fontFamily: 'Inter'),
    ));
  }
}

// --- Category Circle (DUDE TV style) -----------------------------------------

class _CategoryCircle extends StatelessWidget {
  final String label;
  final IconData? icon;
  final String? imageUrl;
  final bool isActive;
  final int count;
  final VoidCallback onTap;

  const _CategoryCircle({
    required this.label,
    this.icon,
    this.imageUrl,
    required this.isActive,
    required this.count,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 68,
        margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isActive
                        ? const Color(0xFF00B4FF).withValues(alpha: 0.18)
                        : context.cBgCard,
                    border: Border.all(
                      color: isActive ? const Color(0xFF00B4FF) : context.cBorder,
                      width: isActive ? 2.2 : 1,
                    ),
                    boxShadow: isActive
                        ? [BoxShadow(color: const Color(0xFF00B4FF).withValues(alpha: 0.35), blurRadius: 10, spreadRadius: 1)]
                        : null,
                  ),
                  child: ClipOval(
                    child: imageUrl != null && imageUrl!.isNotEmpty
                        ? Image.network(imageUrl!, fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => _iconFallback(context))
                        : _iconFallback(context),
                  ),
                ),
                if (count > 0)
                  Positioned(
                    top: -3,
                    right: -3,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEF4444),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: context.cBg, width: 1),
                      ),
                      child: Text(
                        count > 99 ? '99+' : '$count',
                        style: const TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.w800),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 5),
            Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: isActive ? const Color(0xFF00B4FF) : context.cTextSecondary,
                fontSize: 9,
                fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                fontFamily: 'Inter',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _iconFallback(BuildContext context) {
    return Container(
      color: context.cBgElevated,
      child: Icon(
        icon ?? Icons.live_tv_rounded,
        color: const Color(0xFF00B4FF),
        size: 24,
      ),
    );
  }
}

// --- Unified Channel Card (4-column DUDE TV style) ---------------------------

class _UnifiedChannelCard extends StatelessWidget {
  final String name;
  final String? imageUrl;
  final bool isActive;
  final bool isLive;
  final bool isDude;

  const _UnifiedChannelCard({
    required this.name,
    this.imageUrl,
    required this.isActive,
    required this.isLive,
    required this.isDude,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        color: isActive
            ? const Color(0xFF00B4FF).withValues(alpha: 0.12)
            : context.cBgCard,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isActive
              ? const Color(0xFF00B4FF)
              : isLive
                  ? const Color(0xFF22C55E).withValues(alpha: 0.5)
                  : context.cBorder,
          width: isActive ? 1.5 : 1,
        ),
      ),
      child: Stack(
        children: [
          Column(
            children: [
              Expanded(
                child: Container(
                  width: double.infinity,
                  margin: const EdgeInsets.fromLTRB(6, 8, 6, 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: _buildLogo(context),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(5, 0, 5, 6),
                child: Text(
                  name,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: isActive ? const Color(0xFF00B4FF) : context.cTextPrimary,
                    fontSize: 8.5,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'Inter',
                  ),
                ),
              ),
            ],
          ),
          if (isLive && !isDude && !isActive)
            const Positioned(
              top: 5, right: 5,
              child: SizedBox(width: 6, height: 6,
                child: DecoratedBox(
                  decoration: BoxDecoration(color: Color(0xFF22C55E), shape: BoxShape.circle),
                ),
              ),
            ),
          if (isDude)
            Positioned(
              top: 4, left: 4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                decoration: BoxDecoration(
                  color: const Color(0xFF00B4FF).withValues(alpha: 0.85),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: const Text('HD', style: TextStyle(color: Colors.white, fontSize: 6, fontWeight: FontWeight.w800)),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildLogo(BuildContext context) {
    final url = imageUrl;
    if (url != null && url.isNotEmpty) {
      return CachedNetworkImage(
        imageUrl: url,
        fit: BoxFit.contain,
        placeholder: (_, __) => const SizedBox.shrink(),
        errorWidget: (_, __, ___) => _textFallback(context),
        httpHeaders: const {
          'User-Agent': 'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36',
          'Referer': 'https://mdjamsad9.github.io/',
        },
      );
    }
    return _textFallback(context);
  }

  Widget _textFallback(BuildContext context) {
    return Center(
      child: Text(
        name.isNotEmpty ? name[0].toUpperCase() : 'TV',
        style: const TextStyle(
          color: Color(0xFF00B4FF), fontSize: 20,
          fontWeight: FontWeight.w800, fontFamily: 'Inter',
        ),
      ),
    );
  }
}
