import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show AppLifecycleState;
import 'package:flutter/services.dart';

/// Imagen en imagen de Android para el reproductor de YomaTV: el video sigue
/// en una ventana pequeña mientras se usa otra app.
class PictureInPicture {
  static const _channel = MethodChannel('app.yoma/pip');

  /// La app se muestra ahora en la ventana pequeña.
  static final active = ValueNotifier<bool>(false);
  static bool _listening = false;
  static DateTime? _requestedAt;

  static void _listen() {
    if (_listening) return;
    _listening = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'changed') {
        active.value = call.arguments == true;
        _requestedAt = null;
      }
    });
  }

  /// Se acaba de pedir entrar: Android pausa la actividad antes de avisar.
  static bool get entering =>
      _requestedAt != null &&
      DateTime.now().difference(_requestedAt!) < const Duration(seconds: 2);

  /// Si al dejar de estar en primer plano hay que pausar el video: no al
  /// entrar en la ventana pequeña ni mientras se ve en ella, sí cuando la
  /// app deja de verse (también al cerrar la ventana pequeña).
  static bool shouldPause(AppLifecycleState state) =>
      state != AppLifecycleState.resumed &&
      !(state == AppLifecycleState.inactive && (active.value || entering));

  static Future<bool> supported() async {
    if (!Platform.isAndroid) return false;
    _listen();
    try {
      return await _channel.invokeMethod<bool>('supported') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Entra con la proporción del video. Devuelve si Android lo aceptó.
  static Future<bool> enter({required int width, required int height}) async {
    if (!Platform.isAndroid) return false;
    _listen();
    _requestedAt = DateTime.now();
    try {
      final ok =
          await _channel.invokeMethod<bool>('enter', {
            'width': width,
            'height': height,
          }) ??
          false;
      if (!ok) _requestedAt = null;
      return ok;
    } on PlatformException {
      _requestedAt = null;
      return false;
    } on MissingPluginException {
      _requestedAt = null;
      return false;
    }
  }
}
