import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yomashi/data/app_database.dart';
import 'package:yomashi/data/library_store.dart';
import 'package:yomashi/features/anime/data/anime_local_store.dart';
import 'package:yomashi/features/anime/data/anime_controller.dart';
import 'package:yomashi/features/anime/data/yomatv_source.dart';
import 'package:yomashi/features/anime/models/anime_models.dart';

class TestAnimeSource extends YomaTvSource {
  final requests = <Completer<Map<String, dynamic>>>[];
  bool deferred = false;
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
    if (!deferred) return {'items': [], 'page': 1, 'pages': 1};
    final response = Completer<Map<String, dynamic>>();
    requests.add(response);
    return response.future;
  }
}

class RealHttpOverrides extends HttpOverrides {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late LibraryStore db;
  late AnimeLocalStore store;
  final anime = AnimeTitle.fromJson({'slug': 'test', 'title': 'Test'});
  final episode = AnimeEpisode.fromJson({
    'id': 1,
    'slug': 'test',
    'number': '1',
  });
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    db = await LibraryStore.initialize(
      database: AppDatabase.forTesting(NativeDatabase.memory()),
    );
    store = AnimeLocalStore(database: () async => db);
  });
  setUp(() async {
    for (final ns in [
      'anime_cache',
      'anime_progress',
      'anime_library',
      'anime_settings',
    ]) {
      await db.replaceRecords(ns, []);
    }
  });
  test('real audited catalog and detail parse without invented fields', () {
    final catalog =
        jsonDecode(
              File('docs/yoma/source-audit/catalog.json').readAsStringSync(),
            )
            as Map<String, dynamic>;
    final data = animeMap(animeMap(catalog['data'])['catalog']);
    final page = AnimePage.fromJson(
      data.isNotEmpty ? data : animeMap(catalog['catalog']),
    );
    expect(page.items, isNotEmpty);
    expect(page.total, greaterThan(1000));
    final body = animeMap(
      jsonDecode(File('docs/yoma/source-audit/detail.json').readAsStringSync()),
    );
    final detail = AnimeDetail.fromJson(
      animeMap(animeMap(body['data'])['detail']).isNotEmpty
          ? animeMap(animeMap(body['data'])['detail'])
          : animeMap(body['detail']),
    );
    expect(detail.episodes, isNotEmpty);
    expect(detail.episodes.first.url, startsWith('https://animeav1.com/'));
  });
  test(
    'cache clearing preserves manga, favorites, positions and preferences',
    () async {
      await db.putRecord('reader', 'manga-sentinel', {'page': 42});
      await store.putCache('detail:test', {'anime': anime.toJson()});
      await store.saveLibrary(anime, saved: true, favorite: true);
      await store.saveProgress(
        anime,
        episode,
        positionMs: 137123,
        durationMs: 150000,
        watched: true,
      );
      await store.saveSettings({'speed': 1.5});
      await store.clearMetadataCache();
      final reopened = AnimeLocalStore(database: () async => db);
      expect(await reopened.cache('detail:test'), isNull);
      expect((await reopened.progress()).single['positionMs'], 137123);
      expect((await reopened.library()).single['favorite'], true);
      expect((await reopened.settings())['speed'], 1.5);
      expect((await db.getRecord('reader', 'manga-sentinel'))['page'], 42);
    },
  );
  test(
    'ordinary position updates preserve manual watched or unwatched',
    () async {
      await store.saveProgress(
        anime,
        episode,
        positionMs: 1000,
        durationMs: 5000,
        watched: true,
      );
      await store.saveProgress(
        anime,
        episode,
        positionMs: 2000,
        durationMs: 5000,
      );
      expect((await store.progress()).single['watched'], true);
      await store.markWatched(anime, episode, false);
      await store.saveProgress(
        anime,
        episode,
        positionMs: 3000,
        durationMs: 5000,
      );
      expect((await store.progress()).single['watched'], false);
    },
  );
  test('late search responses cannot overwrite the latest query', () async {
    final source = TestAnimeSource()..deferred = true;
    final app = AnimeController(source: source, store: store);
    app.query = 'first';
    final first = app.search();
    while (source.requests.isEmpty) {
      await Future<void>.delayed(Duration.zero);
    }
    app.query = 'second';
    final second = app.search();
    while (source.requests.length < 2) {
      await Future<void>.delayed(Duration.zero);
    }
    source.requests[1].complete({
      'items': [
        {'slug': 'second', 'title': 'Second'},
      ],
    });
    await second;
    source.requests[0].complete({
      'items': [
        {'slug': 'first', 'title': 'First'},
      ],
    });
    await first;
    expect(app.catalogItems.single.slug, 'second');
    app.dispose();
  });
  test(
    'public source uses anonymous cookies and actual catalog query',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final queries = <Uri>[];
      final listener = server.listen((request) async {
        queries.add(request.uri);
        expect(request.headers.value('authorization'), isNull);
        request.response.headers.contentType = ContentType.json;
        request.response.cookies.add(
          Cookie('SEASONAV1_WEB', 'anonymous')..path = '/',
        );
        request.response.write(
          jsonEncode({
            'ok': true,
            'data': request.uri.queryParameters['action'] == 'state'
                ? {}
                : {
                    'catalog': {'items': [], 'page': 1, 'pages': 1},
                  },
          }),
        );
        await request.response.close();
      });
      final source = YomaTvSource(
        base: Uri.parse('http://127.0.0.1:${server.port}/'),
        http: HttpOverrides.runWithHttpOverrides(
          () => HttpClient(),
          RealHttpOverrides(),
        ),
      );
      try {
        await Future.wait([
          source.catalog(search: 'one piece', genre: 'Action'),
          source.catalog(search: 'one piece', genre: 'Action'),
        ]);
        expect(
          queries.where((uri) => uri.queryParameters['action'] == 'catalog'),
          hasLength(1),
        );
        expect(queries.last.queryParameters['search'], 'one piece');
        expect(queries.last.queryParameters['include_genres'], '["Action"]');
      } finally {
        source.close();
        await listener.cancel();
        await server.close(force: true);
      }
    },
  );
  test('catalog cache keeps the 40 most recent searches only', () async {
    await store.putCache('detail:test', {'anime': {}});
    for (var i = 0; i < 45; i++) {
      await store.putCache('catalog:$i', {'items': []});
    }
    final rows = await db.readRecords('anime_cache');
    final catalogs = rows.where((r) => '${r['id']}'.startsWith('catalog:'));
    expect(catalogs, hasLength(40));
    expect(await store.cache('detail:test'), isNotNull);
  });
  test('a ready download in another language is found for offline', () {
    final app = AnimeController(source: TestAnimeSource(), store: store);
    addTearDown(app.dispose);
    app.downloads = [
      AnimeDownload({
        'key': 'k',
        'slug': 'test',
        'number': '1',
        'state': 'done',
        'file': '/x/test-1-lat.mp4',
        'language': 'LAT',
      }),
    ];
    expect(app.downloaded(episode, 'SUB'), isNull);
    expect(app.readyDownload(episode)?.language, 'LAT');
  });
}
