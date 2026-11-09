import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yomashi/data/app_database.dart';
import 'package:yomashi/data/library_store.dart';
import 'package:yomashi/models/chapter.dart';
import 'package:yomashi/models/manga.dart';
import 'package:yomashi/providers/chapter_read_provider.dart';
import 'package:yomashi/providers/library_provider.dart';
import 'package:yomashi/providers/reader_settings_provider.dart';
import 'package:yomashi/screens/reader_screen.dart';
import 'package:yomashi/services/manga_source_adapter.dart';
import 'package:yomashi/services/online_catalog_service.dart';
import 'package:yomashi/utils/app_failure.dart';
import 'package:yomashi/widgets/webtoon_viewer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({
      'reader_volume_navigation_v1': false,
    });
    await LibraryStore.initialize(
      database: AppDatabase.forTesting(NativeDatabase.memory()),
    );
  });
  testWidgets('chapter errors leave the spinner and allow an actual retry', (
    tester,
  ) async {
    final original = OnlineCatalogService.adapters['inmanga']!;
    var attempts = 0;
    OnlineCatalogService.adapters['inmanga'] = CallbackSourceAdapter(
      id: 'inmanga',
      catalogRequest: (p, n, q) =>
          original.catalog(page: p, pageSize: n, query: q),
      feedRequest: original.feed,
      detailRequest: original.detail,
      pagesRequest: (_) async {
        attempts++;
        throw const AppFailure(FailureKind.network, 'Sin conexión de prueba.');
      },
    );
    final library = LibraryProvider(),
        settings = ReaderSettingsProvider(),
        reads = ChapterReadProvider();
    await settings.load();
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: library),
          ChangeNotifierProvider.value(value: settings),
          ChangeNotifierProvider.value(value: reads),
        ],
        child: const MaterialApp(
          home: ReaderScreen(
            manga: Manga(
              title: 'Fixture',
              path: 'https://inmanga.com/manga/fixture',
              chapters: [
                Chapter(
                  title: 'Chapter 1',
                  path: 'https://inmanga.com/chapter/fixture',
                  pages: [],
                  pageCount: 0,
                ),
              ],
            ),
            initialChapterIndex: 0,
            initialPageIndex: 0,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Sin conexión de prueba.'), findsOneWidget);
    expect(find.text('Reintentar capítulo'), findsOneWidget);
    await tester.tap(find.text('Reintentar capítulo'));
    await tester.pumpAndSettle();
    expect(attempts, 2);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
    library.dispose();
    settings.dispose();
    reads.dispose();
    OnlineCatalogService.adapters['inmanga'] = original;
  });
  testWidgets('webtoon resumes at its anchor and reports the visible page', (
    tester,
  ) async {
    final bytes = img.encodePng(img.Image(width: 400, height: 600));
    final visible = <int>[], loaded = <int>[];
    await tester.pumpWidget(
      MaterialApp(
        home: WebtoonViewer(
          initialPage: 2,
          pages: const ['1', '2', '3', '4'],
          imageProvider: (_) => MemoryImage(bytes),
          onPageChanged: visible.add,
          onLoaded: loaded.add,
          errorBuilder: (_) => const Text('Error'),
        ),
      ),
    );
    await tester.runAsync(
      () => precacheImage(
        MemoryImage(bytes),
        tester.element(find.byType(WebtoonViewer)),
      ),
    );
    await tester.pumpAndSettle();
    expect(visible.last, 2);
    expect(loaded, contains(2));
    final scroll = tester.state<ScrollableState>(find.byType(Scrollable));
    scroll.position.jumpTo(1300);
    await tester.pumpAndSettle();
    expect(visible.last, 3);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
