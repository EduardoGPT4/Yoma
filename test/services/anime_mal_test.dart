import 'dart:async';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yomashi/data/app_database.dart';
import 'package:yomashi/data/library_store.dart';
import 'package:yomashi/services/myanimelist_client.dart';
import 'package:yomashi/features/anime/data/anime_mal_client.dart';

class Credentials extends MalCredentialStore {
  Map<String, dynamic>? value = {
    'connected': true,
    'device_token': 'test',
    'profile': {'id': 7},
  };
  @override
  Future<Map<String, dynamic>?> load() async => value;
  @override
  Future<void> save(Map<String, dynamic> v) async {
    value = v;
  }

  @override
  Future<void> clear() async {
    value = null;
  }
}

class Client extends MyAnimeListClient {
  Client(Credentials credentials) : super(credentials: credentials);
  Future<void> Function()? onUpdate;
  int writes = 0;
  int remoteEpisodes = 4;
  @override
  Future<Map<String, dynamic>> request(
    Map<String, dynamic> input, {
    bool anonymous = false,
    int? expectedOwner,
  }) async {
    if (input['action'] == 'anime_capabilities') return {'anime': true};
    if (input['action'] == 'anime_detail') {
      return {
        'anime': {'id': 1, 'episodes_watched': remoteEpisodes},
      };
    }
    writes++;
    await onUpdate?.call();
    // Como el servidor: confirma el anime y el número que quedó guardado.
    return {
      'anime': {
        'id': input['id'],
        'episodes_watched': input['episodes_watched'],
        'status': 'watching',
      },
    };
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late LibraryStore db;
  late Credentials credentials;
  late Client client;
  late AnimeMalClient mal;
  final entry = MalAnimeEntry.fromJson({
    'id': 1,
    'title': 'Test',
    'episodes_watched': 2,
  });
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    db = await LibraryStore.initialize(
      database: AppDatabase.forTesting(NativeDatabase.memory()),
    );
  });
  setUp(() async {
    await db.replaceRecords('anime_mal_links', []);
    await db.replaceRecords('anime_mal_pending', []);
    credentials = Credentials();
    client = Client(credentials);
    mal = AnimeMalClient(client: client, database: () async => db);
    await mal.link('test', entry);
    await mal.queueWatched('test', 3);
  });
  tearDown(() => client.http.close(force: true));
  test(
    'a progress update during synchronization rebases its expected remote count',
    () async {
      client.onUpdate = () async {
        await mal.queueWatched('test', 4);
      };
      await mal.flush();
      final row = (await db.readRecords('anime_mal_pending')).single;
      expect(row['episodes'], 4);
      expect(row['expected_episodes'], 3);
    },
  );
  test('a late response cannot overwrite a new explicit association', () async {
    client.onUpdate = () async {
      await mal.link(
        'test',
        MalAnimeEntry.fromJson({
          'id': 2,
          'title': 'New',
          'episodes_watched': 10,
        }),
      );
    };
    await mal.flush();
    final row = await db.getRecord('anime_mal_links', 'test');
    expect(row['malId'], 2);
    expect(row['remoteEpisodes'], 10);
  });
  test(
    'disconnect stops writes and preserves local pending progress',
    () async {
      await credentials.clear();
      await mal.flush();
      expect(client.writes, 0);
      expect(await db.readRecords('anime_mal_pending'), hasLength(1));
    },
  );
  test('conflict retains the pending update for explicit resolution', () async {
    // MAL va por detrás pero sigue rechazando el avance: no se puede
    // resolver solo y queda para revisión.
    client.remoteEpisodes = 1;
    client.onUpdate = () async {
      throw const MalFailure('Conflict', 409);
    };
    await mal.flush();
    final row = (await db.readRecords('anime_mal_pending')).single;
    expect(row['conflict'], 'Conflict');
    expect(row['episodes'], 3);
  });
  test('a conflict is set aside and does not block other anime', () async {
    await mal.link('zzz', entry);
    await mal.queueWatched('zzz', 3);
    client.remoteEpisodes = 1;
    // El envío de «test» y su reintento fallan; «zzz» se envía igual.
    client.onUpdate = () async {
      if (client.writes <= 2) throw const MalFailure('Conflict', 409);
    };
    await mal.flush();
    final rows = await db.readRecords('anime_mal_pending');
    expect(rows.map((row) => row['id']), ['test']);
    expect(client.writes, 3);
  });
  test('a resolved conflict is sent again at once', () async {
    client.remoteEpisodes = 1;
    client.onUpdate = () async {
      throw const MalFailure('Conflict', 409);
    };
    await mal.flush();
    await mal.flush();
    // Envío y reintento automático; después espera a la revisión.
    expect(client.writes, 2);
    client.onUpdate = null;
    client.remoteEpisodes = 2;
    await mal.resolve('test', keepRemote: false);
    expect(client.writes, 3);
    expect(await db.readRecords('anime_mal_pending'), isEmpty);
  });
  test('network errors still stop the queue for a later retry', () async {
    client.onUpdate = () async {
      throw const MalFailure('Sin conexión');
    };
    await expectLater(mal.flush(), throwsA(isA<MalFailure>()));
    final row = (await db.readRecords('anime_mal_pending')).single;
    expect(row['conflict'], isNull);
  });
  test('concurrent synchronization shares one request', () async {
    final gate = Completer<void>();
    client.onUpdate = () => gate.future;
    final a = mal.flush();
    final b = mal.flush();
    gate.complete();
    await Future.wait([a, b]);
    expect(client.writes, 1);
  });
  test(
    'keeping MAL resolves pending without touching local playback history',
    () async {
      await mal.resolve('test', keepRemote: true);
      expect(await db.readRecords('anime_mal_pending'), isEmpty);
      expect(
        (await db.getRecord('anime_mal_links', 'test'))['remoteEpisodes'],
        4,
      );
      expect(client.writes, 0);
    },
  );
  test(
    'explicit conflict resolution still refuses to reduce remote progress',
    () async {
      await expectLater(
        mal.resolve('test', keepRemote: false),
        throwsA(isA<MalFailure>()),
      );
      expect(await db.readRecords('anime_mal_pending'), hasLength(1));
      expect(client.writes, 0);
    },
  );
  test(
    'explicit local resolution rebases against current MAL before writing',
    () async {
      client.remoteEpisodes = 2;
      await mal.resolve('test', keepRemote: false);
      expect(await db.readRecords('anime_mal_pending'), isEmpty);
      expect(client.writes, 1);
    },
  );
}
