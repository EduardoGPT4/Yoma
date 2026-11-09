import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yomashi/data/app_database.dart';
import 'package:yomashi/data/library_store.dart';
import 'package:yomashi/models/chapter.dart';
import 'package:yomashi/models/favorite_entry.dart';
import 'package:yomashi/models/library_entry.dart';
import 'package:yomashi/models/manga.dart';
import 'package:yomashi/models/reading_progress.dart';
import 'package:yomashi/providers/categories_provider.dart';
import 'package:yomashi/providers/chapter_read_provider.dart';
import 'package:yomashi/providers/density_provider.dart';
import 'package:yomashi/providers/favorites_provider.dart';
import 'package:yomashi/providers/library_provider.dart';
import 'package:yomashi/screens/library_screen.dart';
import 'package:yomashi/services/myanimelist_client.dart';
import 'package:yomashi/services/myanimelist_service.dart';
import 'package:yomashi/widgets/cached_thumbnail.dart';
import 'package:yomashi/widgets/contextual_tip.dart';
import 'package:yomashi/widgets/continue_reading_section.dart';
import 'package:yomashi/widgets/download_activity.dart';
import 'package:yomashi/widgets/manga_card.dart';
import 'package:yomashi/widgets/reader_chapter_end.dart';
import 'package:yomashi/widgets/reader_page_scrubber.dart';
import 'package:yomashi/providers/download_queue_provider.dart';
import 'package:yomashi/models/online_manga.dart';
import 'package:yomashi/widgets/bottom_nav_bar.dart';

const local = Manga(
  title: 'Obra local',
  path: '/books/local',
  sourceUrl: 'https://inmanga.com/manga/local',
  chapters: [
    Chapter(title: 'Capítulo 1', path: '/books/local/1', pageCount: 12),
  ],
);
const saved = FavoriteEntry(
  key: 'https://inmanga.com/manga/saved',
  title: 'Obra guardada',
);
ReadingProgress progress(String ref, {int time = 20}) => ReadingProgress(
  mangaPath: ref,
  mangaTitle: 'Obra guardada',
  chapterPath: '$ref/chapter/1',
  chapterTitle: 'Capítulo 1',
  pageIndex: 4,
  updatedAt: time,
);

class _Library extends LibraryProvider {
  @override
  List<Manga> get mangas => [local];
  @override
  List<ReadingProgress> getRecentProgress() => [progress(saved.key)];
}

class _Credentials extends MalCredentialStore {
  Map<String, dynamic>? value = {
    'device_token': 'test',
    'connected': true,
    'profile': {'id': 1, 'name': 'Reader'},
  };
  @override
  Future<Map<String, dynamic>?> load() async => value;
  @override
  Future<void> save(Map<String, dynamic> value) async => this.value = value;
  @override
  Future<void> clear() async => value = null;
}

class _Client extends MyAnimeListClient {
  _Client(_Credentials store) : super(credentials: store);
  int reads = 0;
  @override
  Future<MalManga> detail(int id) async {
    reads++;
    return const MalManga(
      id: 13,
      title: 'MAL obra',
      chaptersRead: 42,
      totalChapters: 100,
      status: 'on_hold',
      publishingStatus: 'publishing',
    );
  }
}

class _Queue extends DownloadQueueProvider {
  _Queue() : super(useNative: true);
  final tasks = [
    DownloadJob(
      id: 'test',
      manga: const OnlineMangaDetail(
        title: 'Descarga de prueba',
        url: 'https://inmanga.com/manga/test',
        chapters: [Chapter(title: '1', path: 'test', pageCount: 1)],
      ),
      status: DownloadJobStatus.paused,
      error: 'Esperando Wi-Fi',
    ),
  ];
  String? resumed;
  @override
  List<DownloadJob> get jobs => tasks;
  @override
  void resumeJob(String id) {
    resumed = id;
    tasks.first.status = DownloadJobStatus.downloading;
    notifyListeners();
  }

  @override
  void pauseJob(String id) {
    tasks.first.status = DownloadJobStatus.paused;
    notifyListeners();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late LibraryStore store;
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    store = await LibraryStore.initialize(
      database: AppDatabase.forTesting(NativeDatabase.memory()),
    );
  });
  setUp(() async {
    SharedPreferences.setMockInitialValues({'tip_library_v1': true});
    for (final namespace in [
      'mal_links',
      'mal_pending',
      'mal_sync',
      'favorite_updates',
    ]) {
      await store.replaceRecords(namespace, []);
    }
    await store.replaceFavoritesMap({});
  });
  test(
    'unified library joins local source references without merging equal titles',
    () {
      final entries = LibraryEntry.combine(
        local: [local],
        favorites: [
          const FavoriteEntry(key: '/books/local', title: 'Obra local'),
          const FavoriteEntry(
            key: 'https://other.example/manga/local',
            title: 'Obra local',
          ),
          saved,
        ],
        progress: [
          progress(local.sourceUrl!),
          progress(local.path, time: 30),
          progress('/missing'),
        ],
      );
      expect(entries, hasLength(3));
      final downloaded = entries
          .where((e) => e.matches(LibraryView.downloaded))
          .single;
      expect(downloaded.favorite!.key, local.path);
      expect(downloaded.progress!.updatedAt, 30);
      expect(
        entries.where((e) => e.matches(LibraryView.reading)),
        hasLength(1),
      );
      expect(entries.where((e) => e.title == local.title), hasLength(2));
    },
  );
  test('reading filter agrees with the confirmed MAL state', () {
    const savedOnly = LibraryEntry(key: 'remote', title: 'Saved');
    final started = LibraryEntry(
      key: 'remote',
      title: 'Started',
      progress: progress('remote'),
    );
    expect(
      savedOnly.matches(LibraryView.reading, readingStatus: 'reading'),
      isTrue,
    );
    expect(savedOnly.matches(LibraryView.reading), isFalse);
    expect(started.matches(LibraryView.reading), isTrue);
    for (final status in ['completed', 'on_hold', 'dropped', 'plan_to_read']) {
      expect(
        started.matches(LibraryView.reading, readingStatus: status),
        isFalse,
      );
    }
  });
  test(
    'legacy source links join saved online entries without rewriting favorites',
    () {
      final entries = LibraryEntry.combine(
        local: [const Manga(title: 'Legacy', path: '/legacy', chapters: [])],
        favorites: [saved],
        progress: [],
        sourceLinks: {'/legacy': saved.key},
      );
      expect(entries, hasLength(1));
      expect(entries.single.favorite!.key, saved.key);
      expect(entries.single.downloaded, isFalse);
    },
  );
  testWidgets(
    'library includes saved online works and filters without fetching the network',
    (tester) async {
      final library = _Library(),
          favorites = FavoritesProvider(),
          density = DensityProvider(),
          categories = CategoriesProvider(),
          reads = ChapterReadProvider();
      await favorites.toggle(key: saved.key, title: saved.title);
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<LibraryProvider>.value(value: library),
            ChangeNotifierProvider.value(value: favorites),
            ChangeNotifierProvider.value(value: density),
            ChangeNotifierProvider.value(value: categories),
            ChangeNotifierProvider.value(value: reads),
          ],
          child: const MaterialApp(home: LibraryScreen()),
        ),
      );
      await tester.runAsync(
        () async => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pumpAndSettle();
      expect(find.text('Biblioteca'), findsOneWidget);
      expect(find.byType(MangaCard), findsNWidgets(2));
      await tester.tap(find.text('Descargados (1)'));
      await tester.pumpAndSettle();
      expect(find.byType(MangaCard), findsOneWidget);
      expect(
        tester.widget<MangaCard>(find.byType(MangaCard)).title,
        local.title,
      );
      await tester.tap(find.text('Favoritos (1)'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<MangaCard>(find.byType(MangaCard)).title,
        saved.title,
      );
      await tester.enterText(find.byType(TextField), 'sin coincidencias');
      await tester.pumpAndSettle();
      expect(find.byType(MangaCard), findsNothing);
      expect(favorites.entries.single.key, saved.key);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      library.dispose();
      favorites.dispose();
      density.dispose();
      categories.dispose();
      reads.dispose();
    },
  );
  testWidgets('featured continue action stays usable with large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var opened = 0;
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => DensityProvider(),
        child: MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(1.6)),
            child: child!,
          ),
          home: Scaffold(
            body: SingleChildScrollView(
              child: ContinueReadingSection(
                entries: [
                  ContinueReadingEntry(
                    title:
                        'Un título de manga bastante largo para comprobar la tarjeta',
                    chapterLabel: 'Capítulo 42',
                    pageNumber: 9,
                    progress: 0,
                    coverPath: null,
                    timeAgo: 'Hace 2 h',
                    onTap: () => opened++,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continuar'));
    expect(opened, 1);
    expect(find.text('Hace 2 h'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('scrubbing previews a small image and commits only on release', (
    tester,
  ) async {
    final committed = <int>[], interactions = <bool>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReaderPageScrubber(
            pages: List.filled(30, ''),
            page: 2,
            onCommit: committed.add,
            onInteraction: interactions.add,
          ),
        ),
      ),
    );
    final slider = tester.widget<Slider>(find.byType(Slider));
    slider.onChangeStart!(2);
    slider.onChanged!(18);
    await tester.pump(const Duration(milliseconds: 180));
    expect(committed, isEmpty);
    expect(find.text('Página 19 de 30'), findsOneWidget);
    expect(
      tester.widget<CachedThumbnail>(find.byType(CachedThumbnail)).size,
      160,
    );
    slider.onChangeEnd!(18);
    await tester.pumpAndSettle();
    expect(committed, [18]);
    expect(interactions, [true, false]);
    expect(find.byType(CachedThumbnail), findsNothing);
  });
  testWidgets(
    'chapter end distinguishes offline next chapter and being up to date',
    (tester) async {
      var next = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ReaderChapterEnd(
              nextTitle: 'Capítulo 2',
              hasMore: false,
              offline: true,
              onNext: () => next++,
              onExit: () {},
            ),
          ),
        ),
      );
      expect(find.text('Disponible sin conexión'), findsOneWidget);
      await tester.tap(find.text('Siguiente capítulo'));
      expect(next, 1);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ReaderChapterEnd(
              hasMore: false,
              offline: false,
              onNext: () => next++,
              onExit: () {},
            ),
          ),
        ),
      );
      expect(find.text('Estás al día'), findsOneWidget);
      expect(find.text('Siguiente capítulo'), findsNothing);
    },
  );
  testWidgets(
    'download summary and badge expose pause reasons and resume actions',
    (tester) async {
      final queue = _Queue(), density = DensityProvider();
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<DownloadQueueProvider>.value(value: queue),
            ChangeNotifierProvider.value(value: density),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: const DownloadActivity(),
              bottomNavigationBar: YomashiBottomNavBar(
                currentIndex: 0,
                onTap: (_) {},
              ),
            ),
          ),
        ),
      );
      expect(find.text('Esperando Wi-Fi'), findsOneWidget);
      expect(
        tester.widget<Badge>(find.byType(Badge).first).isLabelVisible,
        isTrue,
      );
      await tester.tap(find.text('Descarga de prueba'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Reanudar'));
      await tester.pumpAndSettle();
      expect(queue.resumed, 'test');
      expect(find.text('Pausar'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      queue.dispose();
      density.dispose();
    },
  );
  testWidgets('dismissed contextual help stays dismissed after remounting', (
    tester,
  ) async {
    Widget app() => const MaterialApp(
      home: Scaffold(
        body: ContextualTip(id: 'test', message: 'Consejo de lectura'),
      ),
    );
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    expect(find.text('Consejo de lectura'), findsOneWidget);
    await tester.tap(find.byTooltip('Ocultar consejo'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    expect(find.text('Consejo de lectura'), findsNothing);
  });
  test(
    'MAL status reports confirmed progress, pending work and isolates account changes',
    () async {
      final credentials = _Credentials(), client = _Client(_Credentials());
      final service = MyAnimeListService(client);
      // Use one credential store consistently for the mock client and service.
      await client.credentials.save(credentials.value!);
      const manga = Manga(
        title: 'Obra',
        path: 'https://inmanga.com/manga/test',
        chapters: [],
      );
      const chosen = MalManga(
        id: 13,
        title: 'MAL obra',
        chaptersRead: 40,
        totalChapters: 100,
        status: 'reading',
        publishingStatus: 'publishing',
      );
      await service.link(manga, chosen, automatic: false);
      var state = await service.statusFor(manga);
      expect(state['snapshot']['chapters'], 40);
      expect(state['snapshot']['syncedAt'], isNull);
      expect(client.reads, 0);
      await service.refreshManga(manga);
      state = await service.statusFor(manga);
      expect(state['snapshot']['chapters'], 42);
      expect(state['snapshot']['status'], 'on_hold');
      expect(client.reads, 1);
      await service.recordSnapshot(manga, chosen, sent: true, expectedOwner: 1);
      state = await service.statusFor(manga);
      expect(state['snapshot']['syncedAt'], isA<int>());
      await service.refreshManga(manga);
      state = await service.statusFor(manga);
      expect(state['snapshot']['chapters'], 42);
      expect(state['snapshot']['sentChapters'], 40);

      final link = state['link'] as Map;
      await store.putRecord('mal_pending', MyAnimeListService.mangaKey(manga), {
        'id': link['id'],
        'owner': 1,
        'version': link['version'],
        'chapters': 43,
      });
      expect((await service.statusFor(manga))['pending']['chapters'], 43);
      await client.credentials.save({
        'device_token': 'other',
        'connected': true,
        'profile': {'id': 2},
      });
      state = await service.statusFor(manga);
      expect(state.containsKey('link'), isFalse);
      expect(state.containsKey('snapshot'), isFalse);
      expect(state.containsKey('pending'), isFalse);
      await service.recordSnapshot(manga, chosen, sent: true, expectedOwner: 1);
      expect(
        (await store.getRecord(
          'mal_sync',
          MyAnimeListService.mangaKey(manga),
        ))['chapters'],
        42,
      );
      await service.unlink(manga);
      expect(
        await store.getRecord('mal_sync', MyAnimeListService.mangaKey(manga)),
        isNull,
      );
      client.http.close(force: true);
      client.sessionChanges.dispose();
      service.changes.dispose();
    },
  );
}
