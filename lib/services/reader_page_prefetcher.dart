import 'dart:async';
import 'dart:collection';

/// Prepara los archivos de las páginas siguientes sin decodificar sus imágenes.
class ReaderPagePrefetcher {
  static const pagesAhead = 5;
  final Future<void> Function(String url) load;
  final void Function(Object error)? onError;
  final int concurrency;
  final _queue = Queue<String>();
  final _active = <String>{};
  final _completed = <String>{};
  List<String> _window = const [];
  bool _disposed = false;

  ReaderPagePrefetcher({required this.load, this.onError, this.concurrency = 2})
    : assert(concurrency > 0);

  void update(List<String> pages, {required int currentPage}) {
    if (_disposed) return;
    final next = currentPage < 0 || currentPage >= pages.length
        ? <String>[]
        : pages
              .skip(currentPage + 1)
              .take(pagesAhead)
              .where(
                (url) =>
                    const ['http', 'https'].contains(Uri.tryParse(url)?.scheme),
              )
              .toSet()
              .toList();
    if (_window.length == next.length &&
        Iterable<int>.generate(
          next.length,
        ).every((i) => _window[i] == next[i])) {
      return;
    }
    _window = next;
    _completed.removeWhere((url) => !next.contains(url));
    _queue
      ..clear()
      ..addAll(
        next.where(
          (url) => !_active.contains(url) && !_completed.contains(url),
        ),
      );
    _pump();
  }

  /// Retira lo pendiente; las cargas compartidas con el lector pueden terminar.
  void stop() {
    _window = const [];
    _queue.clear();
    _completed.clear();
  }

  void dispose() {
    _disposed = true;
    stop();
  }

  void _pump() {
    while (!_disposed && _active.length < concurrency && _queue.isNotEmpty) {
      final url = _queue.removeFirst();
      _active.add(url);
      unawaited(_run(url));
    }
  }

  Future<void> _run(String url) async {
    try {
      await load(url);
      if (!_disposed && _window.contains(url)) _completed.add(url);
    } catch (error) {
      // Una precarga fallida no sustituye el error/reintento del lector visible.
      if (!_disposed) onError?.call(error);
    } finally {
      _active.remove(url);
      _pump();
    }
  }
}
