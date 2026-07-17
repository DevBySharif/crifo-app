import 'dart:async';
import 'package:flutter/services.dart';

class DrmPlayerService {
  static const _channel = MethodChannel('com.crifo.crifo/drm_player');

  int? _playerId;
  int? _textureId;
  late StreamController<Map<String, dynamic>> _eventController;
  bool _isDisposed = false;

  DrmPlayerService() {
    _eventController = StreamController<Map<String, dynamic>>.broadcast();
    _channel.setMethodCallHandler(_handleMethodCall);
  }

  void _ensureController() {
    if (_isDisposed || _eventController.isClosed) {
      _eventController = StreamController<Map<String, dynamic>>.broadcast();
      _isDisposed = false;
    }
  }

  Future<Map<String, dynamic>> _handleMethodCall(MethodCall call) async {
    if (_eventController.isClosed) return {};
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

  Stream<Map<String, dynamic>> get events {
    _ensureController();
    return _eventController.stream;
  }

  int? get textureId => _textureId;

  bool get isPlaying => _playerId != null;

  Future<void> play(String url, {String? api}) async {
    _ensureController();
    await _stopNative();
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

  Future<void> playHls(String url) async {
    _ensureController();
    await _stopNative();
    try {
      final result = await _channel.invokeMethod<Map<dynamic, dynamic>>('playHls', {
        'url': url,
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

  Future<void> _stopNative() async {
    final pid = _playerId;
    if (pid != null) {
      try {
        await _channel.invokeMethod('stop', {'id': pid});
      } catch (_) {}
    }
  }

  Future<void> stop() async {
    await _stopNative();
  }

  Future<void> dispose() async {
    if (_isDisposed) return;
    _isDisposed = true;
    final pid = _playerId;
    if (pid != null) {
      try {
        await _channel.invokeMethod('dispose', {'id': pid});
      } catch (_) {}
      _playerId = null;
      _textureId = null;
    }
    await _eventController.close();
  }
}
