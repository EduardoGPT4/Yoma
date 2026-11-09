import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

typedef VolumeButtonCallback = void Function(bool isNextPage);

class VolumeButtonService {
  static const MethodChannel _channel = MethodChannel(
    'app.yomashi.reader/volume',
  );

  VolumeButtonCallback? _onVolumePressed;
  bool _listening = false;
  int _generation = 0;

  Future<void> startListening(VolumeButtonCallback onVolumePressed) async {
    _onVolumePressed = onVolumePressed;
    if (_listening) {
      return;
    }
    final generation = ++_generation;
    try {
      await _channel.invokeMethod<void>('setEnabled', true);
    } on MissingPluginException {
      return;
    } on PlatformException catch (error) {
      debugPrint('Volumen: $error');
      return;
    }
    if (generation != _generation) return;
    _listening = true;
    _channel.setMethodCallHandler(_handleMethodCall);
  }

  void stopListening() {
    _generation++;
    unawaited(
      _channel.invokeMethod<void>('setEnabled', false).catchError((_) {}),
    );
    _listening = false;
    _onVolumePressed = null;
    _channel.setMethodCallHandler(null);
  }

  Future<void> _handleMethodCall(MethodCall call) async {
    final callback = _onVolumePressed;
    if (callback == null) {
      return;
    }

    switch (call.method) {
      case 'volumeUp':
        callback(true);
        break;
      case 'volumeDown':
        callback(false);
        break;
      default:
        if (kDebugMode) {
          debugPrint('VolumeButtonService: metodo desconocido ${call.method}');
        }
    }
  }
}
