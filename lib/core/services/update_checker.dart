import 'package:dio/dio.dart';
import 'package:package_info_plus/package_info_plus.dart';

const _versionUrl = 'https://crifo.netlify.app/version.json';

class AppUpdate {
  final int versionCode;
  final String versionName;
  final String apkUrl;
  final String releaseNotes;
  const AppUpdate({
    required this.versionCode,
    required this.versionName,
    required this.apkUrl,
    required this.releaseNotes,
  });
}

/// Returns update info if the website advertises a newer build than the one
/// running, otherwise null. Never throws — a network failure just means
/// "no update".
Future<AppUpdate?> checkForUpdate() async {
  try {
    final info = await PackageInfo.fromPlatform();
    final installedCode = int.tryParse(info.buildNumber) ?? 0;

    final res = await Dio()
        .get(_versionUrl,
            options: Options(
              responseType: ResponseType.json,
              headers: {'Cache-Control': 'no-cache'},
            ))
        .timeout(const Duration(seconds: 6));

    final data = res.data is Map ? (res.data as Map) : <String, dynamic>{};
    final serverCode = int.tryParse('${data['versionCode']}') ?? 0;
    if (serverCode <= installedCode) return null;

    var apk = '${data['apkUrl'] ?? ''}'.trim();
    if (apk.isEmpty) return null;
    if (apk.startsWith('/')) apk = 'https://crifo.netlify.app$apk';

    return AppUpdate(
      versionCode: serverCode,
      versionName: '${data['versionName'] ?? ''}',
      apkUrl: apk,
      releaseNotes: '${data['releaseNotes'] ?? ''}',
    );
  } catch (_) {
    return null;
  }
}
