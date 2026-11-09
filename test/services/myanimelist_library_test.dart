import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:yomashi/services/myanimelist_client.dart';

class LibraryCredentials extends MalCredentialStore {
  Map<String, dynamic>? value = {
    'device_token': 'fixture-device',
    'connected': true,
    'profile': {'id': 7, 'name': 'Reader'},
  };
  @override
  Future<Map<String, dynamic>?> load() async => value;
  @override
  Future<void> save(Map<String, dynamic> next) async => value = next;
  @override
  Future<void> clear() async => value = null;
}

Map<String, dynamic> libraryRow({
  int id = 1,
  String title = 'Obra',
  String status = 'reading',
}) => {
  'id': id,
  'title': title,
  'status': status,
  'chapters_read': 4,
  'num_chapters': 10,
  'publishing_status': 'finished',
  'picture': '',
  'alternative_titles': ['Other title', '別題'],
};

class _Direct extends HttpOverrides {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late HttpServer server;
  late MyAnimeListClient client;
  late LibraryCredentials credentials;
  final requests = <Map<String, dynamic>>[];
  Map<String, dynamic> response = {};
  int code = 200;
  Completer<void>? gate;

  setUp(() async {
    credentials = LibraryCredentials();
    requests.clear();
    gate = null;
    code = 200;
    response = {
      'items': [libraryRow()],
      'next_offset': null,
    };
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      requests.add(
        Map<String, dynamic>.from(
          jsonDecode(await utf8.decoder.bind(request).join()) as Map,
        ),
      );
      await gate?.future;
      request.response.statusCode = code;
      request.response.write(jsonEncode(response));
      await request.response.close();
    });
    client = MyAnimeListClient(
      api: Uri.parse('http://127.0.0.1:${server.port}/'),
      http: HttpOverrides.runWithHttpOverrides(HttpClient.new, _Direct()),
      credentials: credentials,
    );
  });
  tearDown(() async {
    client.http.close(force: true);
    await server.close(force: true);
  });

  test(
    'reads only the requested manga status with owner and pagination',
    () async {
      response = {
        'items': [libraryRow(), libraryRow(id: 2, status: 'completed')],
        'next_offset': 2,
      };
      final page = await client.library(status: 'reading', limit: 2);
      expect(page.items.map((item) => item.id), [1]);
      expect(page.items.single.alternativeTitles, ['Other title', '別題']);
      expect(page.nextOffset, 2);
      expect(requests.single, {
        'action': 'library',
        'status': 'reading',
        'offset': 0,
        'limit': 2,
        'owner_id': 7,
      });
      response = {
        'items': [libraryRow(id: 3, status: 'plan_to_read')],
        'next_offset': null,
      };
      expect(
        (await client.library(
          status: 'plan_to_read',
          offset: 2,
        )).items.single.id,
        3,
      );
    },
  );

  test(
    'rejects invalid filters and pending accounts before any HTTP request',
    () async {
      for (final status in ['completed', 'watching', 'all']) {
        await expectLater(
          client.library(status: status),
          throwsA(isA<MalFailure>()),
        );
      }
      await expectLater(
        client.library(status: 'reading', offset: -1),
        throwsA(isA<MalFailure>()),
      );
      await expectLater(
        client.library(status: 'reading', limit: 0),
        throwsA(isA<MalFailure>()),
      );
      credentials.value = {
        'connected': false,
        'device_token': 'fixture-device',
      };
      await expectLater(
        client.library(status: 'reading'),
        throwsA(isA<MalFailure>()),
      );
      expect(requests, isEmpty);
    },
  );

  test('rejects a changed owner before reading another account', () async {
    await expectLater(
      client.library(status: 'reading', expectedOwner: 8),
      throwsA(isA<MalFailure>().having((e) => e.status, 'status', 409)),
    );
    expect(requests, isEmpty);
  });

  test(
    'discards a response if the account changes while it is pending',
    () async {
      gate = Completer<void>();
      final pending = client.library(status: 'reading');
      while (requests.isEmpty) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
      credentials.value = {
        'device_token': 'other-fixture',
        'connected': true,
        'profile': {'id': 8},
      };
      gate!.complete();
      await expectLater(
        pending,
        throwsA(isA<MalFailure>().having((e) => e.status, 'status', 409)),
      );
      expect(credentials.value!['device_token'], 'other-fixture');
    },
  );

  test(
    'invalid page data and non-advancing cursors are not accepted',
    () async {
      for (final invalid in [
        {
          'items': [libraryRow()],
          'next_offset': 0,
        },
        {'items': [], 'next_offset': 50},
        {'items': 'invalid', 'next_offset': null},
        {
          'items': [
            {'id': 'wrong'},
          ],
          'next_offset': null,
        },
      ]) {
        response = invalid;
        await expectLater(
          client.library(status: 'reading'),
          throwsA(isA<MalFailure>().having((e) => e.status, 'status', 502)),
        );
      }
    },
  );
}
