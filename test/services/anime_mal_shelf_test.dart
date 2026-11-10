import 'dart:async';

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

/// Listas de MAL en memoria: 7 es la cuenta conectada.
class ListClient extends MyAnimeListClient {
  ListClient(Credentials credentials) : super(credentials: credentials);
  final lists = <String, List<Map<String, dynamic>>>{
    'watching': [
      {
        'id': 1,
        'title': "Demons’ Crest",
        'episodes_watched': 1,
        'num_episodes': 12,
      },
      {'id': 2, 'title': 'Demons Crest', 'episodes_watched': 0},
    ],
    'plan_to_watch': [
      {'id': 3, 'title': 'cyberpunk:  edgerunners 2'},
      {'id': 4, 'title': 'No existe en YomaTV'},
    ],
  };
  int libraryCalls = 0;

  /// Sin conexión: toda petición a MAL falla.
  bool offline = false;

  /// Episodios enviados con `anime_update`, por id de MAL.
  final updates = <int, int>{};
  @override
  Future<Map<String, dynamic>> request(
    Map<String, dynamic> input, {
    bool anonymous = false,
    int? expectedOwner,
  }) async {
    if (offline) throw const MalFailure('Sin conexión de prueba.');
    if (input['action'] == 'anime_capabilities') return {'anime': true};
    if (input['action'] == 'anime_update') {
      updates[input['id'] as int] = input['episodes_watched'] as int;
      return {};
    }
    if (input['action'] == 'anime_library') {
      libraryCalls++;
      final status = input['status'] as String;
      return {
        'items': [
          for (final item in lists[status] ?? const [])
            {...item, 'status': status},
        ],
      };
    }
    return {};
  }
}

/// Catálogo de YomaTV que responde a la búsqueda por texto.
class SearchSource extends TestAnimeSource {
  final titles = {
    'demons-crest': "Demons' Crest",
    'cyberpunk-edgerunners-2': 'Cyberpunk: Edgerunners 2',
    'demons-crest-special': "Demons' Crest Special",
  };
  final searches = <String>[];
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
  }) async {
    searches.add(search);
    final words = search.toLowerCase().split(RegExp(r'[^a-z0-9]+'))
      ..removeWhere((w) => w.isEmpty);
    return {
      'items': [
        for (final entry in titles.entries)
          if (words.any(entry.value.toLowerCase().contains))
            {'slug': entry.key, 'title': entry.value},
      ],
      'page': 1,
      'pages': 1,
    };
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late LibraryStore db;
  late Credentials credentials;
  late ListClient client;
  late AnimeMalClient mal;
  late SearchSource source;
  late AnimeMalShelf shelf;

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
      'anime_library',
      'anime_cache',
    ]) {
      await db.replaceRecords(ns, []);
    }
    credentials = Credentials();
    client = ListClient(credentials);
    mal = AnimeMalClient(client: client, database: () async => db);
    source = SearchSource();
    shelf = AnimeMalShelf(mal: mal, source: source, database: () async => db);
  });
  tearDown(() => client.http.close(force: true));

  test(
    'only exact names match; case, spaces and typographic quotes are unified',
    () {
      AnimeTitle title(String value) =>
          AnimeTitle.fromJson({'slug': 's', 'title': value});
      expect(
        AnimeMalShelf.sameName("Demons’ Crest", title("Demons' Crest")),
        isTrue,
      );
      expect(
        AnimeMalShelf.sameName('DEMONS\' CREST ', title("Demons' Crest")),
        isTrue,
      );
      expect(
        AnimeMalShelf.sameName('Demons Crest', title("Demons' Crest")),
        isFalse,
      );
      expect(
        AnimeMalShelf.sameName("Demons' Crest", title("Demons' Crest Special")),
        isFalse,
      );
      expect(AnimeMalShelf.sameName('', title('')), isFalse);
    },
  );

  test(
    'refresh keeps MAL order, ignores partial names and stores the result',
    () async {
      final snapshot = await shelf.refresh(7);
      expect(snapshot.watching.map((e) => e.anime.slug), ['demons-crest']);
      expect(snapshot.watching.single.entry.watched, 1);
      expect(snapshot.planned.map((e) => e.anime.slug), [
        'cyberpunk-edgerunners-2',
      ]);

      final cached = await shelf.cached(7);
      expect(cached!.watching.single.anime.title, "Demons' Crest");
      expect(cached.planned.single.entry.title, 'cyberpunk:  edgerunners 2');
      // Otra cuenta no ve esta copia.
      expect(await shelf.cached(8), isNull);
    },
  );

  test('known matches are not searched again on the next refresh', () async {
    await shelf.refresh(7);
    final first = source.searches.length;
    expect(first, 4);
    await shelf.refresh(7);
    // Las coincidencias y las ausencias recientes salen del teléfono.
    expect(source.searches.length, first);
    client.lists['watching']!.add({
      'id': 5,
      'title': 'Cyberpunk: Edgerunners 2',
    });
    await shelf.refresh(7);
    expect(source.searches.length, first + 1);
  });

  test(
    'controller shows the stored shelf without asking MAL while it is fresh',
    () async {
      await shelf.refresh(7);
      final calls = client.libraryCalls;
      final controller = AnimeController(
        source: source,
        mal: mal,
        store: AnimeLocalStore(database: () async => db),
      );
      addTearDown(controller.dispose);
      await controller.loadMalShelf();
      expect(controller.malWatching.single.anime.slug, 'demons-crest');
      expect(
        controller.malPlanned.single.anime.slug,
        'cyberpunk-edgerunners-2',
      );
      expect(client.libraryCalls, calls);

      await controller.loadMalShelf(force: true);
      expect(client.libraryCalls, calls + 2);

      credentials.value = null;
      await controller.loadMalShelf();
      expect(controller.malWatching, isEmpty);
    },
  );

  test(
    'starting from the MAL shelf links once and never replaces a link',
    () async {
      final controller = AnimeController(
        source: source,
        mal: mal,
        store: AnimeLocalStore(database: () async => db),
      );
      addTearDown(controller.dispose);
      final entry = MalAnimeEntry.fromJson({
        'id': 1,
        'title': "Demons' Crest",
        'episodes_watched': 1,
        'status': 'watching',
      });
      expect(await controller.autoLinkMal('demons-crest', entry), isTrue);
      final link = await mal.linkOf('demons-crest');
      expect(link!['malId'], 1);
      expect(link['remoteEpisodes'], 1);

      final other = MalAnimeEntry.fromJson({'id': 99, 'title': 'Otro'});
      expect(await controller.autoLinkMal('demons-crest', other), isFalse);
      expect((await mal.linkOf('demons-crest'))!['malId'], 1);

      // Ver un episodio después de vincular deja el avance listo para MAL.
      await mal.queueWatched('demons-crest', 2);
      expect((await mal.pending()).single['episodes'], 2);
    },
  );

  group('watching syncs through the MAL list match', () {
    late StreamController<bool> network;
    late AnimeController controller;
    final demons = AnimeTitle.fromJson({
      'slug': 'demons-crest',
      'title': "Demons' Crest",
    });
    AnimeEpisode episode(String number) => AnimeEpisode.fromJson({
      'id': int.parse(number),
      'slug': 'demons-crest',
      'number': number,
    });

    setUp(() async {
      network = StreamController<bool>.broadcast();
      controller = AnimeController(
        source: source,
        mal: mal,
        store: AnimeLocalStore(database: () async => db),
        connectivity: () => network.stream,
      );
      await shelf.refresh(7);
    });

    tearDown(() async {
      controller.dispose();
      await network.close();
    });

    test(
      'an anime from the list is linked and synced from any screen',
      () async {
        // Se abre desde la ficha o Explorar: no hay vinculación previa.
        expect(await mal.linkOf('demons-crest'), isNull);
        await controller.progress(
          demons,
          episode('2'),
          1000,
          1000,
          watched: true,
        );
        await controller.syncMal();
        expect((await mal.linkOf('demons-crest'))!['malId'], 1);
        expect(client.updates, {1: 2});
        expect(await mal.pending(), isEmpty);
      },
    );

    test('an anime outside the MAL list is not linked', () async {
      final other = AnimeTitle.fromJson({'slug': 'otro', 'title': 'Otro'});
      await controller.progress(
        other,
        AnimeEpisode.fromJson({'id': 9, 'slug': 'otro', 'number': '1'}),
        1000,
        1000,
        watched: true,
      );
      await controller.syncMal();
      expect(await mal.linkOf('otro'), isNull);
      expect(client.updates, isEmpty);
    });

    test(
      'episodes watched offline are uploaded when the network returns',
      () async {
        await controller.initialize();
        client.offline = true;
        await controller.progress(
          demons,
          episode('3'),
          1000,
          1000,
          watched: true,
        );
        await controller.syncMal();
        // Queda en la cola del teléfono, vinculado con la copia guardada.
        expect((await mal.pending()).single['episodes'], 3);
        expect(client.updates, isEmpty);

        client.offline = false;
        network.add(true);
        for (var i = 0; i < 20 && client.updates.isEmpty; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
        expect(client.updates, {1: 3});
        expect(await mal.pending(), isEmpty);
      },
    );

    test(
      'episodes watched before linking are sent, never lowering MAL',
      () async {
        // Visto en el teléfono antes de esta versión: episodio 4, MAL tiene 1.
        await AnimeLocalStore(database: () async => db).saveProgress(
          demons,
          episode('4'),
          positionMs: 1000,
          durationMs: 1000,
          watched: true,
        );
        final fresh = AnimeController(
          source: source,
          mal: mal,
          store: AnimeLocalStore(database: () async => db),
          connectivity: () => network.stream,
        );
        addTearDown(fresh.dispose);
        await fresh.initialize();
        for (var i = 0; i < 50 && client.updates.isEmpty; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
        expect(client.updates, {1: 4});

        // Si MAL ya tiene más episodios que el teléfono, no se toca.
        client.updates.clear();
        client.lists['watching']![0]['episodes_watched'] = 9;
        await fresh.loadMalShelf(force: true);
        await Future<void>.delayed(const Duration(milliseconds: 50));
        expect(client.updates, isEmpty);
      },
    );
  });
}
