import 'dart:async';
import 'app_failure.dart';

/// Límite global por bloques; conserva toda la deuda de tiempo.
class DownloadRateLimiter {
  int maxBytesPerSecond;
  final Stopwatch _clock = Stopwatch()..start();
  int _nextMicros = 0;
  Future<void> _tail = Future.value();
  DownloadRateLimiter({this.maxBytesPerSecond = 0});
  void updateLimit(int bytesPerSecond) {
    maxBytesPerSecond = bytesPerSecond < 0 ? 0 : bytesPerSecond;
    _nextMicros = _clock.elapsedMicroseconds;
  }

  Future<void> consume(int bytes, {CancellationToken? cancellation}) {
    final next = _tail.then((_) async {
      if (bytes <= 0 || maxBytesPerSecond <= 0) return;
      cancellation?.check();
      final start = _clock.elapsedMicroseconds;
      _nextMicros =
          (_nextMicros < start ? start : _nextMicros) +
          (bytes * 1000000 / maxBytesPerSecond).ceil();
      while (maxBytesPerSecond > 0 &&
          _clock.elapsedMicroseconds < _nextMicros) {
        cancellation?.check();
        final remaining = _nextMicros - _clock.elapsedMicroseconds;
        await Future<void>.delayed(
          Duration(microseconds: remaining.clamp(1, 100000)),
        );
      }
      cancellation?.check();
    });
    _tail = next.catchError((_) {});
    return next;
  }
}
