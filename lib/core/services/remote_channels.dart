import 'package:dio/dio.dart';
import '../api/tv_channels.dart';

/// Remote TV channel list. Lets us add/remove/fix channels or rotate stream
/// URLs WITHOUT shipping an app update — the app fetches this JSON on the TV
/// screen and falls back to the built-in [tvChannels] if it can't be reached.
///
/// Update flow: edit football-eon-web/public/channels.json, commit + push →
/// Netlify deploys → every app picks up the new list on next TV-tab open.
const _channelsUrl = 'https://crifo.netlify.app/channels.json';

List<TVChannel>? _cached;

Future<List<TVChannel>> loadChannels() async {
  if (_cached != null) return _cached!;
  try {
    final res = await Dio()
        .get(_channelsUrl,
            options: Options(
              responseType: ResponseType.json,
              headers: {'Cache-Control': 'no-cache'},
            ))
        .timeout(const Duration(seconds: 8));

    final raw = res.data;
    final list = raw is Map ? raw['channels'] : raw; // support {channels:[...]} or [...]
    if (list is List && list.isNotEmpty) {
      final parsed = <TVChannel>[];
      for (final e in list) {
        if (e is Map) {
          final c = TVChannel.fromJson(e.cast<String, dynamic>());
          if (c.streamUrl.isNotEmpty && c.name.isNotEmpty) parsed.add(c);
        }
      }
      if (parsed.isNotEmpty) {
        _cached = parsed;
        return parsed;
      }
    }
  } catch (_) {}
  // Remote unavailable/empty → ship-with-the-app list.
  _cached = tvChannels;
  return tvChannels;
}
