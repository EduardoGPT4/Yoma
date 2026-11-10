import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yomashi/data/app_database.dart';
import 'package:yomashi/data/library_store.dart';
import 'package:yomashi/features/anime/data/anime_mal_client.dart';
import 'package:yomashi/services/myanimelist_client.dart';

import 'anime_mal_test.dart' show Credentials;

/// Aplica las mismas reglas que `anime_update` en el servidor
/// (server/private/yoma-anime-mal.php).
class ServerRules extends MyAnimeListClient {
  ServerRules(Credentials credentials) : super(credentials: credentials);
  int count = 0, total = 12, patches = 0, rejections = 0;

  @override
  Future<Map<String, dynamic>> request(
    Map<String, dynamic> input, {
    bool anonymous = false,
    int? expectedOwner,
  }) async {
    Map<String, dynamic> anime() => {
      'id': 1,
      'title': 'Test',
      'episodes_watched': count,
      'num_episodes': total,
    };
    switch (input['action']) {
      case 'anime_capabilities':
        return {'anime': true};
      case 'anime_detail':
        return {'anime': anime()};
      case 'anime_update':
        final wanted = input['episodes_watched'] as int;
        final expected = input['expected_episodes'] as int;
        if (wanted == count && wanted >= expected) return {'anime': anime()};
        String? reason;
        if (count != expected) reason = 'El progreso cambió en MAL.';
        if (reason == null && wanted < count) reason = 'No se reducirá.';
        if (reason == null && total > 0 && wanted > total) {
          reason = 'El progreso supera los episodios del anime en MAL.';
        }
        if (reason != null) {
          rejections++;
          throw MalFailure(reason, 409);
        }
        count = wanted;
        patches++;
        return {'anime': anime()};
    }
    return {};
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late LibraryStore db;
  late ServerRules server;
  late AnimeMalClient mal;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    db = await LibraryStore.initialize(
      database: AppDatabase.forTesting(NativeDatabase.memory()),
    );
  });

  setUp(() async {
    await db.replaceRecords('anime_mal_links', []);
    await db.replaceRecords('anime_mal_pending', []);
    server = ServerRules(Credentials());
    mal = AnimeMalClient(client: server, database: () async => db);
  });
  tearDown(() => server.http.close(force: true));

  /// Vinculado con la copia de la lista, que creía que MAL iba por [known].
  Future<void> watch(int known, int episode) async {
    await mal.link(
      'test',
      MalAnimeEntry.fromJson({
        'id': 1,
        'title': 'Test',
        'episodes_watched': known,
      }),
    );
    await mal.queueWatched('test', episode);
    await mal.flush();
  }

  Future<int> linkedRemote() async =>
      (await db.getRecord('anime_mal_links', 'test'))['remoteEpisodes'] as int;

  test('without changes in MAL the episode is sent directly', () async {
    server.count = 2;
    await watch(2, 3);
    expect(server.count, 3);
    expect(server.rejections, 0);
    expect(await mal.pending(), isEmpty);
    expect(await linkedRemote(), 3);
  });

  test('MAL behind the saved copy: rebased and sent at once', () async {
    // La copia decía 2, pero en MAL se bajó a 1 desde la web.
    server.count = 1;
    await watch(2, 3);
    expect(server.count, 3);
    expect(server.patches, 1);
    expect(await mal.pending(), isEmpty);
    expect(await linkedRemote(), 3);
  });

  test(
    'MAL already ahead: its number is kept and nothing is lowered',
    () async {
      // Se vieron episodios en otra app: MAL va por el 5.
      server.count = 5;
      await watch(2, 3);
      expect(server.count, 5);
      expect(server.patches, 0);
      expect(await mal.pending(), isEmpty);
      expect(await linkedRemote(), 5);
      // Un episodio posterior se envía con el número correcto.
      await mal.queueWatched('test', 6);
      await mal.flush();
      expect(server.count, 6);
      expect(server.rejections, 1);
    },
  );

  test('a wrong link stays as a conflict for review', () async {
    // El episodio 20 no existe en un anime de 12 en MAL.
    server.count = 5;
    await watch(2, 20);
    expect(server.count, 5);
    expect(server.patches, 0);
    final row = (await mal.pending()).single;
    expect(row['episodes'], 20);
    expect(row['conflict'], isNotNull);
  });
}
