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
      return 'Sin conexion a internet. Revisa tu red e intentalo de nuevo.';
    }

    if (text.contains('timeout') || text.contains('timed out')) {
      return 'La conexion tardo demasiado. Intentalo de nuevo.';
    }

    if (text.contains('http 403') || text.contains('forbidden')) {
      return 'El servidor rechazo la peticion (403). Prueba mas tarde.';
    }

    if (text.contains('http 404') || text.contains('not found')) {
      return 'No se encontro el contenido (404).';
    }

    if (text.contains('http 429') || text.contains('too many')) {
      return 'Demasiadas peticiones. Espera un momento e intentalo de nuevo.';
    }

    if (text.contains('imageshack') ||
        text.contains('el hosting imageshack caducó') ||
        text.contains('el hosting imageshack caduco')) {
      return 'Las imagenes de este capitulo ya no estan en ManhwaWeb (ImageShack caduco). Prueba otro capitulo.';
    }

    if (text.contains('http 5') || text.contains('server error')) {
      return 'El servidor no responde. Prueba mas tarde.';
    }

    if (text.contains('handshake') || text.contains('certificate')) {
      return 'Error de seguridad de la conexion. Revisa la fecha del dispositivo.';
    }

    if (text.contains('wifi') || text.contains('esperando conexion')) {
      return error.toString();
    }

    final raw = error.toString();
    if (raw.length > 180) {
      return 'Ocurrio un error de red. Intentalo de nuevo.';
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
