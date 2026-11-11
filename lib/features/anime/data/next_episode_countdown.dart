import 'dart:async';

import 'package:flutter/foundation.dart';

/// Cuenta atrás para pasar al siguiente episodio al terminar uno. Su valor
/// son los segundos que faltan, o `null` si no hay cuenta en marcha.
class NextEpisodeCountdown extends ValueNotifier<int?> {
  NextEpisodeCountdown({this.seconds = 5}) : super(null);
  final int seconds;
  Timer? _timer;

  bool get running => value != null;

  /// Empieza (o reinicia) la cuenta; al llegar a cero llama a [onDone].
  void start(VoidCallback onDone) {
    cancel();
    value = seconds;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      final left = (value ?? 0) - 1;
      if (left <= 0) {
        cancel();
        onDone();
      } else {
        value = left;
      }
    });
  }

  void cancel() {
    _timer?.cancel();
    _timer = null;
    value = null;
  }

  /// La reproducción llegó al final: parada a menos de medio segundo.
  static bool ended({
    required bool playing,
    required int positionMs,
    required int durationMs,
  }) => !playing && durationMs > 0 && positionMs >= durationMs - 500;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
