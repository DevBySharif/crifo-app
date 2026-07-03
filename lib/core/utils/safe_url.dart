import 'package:url_launcher/url_launcher.dart';

/// Opens an externally-sourced URL (news article links from third-party APIs)
/// only if it is a well-formed http/https web address.
///
/// News/link data comes from remote APIs we don't control. Passing those
/// strings straight to [launchUrl] would let a compromised or spoofed API
/// response smuggle dangerous schemes (`javascript:`, `intent:`, `file:`,
/// `content:`, `tel:`…) onto the device. This gate blocks everything that is
/// not a normal https (or http) web link.
Future<bool> openExternalLink(String rawUrl, {String? relativeBase}) async {
  if (rawUrl.isEmpty) return false;

  Uri? uri = Uri.tryParse(rawUrl.trim());
  // Resolve site-relative links against a trusted base (e.g. fotmob.com)
  if (uri != null && !uri.hasScheme && relativeBase != null) {
    uri = Uri.tryParse('$relativeBase$rawUrl');
  }
  if (uri == null) return false;

  final scheme = uri.scheme.toLowerCase();
  if (scheme != 'https' && scheme != 'http') return false;
  if (uri.host.isEmpty) return false;

  try {
    return await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {
    return false;
  }
}
