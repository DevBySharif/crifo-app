import 'dart:async';
import 'package:flutter/services.dart';

class DrmPlayerService {
  static const _channel = MethodChannel('com.crifo.crifo/drm_player');

  int? _playerId;
  int? _textureId;
  final StreamController<Map<String, dynamic>> _eventController =
      StreamController<Map<String, dynamic>>.broadcast();

  DrmPlayerService() {
    _channel.setMethodCallHandler(_handleMethodCall);
  }

  Future<Map<String, dynamic>> _handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'onReady':
        _eventController.add({'type': 'ready', 'id': call.arguments});
        break;
      case 'onError':
        final args = call.arguments as Map<dynamic, dynamic>;
        _eventController.add({
          'type': 'error',
          'id': args['id'],
          'error': args['error'],
        });
        break;
    }
    return {};
  }

  Stream<Map<String, dynamic>> get events => _eventController.stream;

  int? get textureId => _textureId;

  bool get isPlaying => _playerId != null;

  Future<void> play(String url, {String? api}) async {
    await stop();
    try {
      final result = await _channel.invokeMethod<Map<dynamic, dynamic>>('play', {
        'url': url,
        if (api != null && api.isNotEmpty) 'api': api,
      });
      if (result != null) {
        _playerId = result['id'] as int;
        _textureId = result['textureId'] as int;
      }
    } catch (e) {
      _playerId = null;
      _textureId = null;
      rethrow;
    }
  }

  Future<void> stop() async {
    if (_playerId != null) {
      await _channel.invokeMethod('stop', {'id': _playerId});
    }
  }

  Future<void> dispose() async {
    if (_playerId != null) {
      await _channel.invokeMethod('dispose', {'id': _playerId});
      _playerId = null;
      _textureId = null;
    }
    await _eventController.close();
  }
}
