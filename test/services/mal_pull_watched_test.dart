import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yomashi/data/app_database.dart';
import 'package:yomashi/data/library_store.dart';
import 'package:yomashi/features/anime/data/anime_controller.dart';
import 'package:yomashi/features/anime/data/anime_local_store.dart';
import 'package:yomashi/features/anime/data/anime_mal_client.dart';
import 'package:yomashi/features/anime/data/anime_mal_shelf.dart';
import 'package:yomashi/features/anime/models/anime_models.dart';
import 'package:yomashi/services/myanimelist_client.dart';

import '../unit/native_anime_test.dart' show TestAnimeSource;
import 'anime_mal_test.dart' show Credentials;

/// MAL simulado: lista «Viendo» y envíos recibidos. No es MyAnimeList.
class WatchingMal extends MyAnimeListClient {
  WatchingMal(Credentials credentials) : super(credentials: credentials);
  final watching = <Map<String, dynamic>>[
    {
      'id': 1,
      'title': 'Uno',
      'episodes_watched': 5,
      'num_episodes': 12,
      'status': 'watching',
    },
  ];
  final updates = <int, int>{};
  bool offline = false;

  @override
  Future<Map<String, dynamic>> request(
    Map<String, dynamic> input, {
    bool anonymous = false,
    int? expectedOwner,
  }) async {
    if (offline) throw const MalFailure('Sin conexión de prueba.');
    switch (input['action']) {
      case 'anime_capabilities':
        return {'anime': true};
      case 'anime_library':
        return {'items': input['status'] == 'watching' ? watching : const []};
      case 'anime_update':
        final id = input['id'] as int, wanted = input['episodes_watched'];
        updates[id] = wanted as int;
        return {
          'anime': {'id': id, 'episodes_watched': wanted, 'status': 'watching'},
        };
    }
    return {};
  }
}

/// YomaTV simulado con «Uno» de 8 episodios publicados.
class Catalog extends TestAnimeSource {
  int detailCalls = 0;
  int published = 8;
  @override
  Future<Map<String, dynamic>> catalog({
    int page = 1,
    String search = '',
    String category = '',
    String season = '',
    String year = '',
    String genre = '',
    String order = 'recent',
    bool seasonal = false,
  }) async => {
    'items': [
      if (search == 'Uno') {'slug': 'uno', 'title': 'Uno', 'episodes': 8},
    ],
    'page': 1,
    'pages': 1,
  };

  @override
  Future<Map<String, dynamic>> detail(String slug) async {
    detailCalls++;
    return {
      'anime': {'slug': slug, 'title': 'Uno'},
      'episodes': [
        for (var i = 1; i <= published; i++)
          {'id': 100 + i, 'slug': slug, 'number': '$i'},
      ],
    };
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late LibraryStore db;
  late Credentials credentials;
  late WatchingMal server;
  late AnimeMalClient mal;
  late Catalog source;

  final uno = AnimeTitle.fromJson({'slug': 'uno', 'title': 'Uno'});
  AnimeEpisode episode(int n) =>
      AnimeEpisode.fromJson({'id': 100 + n, 'slug': 'uno', 'number': '$n'});

  AnimeController controller() {
    final app = AnimeController(
      source: source,
      mal: mal,
      store: AnimeLocalStore(database: () async => db),
      connectivity: () => const Stream.empty(),
    );
    addTearDown(app.dispose);
    return app;
  }

  /// Carga la lista de MAL y espera a que termine la sincronización.
  Future<void> load(AnimeController app) async {
    await app.loadMalShelf(force: true);
    for (var i = 0; i < 100; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
      if (app.positions.values.any((r) => r['watched'] == true)) break;
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }

  List<int> watched(AnimeController app) => [
    for (final row in app.positions.values)
      if (row['watched'] == true)
        int.parse('${animeMap(row['episode'])['number']}'),
  ]..sort();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    db = await LibraryStore.initialize(
      database: AppDatabase.forTesting(NativeDatabase.memory()),
    );
  });
  setUp(() async {
    for (final ns in [
      AnimeMalShelf.namespace,
      'anime_mal_links',
      'anime_mal_pending',
      'anime_progress',
      'anime_cache',
    ]) {
      await db.replaceRecords(ns, []);
    }
    credentials = Credentials();
    server = WatchingMal(credentials);
    mal = AnimeMalClient(client: server, database: () async => db);
    source = Catalog();
  });
  tearDown(() => server.http.close(force: true));

  test('los episodios vistos en MAL quedan vistos en YomaTV', () async {
    final app = controller();
    await load(app);
    expect(watched(app), [1, 2, 3, 4, 5]);
    // Vinculado automáticamente con la entrada de «Viendo».
    final link = await mal.linkOf('uno');
    expect(link!['malId'], 1);
    expect(link['remoteEpisodes'], 5);
    // Ya estaban en MAL: no se reenvían.
    expect(server.updates, isEmpty);
    expect(await mal.pending(), isEmpty);
    // No se reprodujeron aquí: no aparecen en el historial ni en «Continuar».
    expect(app.history, isEmpty);
    expect(app.continuing, isEmpty);
    // «Reproducir» sigue por el primero sin ver.
    final detail = await app.detail('uno');
    expect(app.resumeEpisode(detail)!.number, '6');

    // Se guarda en el teléfono.
    final reopened = controller();
    await reopened.initialize();
    expect(watched(reopened), [1, 2, 3, 4, 5]);
  });

  test('solo se marca lo que YomaTV ya publicó', () async {
    source.published = 3;
    server.watching[0]['episodes_watched'] = 5;
    final app = controller();
    await load(app);
    expect(watched(app), [1, 2, 3]);
    // Cuando salgan más episodios se completan en la siguiente carga.
    source.published = 8;
    app.details.clear();
    await app.store.clearMetadataCache();
    await load(app);
    expect(watched(app), [1, 2, 3, 4, 5]);
  });

  test('un episodio a medias pasa a visto conservando su posición', () async {
    final app = controller();
    await app.progress(uno, episode(4), 300, 1000);
    await load(app);
    final row = app.positions['uno:4']!;
    expect(row['watched'], true);
    expect(row['positionMs'], 300);
    // Sí se reprodujo aquí: sigue en el historial.
    expect(app.history.map((r) => animeMap(r['episode'])['number']), ['4']);
  });

  test('un episodio que el usuario desmarcó no se vuelve a marcar', () async {
    final app = controller();
    await load(app);
    // Sin conexión, para que el deshacer no llegue a MAL.
    server.offline = true;
    await app.mark(uno, episode(3), false);
    await app.mal.flush().catchError((_) {});
    await mal.replaceRecordsForTest(db);
    server.offline = false;
    await load(app);
    expect(watched(app), [1, 2, 4, 5]);
    expect(app.positions['uno:3']!['unmarked'], true);

    // Marcarlo de nuevo quita la marca de desmarcado.
    await app.mark(uno, episode(3), true);
    expect(app.positions['uno:3']!.containsKey('unmarked'), isFalse);
  });

  test('con un envío pendiente manda lo del teléfono', () async {
    final app = controller();
    await mal.link(
      'uno',
      MalAnimeEntry.fromJson({'id': 1, 'title': 'Uno', 'episodes_watched': 1}),
    );
    server.offline = true;
    await app.mark(uno, episode(2), true);
    expect(await mal.hasPending('uno'), isTrue);
    server.offline = false;
    // La lista guardada dice 5, pero hay un envío pendiente.
    await app.malShelf.refresh(7);
    await app.loadMalShelf();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(watched(app), [2]);
  });

  test('un anime vinculado con otra entrada de MAL no se toca', () async {
    await mal.link(
      'uno',
      MalAnimeEntry.fromJson({
        'id': 99,
        'title': 'Otro',
        'episodes_watched': 0,
      }),
    );
    final app = controller();
    await load(app);
    expect(watched(app), isEmpty);
    expect((await mal.linkOf('uno'))!['malId'], 99);
  });

  group('animes vinculados a mano', () {
    setUp(() {
      // En MAL tiene otro nombre: no coincide con «Uno» de YomaTV.
      server.watching
        ..clear()
        ..add({
          'id': 3,
          'title': 'Ichi no Monogatari',
          'episodes_watched': 4,
          'num_episodes': 12,
          'status': 'watching',
        });
    });

    test('se marcan sus episodios vistos en MAL', () async {
      await mal.link(
        'uno',
        MalAnimeEntry.fromJson({
          'id': 3,
          'title': 'Ichi no Monogatari',
          'episodes_watched': 1,
        }),
      );
      final app = controller();
      await load(app);
      // No aparece en la sección de MAL (el nombre no coincide)…
      expect(app.malWatching, isEmpty);
      // …pero sus episodios vistos sí pasan a YomaTV.
      expect(watched(app), [1, 2, 3, 4]);
      expect((await mal.linkOf('uno'))!['remoteEpisodes'], 4);
      expect(server.updates, isEmpty);
    });

    test('se guarda la lista completa para la próxima vez', () async {
      await mal.link(
        'uno',
        MalAnimeEntry.fromJson({
          'id': 3,
          'title': 'Ichi',
          'episodes_watched': 0,
        }),
      );
      await controller().malShelf.refresh(7);
      // Sin red, la copia guardada basta.
      server.offline = true;
      final app = controller();
      await app.loadMalShelf();
      for (var i = 0; i < 100 && watched(app).isEmpty; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      expect(watched(app), [1, 2, 3, 4]);
    });

    test('un vínculo con algo que no está en «Viendo» no marca nada', () async {
      await mal.link(
        'uno',
        MalAnimeEntry.fromJson({
          'id': 50,
          'title': 'Otro',
          'episodes_watched': 0,
        }),
      );
      final app = controller();
      await load(app);
      expect(watched(app), isEmpty);
    });

    test('al vincular desde la pantalla de MAL se marca enseguida', () async {
      final app = controller();
      final entry = MalAnimeEntry.fromJson({
        'id': 8,
        'title': 'Hachi',
        'episodes_watched': 6,
        'status': 'completed',
      });
      await mal.link('uno', entry);
      expect(await app.applyMalProgress('uno', entry), 6);
      expect(watched(app), [1, 2, 3, 4, 5, 6]);
      // Repetirlo no vuelve a marcar nada.
      expect(await app.applyMalProgress('uno', entry), 0);
      // Con otra entrada de MAL vinculada no se toca.
      expect(
        await app.applyMalProgress(
          'uno',
          MalAnimeEntry.fromJson({'id': 9, 'episodes_watched': 8}),
        ),
        0,
      );
    });
  });

  test('lo visto solo en el teléfono sigue subiendo a MAL', () async {
    final app = controller();
    for (var n = 1; n <= 7; n++) {
      await app.progress(uno, episode(n), 1000, 1000, watched: true);
    }
    server.updates.clear();
    await load(app);
    for (var i = 0; i < 50 && server.updates.isEmpty; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(server.updates, {1: 7});
    expect(watched(app), [1, 2, 3, 4, 5, 6, 7]);
  });

  test('MAL por detrás del teléfono no desmarca nada', () async {
    server.watching[0]['episodes_watched'] = 2;
    final app = controller();
    for (var n = 1; n <= 4; n++) {
      await app.progress(uno, episode(n), 1000, 1000, watched: true);
    }
    await load(app);
    expect(watched(app), [1, 2, 3, 4]);
  });
}

extension on AnimeMalClient {
  /// Retira el deshacer encolado sin conexión: simula que el servidor no lo
  /// admitió, para comprobar solo la marca local de desmarcado.
  Future<void> replaceRecordsForTest(LibraryStore db) =>
      db.replaceRecords('anime_mal_pending', []);
}
