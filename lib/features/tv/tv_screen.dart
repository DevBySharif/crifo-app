import 'dart:convert';
import 'dart:math' as math;
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';
import '../../core/api/tv_channels.dart';
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
    ..sort((a, b) => _channelSortKey(a).compareTo(_channelSortKey(b)));
  Set<String> _workingIds = {};
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    _runChannelCheck();
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
        final aW = working.contains(a.id) ? 0 : 1;
        final bW = working.contains(b.id) ? 0 : 1;
        return _channelSortKey(a, working: aW)
            .compareTo(_channelSortKey(b, working: bW));
      });
    setState(() {
      _workingIds = working;
      _channels = sorted;
      _checking = false;
    });
  }

  // Handle play requests coming from other screens (match "Where to watch")
  void _handlePlayRequest(String? channelId) {
    if (channelId == null) return;
    ref.read(tvPlayRequestProvider.notifier).state = null;
    final ch = _channels.where((c) => c.id == channelId).toList();
    if (ch.isNotEmpty) _play(ch.first);
  }

  List<TVChannel> get _filtered => _channels.where((c) {
        if (_cat != null && c.category != _cat) return false;
        if (_query.isNotEmpty &&
            !c.name.toLowerCase().contains(_query.toLowerCase())) return false;
        return true;
      }).toList();

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
              _buildPills(),
              Expanded(child: _buildGrid()),
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
                  child: Text('${_workingIds.length} live', style: const TextStyle(
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

  Widget _buildGrid() {
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
        final isWorking = _workingIds.contains(ch.id);
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
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.signal_wifi_off_rounded, color: Color(0xFF8888AA), size: 36),
                const SizedBox(height: 8),
                const Text('Stream unavailable', style: TextStyle(
                  color: Color(0xFF8888AA), fontSize: 12, fontFamily: 'Inter')),
                const SizedBox(height: 10),
                GestureDetector(
                  onTap: onRetry,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
                    decoration: BoxDecoration(
                      color: const Color(0xFF00B4FF),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text('Retry', style: TextStyle(
                      color: Colors.white, fontSize: 11,
                      fontWeight: FontWeight.w700, fontFamily: 'Inter')),
                  ),
                ),
              ]),
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
