import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yomashi/services/myanimelist_client.dart';

import 'myanimelist_library_test.dart' show LibraryCredentials;

class _Direct extends HttpOverrides {}

/// Servidor local que hace de api.yoma.site o de tv.yoma.site.
class _Host {
  final String name;
  late final HttpServer server;
  final actions = <String>[];

  /// Cómo responde a `ping`: con el servicio, con un error o con HTML.
  String ping = 'ok';
  _Host(this.name);

  Uri get uri => Uri.parse('http://127.0.0.1:${server.port}/yomashi-api.php');

  Future<void> start() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final input = jsonDecode(await utf8.decoder.bind(request).join()) as Map;
      final action = '${input['action']}';
      actions.add(action);
      final response = request.response;
      if (action == 'ping' && ping == 'html') {
        response.headers.contentType = ContentType.html;
        response.write('<html>Hosting</html>');
      } else if (action == 'ping' && ping == 'error') {
        response.statusCode = 500;
        response.write(
          jsonEncode({'error': 'No se pudo completar la operación.'}),
        );
      } else if (action == 'ping') {
        response.write(jsonEncode({'service': 'yoma-api', 'sync': true}));
      } else {
        response.write(jsonEncode({'connected': true, 'host': name}));
      }
      await response.close();
    });
  }
}

void main() {
  late _Host api, tv;
  late MyAnimeListClient client;

  setUp(() async {
    api = _Host('api');
    tv = _Host('tv');
    await api.start();
    await tv.start();
    client = MyAnimeListClient(
      api: api.uri,
      fallback: tv.uri,
      http: HttpOverrides.runWithHttpOverrides(HttpClient.new, _Direct()),
      credentials: LibraryCredentials(),
    );
  });
  tearDown(() async {
    client.http.close(force: true);
    client.sessionChanges.dispose();
    await api.server.close(force: true);
    await tv.server.close(force: true);
  });

  Future<String> host() async =>
      '${(await client.request({'action': 'status'}))['host']}';

  test('usa api.yoma.site cuando responde a ping', () async {
    expect(await host(), 'api');
    expect(await host(), 'api');
    expect(api.actions, ['ping', 'status', 'status']); // Un solo ping.
    expect(tv.actions, isEmpty);
  });

  for (final failure in ['html', 'error']) {
    test(
      'con api.yoma.site sin preparar ($failure) sigue en tv.yoma.site',
      () async {
        api.ping = failure;
        expect(await host(), 'tv');
        expect(await host(), 'tv');
        // No vuelve a probar api en cada petición.
        expect(api.actions, ['ping']);
        expect(tv.actions, ['status', 'status']);
      },
    );
  }

  test(
    'sin respuesta de api.yoma.site (sin SSL, caído) usa tv.yoma.site',
    () async {
      await api.server.close(force: true);
      expect(await host(), 'tv');
    },
  );

  test(
    'si api.yoma.site se cae después, la siguiente petición va a tv',
    () async {
      expect(await host(), 'api');
      await api.server.close(force: true);
      await expectLater(
        client.request({'action': 'status'}),
        throwsA(isA<MalFailure>()),
      );
      expect(await host(), 'tv');
    },
  );

  test('sin respaldo (pruebas o servidor fijo) no hay ping', () async {
    final fixed = MyAnimeListClient(
      api: tv.uri,
      http: HttpOverrides.runWithHttpOverrides(HttpClient.new, _Direct()),
      credentials: LibraryCredentials(),
    );
    addTearDown(() {
      fixed.http.close(force: true);
      fixed.sessionChanges.dispose();
    });
    expect((await fixed.request({'action': 'status'}))['host'], 'tv');
    expect(tv.actions, ['status']);
  });
}
