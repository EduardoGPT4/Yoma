// Optional visual inspection: flutter test test/widgets/ui_preview_test.dart
// --dart-define=YOMASHI_UI_CAPTURE=true --update-goldens
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yomashi/data/app_database.dart';
import 'package:yomashi/data/library_store.dart';
import 'package:yomashi/models/chapter.dart';
import 'package:yomashi/models/online_manga.dart';
import 'package:yomashi/providers/density_provider.dart';
import 'package:yomashi/providers/download_queue_provider.dart';
import 'package:yomashi/providers/library_provider.dart';
import 'package:yomashi/providers/profile_provider.dart';
import 'package:yomashi/providers/reader_settings_provider.dart';
import 'package:yomashi/providers/source_provider.dart';
import 'package:yomashi/providers/theme_accent_provider.dart';
import 'package:yomashi/screens/download_queue_screen.dart';
import 'package:yomashi/screens/myanimelist_screen.dart';
import 'package:yomashi/screens/profile_screen.dart';
import 'package:yomashi/screens/sources_screen.dart';
import 'package:yomashi/screens/library_screen.dart';
import 'package:yomashi/models/manga.dart';
import 'package:yomashi/models/reading_progress.dart';
import 'package:yomashi/providers/favorites_provider.dart';
import 'package:yomashi/providers/categories_provider.dart';
import 'package:yomashi/providers/chapter_read_provider.dart';
import 'package:yomashi/widgets/reader_chapter_end.dart';
import 'package:yomashi/widgets/reader_page_scrubber.dart';
import 'package:yomashi/services/myanimelist_client.dart';
import 'package:yomashi/services/myanimelist_service.dart';
import 'package:yomashi/widgets/app_metrics.dart';
import 'package:yomashi/widgets/app_theme.dart';
import 'package:yomashi/widgets/bottom_nav_bar.dart';
import 'package:yomashi/widgets/chapter_drawer.dart';

const _previewKey = ValueKey('ui-preview-capture');

class _PreviewCredentials extends MalCredentialStore {
  Map<String, dynamic>? value;
  @override
  Future<Map<String, dynamic>?> load() async => value;
  @override
  Future<void> save(Map<String, dynamic> next) async => value = next;
  @override
  Future<void> clear() async => value = null;
}

class _PreviewMal extends MyAnimeListClient {
  _PreviewMal(_PreviewCredentials store) : super(credentials: store);
  @override
  Future<Map<String, dynamic>?> account() => credentials.load();
}

class _PreviewLibrary extends LibraryProvider {
  @override
  List<Manga> get mangas => [
    const Manga(
      title: 'Colección descargada',
      path: '/preview/local',
      chapters: [
        Chapter(title: 'Capítulo 1', path: '/preview/1', pageCount: 24),
      ],
    ),
  ];
  @override
  List<ReadingProgress> getRecentProgress() => [
    ReadingProgress(
      mangaPath: '/preview/local',
      mangaTitle: 'Colección descargada',
      chapterPath: '/preview/1',
      chapterTitle: 'Capítulo 1',
      pageIndex: 8,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    ),
  ];
  @override
  Future<void> flushStats() async {}
}

class _PreviewQueue extends DownloadQueueProvider {
  _PreviewQueue(this.fixtureJobs, this.fixtureArchive) : super(useNative: true);
  final List<DownloadJob> fixtureJobs;
  final List<DownloadArchiveEntry> fixtureArchive;
  @override
  List<DownloadJob> get jobs => fixtureJobs;
  @override
  List<DownloadArchiveEntry> get archive => fixtureArchive;
  @override
  String? get downloadRoot => '/storage/emulated/0/YomaShi';
  @override
  bool get wifiOnlyDownloads => true;
  @override
  int get downloadThreads => 8;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  if (!const bool.fromEnvironment('YOMASHI_UI_CAPTURE')) {
    test(
      'UI previews are opt-in',
      () {},
      skip: 'Enable YOMASHI_UI_CAPTURE to render previews.',
    );
    return;
  }

  late AppDatabase database;
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({
      'active_manga_source_v1': 'inmanga',
      'reader_volume_navigation_v1': false,
    });
    database = AppDatabase.forTesting(NativeDatabase.memory());
    await LibraryStore.initialize(database: database);
    final sdk = Directory(
      Platform.environment['FLUTTER_ROOT'] ?? r'C:\flutter',
    );
    final fonts = Directory(
      '${sdk.path}/bin/cache/dart-sdk/bin/resources/devtools/assets/fonts/Roboto',
    );
    final roboto = FontLoader('Roboto');
    // Widget tests default otherwise-unset font families to Ahem. Register a
    // readable alias as well, including explicit AppBar/button text styles.
    final defaultTestFont = FontLoader('Ahem');
    for (final name in ['Roboto-Regular.ttf', 'Roboto-Bold.ttf']) {
      final data = await File('${fonts.path}/$name').readAsBytes();
      final bytes = Future.value(ByteData.sublistView(data));
      roboto.addFont(bytes);
      defaultTestFont.addFont(bytes);
    }
    await roboto.load();
    await defaultTestFont.load();
    final icons = FontLoader('MaterialIcons');
    final iconData = await File(
      '${fonts.parent.path}/MaterialIcons-Regular.otf',
    ).readAsBytes();
    icons.addFont(Future.value(ByteData.sublistView(iconData)));
    await icons.load();
    await Directory('build/verification/ui-2.5.0').create(recursive: true);
  });
  tearDownAll(() async => database.close());

  testWidgets('capture current mobile layouts with offline fixtures', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final credentials = _PreviewCredentials()
      ..value = {
        'connected': true,
        'device_token': 'preview-only',
        'profile': {'id': 7, 'name': 'Hk-Br035'},
      };
    final client = _PreviewMal(credentials);
    final profile = ProfileProvider(malClient: client);
    final library = _PreviewLibrary();
    final density = DensityProvider();
    final favorites = FavoritesProvider();
    final categories = CategoriesProvider();
    final reads = ChapterReadProvider();
    final settings = ReaderSettingsProvider();
    final source = SourceProvider();
    final accent = ThemeAccentProvider();
    final chapters = List.generate(
      380,
      (index) => Chapter(
        title: 'Capítulo ${index + 1}',
        path: '/preview/${index + 1}',
      ),
    );
    final archiveTitles = List.generate(
      500,
      (index) => 'Capítulo ${index + 1}',
    );
    final queue = _PreviewQueue(
      [
        DownloadJob(
          id: 'preview-failed',
          manga: OnlineMangaDetail(
            title: 'Manga de prueba',
            url: 'https://example.test/manga',
            chapters: chapters,
          ),
          status: DownloadJobStatus.failed,
          completedChapters: 344,
          completedPages: 7248,
          totalPages: 7248,
          receivedBytes: 2662879723,
          currentChapter: 'Capítulo 326',
          error: 'La fuente no encontró páginas para este capítulo.',
        ),
      ],
      [
        DownloadArchiveEntry(
          id: 'preview-completed',
          title: 'Colección descargada',
          reason: 'Descargada',
          chapterFrom: archiveTitles.first,
          chapterTo: archiveTitles.last,
          completedChapters: 500,
          completedPages: 10000,
          totalPages: 10000,
          updatedAt: DateTime(2026, 10, 28, 10, 42).millisecondsSinceEpoch,
          completedTitles: archiveTitles,
        ),
      ],
    );
    await profile.load();
    await profile.refreshMyAnimeList();
    await source.load();
    await settings.load();

    Future<void> show(Widget screen, {int? navigationIndex}) async {
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      final theme = buildYomashiTheme(
        const Color(0xFFC62828),
        AppMetrics.compact,
      );
      ButtonStyle readableButton(ButtonStyle? style) {
        final text =
            style?.textStyle?.resolve(const <WidgetState>{}) ??
            const TextStyle(fontWeight: FontWeight.w700);
        return (style ?? const ButtonStyle()).copyWith(
          textStyle: WidgetStatePropertyAll(
            text.copyWith(fontFamily: 'Roboto'),
          ),
        );
      }

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<ProfileProvider>.value(value: profile),
            ChangeNotifierProvider.value(value: favorites),
            ChangeNotifierProvider.value(value: categories),
            ChangeNotifierProvider.value(value: reads),
            ChangeNotifierProvider<LibraryProvider>.value(value: library),
            ChangeNotifierProvider<DownloadQueueProvider>.value(value: queue),
            ChangeNotifierProvider<ReaderSettingsProvider>.value(
              value: settings,
            ),
            ChangeNotifierProvider<DensityProvider>.value(value: density),
            ChangeNotifierProvider<SourceProvider>.value(value: source),
            ChangeNotifierProvider<ThemeAccentProvider>.value(value: accent),
          ],
          child: RepaintBoundary(
            key: _previewKey,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: theme.copyWith(
                textTheme: theme.textTheme.apply(fontFamily: 'Roboto'),
                primaryTextTheme: theme.primaryTextTheme.apply(
                  fontFamily: 'Roboto',
                ),
                appBarTheme: theme.appBarTheme.copyWith(
                  titleTextStyle: theme.appBarTheme.titleTextStyle?.copyWith(
                    fontFamily: 'Roboto',
                  ),
                  toolbarTextStyle: theme.appBarTheme.toolbarTextStyle
                      ?.copyWith(fontFamily: 'Roboto'),
                ),
                filledButtonTheme: FilledButtonThemeData(
                  style: readableButton(theme.filledButtonTheme.style),
                ),
                textButtonTheme: TextButtonThemeData(
                  style: readableButton(theme.textButtonTheme.style),
                ),
                outlinedButtonTheme: OutlinedButtonThemeData(
                  style: readableButton(theme.outlinedButtonTheme.style),
                ),
                elevatedButtonTheme: ElevatedButtonThemeData(
                  style: readableButton(theme.elevatedButtonTheme.style),
                ),
                chipTheme: theme.chipTheme.copyWith(
                  labelStyle: theme.chipTheme.labelStyle?.copyWith(
                    fontFamily: 'Roboto',
                  ),
                  secondaryLabelStyle: theme.chipTheme.secondaryLabelStyle
                      ?.copyWith(fontFamily: 'Roboto'),
                ),
                navigationBarTheme: theme.navigationBarTheme.copyWith(
                  labelTextStyle: WidgetStateProperty.resolveWith(
                    (states) =>
                        (theme.navigationBarTheme.labelTextStyle?.resolve(
                                  states,
                                ) ??
                                const TextStyle())
                            .copyWith(fontFamily: 'Roboto'),
                  ),
                ),
              ),
              home: navigationIndex == null
                  ? screen
                  : Scaffold(
                      body: screen,
                      bottomNavigationBar: YomashiBottomNavBar(
                        currentIndex: navigationIndex,
                        onTap: (_) {},
                      ),
                    ),
            ),
          ),
        ),
      );
      // Drift reads complete outside the fake widget-test clock.
      await tester.runAsync(
        () async => Future<void>.delayed(const Duration(milliseconds: 60)),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }

    Future<void> capture(String name) async {
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byKey(_previewKey),
        matchesGoldenFile(
          File('build/verification/ui-2.5.0/$name.png').absolute.uri,
        ),
      );
    }

    try {
      await show(
        const DownloadQueueScreen(),
        navigationIndex: YomashiNavIndex.downloads,
      );
      await capture('01-downloads');
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -540));
      await tester.pumpAndSettle();
      await capture('02-download-history');

      await show(
        const ProfileScreen(),
        navigationIndex: YomashiNavIndex.profile,
      );
      await capture('03-profile');
      await show(
        const ProfileScreen(settingsMode: true, initialSettingsQuery: 'brillo'),
      );
      await capture('07-settings-search');
      await show(
        const LibraryScreen(),
        navigationIndex: YomashiNavIndex.offline,
      );
      await capture('08-library');
      await show(
        Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                ReaderChapterEnd(
                  nextTitle: 'Capítulo 43 · Un nuevo comienzo',
                  hasMore: false,
                  offline: true,
                  onNext: () {},
                  onExit: () {},
                ),
                ReaderPageScrubber(
                  pages: const ['', '', ''],
                  page: 1,
                  onCommit: (_) {},
                  onInteraction: (_) {},
                ),
              ],
            ),
          ),
        ),
      );
      await capture('09-reader-end');

      credentials.value = null;
      await show(MyAnimeListScreen(service: MyAnimeListService(client)));
      await capture('04-myanimelist-disconnected');

      await show(const SourcesScreen());
      await capture('05-sources');

      final longChapters = List.generate(
        1200,
        (index) => Chapter(
          title: 'Capítulo ${(index + 1).toString().padLeft(3, '0')}',
          path: '/preview-chapters/$index',
          pageCount: 22,
        ),
      );
      await show(
        Scaffold(
          body: ChapterDrawer(
            chapters: longChapters,
            currentIndex: 999,
            onSelect: (_) {},
          ),
        ),
      );
      await capture('06-current-chapter');
    } finally {
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      favorites.dispose();
      categories.dispose();
      reads.dispose();
      profile.dispose();
      library.dispose();
      queue.dispose();
      settings.dispose();
      density.dispose();
      source.dispose();
      accent.dispose();
      client.sessionChanges.dispose();
      client.http.close(force: true);
    }
  });
}
