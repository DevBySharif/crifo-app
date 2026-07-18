import 'dart:async';
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
import '../../core/providers/tv_live_count_provider.dart';
import '../../core/widgets/skeleton.dart';
import '../../core/services/drm_player.dart';

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
  final toCheck = channels.take(50).toList();
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
  final DrmPlayerService _drmPlayer = DrmPlayerService();
  int? _drmTextureId;
  bool _isDrmPlaying = false;
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
  bool _useGridView = true;

  // --- DUDE TV State ---
  List<DudeCategory> _dudeCategories = [];
  DudeCategory? _selectedDudeCategory;
  List<DudeChannel> _dudeChannels = [];
  bool _dudeLoading = false;
  bool _dudeLoadingAll = false;
  bool _dudeError = false;
  final Map<String, List<DudeChannel>> _dudeChannelsCache = {};
  List<DudeChannel> _allDudeChannels = []; // all loaded dude channels merged

  // unified category: null = All, TVCategory = crifo cat, String = dude cat id
  Object? _selectedCatKey; // null | TVCategory | String(DudeCategory.id)
  final _pageController = PageController();

  // Strip trailing numbers / HD / FHD etc. to get base channel name for grouping.
  String _channelBaseName(String name) {
    var s = name.trim();
    // strip quality suffixes
    s = s.replaceAll(RegExp(r'\s*(HD|FHD|4K|UHD|HDR|HQ|LQ|SD|1080p|720p|480p)\s*$', caseSensitive: false), '');
    // strip trailing numbers
    s = s.replaceAll(RegExp(r'\s+\d+$'), '');
    // strip parenthesized variants (Backup), (Opcion 1), etc
    s = s.replaceAll(RegExp(r'\s*\([^)]*\)'), '');
    // strip leading junk
    s = s.replaceAll(RegExp(r'^[|\-\s:]+'), '');
    // strip trailing HD/FHD that may re-appear after stripping parens
    s = s.replaceAll(RegExp(r'\s*(HD|FHD)\s*$', caseSensitive: false), '');
    return s.trim();
  }

  // Group channels by base name. Returns list of (baseName, list-of-channels).
  List<(String, List<TVChannel>)> _groupChannels(List<TVChannel> channels) {
    final Map<String, List<TVChannel>> groups = {};
    for (final ch in channels) {
      final key = _channelBaseName(ch.name).toLowerCase();
      groups.putIfAbsent(key, () => []).add(ch);
    }
    final result = groups.entries
        .map((e) => (e.value.first.name, e.value))
        .toList();
    result.sort((a, b) => a.$1.compareTo(b.$1));
    return result;
  }

  @override
  void initState() {
    super.initState();
    _pageController.addListener(_onPageChanged);
    _loadRemoteThenCheck();
    _fetchDudeCategories();
    WidgetsBinding.instance.addPostFrameCallback((_) => _reportLiveCount());
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
    _pageController.removeListener(_onPageChanged);
    _pageController.dispose();
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
    _reportLiveCount();
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
            _dudeLoadingAll = true;
          });
          if (parsed.isNotEmpty) {
            await _fetchDudeChannelsForCategory(parsed.first);
          }
          _loadAllDudeChannelsInBackground(parsed);
        }
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

  Future<void> _loadAllDudeChannelsInBackground(List<DudeCategory> categories) async {
    for (final cat in categories) {
      if (!mounted) return;
      if (_dudeChannelsCache.containsKey(cat.catLink)) continue;
      try {
        await _fetchDudeChannelsForCategory(cat);
      } catch (_) {}
    }
    if (mounted) {
      setState(() => _dudeLoadingAll = false);
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
        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: context.cBorder, width: 0.8),
                      ),
                      child: ListTile(
                        leading: Container(
                          width: 36,
                          height: 36,
                          padding: const EdgeInsets.all(5),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFF00B4FF), Color(0xFF0077FF)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(8),
                            boxShadow: [BoxShadow(color: const Color(0xFF00B4FF).withValues(alpha: 0.3), blurRadius: 4)],
                          ),
                          child: Center(
                            child: fmt.logo.isNotEmpty
                                ? CachedNetworkImage(
                                    imageUrl: fmt.logo,
                                    fit: BoxFit.contain,
                                    color: Colors.white,
                                    errorWidget: (_, __, ___) => const Icon(
                                        Icons.tv_rounded,
                                        size: 16,
                                        color: Colors.white),
                                  )
                                : const Icon(Icons.tv_rounded,
                                    size: 16, color: Colors.white),
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

        // type=0: plain HLS — use video_player
        final hlsStreams = streams.where((s) => s.type == '0' && s.link.isNotEmpty).toList();

        // type=1: Widevine DRM — use native ExoPlayer with DRM
        final drmStreams = streams.where((s) => s.type == '1' && s.link.isNotEmpty).toList();

        // Prefer stream matching the selected format title
        final matchedHls = hlsStreams
            .where((s) => s.title.toLowerCase() == fmt.title.toLowerCase())
            .toList();
        final matchedDrm = drmStreams
            .where((s) => s.title.toLowerCase() == fmt.title.toLowerCase())
            .toList();

        // Try HLS first, then fall back to DRM
        if (matchedHls.isNotEmpty || hlsStreams.isNotEmpty) {
          final chosen = matchedHls.isNotEmpty ? matchedHls.first : hlsStreams.first;
          final tvCh = TVChannel(
            id: '${ch.id}_${chosen.title}',
            name: '${ch.title} - ${chosen.title}',
            category: categoryFromString(ch.category),
            streamUrl: chosen.link,
            logoUrl: ch.image,
          );
          _play(tvCh);
        } else if (matchedDrm.isNotEmpty || drmStreams.isNotEmpty) {
          final chosen = matchedDrm.isNotEmpty ? matchedDrm.first : drmStreams.first;
          _playDrm(
            url: chosen.link,
            api: chosen.api,
            channelName: '${ch.title} - ${chosen.title}',
            channelImage: ch.image,
          );
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

  void _showChannelGroupSheet(String name, List<TVChannel> channels) {
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
                width: 40, height: 4,
                decoration: BoxDecoration(
                  color: context.cBorder,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 12),
              Text(name.toUpperCase(), style: TextStyle(
                color: context.cTextPrimary,
                fontSize: 14, fontWeight: FontWeight.bold, fontFamily: 'Inter', letterSpacing: 0.5,
              )),
              const SizedBox(height: 6),
              Text('${channels.length} channels', style: TextStyle(
                color: context.cTextMuted, fontSize: 11, fontFamily: 'Inter',
              )),
              const SizedBox(height: 14),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: channels.length,
                  itemBuilder: (subCtx, subIdx) {
                    final subCh = channels[subIdx];
                    final isWorking = subCh.live || _workingIds.contains(subCh.id);
                    return Container(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      decoration: BoxDecoration(
                        color: context.cBgElevated,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: isWorking
                            ? const Color(0xFF22C55E).withValues(alpha: 0.4)
                            : context.cBorder, width: 0.8),
                      ),
                      child: ListTile(
                        leading: Container(
                          width: 36, height: 36,
                          padding: const EdgeInsets.all(5),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFF00B4FF), Color(0xFF0077FF)],
                              begin: Alignment.topLeft, end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Center(
                            child: subCh.logoUrl.isNotEmpty
                                ? CachedNetworkImage(
                                    imageUrl: subCh.logoUrl,
                                    fit: BoxFit.contain,
                                    color: Colors.white,
                                    errorWidget: (_, __, ___) => const Icon(Icons.tv_rounded, size: 16, color: Colors.white),
                                  )
                                : const Icon(Icons.tv_rounded, size: 16, color: Colors.white),
                          ),
                        ),
                        title: Text(subCh.name, style: TextStyle(
                          color: context.cTextPrimary, fontSize: 12, fontWeight: FontWeight.bold, fontFamily: 'Inter',
                        )),
                        subtitle: isWorking
                            ? Row(
                                children: [
                                  Container(
                                    width: 6, height: 6,
                                    decoration: const BoxDecoration(
                                      color: Color(0xFF22C55E), shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  Text('LIVE', style: TextStyle(
                                    color: const Color(0xFF22C55E), fontSize: 9, fontWeight: FontWeight.w700,
                                  )),
                                ],
                              )
                            : null,
                        trailing: const Icon(Icons.play_circle_fill_rounded, color: Color(0xFF00B4FF), size: 24),
                        onTap: () {
                          Navigator.pop(ctx);
                          _play(subCh);
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

  // Live = server-verified reachable this cycle, or confirmed by client check.
  int get _liveCount =>
      _channels.where((c) => c.live || _workingIds.contains(c.id)).length;

  void _reportLiveCount() {
    ref.read(tvLiveCountProvider.notifier).state = _liveCount;
  }

  // Unified filtered list: CriFO + DUDE channels based on selected category
  // Working/live channels sorted first.
  List<TVChannel> get _filteredCrifo {
    final filtered = _channels.where((c) {
      if (_selectedCatKey is TVCategory && c.category != _selectedCatKey) return false;
      if (_selectedCatKey is String) return false;
      if (_query.isNotEmpty && !c.name.toLowerCase().contains(_query.toLowerCase())) return false;
      return true;
    }).toList();
    filtered.sort((a, b) {
      final aWorking = a.live || _workingIds.contains(a.id);
      final bWorking = b.live || _workingIds.contains(b.id);
      if (aWorking && !bWorking) return -1;
      if (!aWorking && bWorking) return 1;
      return 0;
    });
    return filtered;
  }

  List<DudeChannel> get _filteredDude {
    if (_selectedCatKey is TVCategory) {
      final catName = (_selectedCatKey as TVCategory).name.toLowerCase();
      return _allDudeChannels.where((c) {
        final chCat = c.category.toLowerCase();
        final chTitle = c.title.toLowerCase();
        // exact match on category field
        if (chCat == catName) return true;
        // broader match: category or title contains the keyword
        if (chCat.contains(catName) || chTitle.contains(catName)) return true;
        // football also matches "soccer"
        if (catName == 'football' && (chCat.contains('soccer') || chTitle.contains('soccer'))) return true;
        return false;
      }).toList();
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

  StreamSubscription<Map<String, dynamic>>? _drmSub;

  Future<void> _playDrm({required String url, String api = '', required String channelName, required String channelImage}) async {
    final token = ++_playToken;
    _drmSub?.cancel();
    setState(() {
      _playing = TVChannel(
        id: 'drm_$token',
        name: channelName,
        category: TVCategory.Sports,
        streamUrl: url,
        logoUrl: channelImage,
      );
      _isDrmPlaying = true;
      _playerLoading = true;
      _playerError = false;
      _fullscreen = false;
      _drmTextureId = null;
    });
    _vpc?.dispose();
    _vpc = null;

    try {
      await _drmPlayer.play(url, api: api);
      if (token != _playToken || !mounted) return;

      // Show texture immediately — player is buffering
      setState(() {
        _drmTextureId = _drmPlayer.textureId;
      });

      // Listen for events asynchronously
      _drmSub = _drmPlayer.events.listen((e) {
        if (token != _playToken || !mounted) return;
        if (e['type'] == 'ready') {
          setState(() => _playerLoading = false);
        } else if (e['type'] == 'error') {
          final errMsg = e['error']?.toString() ?? 'Unknown error';
          setState(() {
            _playerLoading = false;
            _playerError = true;
            _isDrmPlaying = false;
          });
          if (mounted) _showErrorSnackBar('DRM Error: $errMsg');
        }
      });

      // Timeout safeguard
      Future.delayed(const Duration(seconds: 15), () {
        if (token != _playToken || !mounted || !_playerLoading) return;
        setState(() {
          _playerLoading = false;
          _playerError = true;
          _isDrmPlaying = false;
        });
        _showErrorSnackBar('DRM player timed out.');
      });
    } catch (e) {
      if (token != _playToken || !mounted) return;
      setState(() {
        _playerLoading = false;
        _playerError = true;
        _isDrmPlaying = false;
      });
      _showErrorSnackBar('DRM Error: ${e.toString()}');
    }
  }

  void _closePlayer() {
    _playToken++;
    _exitFullscreen();
    _vpc?.dispose();
    _drmSub?.cancel();
    _drmSub = null;
    _drmPlayer.dispose();
    setState(() {
      _playing = null;
      _vpc = null;
      _playerLoading = false;
      _playerError = false;
      _fullscreen = false;
      _isDrmPlaying = false;
      _drmTextureId = null;
    });
  }

  void _enterFullscreen() {
    final vpc = _vpc;
    final ch = _playing;
    if (ch == null) return;
    if (vpc == null && !_isDrmPlaying) return;

    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    setState(() => _fullscreen = true);

    ref.read(tvFullscreenProvider.notifier).state = _FullscreenPage(
      controller: vpc,
      textureId: _drmTextureId,
      isDrm: _isDrmPlaying,
      channelName: ch.name,
      streamUrl: ch.streamUrl,
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
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        childAspectRatio: 0.68,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
      ),
      itemCount: _dudeChannels.length,
      itemBuilder: (ctx, idx) {
        final ch = _dudeChannels[idx];
        return GestureDetector(
          onTap: () => _showDudeSubChannelsSheet(ch),
          child: _UnifiedChannelCard(
            name: ch.title,
            imageUrl: ch.image,
            isActive: false,
            isLive: false,
            isDude: true,
          ),
        );
      },
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
              Expanded(
                child: RefreshIndicator(
                  color: AppColors.accentPrimary,
                  backgroundColor: context.cBgCard,
                  onRefresh: () async {
                    await _loadRemoteThenCheck();
                    _reportLiveCount();
                  },
                  child: _buildUnifiedGrid(),
                ),
              ),
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
        textureId: _drmTextureId,
        isDrm: _isDrmPlaying,
        streamUrl: _playing?.streamUrl,
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
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
      child: Row(
        children: [
          ShaderMask(
            shaderCallback: (bounds) => AppColors.primaryGradient.createShader(bounds),
            child: const Text('LIVE TV', style: TextStyle(
              color: Colors.white, fontSize: 18,
              fontWeight: FontWeight.w900, fontFamily: 'Inter', letterSpacing: 1.5,
            )),
          ),
          const SizedBox(width: 8),
          _checking
              ? const SizedBox(width: 12, height: 12,
                  child: CircularProgressIndicator(strokeWidth: 1.5, color: Color(0xFF00B4FF)))
              : Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        const Color(0xFF00B4FF).withValues(alpha: 0.2),
                        const Color(0xFF0077FF).withValues(alpha: 0.1),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFF00B4FF).withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 5, height: 5,
                        decoration: const BoxDecoration(
                          color: Color(0xFF22C55E),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text('$_liveCount live', style: const TextStyle(
                        color: Color(0xFF00B4FF), fontSize: 10,
                        fontWeight: FontWeight.w700, fontFamily: 'Inter',
                      )),
                    ],
                  ),
                ),
          const SizedBox(width: 6),
          // View toggle
          GestureDetector(
            onTap: () => setState(() => _useGridView = !_useGridView),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: context.cBgCard,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: context.cBorder),
              ),
              child: Icon(
                _useGridView ? Icons.list_rounded : Icons.grid_view_rounded,
                color: context.cTextSecondary, size: 16,
              ),
            ),
          ),
          const SizedBox(width: 6),
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
    (null, 'ALL'),
    (TVCategory.Sports, 'SPORTS'),
    (TVCategory.Cricket, 'CRICKET'),
    (TVCategory.Football, 'FOOTBALL'),
    (TVCategory.Bangla, 'BANGLA'),
    (TVCategory.News, 'NEWS'),
    (TVCategory.Entertainment, 'ENTERTAIN'),
  ];

  Widget _buildUnifiedCategories() {
    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        children: [
          ..._crifoCats.map((item) {
            final isActive = _selectedCatKey == item.$1;
            return _CategoryChip(
              label: item.$2,
              isActive: isActive,
              onTap: () => _selectCategory(item.$1),
            );
          }),
          ..._dudeCategories.map((cat) {
            final isActive = _selectedCatKey == cat.id;
            return _CategoryChip(
              label: cat.title.toUpperCase(),
              isActive: isActive,
              onTap: () => _selectCategory(cat.id),
            );
          }),
          if (_dudeLoading && _dudeCategories.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              child: SizedBox(width: 16, height: 16,
                child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF00B4FF))),
            ),
        ],
      ),
    );
  }

  // ─── Swipe category navigation ───────────────────────────────────────────

  List<Object?> _allCategoryKeys() {
    final keys = <Object?>[];
    for (final item in _crifoCats) keys.add(item.$1);
    for (final cat in _dudeCategories) keys.add(cat.id);
    return keys;
  }

  void _selectNextCategory() {
    final keys = _allCategoryKeys();
    final idx = keys.indexOf(_selectedCatKey);
    if (idx < keys.length - 1) _selectCategory(keys[idx + 1]);
  }

  void _selectPreviousCategory() {
    final keys = _allCategoryKeys();
    final idx = keys.indexOf(_selectedCatKey);
    if (idx > 0) _selectCategory(keys[idx - 1]);
  }

  void _onPageChanged() {
    final page = _pageController.page?.round() ?? 0;
    final keys = _allCategoryKeys();
    if (page < 0 || page >= keys.length) return;
    final newKey = keys[page];
    if (newKey == _selectedCatKey) return;
    setState(() {
      _selectedCatKey = newKey;
      if (newKey == null) {
        _selectedDudeCategory = null;
        _dudeChannels = List.from(_allDudeChannels);
      } else if (newKey is String) {
        final cat = _dudeCategories.where((c) => c.id == newKey).firstOrNull;
        if (cat != null) {
          _selectedDudeCategory = cat;
          _dudeChannels = [];
          _fetchDudeChannelsForCategory(cat);
        } else {
          _selectedDudeCategory = null;
          _dudeChannels = [];
        }
      } else {
        _selectedDudeCategory = null;
        _dudeChannels = [];
      }
    });
  }

  void _selectCategory(Object? key) {
    final keys = _allCategoryKeys();
    final idx = keys.indexOf(key);
    if (idx >= 0) {
      _pageController.animateToPage(
        idx, duration: const Duration(milliseconds: 250), curve: Curves.easeOut,
      );
    }
  }

  String _categoryLabel(Object? key) {
    if (key == null) return 'ALL';
    if (key is TVCategory) return key.name.toUpperCase();
    return key.toString();
  }

  // ─── Unified Grid (PageView) ──────────────────────────────────────────────

  Widget _buildUnifiedGrid() {
    final keys = _allCategoryKeys();
    if (keys.isEmpty) {
      if (_dudeLoading) return const Center(
          child: CircularProgressIndicator(color: Color(0xFF00B4FF)));
      return Center(child: Text('No channels found',
          style: TextStyle(color: context.cTextMuted, fontFamily: 'Inter')));
    }
    return PageView(
      controller: _pageController,
      children: [
        for (final k in keys) _buildCategoryGrid(k),
      ],
    );
  }

  Widget _buildCategoryGrid(Object? catKey) {
    if (_dudeLoading && _allDudeChannels.isEmpty) {
      return _buildSkeletonGrid();
    }
    List<TVChannel> crifoChs;
    List<DudeChannel> dudeChs;
      crifoChs = _channels.where((c) => c.category == catKey).toList();
      final cn = catKey.name.toLowerCase();
      dudeChs = _allDudeChannels.where((c) {
        final chCat = c.category.toLowerCase();
        final chTitle = c.title.toLowerCase();
        if (chCat == cn || chCat.contains(cn) || chTitle.contains(cn)) return true;
        if (cn == 'football' && (chCat.contains('soccer') || chTitle.contains('soccer'))) return true;
        return false;
      }).toList();
    } else {
      crifoChs = [];
      dudeChs = _dudeChannelsCache[catKey] ?? [];
    }

    final grps = _groupChannels(crifoChs);
    final total = grps.length + dudeChs.length;
    if (total == 0) {
      return Center(child: Text('No channels found',
          style: TextStyle(color: context.cTextMuted, fontFamily: 'Inter')));
    }

    final entries = <_GridEntry>[];
    for (final g in grps) {
      final anyWorking = g.$2.any((c) => c.live || _workingIds.contains(c.id));
      entries.add(_GridEntry(
        name: g.$1, image: g.$2.first.logoUrl, channels: g.$2,
        isGroup: g.$2.length > 1, isDude: false, isLive: anyWorking,
      ));
    }
    for (final d in dudeChs) {
      entries.add(_GridEntry(
        name: d.title, image: d.image, channels: [], isGroup: false,
        isDude: true, isLive: false, dude: d,
      ));
    }
    entries.sort((a, b) {
      if (a.isLive && !b.isLive) return -1;
      if (!a.isLive && b.isLive) return 1;
      return 0;
    });

    if (_useGridView) {
      return _buildGridChannels(entries);
    }
    return _buildListChannels(entries);
  }

  Widget _buildSkeletonGrid() {
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 90),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4, childAspectRatio: 1.0,
        crossAxisSpacing: 8, mainAxisSpacing: 8,
      ),
      itemCount: 12,
      itemBuilder: (_, i) => const SkeletonBlock(height: double.infinity, borderRadius: 10),
    );
  }

  Widget _buildGridChannels(List<_GridEntry> entries) {
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 90),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4, childAspectRatio: 1.0,
        crossAxisSpacing: 8, mainAxisSpacing: 8,
      ),
      itemCount: entries.length,
      itemBuilder: (_, i) {
        final e = entries[i];
        if (e.isDude) {
          final active = _playing?.id == '${e.dude!.id}_playing';
          return GestureDetector(
            onTap: () => _showDudeSubChannelsSheet(e.dude!),
            child: _UnifiedChannelCard(
              name: e.name, imageUrl: e.image,
              isActive: active, isLive: false, isDude: true,
            ),
          );
        }
        if (e.isGroup) {
          return _GroupedChannelCard(
            name: e.name, imageUrl: e.image,
            count: e.channels.length,
            onTap: () => _showChannelGroupSheet(e.name, e.channels),
          );
        }
        final ch = e.channels.first;
        return GestureDetector(
          onTap: () => _play(ch),
          child: _UnifiedChannelCard(
            name: ch.name, imageUrl: e.image,
            isActive: _playing?.id == ch.id,
            isLive: ch.live || _workingIds.contains(ch.id),
            isDude: false,
          ),
        );
      },
    );
  }

  Widget _buildListChannels(List<_GridEntry> entries) {
    final sorted = entries.map((e) => e.name).toSet().toList()..sort();
    final letters = sorted.map((n) => n[0].toUpperCase()).toSet().toList()..sort();
    return Stack(
      children: [
        ListView.builder(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 90),
          itemCount: entries.length,
          itemBuilder: (_, i) {
            final e = entries[i];
            final showLetter = i == 0 || e.name[0].toUpperCase() != entries[i - 1].name[0].toUpperCase();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (showLetter)
                  Padding(
                    padding: const EdgeInsets.only(top: 8, bottom: 4),
                    child: Text(e.name[0].toUpperCase(), style: TextStyle(
                      color: AppColors.accentPrimary, fontSize: 13,
                      fontWeight: FontWeight.w800, fontFamily: 'Inter',
                    )),
                  ),
                GestureDetector(
                  onTap: () {
                    if (e.isDude && e.dude != null) {
                      _showDudeSubChannelsSheet(e.dude!);
                    } else if (e.isGroup) {
                      _showChannelGroupSheet(e.name, e.channels);
                    } else {
                      _play(e.channels.first);
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    margin: const EdgeInsets.symmetric(vertical: 2),
                    decoration: BoxDecoration(
                      color: context.cBgCard,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: context.cBorder.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 32, height: 32,
                          decoration: BoxDecoration(
                            color: context.cBgElevated,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Center(
                            child: e.image != null && e.image != 'o'
                                ? ClipRRect(
                                    borderRadius: BorderRadius.circular(4),
                                    child: Image.network(e.image!, width: 24, height: 24, fit: BoxFit.contain,
                                      errorBuilder: (_, __, ___) => Text(e.name[0].toUpperCase(),
                                        style: const TextStyle(color: Color(0xFF00B4FF), fontSize: 14, fontWeight: FontWeight.w700)),
                                    ),
                                  )
                                : Text(e.name[0].toUpperCase(),
                                    style: const TextStyle(color: Color(0xFF00B4FF), fontSize: 14, fontWeight: FontWeight.w700)),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(e.name, style: TextStyle(
                            color: context.cTextPrimary, fontSize: 12,
                            fontWeight: FontWeight.w600, fontFamily: 'Inter',
                          ), maxLines: 1, overflow: TextOverflow.ellipsis),
                        ),
                        if (e.isGroup)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.accentPrimary.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text('${e.channels.length}', style: const TextStyle(
                              color: AppColors.accentPrimary, fontSize: 9, fontWeight: FontWeight.w700)),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
        if (letters.length > 3 && !_query.isEmpty)
          Positioned(
            right: 2, top: 0, bottom: 0,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: letters.map((l) {
                return GestureDetector(
                  onTap: () {
                    final idx = entries.indexWhere((e) => e.name[0].toUpperCase() == l);
                    if (idx >= 0) {
                      if (context.findAncestorStateOfType<ScrollableState>() case final s?) {
                        s.position.jumpTo(idx * 56.0);
                      }
                    }
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1.5),
                    child: Text(l, style: TextStyle(
                      color: AppColors.accentPrimary, fontSize: 9,
                      fontWeight: FontWeight.w700, fontFamily: 'Inter',
                    )),
                  ),
                );
              }).toList(),
            ),
          ),
      ],
    );
  }
}

class _GridEntry {
  final String name;
  final String? image;
  final List<TVChannel> channels;
  final bool isGroup;
  final bool isDude;
  final bool isLive;
  final DudeChannel? dude;
  _GridEntry({
    required this.name, this.image,
    required this.channels,
    required this.isGroup, required this.isDude, required this.isLive,
    this.dude,
  });
}


// ─── Fullscreen page ──────────────────────────────────────────────────────────

class _FullscreenPage extends StatelessWidget {
  final VideoPlayerController? controller;
  final int? textureId;
  final bool isDrm;
  final String channelName;
  final String? streamUrl;
  final VoidCallback onExit;

  const _FullscreenPage({
    this.controller,
    this.textureId,
    this.isDrm = false,
    required this.channelName,
    this.streamUrl,
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
                    textureId: textureId,
                    isDrm: isDrm,
                    streamUrl: streamUrl,
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
  final int? textureId;
  final bool isDrm;
  final bool loading;
  final bool hasError;
  final String channelName;
  final bool fullscreen;
  final String? streamUrl;
  final VoidCallback onClose;
  final VoidCallback onFullscreen;
  final VoidCallback onRetry;

  const _PlayerStack({
    this.controller,
    this.textureId,
    this.isDrm = false,
    this.streamUrl,
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
    final tid = textureId;
    return Container(
      color: Colors.black,
      child: Stack(children: [
        // Video (non-DRM)
        if (ctrl != null && ctrl.value.isInitialized)
          Center(
            child: AspectRatio(
              aspectRatio: ctrl.value.aspectRatio,
              child: VideoPlayer(ctrl),
            ),
          ),
        // Video (DRM via native texture)
        if (tid != null && isDrm)
          Center(
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: Texture(textureId: tid),
            ),
          ),
        if (ctrl == null && tid == null)
          const SizedBox.expand(),

        // Loading overlay (transparent bg for DRM so texture shows through)
        if (loading)
          Container(
            color: isDrm ? Colors.transparent : Colors.black,
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
            color: isDrm ? Colors.black87 : Colors.black,
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
            if (streamUrl != null && streamUrl!.isNotEmpty)
              _CtrlBtn(
                icon: Icons.copy_rounded,
                onTap: () {
                  Clipboard.setData(ClipboardData(text: streamUrl!));
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'Stream URL copied',
                        style: const TextStyle(
                            color: Colors.white, fontSize: 12,
                            fontFamily: 'Inter', fontWeight: FontWeight.w600),
                      ),
                      backgroundColor: const Color(0xFF00B4FF),
                      behavior: SnackBarBehavior.floating,
                      duration: const Duration(seconds: 2),
                    ),
                  );
                },
              ),
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
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              context.cBgElevated,
              context.cBgCard,
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: logoUrl.isNotEmpty
            ? Image.network(logoUrl, fit: BoxFit.contain,
                width: double.infinity, height: double.infinity,
                loadingBuilder: (_, child, p) => p == null ? child : _fallback(context),
                errorBuilder: (_, __, ___) => _fallback(context))
            : _fallback(context),
      ),
    );
  }

  Widget _fallback(BuildContext context) {
    final letter = name.isNotEmpty ? name[0].toUpperCase() : 'T';
    return Center(
      child: Container(
        width: 30,
        height: 30,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            colors: [Color(0xFF00B4FF), Color(0xFF0077FF)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Center(
          child: Text(letter, style: const TextStyle(
            color: Colors.white, fontSize: 16,
            fontWeight: FontWeight.w800, fontFamily: 'Inter',
          )),
        ),
      ),
    );
  }
}

// --- Category Chip (professional inline pill) -------------------------------

class _CategoryChip extends StatelessWidget {
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  const _CategoryChip({
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final accent = const Color(0xFF00B4FF);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
        margin: const EdgeInsets.symmetric(horizontal: 3),
        decoration: BoxDecoration(
          color: isActive ? accent : context.cBgCard,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isActive ? accent : context.cBorder.withValues(alpha: 0.5),
            width: isActive ? 0 : 0.5,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isActive ? Colors.white : context.cTextSecondary,
            fontSize: 12,
            letterSpacing: 0.3,
            fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
            fontFamily: 'Inter',
          ),
        ),
      ),
    );
  }
}

// --- Unified Channel Card (minimal professional) -------------------------

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
    final accent = const Color(0xFF00B4FF);
    final green = const Color(0xFF22C55E);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        color: context.cBgCard,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isActive
              ? accent
              : isLive
                  ? green.withValues(alpha: 0.5)
                  : context.cBorder,
          width: isActive ? 1.5 : 0.5,
        ),
      ),
      child: Stack(
        children: [
          Column(
            children: [
              const SizedBox(height: 12),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: _buildLogo(context),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
                child: Text(
                  name,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: isActive ? accent : context.cTextPrimary,
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'Inter',
                    height: 1.15,
                  ),
                ),
              ),
            ],
          ),
          if (isLive && !isDude && !isActive)
            Positioned(
              top: 6, right: 6,
              child: Container(
                width: 7, height: 7,
                decoration: BoxDecoration(
                  color: green,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          if (isDude)
            Positioned(
              top: 6, right: 6,
              child: Text('HD', style: TextStyle(
                color: accent, fontSize: 6, fontWeight: FontWeight.w800,
                fontFamily: 'Inter',
              )),
            ),
        ],
      ),
    );
  }

  Widget _buildLogo(BuildContext context) {
    final url = imageUrl;
    if (url != null && url.isNotEmpty && url != 'o') {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: CachedNetworkImage(
            imageUrl: url,
            fit: BoxFit.contain,
            placeholder: (_, __) => const SizedBox.shrink(),
            errorWidget: (_, __, ___) => _letterFallback(context),
            httpHeaders: const {
              'User-Agent': 'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36',
              'Referer': 'https://mdjamsad9.github.io/',
            },
          ),
        ),
      );
    }
    return _letterFallback(context);
  }

  Widget _letterFallback(BuildContext context) {
    final letter = name.isNotEmpty ? name[0].toUpperCase() : 'T';
    return Center(
      child: Text(letter, style: const TextStyle(
        color: Color(0xFF00B4FF), fontSize: 18, fontWeight: FontWeight.w700, fontFamily: 'Inter',
      )),
    );
  }
}

// --- Grouped Channel Card (minimal professional) -------------------------

class _GroupedChannelCard extends StatelessWidget {
  final String name;
  final String? imageUrl;
  final int count;
  final VoidCallback onTap;

  const _GroupedChannelCard({
    required this.name,
    this.imageUrl,
    required this.count,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final accent = const Color(0xFF00B4FF);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: context.cBgCard,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: accent.withValues(alpha: 0.3), width: 0.5),
        ),
        child: Stack(
          children: [
            Column(
              children: [
                const SizedBox(height: 12),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: _buildLogo(context),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
                  child: Text(
                    name,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: context.cTextPrimary,
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                      fontFamily: 'Inter',
                      height: 1.15,
                    ),
                  ),
                ),
              ],
            ),
            Positioned(
              top: 6, right: 6,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: accent,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text('+$count', style: const TextStyle(
                  color: Colors.white, fontSize: 6, fontWeight: FontWeight.w800,
                  fontFamily: 'Inter',
                )),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLogo(BuildContext context) {
    final url = imageUrl;
    if (url != null && url.isNotEmpty && url != 'o') {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: CachedNetworkImage(
            imageUrl: url,
            fit: BoxFit.contain,
            placeholder: (_, __) => const SizedBox.shrink(),
            errorWidget: (_, __, ___) => _letterFallback(context),
            httpHeaders: const {
              'User-Agent': 'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36',
              'Referer': 'https://mdjamsad9.github.io/',
            },
          ),
        ),
      );
    }
    return _letterFallback(context);
  }

  Widget _letterFallback(BuildContext context) {
    final letter = name.isNotEmpty ? name[0].toUpperCase() : 'T';
    return Center(
      child: Text(letter, style: const TextStyle(
        color: Color(0xFF00B4FF), fontSize: 18, fontWeight: FontWeight.w700, fontFamily: 'Inter',
      )),
    );
  }
}
