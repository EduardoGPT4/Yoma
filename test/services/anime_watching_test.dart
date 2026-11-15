import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yomashi/data/app_database.dart';
import 'package:yomashi/data/library_store.dart';
import 'package:yomashi/features/anime/data/anime_controller.dart';
import 'package:yomashi/features/anime/data/anime_local_store.dart';
import 'package:yomashi/features/anime/data/anime_mal_client.dart';
import 'package:yomashi/features/anime/data/anime_mal_shelf.dart';
import 'package:yomashi/features/anime/data/local_anime_downloads.dart';
import 'package:yomashi/features/anime/models/anime_models.dart';

import 'anime_mal_test.dart' show Credentials;
import 'mal_pull_watched_test.dart' show Catalog, WatchingMal;

/// Cola de descargas simulada con Android compatible: lo pedido queda en
/// la cola como en el teléfono.
class _Queue extends LocalAnimeDownloads {
  final items = <Map<String, dynamic>>[];
  List<String> get numbers => [for (final i in items) '${i['number']}'];

  @override
  Future<Map<String, dynamic>> snapshot() async => {
    'items': [...items],
    'supported': true,
    'wifiOnly': true,
    'paused': false,
  };

  @override
  Future<String> enqueue(
    AnimeTitle anime,
    AnimeEpisode episode,
    String language,
  ) async {
    items.add({
      ...payload(anime, episode, language),
      'key': '${anime.slug}:${episode.number}:$language',
      'state': 'queued',
    });
    return 'added';
  }

  /// Acciones recibidas; como Android, rechaza borrar mientras se descarga
  /// algo sin pausar y la primera vez tras pausar (aún suelta el archivo).
  final controls = <String>[];
  bool paused = false, released = false;
  @override
  Future<void> control(String action, {String? key, bool? value}) async {
    controls.add(key == null ? action : '$action $key');
    switch (action) {
      case 'pauseAll':
        paused = true;
      case 'resumeAll':
        paused = false;
      case 'delete' || 'cancel':
        final busy = items.any((i) => i['state'] == 'downloading');
        if (busy && !paused) throw StateError('Pausa las descargas.');
        if (!released) {
          released = true;
          throw StateError('La descarga se está deteniendo.');
        }
        items.removeWhere((i) => i['key'] == key);
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late LibraryStore db;
  late Credentials credentials;
  late WatchingMal server;
  late AnimeMalClient mal;
  late Catalog source;
  late _Queue queue;

  final uno = AnimeTitle.fromJson({'slug': 'uno', 'title': 'Uno'});
  AnimeEpisode episode(int n) =>
      AnimeEpisode.fromJson({'id': 100 + n, 'slug': 'uno', 'number': '$n'});

  AnimeController controller() {
    final app = AnimeController(
      source: source,
      mal: mal,
      store: AnimeLocalStore(database: () async => db),
      transfers: queue,
      connectivity: () => const Stream.empty(),
    );
    addTearDown(app.dispose);
    return app;
  }

  /// Lee la cola, carga la lista de MAL y espera a que todo termine.
  Future<void> settle(AnimeController app, {bool shelf = true}) async {
    await app.refreshDownloads();
    if (shelf) await app.loadMalShelf(force: true);
    for (var i = 0; i < 6; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await app.syncWatching();
    }
  }

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    db = await LibraryStore.initialize(
      database: AppDatabase.forTesting(NativeDatabase.memory()),
    );
  });
  setUp(() async {
    for (final ns in [
      AnimeMalShelf.namespace,
      AnimeControllerWatching.autoNamespace,
      AnimeControllerWatching.adoptedNamespace,
      AnimeControllerWatching.watchedNamespace,
      'anime_mal_links',
      'anime_mal_pending',
      'anime_progress',
      'anime_cache',
      'anime_library',
      'anime_settings',
    ]) {
      await db.replaceRecords(ns, []);
    }
    credentials = Credentials();
    server = WatchingMal(credentials);
    mal = AnimeMalClient(client: server, database: () async => db);
    source = Catalog();
    queue = _Queue();
  });
  tearDown(() => server.http.close(force: true));

  test('«Viendo» de MAL entra en la biblioteca, se vincula y se descarga '
      'lo siguiente sin ver', () async {
    final app = controller();
    await settle(app);
    expect(app.saved['uno']!['saved'], true);
    expect(app.saved['uno']!['status'], 'watching');
    expect((await mal.linkOf('uno'))!['malId'], 1);
    // MAL tiene 5 vistos: se piden el 6 y el 7.
    expect(queue.numbers, ['6', '7']);
    expect(app.downloads.map((d) => d.number), ['6', '7']);

    // Al ver el 6 se pide el siguiente que falta (el 8).
    await app.mark(uno, episode(6), true);
    await settle(app, shelf: false);
    expect(queue.numbers, ['6', '7', '8']);
  });

  test('una descarga automática borrada no se vuelve a pedir', () async {
    final app = controller();
    await settle(app);
    queue.items.removeWhere((i) => i['number'] == '6');
    await settle(app);
    expect(queue.numbers, ['7']);
  });

  test('sin MAL: lo que está en «Viendo» en la biblioteca', () async {
    credentials.value = null;
    final app = controller();
    await app.refreshDownloads();
    await app.updateLibrary(uno, savedValue: true, status: 'watching');
    await settle(app, shelf: false);
    expect(queue.numbers, ['1', '2']);
  });

  test('lo planeado no se descarga y pasa a «Viendo» al verlo', () async {
    credentials.value = null;
    final app = controller();
    await app.refreshDownloads();
    await app.updateLibrary(uno, savedValue: true, status: 'planned');
    await settle(app, shelf: false);
    expect(queue.items, isEmpty);
    await app.mark(uno, episode(1), true);
    await settle(app, shelf: false);
    expect(app.saved['uno']!['status'], 'watching');
    expect(queue.numbers, ['2', '3']);
  });

  test('desactivada o con otro número de episodios por adelantado', () async {
    final app = controller();
    await app.setAutoDownload(enabled: false);
    await settle(app);
    expect(queue.items, isEmpty);
    // La biblioteca sí queda vinculada con MAL.
    expect(app.saved['uno']!['status'], 'watching');
    await app.setAutoDownload(enabled: true, ahead: 1);
    await settle(app);
    expect(queue.numbers, ['6']);
    // Se recuerda en el teléfono.
    final reopened = controller();
    await reopened.initialize();
    expect((reopened.autoDownload, reopened.autoDownloadAhead), (true, 1));
  });

  test(
    'un anime de MAL quitado de la biblioteca no se vuelve a añadir',
    () async {
      final app = controller();
      await app.setAutoDownload(enabled: false);
      await settle(app);
      await app.updateLibrary(uno, savedValue: false);
      await settle(app);
      expect(app.saved['uno']!['saved'], false);
    },
  );

  test('borrar desde la página pausa la cola, borra y la reanuda', () async {
    credentials.value = null;
    final app = controller();
    queue.items.addAll([
      {
        'key': 'uno:1:SUB',
        'slug': 'uno',
        'number': '1',
        'state': 'downloading',
      },
      {'key': 'uno:2:SUB', 'slug': 'uno', 'number': '2', 'state': 'queued'},
    ]);
    await app.refreshDownloads();
    await app.removeDownloads([app.downloads.last]);
    expect(queue.controls, [
      'pauseAll',
      'cancel uno:2:SUB',
      'cancel uno:2:SUB',
      'resumeAll',
    ]);
    expect(queue.numbers, ['1']);
    expect(app.downloads.map((d) => d.number), ['1']);
  });

  group('episodios vistos', () {
    late AnimeController app;
    late DateTime now;
    const day = Duration(days: 1);

    /// Episodio [n] de «Uno» ya descargado.
    Map<String, dynamic> done(int n) => {
      'key': 'uno:$n:SUB',
      'slug': 'uno',
      'number': '$n',
      'state': 'done',
      'file': '/x/uno-$n.mp4',
    };

    setUp(() async {
      credentials.value = null;
      queue.released = true;
      now = DateTime(2026, 11, 1, 12);
      app = controller()..clock = () => now;
      await app.setAutoDownload(enabled: false);
      queue.items.addAll([done(1), done(2)]);
      await app.refreshDownloads();
    });

    test('se borran una semana después de verlos', () async {
      await app.mark(uno, episode(1), true);
      await settle(app, shelf: false);
      expect(queue.numbers, ['1', '2']);
      now = now.add(const Duration(days: 6, hours: 23));
      await settle(app, shelf: false);
      expect(queue.numbers, ['1', '2']);
      now = now.add(const Duration(hours: 2));
      await settle(app, shelf: false);
      // Solo el visto; el 2 sin ver se conserva.
      expect(queue.numbers, ['2']);
      expect(app.downloads.map((d) => d.number), ['2']);
      // Sigue visto: se borra el archivo, no el progreso.
      expect(app.positions['uno:1']!['watched'], true);
    });

    test('lo visto en MAL cuenta desde que el teléfono lo sabe', () async {
      final db = await app.store.database();
      await db.putRecord('anime_progress', 'uno:2', {
        'slug': 'uno',
        'anime': uno.toJson(),
        'episode': episode(2).toJson(),
        'watched': true,
        'updatedAt': 0,
        'source': 'mal',
      });
      final reopened = controller()..clock = () => now;
      await reopened.initialize();
      await reopened.setAutoDownload(enabled: false);
      await settle(reopened, shelf: false);
      now = now.add(const Duration(days: 6));
      await settle(reopened, shelf: false);
      expect(queue.numbers, ['1', '2']);
      now = now.add(day);
      await settle(reopened, shelf: false);
      expect(queue.numbers, ['1']);
    });

    test('desmarcado vuelve a contar; desactivado no borra', () async {
      await app.mark(uno, episode(1), true);
      await settle(app, shelf: false);
      now = now.add(const Duration(days: 5));
      // Desmarcado y vuelto a marcar sin que pase la limpieza entre medias.
      await app.mark(uno, episode(1), false);
      await app.mark(uno, episode(1), true);
      await settle(app, shelf: false);
      now = now.add(const Duration(days: 3));
      await settle(app, shelf: false);
      expect(queue.numbers, ['1', '2']);

      await app.setAutoDownload(deleteWatched: false);
      now = now.add(const Duration(days: 30));
      await settle(app, shelf: false);
      expect(queue.numbers, ['1', '2']);
      await app.setAutoDownload(deleteWatched: true);
      await settle(app, shelf: false);
      expect(queue.numbers, ['2']);
    });
  });
}
