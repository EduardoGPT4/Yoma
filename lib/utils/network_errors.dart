import 'app_failure.dart';

/// Mensajes de error de red legibles para el usuario.
class NetworkErrors {
  static String friendly(Object error) {
    if (error is AppFailure) {
      if (error.kind == FailureKind.http) {
        return switch (error.statusCode) {
          403 => 'El servidor rechazó la petición (403). Prueba más tarde.',
          404 =>
            'El contenido no está disponible en la fuente (404). Prueba otra página o capítulo.',
          429 =>
            'Demasiadas peticiones. Espera un momento e inténtalo de nuevo.',
          final int status when status >= 500 =>
            'El servidor no responde ($status). Prueba más tarde.',
          _ => error.message,
        };
      }
      return error.message;
    }
    final text = error.toString().toLowerCase();

    if (text.contains('socketexception') ||
        text.contains('failed host lookup') ||
        text.contains('network is unreachable') ||
        text.contains('connection refused') ||
        text.contains('connection reset')) {
      return 'Sin conexión a internet. Revisa tu red e inténtalo de nuevo.';
    }

    if (text.contains('timeout') || text.contains('timed out')) {
      return 'La conexión tardó demasiado. Inténtalo de nuevo.';
    }

    if (text.contains('http 403') || text.contains('forbidden')) {
      return 'El servidor rechazó la petición (403). Prueba más tarde.';
    }

    if (text.contains('http 404') || text.contains('not found')) {
      return 'No se encontró el contenido (404).';
    }

    if (text.contains('http 429') || text.contains('too many')) {
      return 'Demasiadas peticiones. Espera un momento e inténtalo de nuevo.';
    }

    if (text.contains('imageshack') ||
        text.contains('el hosting imageshack caducó') ||
        text.contains('el hosting imageshack caduco')) {
      return 'Las imágenes de este capítulo ya no están en ManhwaWeb (ImageShack caducó). Prueba otro capítulo.';
    }

    if (text.contains('http 5') || text.contains('server error')) {
      return 'El servidor no responde. Prueba más tarde.';
    }

    if (text.contains('handshake') || text.contains('certificate')) {
      return 'Error de seguridad de la conexión. Revisa la fecha del dispositivo.';
    }

    if (text.contains('wifi') || text.contains('esperando conexion')) {
      return error.toString();
    }

    final raw = error.toString();
    if (raw.length > 180) {
      return 'Ocurrió un error de red. Inténtalo de nuevo.';
    }
    return raw.replaceFirst(RegExp(r'^Exception:\s*'), '');
  }

  /// El origen no contestó: timeout, corte de red o HTTP 5xx (incluido 522).
  static bool isServerUnreachable(Object error) {
    if (error is AppFailure) return error.retryable;
    final text = error.toString().toLowerCase();
    return text.contains('socketexception') ||
        text.contains('failed host lookup') ||
        text.contains('network is unreachable') ||
        text.contains('connection refused') ||
        text.contains('connection reset') ||
        text.contains('clientexception') ||
        text.contains('timeout') ||
        text.contains('timed out') ||
        text.contains('handshake') ||
        text.contains('certificate') ||
        text.contains('http 5') ||
        text.contains('server error');
  }
}
