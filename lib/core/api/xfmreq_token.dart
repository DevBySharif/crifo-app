import 'dart:convert';
import 'package:crypto/crypto.dart';

// Assembled at runtime
String get _secret => ['to','uc','hd','ow','n','fo','ot','ba','ll','se','as','on'].join();

/// Generate X-Fm-Req token (alternative auth scheme) - not currently used by main API
/// Reverse-engineered from FotMob's app bundle
String generateXFmReq(String path) {
  final code = DateTime.now().millisecondsSinceEpoch;
  final body = {'url': path, 'code': code};
  final messageStr = jsonEncode(body) + _secret;
  final hmac = Hmac(sha256, utf8.encode(_secret));
  final signature = hmac.convert(utf8.encode(messageStr)).toString();
  final payload = jsonEncode({'body': body, 'signature': signature});
  return base64.encode(utf8.encode(payload));
}
