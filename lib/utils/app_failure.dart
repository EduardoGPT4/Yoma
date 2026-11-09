import 'dart:async';
import 'dart:io';

enum FailureKind { network, timeout, http, parsing, storage, cancelled }

class AppFailure implements Exception {
  final FailureKind kind;
  final String message;
  final int? statusCode;
  final Duration? retryAfter;
  final Object? cause;
  const AppFailure(
    this.kind,
    this.message, {
    this.statusCode,
    this.retryAfter,
    this.cause,
  });
  bool get retryable =>
      kind == FailureKind.network ||
      kind == FailureKind.timeout ||
      (kind == FailureKind.http &&
          (statusCode == 408 || statusCode == 429 || (statusCode ?? 0) >= 500));
  static AppFailure from(Object error) {
    if (error is AppFailure) return error;
    if (error is TimeoutException) {
      return AppFailure(
        FailureKind.timeout,
        'La conexión tardó demasiado.',
        cause: error,
      );
    }
    if (error is SocketException) {
      return AppFailure(
        FailureKind.network,
        'Sin conexión a internet.',
        cause: error,
      );
    }
    if (error is FileSystemException) {
      return AppFailure(
        FailureKind.storage,
        'No se pudo acceder al almacenamiento. Revisa permisos y espacio libre.',
        cause: error,
      );
    }
    return AppFailure(FailureKind.parsing, error.toString(), cause: error);
  }

  @override
  String toString() => message;
}

class CancellationToken {
  bool _cancelled = false;
  final List<void Function()> _callbacks = [];
  bool get isCancelled => _cancelled;
  void check() {
    if (_cancelled) {
      throw const AppFailure(FailureKind.cancelled, 'Operación cancelada.');
    }
  }

  void Function() onCancel(void Function() callback) {
    if (_cancelled) {
      callback();
    } else {
      _callbacks.add(callback);
    }
    return () => _callbacks.remove(callback);
  }

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    for (final callback in List<void Function()>.from(_callbacks)) {
      callback();
    }
    _callbacks.clear();
  }
}
