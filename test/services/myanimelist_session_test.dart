import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:yomashi/services/myanimelist_client.dart';
import 'package:yomashi/providers/profile_provider.dart';
import 'download_engine_regression_test.dart' show RealHttp;

class SessionCredential extends MalCredentialStore {
  Map<String, dynamic>? value;
  SessionCredential(this.value);
  Future<void> Function()? beforeReplace;
  @override
  Future<Map<String, dynamic>?> load() async => value;
  @override
  Future<void> save(Map<String, dynamic> next) async => value = next;
  @override
  Future<void> clear() async => value = null;
  @override
  Future<bool> replaceIfToken(
    String? expectedToken,
    Map<String, dynamic>? next,
  ) async {
    await beforeReplace?.call();
    if (value?['device_token'] != expectedToken) return false;
    value = next;
    return true;
  }
}

Map<String, dynamic> session(String token, int owner, {String? picture}) => {
  'device_token': token * 64,
  'connected': true,
  'profile': {'id': owner, 'name': 'Owner$owner', 'picture': ?picture},
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late HttpServer server;
  late HttpClient raw;
  late MyAnimeListClient client;
  late SessionCredential credentials;
  late Completer<HttpRequest> incoming;
  late Completer<void> handled;
  late Future<void> Function(HttpRequest) respond;
  late int sessionEvents;
  setUp(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    raw = HttpOverrides.runWithHttpOverrides(() => HttpClient(), RealHttp());
    credentials = SessionCredential(session('a', 7));
    client = MyAnimeListClient(
      api: Uri.parse('http://127.0.0.1:${server.port}/api'),
      http: raw,
      credentials: credentials,
    );
    sessionEvents = 0;
    client.sessionChanges.addListener(() => sessionEvents++);
    incoming = Completer<HttpRequest>();
    handled = Completer<void>();
    respond = (r) async {
      await r.drain<void>();
      incoming.complete(r);
      await handled.future;
      r.response.headers.contentType = ContentType.json;
      r.response.write(
        jsonEncode({
          'connected': true,
          'profile': {'id': 7, 'name': 'FirstOwner'},
        }),
      );
      await r.response.close();
    };
    server.listen((r) async => respond(r));
  });
  tearDown(() async {
    if (!handled.isCompleted) handled.complete();
    raw.close(force: true);
    await server.close(force: true);
  });
  test(
    'late account status cannot overwrite a newly connected credential',
    () async {
      final pending = client.account();
      final request = await incoming.future;
      expect(request.headers.value('authorization'), 'Bearer ${'a' * 64}');
      const replacementPicture =
          'https://cdn.myanimelist.net/images/userimages/8.jpg';
      credentials.value = session('b', 8, picture: replacementPicture);
      final assertion = expectLater(
        pending,
        throwsA(isA<MalFailure>().having((e) => e.status, 'status', 409)),
      );
      handled.complete();
      await assertion;
      expect(credentials.value!['device_token'], 'b' * 64);
      expect((credentials.value!['profile'] as Map)['id'], 8);
      expect(
        (credentials.value!['profile'] as Map)['picture'],
        replacementPicture,
      );
      expect(sessionEvents, 0);
    },
  );
  test(
    '401 from a previous session cannot clear the replacement connection',
    () async {
      respond = (r) async {
        await r.drain<void>();
        incoming.complete(r);
        await handled.future;
        r.response.statusCode = 401;
        r.response.write('{"error":"Expired old session"}');
        await r.response.close();
      };
      final pending = client.detail(2);
      await incoming.future;
      credentials.value = session('b', 8);
      final assertion = expectLater(pending, throwsA(isA<MalFailure>()));
      handled.complete();
      await assertion;
      expect(credentials.value!['device_token'], 'b' * 64);
      expect(sessionEvents, 0);
    },
  );
  test(
    'account status compare-and-swap rejects a change immediately before storage',
    () async {
      credentials.beforeReplace = () async =>
          credentials.value = session('b', 8);
      final pending = client.account();
      await incoming.future;
      final assertion = expectLater(
        pending,
        throwsA(isA<MalFailure>().having((e) => e.status, 'status', 409)),
      );
      handled.complete();
      await assertion;
      expect((credentials.value!['profile'] as Map)['id'], 8);
      expect(credentials.value!['device_token'], 'b' * 64);
      expect(sessionEvents, 0);
    },
  );
  test(
    'disconnect cannot forget a connection created during remote revocation',
    () async {
      final pending = client.disconnect();
      await incoming.future;
      credentials.value = session('b', 8);
      final assertion = expectLater(pending, throwsA(isA<MalFailure>()));
      handled.complete();
      await assertion;
      expect(credentials.value!['device_token'], 'b' * 64);
      expect(sessionEvents, 0);
    },
  );
  test(
    'unchanged session status is saved with its original device token',
    () async {
      final pending = client.account();
      await incoming.future;
      handled.complete();
      final account = await pending;
      expect(account!['device_token'], 'a' * 64);
      expect((account['profile'] as Map)['name'], 'FirstOwner');
      expect(credentials.value, account);
      expect(sessionEvents, 1);
    },
  );
  test(
    'parallel status refreshes share one request and one committed event',
    () async {
      final first = client.account();
      final second = client.account();
      expect(identical(first, second), true);
      await incoming.future;
      handled.complete();
      await Future.wait([first, second]);
      expect(sessionEvents, 1);
    },
  );
  test(
    'status commits the MAL picture and updates the visible profile automatically',
    () async {
      const picture = 'https://cdn.myanimelist.net/images/userimages/7.jpg?t=2';
      final profile = ProfileProvider(malClient: client);
      addTearDown(profile.dispose);
      await profile.reloadMyAnimeListIdentity();
      expect(profile.myAnimeListAvatarUrl, isNull);
      respond = (request) async {
        await request.drain<void>();
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'connected': true,
            'profile': {'id': 7, 'name': 'Owner7', 'picture': picture},
          }),
        );
        await request.response.close();
      };
      await client.account();
      await Future<void>.delayed(Duration.zero);
      expect((credentials.value!['profile'] as Map)['picture'], picture);
      expect(profile.myAnimeListAvatarUrl, picture);
      expect(sessionEvents, 1);

      respond = (request) async {
        await request.drain<void>();
        request.response.write('{"connected":false}');
        await request.response.close();
      };
      await client.disconnect();
      await Future<void>.delayed(Duration.zero);
      expect(profile.myAnimeListAvatarUrl, isNull);
    },
  );
  test('profile follows committed login and logout automatically', () async {
    final profile = ProfileProvider(malClient: client);
    addTearDown(profile.dispose);
    await profile.reloadMyAnimeListIdentity();
    expect(profile.displayName, 'Owner7');
    final refreshed = client.account();
    await incoming.future;
    handled.complete();
    await refreshed;
    await Future<void>.delayed(Duration.zero);
    expect(profile.displayName, 'FirstOwner');
    expect(profile.myAnimeListUsername, 'FirstOwner');
    respond = (r) async {
      await r.drain<void>();
      r.response.write('{"connected":false}');
      await r.response.close();
    };
    await client.disconnect();
    await Future<void>.delayed(Duration.zero);
    expect(profile.myAnimeListUsername, isNull);
    expect(profile.displayName, ProfileProvider.defaultDisplayName);
    expect(sessionEvents, 2);
  });
  test(
    'revoked account clears the MAL profile through a committed event',
    () async {
      final profile = ProfileProvider(malClient: client);
      addTearDown(profile.dispose);
      await profile.reloadMyAnimeListIdentity();
      respond = (r) async {
        await r.drain<void>();
        r.response.statusCode = 401;
        r.response.write('{"error":"Reconnect"}');
        await r.response.close();
      };
      await expectLater(client.detail(2), throwsA(isA<MalFailure>()));
      await Future<void>.delayed(Duration.zero);
      expect(profile.usesMyAnimeListIdentity, false);
      expect(sessionEvents, 1);
    },
  );
}
