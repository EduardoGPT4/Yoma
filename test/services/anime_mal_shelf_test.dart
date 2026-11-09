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
  @override
  Future<Map<String, dynamic>> request(
    Map<String, dynamic> input, {
    bool anonymous = false,
    int? expectedOwner,
  }) async {
    if (input['action'] == 'anime_capabilities') return {'anime': true};
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
}
