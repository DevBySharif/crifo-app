import 'dart:math' as math;
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import '../../core/api/tv_channels.dart';
import '../../core/providers/tv_fullscreen_provider.dart';

// ─── Sorting helpers ──────────────────────────────────────────────────────────

const _catOrder = {
  TVCategory.Sports: 0,
  TVCategory.Football: 1,
  TVCategory.Cricket: 2,
  TVCategory.Bangla: 3,
  TVCategory.News: 4,
  TVCategory.Entertainment: 5,
};

const _popularKeywords = [
  // BD sports — highest priority
  't sports', 'akash go', 'akash sports', 'a sports', 'gazi tv', 'gtv',
  // BD news / general
  'btv', 'maasranga', 'somoy', 'jamuna', 'rtv', 'channel 9', 'channel i',
  'desh tv', 'ntv', 'independent', 'ekattor', 'dbc', 'bangla vision',
  'channel 24', 'boishakhi', 'my tv', 'atv', 'atn bangla', 'atn news',
  'sa tv', 'news24',
  // International sports
  'star sports', 'sony sports', 'sony ten', 'sony six',
  'bein sports', 'sky sports', 'espn', 'ten sports', 'willow',
  'fox sports', 'cricket gold', 'cricket 24',
  // International news
  'al jazeera', 'bbc', 'cnn', 'euronews',
  // Entertainment
  'zee', 'colors', 'star plus', 'star gold', 'set max',
  'discovery', 'national geographic', 'nat geo',
];

int _popularityRank(String name) {
  final n = name.toLowerCase();
  for (var i = 0; i < _popularKeywords.length; i++) {
    if (n.contains(_popularKeywords[i])) return i;
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
  if (RegExp(r'https?://\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}').hasMatch(u))
    return 9;
  return 6;
}

int _channelSortKey(TVChannel ch, {int working = 1}) {
  final pop = _popularityRank(ch.name);
  final cdn = _cdnScore(ch.streamUrl);
  final cat = _catOrder[ch.category] ?? 9;
  if (pop < 9999) return working * 10000 + pop * 100 + cdn * 10 + cat;
  return working * 100000 + cdn * 1000 + cat * 100;
}

// ─── Channel health check ─────────────────────────────────────────────────────

final _dio = Dio(BaseOptions(
  connectTimeout: const Duration(seconds: 5),
  receiveTimeout: const Duration(seconds: 8),
  headers: {
    'User-Agent':
        'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 Mobile Safari/537.36',
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
          final isHls = u.contains('.m3u8') ||
              u.contains('/master') ||
              u.contains('playlist') ||
              u.contains('chunks');
          if (isHls) {
            final res = await _dio.get<String>(
              ch.streamUrl,
              options: Options(responseType: ResponseType.plain),
            );
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
  WebViewController? _playerCtrl;
  bool _playerLoading = false;
  bool _fullscreen = false;

  List<TVChannel> _channels = List.from(tvChannels)
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

  List<TVChannel> get _filtered => _channels.where((c) {
        if (_cat != null && c.category != _cat) return false;
        if (_query.isNotEmpty &&
            !c.name.toLowerCase().contains(_query.toLowerCase())) return false;
        return true;
      }).toList();

  // ── Playback ───────────────────────────────────────────────────────────────

  void _play(TVChannel ch) {
    final pc = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.black)
      ..setUserAgent(
          'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 (KHTML, like Gecko)'
          ' Chrome/120.0.0.0 Mobile Safari/537.36');

    if (pc.platform is AndroidWebViewController) {
      (pc.platform as AndroidWebViewController)
          .setMediaPlaybackRequiresUserGesture(false);
    }

    pc.setNavigationDelegate(NavigationDelegate(
      onPageFinished: (_) {
        final safe = ch.streamUrl
            .replaceAll('\\', '\\\\')
            .replaceAll("'", "\\'")
            .replaceAll('\n', '');
        pc.runJavaScript("""
(function tryPlay(n){
  if(typeof window.playStream==='function'){
    window.playStream('$safe');
  } else if(n>0){
    setTimeout(function(){tryPlay(n-1);},200);
  }
})(30);
""");
        if (mounted) setState(() => _playerLoading = false);
      },
      onNavigationRequest: (r) {
        final u = r.url;
        if (u.startsWith('flutter-asset://')) return NavigationDecision.navigate;
        if (u.startsWith('https://appassets.androidplatform.net'))
          return NavigationDecision.navigate;
        if (u.startsWith('about:')) return NavigationDecision.navigate;
        return NavigationDecision.prevent;
      },
    ));

    pc.loadFlutterAsset('assets/tv_player.html');

    setState(() {
      _playing = ch;
      _playerCtrl = pc;
      _playerLoading = true;
      _fullscreen = false;
    });
  }

  void _closePlayer() {
    setState(() {
      _playing = null;
      _playerCtrl = null;
      _playerLoading = false;
      _fullscreen = false;
    });
  }

  // ── Fullscreen via MainShell Stack overlay (truly covers BottomNav) ──────────

  void _enterFullscreen() {
    final ctrl = _playerCtrl;
    final ch = _playing;
    if (ctrl == null || ch == null) return;

    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    setState(() => _fullscreen = true);

    // Inject fullscreen widget into MainShell's Stack via provider
    ref.read(tvFullscreenProvider.notifier).state = _FullscreenPage(
      controller: ctrl,
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
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (_, __) {
        if (_fullscreen) { _exitFullscreen(); return; }
        if (_playing != null) _closePlayer();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF0A0A0F),
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
        controller: _playerCtrl,
        loading: _playerLoading,
        channelName: _playing?.name ?? '',
        fullscreen: false,
        onClose: _closePlayer,
        onFullscreen: _enterFullscreen,
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
      child: Row(
        children: [
          const Text(
            'LIVE TV',
            style: TextStyle(
              color: Color(0xFFF0F0FF),
              fontSize: 16,
              fontWeight: FontWeight.w800,
              fontFamily: 'Inter',
              letterSpacing: 1,
            ),
          ),
          const SizedBox(width: 6),
          _checking
              ? const SizedBox(
                  width: 10,
                  height: 10,
                  child: CircularProgressIndicator(
                      strokeWidth: 1.5, color: Color(0xFF5B6EF5)),
                )
              : Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFF5B6EF5).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: const Color(0xFF5B6EF5).withValues(alpha: 0.3)),
                  ),
                  child: Text(
                    '${_workingIds.length} live',
                    style: const TextStyle(
                      color: Color(0xFF5B6EF5),
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      fontFamily: 'Inter',
                    ),
                  ),
                ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _searchCtrl,
              onChanged: (v) => setState(() => _query = v),
              style: const TextStyle(
                color: Color(0xFFF0F0FF),
                fontSize: 12,
                fontFamily: 'Inter',
              ),
              decoration: InputDecoration(
                hintText: 'Search channels...',
                hintStyle:
                    const TextStyle(color: Color(0xFF8888AA), fontSize: 12),
                prefixIcon: const Icon(Icons.search_rounded,
                    color: Color(0xFF8888AA), size: 18),
                prefixIconConstraints:
                    const BoxConstraints(minWidth: 36, minHeight: 36),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
                filled: true,
                fillColor: const Color(0xFF16161F),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Color(0xFF1E1E2E)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Color(0xFF1E1E2E)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide:
                      const BorderSide(color: Color(0xFF5B6EF5), width: 1.2),
                ),
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
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(
                color: active
                    ? const Color(0xFF5B6EF5)
                    : const Color(0xFF13131A),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: active
                      ? const Color(0xFF5B6EF5)
                      : const Color(0xFF1E1E2E),
                ),
              ),
              child: Text(
                item.$2,
                style: TextStyle(
                  color: active ? Colors.white : const Color(0xFF8888AA),
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  fontFamily: 'Inter',
                  letterSpacing: 0.5,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildGrid() {
    final channels = _filtered;
    if (channels.isEmpty) {
      return const Center(
        child: Text('No channels',
            style: TextStyle(color: Color(0xFF8888AA), fontFamily: 'Inter')),
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        childAspectRatio: 0.82,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
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
                  ? const Color(0xFF5B6EF5).withValues(alpha: 0.12)
                  : const Color(0xFF13131A),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isActive
                    ? const Color(0xFF5B6EF5)
                    : isWorking
                        ? const Color(0xFF22C55E).withValues(alpha: 0.4)
                        : const Color(0xFF1E1E2E),
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
                        padding: const EdgeInsets.fromLTRB(8, 10, 8, 4),
                        child: _ChannelLogo(
                            logoUrl: ch.logoUrl, name: ch.name),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(6, 0, 6, 8),
                      child: Text(
                        ch.name,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: isActive
                              ? const Color(0xFF5B6EF5)
                              : const Color(0xFFDDDDFF),
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                          fontFamily: 'Inter',
                        ),
                      ),
                    ),
                  ],
                ),
                if (isWorking && !isActive)
                  Positioned(
                    top: 5,
                    right: 5,
                    child: Container(
                      width: 6,
                      height: 6,
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
    );
  }
}

// ─── Fullscreen page ──────────────────────────────────────────────────────────
// Pushed on ROOT navigator — guaranteed to cover BottomNavigationBar

class _FullscreenPage extends StatelessWidget {
  final WebViewController controller;
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
    final w = size.shortestSide; // portrait width
    final h = size.longestSide;  // portrait height

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (_, __) => onExit(),
      child: Material(
        color: Colors.black,
        child: SizedBox.expand(
          child: Center(
            child: OverflowBox(
              maxWidth: h,
              maxHeight: w,
              child: Transform.rotate(
                angle: math.pi / 2,
                child: SizedBox(
                  width: h,
                  height: w,
                  child: _PlayerStack(
                    controller: controller,
                    loading: false,
                    channelName: channelName,
                    fullscreen: true,
                    onClose: onExit,
                    onFullscreen: onExit,
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
  final WebViewController? controller;
  final bool loading;
  final String channelName;
  final bool fullscreen;
  final VoidCallback onClose;
  final VoidCallback onFullscreen;

  const _PlayerStack({
    required this.controller,
    required this.loading,
    required this.channelName,
    required this.fullscreen,
    required this.onClose,
    required this.onFullscreen,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black,
      child: Stack(
        children: [
          if (controller != null) WebViewWidget(controller: controller!),
          if (loading)
            Container(
              color: Colors.black,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(
                      width: 28,
                      height: 28,
                      child: CircularProgressIndicator(
                          color: Color(0xFF5B6EF5), strokeWidth: 2.5),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      channelName,
                      style: const TextStyle(
                        color: Color(0xFF8888AA),
                        fontSize: 11,
                        fontFamily: 'Inter',
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          Positioned(
            top: 8,
            left: 8,
            right: 8,
            child: Row(
              children: [
                _CtrlBtn(icon: Icons.close_rounded, onTap: onClose),
                const Spacer(),
                if (channelName.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFF5B6EF5).withValues(alpha: 0.9),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 5,
                          height: 5,
                          decoration: const BoxDecoration(
                              color: Colors.white, shape: BoxShape.circle),
                        ),
                        const SizedBox(width: 5),
                        Text(
                          channelName,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            fontFamily: 'Inter',
                          ),
                        ),
                      ],
                    ),
                  ),
                const Spacer(),
                _CtrlBtn(
                  icon: fullscreen
                      ? Icons.fullscreen_exit_rounded
                      : Icons.fullscreen_rounded,
                  onTap: onFullscreen,
                ),
              ],
            ),
          ),
        ],
      ),
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
        width: 30,
        height: 30,
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
        color: const Color(0xFF1A1A28),
        child: logoUrl.isNotEmpty
            ? Image.network(
                logoUrl,
                fit: BoxFit.contain,
                width: double.infinity,
                height: double.infinity,
                loadingBuilder: (_, child, progress) =>
                    progress == null ? child : _initial(),
                errorBuilder: (_, __, ___) => _initial(),
              )
            : _initial(),
      ),
    );
  }

  Widget _initial() {
    return Center(
      child: Text(
        name.isNotEmpty ? name[0].toUpperCase() : 'T',
        style: const TextStyle(
          color: Color(0xFF5B6EF5),
          fontSize: 24,
          fontWeight: FontWeight.w800,
          fontFamily: 'Inter',
        ),
      ),
    );
  }
}
