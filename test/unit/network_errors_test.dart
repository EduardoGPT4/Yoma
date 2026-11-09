import 'package:flutter_test/flutter_test.dart';
import 'package:yomashi/utils/network_errors.dart';
import 'package:yomashi/utils/app_failure.dart';

void main() {
  test('typed HTTP errors explain unavailable source content', () {
    final message = NetworkErrors.friendly(
      const AppFailure(
        FailureKind.http,
        'HTTP 404: cdn.example',
        statusCode: 404,
      ),
    );
    expect(message, contains('404'));
    expect(message, contains('fuente'));
    expect(message, isNot(contains('cdn.example')));
  });
  test('friendly maps socket errors', () {
    final msg = NetworkErrors.friendly(
      Exception('SocketException: Failed host lookup'),
    );
    expect(msg.toLowerCase(), contains('conexion'));
  });

  test('friendly maps timeout', () {
    final msg = NetworkErrors.friendly(
      Exception('TimeoutException: timed out'),
    );
    expect(msg.toLowerCase(), contains('tardo'));
  });

  test('friendly maps http 403', () {
    final msg = NetworkErrors.friendly(Exception('HTTP 403 forbidden'));
    expect(msg, contains('403'));
  });

  test('server unreachable covers zonatmo outages and ignores 404', () {
    expect(
      NetworkErrors.isServerUnreachable(
        Exception('HTTP 522 for https://zonatmo.to/wp-api/api/listing/manga'),
      ),
      isTrue,
    );
    expect(
      NetworkErrors.isServerUnreachable(
        Exception('TimeoutException: timed out'),
      ),
      isTrue,
    );
    expect(
      NetworkErrors.isServerUnreachable(Exception('HTTP 404 not found')),
      isFalse,
    );
  });
}
