import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yomashi/models/chapter.dart';
import 'package:yomashi/models/manga.dart';
import 'package:yomashi/models/online_manga.dart';
import 'package:yomashi/providers/density_provider.dart';
import 'package:yomashi/providers/download_queue_provider.dart';
import 'package:yomashi/providers/library_provider.dart';
import 'package:yomashi/screens/download_queue_screen.dart';
import 'package:yomashi/screens/storage_screen.dart';

class _QueueFixture extends DownloadQueueProvider {
  final List<DownloadJob> fixtureJobs;
  final List<DownloadArchiveEntry> fixtureArchive;
  String? resumed;
  _QueueFixture({this.fixtureJobs = const [], this.fixtureArchive = const []})
    : super(useNative: false);
  @override
  List<DownloadJob> get jobs => fixtureJobs;
  @override
  List<DownloadArchiveEntry> get archive => fixtureArchive;
  @override
  void resumeJob(String id) => resumed = id;
}

class _LibraryFixture extends LibraryProvider {
  final List<Manga> values;
  _LibraryFixture(this.values);
  @override
  List<Manga> get mangas => values;
  @override
  Future<void> flushStats() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(
    () => SharedPreferences.setMockInitialValues({'tip_downloads_v1': true}),
  );

  Future<void> showScreen(
    WidgetTester tester,
    Widget child,
    _QueueFixture queue, {
    _LibraryFixture? library,
    double scale = 1.5,
  }) async {
    tester.view.physicalSize = const Size(320, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final resolvedLibrary = library ?? _LibraryFixture(const []);
    if (library == null) addTearDown(resolvedLibrary.dispose);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<DownloadQueueProvider>.value(value: queue),
          ChangeNotifierProvider<LibraryProvider>.value(value: resolvedLibrary),
          ChangeNotifierProvider(create: (_) => DensityProvider()),
        ],
        child: MaterialApp(
          theme: ThemeData(brightness: Brightness.dark, useMaterial3: true),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: child,
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('a huge download history stays compact and details scroll', (
    tester,
  ) async {
    final titles = List.generate(500, (index) => 'Capítulo ${index + 1}');
    final queue = _QueueFixture(
      fixtureArchive: [
        DownloadArchiveEntry(
          id: 'large',
          title: 'Manga de prueba',
          reason: 'Descargada',
          chapterFrom: titles.first,
          chapterTo: titles.last,
          completedChapters: 500,
          completedPages: 10000,
          totalPages: 10000,
          updatedAt: 0,
          completedTitles: titles,
        ),
      ],
    );
    addTearDown(queue.dispose);
    await showScreen(tester, const DownloadQueueScreen(), queue);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Capítulo 1 … Capítulo 500'), findsOneWidget);
    expect(find.text(titles.join(', ')), findsNothing);
    expect(
      tester.getBottomLeft(find.text('Ver detalles')).dy -
          tester.getTopLeft(find.text('Manga de prueba')).dy,
      lessThan(500),
    );
    await tester.ensureVisible(find.text('Ver detalles'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ver detalles'));
    await tester.pumpAndSettle();
    expect(find.text('Capítulo 1'), findsOneWidget);
    expect(find.text('Capítulo 500'), findsNothing);
    final list = find.descendant(
      of: find.byType(BottomSheet),
      matching: find.byType(Scrollable),
    );
    await tester.scrollUntilVisible(
      find.text('Capítulo 12'),
      300,
      scrollable: list,
    );
    expect(find.text('Capítulo 12'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a failed download explains pending chapters and retries them', (
    tester,
  ) async {
    final queue = _QueueFixture(
      fixtureJobs: [
        DownloadJob(
          id: 'failed',
          manga: OnlineMangaDetail(
            title: 'Manga',
            url: 'https://example.test/manga',
            chapters: List.generate(
              380,
              (index) => Chapter(title: 'Capítulo $index', path: '/$index'),
            ),
          ),
          status: DownloadJobStatus.failed,
          completedChapters: 344,
          completedPages: 7248,
          totalPages: 7248,
          currentChapter: 'Capítulo 326',
          error: 'No se encontraron páginas.',
        ),
      ],
    );
    addTearDown(queue.dispose);
    await showScreen(tester, const DownloadQueueScreen(), queue);
    await tester.pumpAndSettle();
    expect(find.text('36 capítulos pendientes'), findsOneWidget);
    expect(find.textContaining('7248 páginas guardadas'), findsOneWidget);
    expect(
      find.textContaining('páginas identificadas hasta ahora'),
      findsOneWidget,
    );
    expect(find.text('Se detuvo en: Capítulo 326'), findsOneWidget);
    expect(find.text('Priorizar'), findsNothing);
    expect(find.byTooltip('Subir en la cola'), findsNothing);
    await tester.ensureVisible(find.text('Reintentar pendientes'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reintentar pendientes'));
    expect(queue.resumed, 'failed');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'storage waits for measurement then supports sorting and search',
    (tester) async {
      final pending = Completer<StorageSnapshot>();
      final queue = _QueueFixture();
      final library = _LibraryFixture(const [
        Manga(title: 'Alfa', path: '/alfa', chapters: []),
        Manga(title: 'Zeta', path: '/zeta', chapters: []),
      ]);
      addTearDown(queue.dispose);
      addTearDown(library.dispose);
      await showScreen(
        tester,
        StorageScreen(loadMetrics: (_, _) => pending.future),
        queue,
        library: library,
      );
      expect(find.text('Calculando almacenamiento…'), findsOneWidget);
      expect(find.text('Biblioteca: —'), findsOneWidget);
      expect(find.textContaining('0 B'), findsNothing);
      pending.complete(
        const StorageSnapshot(
          sizes: {'/alfa': 1024, '/zeta': 2048},
          cache: 1024,
          thumbnails: 0,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Calculando almacenamiento…'), findsNothing);
      expect(find.text('Biblioteca: 3.0 KiB'), findsOneWidget);
      final storageScroll = find
          .descendant(
            of: find.byType(ListView),
            matching: find.byType(Scrollable),
          )
          .first;
      await tester.scrollUntilVisible(
        find.text('Zeta'),
        250,
        scrollable: storageScroll,
      );
      expect(
        tester.getTopLeft(find.text('Zeta')).dy,
        lessThan(tester.getTopLeft(find.text('Alfa')).dy),
      );
      await tester.ensureVisible(find.byType(TextField));
      await tester.enterText(find.byType(TextField), 'alfa');
      await tester.pumpAndSettle();
      expect(find.text('1 de 2 mangas'), findsOneWidget);
      expect(find.text('Zeta'), findsNothing);
      expect(find.text('Alfa'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
