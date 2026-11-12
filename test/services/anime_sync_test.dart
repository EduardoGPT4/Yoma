import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yomashi/data/app_database.dart';
import 'package:yomashi/data/library_store.dart';
import 'package:yomashi/features/anime/data/anime_local_store.dart';
import 'package:yomashi/features/anime/data/anime_sync.dart';
import 'package:yomashi/features/anime/models/anime_models.dart';
import 'package:yomashi/services/myanimelist_client.dart';

class _Credentials extends MalCredentialStore {
  Map<String, dynamic>? value;
  _Credentials(int owner)
    : value = {
        'device_token': 'device-$owner',
        'connected': true,
        'profile': {'id': owner, 'name': 'Tester'},
      };
  @override
  Future<Map<String, dynamic>?> load() async => value;
  @override
  Future<void> save(Map<String, dynamic> value) async => this.value = value;
  @override
  Future<void> clear() async => value = null;
}

/// Servidor de sincronización en memoria con las reglas de yoma-sync.php.
class _Server {
  final rows = <String, Map<String, dynamic>>{};
  int rev = 0;
  bool available = true;
  int requests = 0;

  Map<String, dynamic> handle(int owner, Map<String, dynamic> input) {
    requests++;
    if (!available) throw const MalFailure('Operación no disponible.', 404);
    if (input['action'] == 'sync_push') {
      var accepted = 0;
      for (final change in (input['changes'] as List).cast<Map>()) {
        final id = '$owner|${change['kind']}|${change['key']}';
        final current = rows[id];
        if (current != null &&
            (current['updated_at'] as int) >= (change['updated_at'] as int)) {
          continue;
        }
        rows[id] = {
          'owner': owner,
          'kind': change['kind'],
          'key': change['key'],
          'payload': change['payload'] ?? {},
          'updated_at': change['updated_at'],
          'deleted': change['deleted'] == true,
          'rev': ++rev,
        };
        accepted++;
      }
      return {'accepted': accepted, 'cursor': rev};
    }
    final since = input['since'] as int;
    final changes =
        rows.values
            .where((r) => r['owner'] == owner && (r['rev'] as int) > since)
            .toList()
          ..sort((a, b) => (a['rev'] as int).compareTo(b['rev'] as int));
    return {
      'changes': changes,
      'cursor': changes.isEmpty ? rev : changes.last['rev'],
      'more': false,
    };
  }
}

class _Client extends MyAnimeListClient {
  final _Server server;
  final int owner;
  _Client(this.server, this.owner) : super(credentials: _Credentials(owner));
  @override
  Future<Map<String, dynamic>> request(
    Map<String, dynamic> input, {
    bool anonymous = false,
    int? expectedOwner,
  }) async {
    expect(expectedOwner, owner);
    return server.handle(owner, input);
  }
}

/// Un teléfono: su base de datos y su sincronización.
class _Phone {
  final LibraryStore db;
  final AnimeLocalStore store;
  final AnimeSync sync;
  final _Client client;
  _Phone(this.db, this.client)
    : store = AnimeLocalStore(database: () async => db),
      sync = AnimeSync(client: client, database: () async => db);
}

final anime = AnimeTitle.fromJson({
  'slug': 'frieren-2',
  'title': 'Frieren',
  'cover': 'https://cdn.example/f.jpg',
});
AnimeEpisode episode(int number) => AnimeEpisode.fromJson({
  'id': 130 + number,
  'slug': 'frieren-2',
  'number': '$number',
  'url': '',
});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Server server;
  // Cada teléfono con su propia base de datos (no la compartida de la app).
  Future<_Phone> phone({int owner = 7}) async => _Phone(
    LibraryStore(AppDatabase.forTesting(NativeDatabase.memory())),
    _Client(server, owner),
  );

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    server = _Server();
  });

  test(
    'dos teléfonos de la misma cuenta comparten biblioteca y progreso',
    () async {
      final a = await phone();
      await a.store.saveLibrary(
        anime,
        saved: true,
        favorite: true,
        status: 'watching',
      );
      await a.store.saveProgress(
        anime,
        episode(1),
        positionMs: 1400000,
        durationMs: 1420000,
        watched: true,
      );
      await a.store.saveProgress(
        anime,
        episode(2),
        positionMs: 300000,
        durationMs: 1420000,
      );
      final first = await a.sync.sync();
      expect(first.sent, 3);
      expect(await a.sync.pending(7), isEmpty);

      final b = await phone();
      final got = await b.sync.sync();
      expect(got.received, 3);
      final library = (await b.store.library()).single;
      expect(library['favorite'], isTrue);
      expect(library['status'], 'watching');
      expect(animeMap(library['anime'])['title'], 'Frieren');
      final progress = {
        for (final row in await b.store.progress())
          AnimeEpisode.fromJson(animeMap(row['episode'])).key: row,
      };
      expect(progress['frieren-2:1']!['watched'], isTrue);
      expect(progress['frieren-2:2']!['positionMs'], 300000);
      expect(animeMap(progress['frieren-2:2']!['episode'])['id'], 132);
      // Lo recibido no se vuelve a subir.
      expect(await b.sync.pending(7), isEmpty);
    },
  );

  test(
    'gana el cambio más reciente; lo de aquí más nuevo no se pisa',
    () async {
      final a = await phone(), b = await phone();
      await a.store.saveLibrary(
        anime,
        saved: true,
        favorite: false,
        status: 'planned',
      );
      await a.sync.sync();
      await b.sync.sync();
      await Future<void>.delayed(const Duration(milliseconds: 5));
      // B lo cambia después; A cambia algo antes de recibirlo pero más tarde.
      await b.store.saveLibrary(
        anime,
        saved: true,
        favorite: true,
        status: 'watching',
      );
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await a.store.saveLibrary(
        anime,
        saved: true,
        favorite: false,
        status: 'completed',
      );
      await b.sync.sync();
      await a.sync
          .sync(); // A sube su cambio, más reciente, y no aplica el de B.
      await b.sync.sync();
      for (final p in [a, b]) {
        expect((await p.store.library()).single['status'], 'completed');
      }
    },
  );

  test(
    'un episodio desmarcado en otro sitio no vuelve a marcarlo MAL',
    () async {
      final a = await phone(), b = await phone();
      await a.store.saveProgress(
        anime,
        episode(3),
        positionMs: 0,
        durationMs: 0,
        watched: true,
      );
      await a.sync.sync();
      await b.sync.sync();
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await a.store.markWatched(anime, episode(3), false);
      await a.sync.sync();
      await b.sync.sync();
      final row = (await b.store.progress()).single;
      expect(row['watched'], isFalse);
      expect(row['unmarked'], isTrue);
    },
  );

  test('lo que vino de MyAnimeList no se sube', () async {
    final a = await phone();
    await a.store.markWatchedFromMal(anime, [episode(1)]);
    expect(await a.sync.pending(7), isEmpty);
  });

  test('las cuentas no se mezclan', () async {
    final a = await phone(owner: 7), other = await phone(owner: 8);
    await a.store.saveLibrary(anime, saved: true, favorite: true);
    await a.sync.sync();
    expect((await other.sync.sync()).received, 0);
    expect(await other.store.library(), isEmpty);
  });

  test('sin el servidor nuevo o sin cuenta no hace nada ni falla', () async {
    final a = await phone();
    await a.store.saveLibrary(anime, saved: true, favorite: true);
    server.available = false;
    expect((await a.sync.sync()).ran, isFalse);
    expect(a.sync.unsupported, isTrue);
    // No insiste en cada cambio.
    final requests = server.requests;
    await a.sync.sync();
    expect(server.requests, requests);

    final b = await phone();
    await b.client.credentials.clear();
    expect((await b.sync.sync()).ran, isFalse);
  });
}
