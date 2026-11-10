import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yomashi/data/app_database.dart';
import 'package:yomashi/data/library_store.dart';
import 'package:yomashi/models/chapter.dart';
import 'package:yomashi/models/manga.dart';
import 'package:yomashi/providers/chapter_read_provider.dart';
import 'package:yomashi/providers/download_queue_provider.dart';
import 'package:yomashi/providers/library_provider.dart';
import 'package:yomashi/providers/reader_settings_provider.dart';
import 'package:yomashi/screens/online_manga_detail_screen.dart';
import 'package:yomashi/screens/reader_screen.dart';
import 'package:yomashi/services/manga_source_adapter.dart';
import 'package:yomashi/services/online_catalog_service.dart';
import 'package:yomashi/utils/app_failure.dart';

const _remote = Manga(
  title: 'Fixture',
  path: 'https://inmanga.com/manga/fixture',
  sourceUrl: 'https://inmanga.com/manga/fixture',
  chapters: [
    Chapter(
      title: 'Capítulo 1',
      path: 'https://inmanga.com/chapter/fixture',
      pages: [],
      pageCount: 0,
    ),
  ],
);

const _local = Manga(
  title: 'Local',
  path: '/storage/emulated/0/Yoma/YomaShi/Manga/Local',
  chapters: [
    Chapter(title: 'Capítulo 1', path: '/x/1', pages: [], pageCount: 0),
  ],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late MangaSourceAdapter original;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({
      'reader_volume_navigation_v1': false,
    });
    await LibraryStore.initialize(
      database: AppDatabase.forTesting(NativeDatabase.memory()),
    );
  });

  setUp(() {
    original = OnlineCatalogService.adapters['inmanga']!;
    // Sin red: las páginas y la ficha fallan al instante.
    OnlineCatalogService.adapters['inmanga'] = CallbackSourceAdapter(
      id: 'inmanga',
      catalogRequest: (p, n, q) =>
          original.catalog(page: p, pageSize: n, query: q),
      feedRequest: original.feed,
      detailRequest: (_) async =>
          throw const AppFailure(FailureKind.network, 'Sin red de prueba.'),
      pagesRequest: (_) async =>
          throw const AppFailure(FailureKind.network, 'Sin red de prueba.'),
    );
  });

  tearDown(() => OnlineCatalogService.adapters['inmanga'] = original);

  /// Pantalla de origen con un botón que abre el lector.
  Future<void> open(
    WidgetTester tester,
    Manga manga, {
    bool fromDetail = false,
  }) async {
    final library = LibraryProvider(),
        settings = ReaderSettingsProvider(),
        reads = ChapterReadProvider(),
        downloads = DownloadQueueProvider();
    await settings.load();
    addTearDown(() {
      library.dispose();
      settings.dispose();
      reads.dispose();
    });
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: library),
          ChangeNotifierProvider.value(value: settings),
          ChangeNotifierProvider.value(value: reads),
          ChangeNotifierProvider.value(value: downloads),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => ReaderScreen(
                      manga: manga,
                      initialChapterIndex: 0,
                      initialPageIndex: 0,
                      openedFromDetail: fromDetail,
                    ),
                  ),
                ),
                child: const Text('origen'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('origen'));
    // El lector de un manga sin páginas reales mantiene un indicador de
    // carga; se avanza un tiempo fijo en lugar de esperar a que se asiente.
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
  }

  testWidgets('from the library the reader is replaced by the manga page', (
    tester,
  ) async {
    await open(tester, _remote);
    await tester.tap(find.byTooltip('Ficha del manga'));
    await tester.pumpAndSettle();
    expect(find.byType(ReaderScreen), findsNothing);
    final detail = tester.widget<OnlineMangaDetailScreen>(
      find.byType(OnlineMangaDetailScreen),
    );
    expect(detail.mangaUrl, 'https://inmanga.com/manga/fixture');
    expect(detail.sourceId, 'inmanga');
    // Atrás vuelve a la pantalla desde la que se abrió el lector.
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('origen'), findsOneWidget);
    await close(tester);
  });

  testWidgets('from the manga page it goes back instead of stacking it', (
    tester,
  ) async {
    await open(tester, _remote, fromDetail: true);
    await tester.tap(find.byTooltip('Ficha del manga'));
    await tester.pumpAndSettle();
    expect(find.byType(ReaderScreen), findsNothing);
    expect(find.byType(OnlineMangaDetailScreen), findsNothing);
    expect(find.text('origen'), findsOneWidget);
    await close(tester);
  });

  testWidgets('local manga without a source has no manga page button', (
    tester,
  ) async {
    await open(tester, _local);
    expect(find.byTooltip('Ficha del manga'), findsNothing);
    expect(find.byTooltip('Ajustes del lector'), findsOneWidget);
    await close(tester);
  });
}
