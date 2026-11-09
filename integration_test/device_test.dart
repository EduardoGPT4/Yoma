import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
// Conserva la biblioteca del punto de entrada del motor de descargas nativo.
import 'package:yomashi/main.dart' as app;
import 'package:yomashi/data/library_store.dart';
import 'package:yomashi/data/download_storage.dart';
import 'package:yomashi/models/automation_settings.dart';
import 'package:yomashi/models/chapter.dart';
import 'package:yomashi/models/online_manga.dart';
import 'package:yomashi/providers/chapter_read_provider.dart';
import 'package:yomashi/providers/favorites_provider.dart';
import 'package:yomashi/providers/categories_provider.dart';
import 'package:yomashi/providers/density_provider.dart';
import 'package:yomashi/providers/profile_provider.dart';
import 'package:yomashi/screens/library_screen.dart';
import 'package:yomashi/screens/profile_screen.dart';
import 'package:yomashi/widgets/manga_card.dart';
import 'package:yomashi/widgets/reader_page_scrubber.dart';
import 'package:yomashi/widgets/reader_chapter_end.dart';
import 'package:yomashi/providers/download_queue_provider.dart';
import 'package:yomashi/providers/library_provider.dart';
import 'package:yomashi/providers/reader_settings_provider.dart';
import 'package:yomashi/screens/reader_screen.dart';
import 'package:yomashi/screens/automation_screen.dart';
import 'package:yomashi/services/bookmark_service.dart';
import 'package:yomashi/services/maintenance_service.dart';
import 'package:yomashi/services/reader_crop_service.dart';
import 'package:yomashi/services/repair_service.dart';
import 'package:yomashi/services/rotating_backup_service.dart';
import 'package:yomashi/utils/fs_scanner.dart';
import 'package:yomashi/utils/backup_service.dart';
import 'package:yomashi/utils/preferences.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('Android: cola nativa, reparación, lector, copias y WorkManager', (
    tester,
  ) async {
    expect(app.downloadMain, isA<Function>());
    final info = await MaintenancePlatform.channel
        .invokeMapMethod<String, dynamic>('info');
    // Falla antes de escribir si se intenta ejecutar sobre la biblioteca personal.
    expect(
      const bool.fromEnvironment('YOMASHI_QA'),
      isTrue,
      reason: 'Exige --dart-define=YOMASHI_QA=true',
    );
    expect(
      info?['package'],
      'app.yomashi.reader.qa',
      reason: 'Exige ORG_GRADLE_PROJECT_yomashiTestApp=true',
    );
    // Profile mode needs a registered text-input client for injected editing events.
    tester.testTextInput.register();
    addTearDown(tester.testTextInput.unregister);
    await LibraryStore.initialize();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('reader_volume_navigation_v1', false);
    for (final id in ['reader-controls', 'library', 'downloads']) {
      await prefs.setBool('tip_${id}_v1', true);
    }
    final favorites = FavoritesProvider(),
        categories = CategoriesProvider(),
        density = DensityProvider(),
        profile = ProfileProvider();
    await PreferencesService.setFavoritesMap({});
    await favorites.load();
    await categories.load();
    await density.load();
    await profile.load();
    await const AutomationSettings(backups: true).save();
    final root = await Directory(
      '${(await getApplicationSupportDirectory()).path}/qa_${DateTime.now().microsecondsSinceEpoch}',
    ).create();
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final image = img.Image(width: 400, height: 600);
    img.fill(image, color: img.ColorRgb8(255, 255, 255));
    img.fillRect(
      image,
      x1: 30,
      y1: 40,
      x2: 369,
      y2: 559,
      color: img.ColorRgb8(40, 40, 40),
    );
    final png = img.encodePng(image);
    var requests = 0;
    server.listen((request) async {
      requests++;
      try {
        request.response.headers.contentType = ContentType('image', 'png');
        await Future<void>.delayed(const Duration(milliseconds: 150));
        request.response.add(png);
        await request.response.close();
      } catch (_) {}
    });
    final detail = OnlineMangaDetail(
      title: 'QA Android',
      url: 'https://inmanga.com/qa-${server.port}',
      chapters: [
        for (var ch = 0; ch < 2; ch++)
          Chapter(
            title: 'Capítulo ${ch + 1}',
            path: 'https://inmanga.com/qa-${server.port}/chapter/$ch',
            pages: [
              for (var page = 0; page < 4; page++)
                'http://127.0.0.1:${server.port}/$ch/$page',
            ],
          ),
      ],
    );
    final queue = DownloadQueueProvider(),
        library = LibraryProvider(),
        settings = ReaderSettingsProvider(),
        reads = ChapterReadProvider();
    Future<void> until(
      FutureOr<bool> Function() predicate, {
      int seconds = 50,
    }) async {
      final end = DateTime.now().add(Duration(seconds: seconds));
      while (!await predicate()) {
        if (DateTime.now().isAfter(end)) {
          fail(
            'Tiempo agotado. Cola: ${queue.jobs.map((j) => j.toMap())}; error: ${queue.persistenceError}',
          );
        }
        await tester.pump(const Duration(milliseconds: 100));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    }

    Widget host(Widget child) => MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: queue),
        ChangeNotifierProvider.value(value: library),
        ChangeNotifierProvider.value(value: settings),
        ChangeNotifierProvider.value(value: reads),
        ChangeNotifierProvider.value(value: favorites),
        ChangeNotifierProvider.value(value: categories),
        ChangeNotifierProvider.value(value: density),
        ChangeNotifierProvider.value(value: profile),
      ],
      child: MaterialApp(home: child),
    );
    try {
      await tester.pumpWidget(
        host(const Scaffold(body: Text('Prueba de Android'))),
      );
      await queue.load();
      await const MethodChannel(
        'app.yomashi.reader/downloads',
      ).invokeMethod('root', {'root': root.path});
      await queue.setDownloadThreads(1);
      await queue.enqueueManga(detail);
      await until(() => queue.jobs.any((j) => j.completedPages > 0));
      final id = queue.jobs.single.id;
      queue.pauseJob(id);
      await until(
        () => queue.jobs.any((j) => j.status == DownloadJobStatus.paused),
      );
      await until(
        () async => (await PreferencesService.getDownloadQueue()).any(
          (j) => j['id'] == id && j['status'] == 'paused',
        ),
      );
      queue.resumeJob(id);
      await until(() => queue.archive.any((e) => e.id == id));
      final storage = DownloadStorage(),
          folder = DownloadStorage().mangaFolder(root.path, detail);
      expect((await RepairService.inspect(folder.path)).damaged, isEmpty);
      final chapter = storage.chapterFolder(folder, detail.chapters.first);
      final good = storage.pageFile(chapter, 0),
          stamp = await storage.pageFile(chapter, 0).lastModified();
      await storage.pageFile(chapter, 2).delete();
      final before = requests;
      expect((await RepairService.inspect(folder.path)).missingPages, 1);
      final archiveBeforeRepair = queue.archive.length;
      await queue.repair(folder.path);
      await until(() => queue.archive.length > archiveBeforeRepair);
      expect(requests - before, 1);
      expect(await good.lastModified(), stamp);
      expect((await RepairService.inspect(folder.path)).damaged, isEmpty);

      final mangas = await FsScanner.scanLibraryMetadata([folder.parent.path]);
      final manga = mangas.singleWhere((m) => m.path == folder.path);
      expect(manga.chapters, hasLength(2));
      await settings.load();
      await reads.load();
      final open = Stopwatch()..start();
      await tester.pumpWidget(
        host(
          ReaderScreen(
            manga: manga,
            initialChapterIndex: 0,
            initialPageIndex: 0,
          ),
        ),
      );
      await until(
        () => find.byTooltip('Más opciones de lectura').evaluate().isNotEmpty,
      );
      await tester.pump(const Duration(milliseconds: 500));
      final readerOpenMs = open.elapsedMilliseconds;
      await tester.tap(find.byTooltip('Más opciones de lectura'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Añadir o quitar marcador'));
      await tester.pumpAndSettle();
      expect((await BookmarkService.list(detail.url)).length, 1);
      await settings.setCropWhite(true);
      await tester.pump(const Duration(seconds: 1));
      final cropped = await ReaderCropService.crop(good);
      expect(img.decodePng(await cropped.readAsBytes())!.width, 340);
      expect(await good.length(), png.length);
      // La opción de orientación se guarda por obra; se conserva para otro arranque.
      await settings.setOrientation('portrait');
      await tester.pumpAndSettle();
      expect(settings.orientation, 'portrait');
      final memoryBefore = await MaintenancePlatform.channel.invokeMapMethod(
        'info',
      );
      final seenPages = <int>{};
      await binding.watchPerformance(() async {
        for (var n = 0; n < 12; n++) {
          final rect = tester.getRect(find.byType(ReaderScreen));
          final next = n % 6 < 3;
          final right = next != settings.isRightToLeft;
          await tester.tapAt(
            Offset(right ? rect.right - 30 : rect.left + 30, rect.center.dy),
          );
          // PhotoView espera la ventana de doble toque antes de aceptar el toque.
          await Future<void>.delayed(const Duration(milliseconds: 350));
          await tester.pump();
          await tester.pumpAndSettle(const Duration(milliseconds: 16));
          seenPages.add(
            (await PreferencesService.getProgressMap())[detail.url]!.pageIndex,
          );
        }
      }, reportKey: 'reader_frames');
      expect(seenPages, containsAll([0, 1, 2, 3]));
      // Start at the first chapter independently of the performance gesture loop.
      await tester.pumpWidget(
        host(const Scaffold(body: Text('Abrir capítulo de prueba'))),
      );
      await tester.pumpAndSettle();
      await tester.pumpWidget(
        host(
          ReaderScreen(
            manga: manga,
            initialChapterIndex: 0,
            initialPageIndex: 0,
          ),
        ),
      );
      await until(() => find.byType(ReaderPageScrubber).evaluate().isNotEmpty);
      await tester.pump(const Duration(milliseconds: 500));
      // Scrubbing changes the saved position only after releasing the control.
      if (find.byType(ReaderPageScrubber).evaluate().isEmpty) {
        await tester.tapAt(tester.getRect(find.byType(ReaderScreen)).center);
        await Future<void>.delayed(const Duration(milliseconds: 350));
        await tester.pump();
      }
      final pageBeforeScrub =
          (await PreferencesService.getProgressMap())[detail.url]!.pageIndex;
      final slider = find.descendant(
        of: find.byType(ReaderPageScrubber),
        matching: find.byType(Slider),
      );
      await tester.ensureVisible(slider);
      final sliderRect = tester.getRect(slider);
      final gesture = await tester.startGesture(
        Offset(sliderRect.left + 24, sliderRect.center.dy),
      );
      await gesture.moveTo(Offset(sliderRect.right - 24, sliderRect.center.dy));
      await tester.pump(const Duration(milliseconds: 200));
      expect(
        (await PreferencesService.getProgressMap())[detail.url]!.pageIndex,
        pageBeforeScrub,
      );
      await gesture.up();
      await tester.pumpAndSettle();
      expect(
        (await PreferencesService.getProgressMap())[detail.url]!.pageIndex,
        3,
      );
      final scrubProgress =
          (await PreferencesService.getProgressMap())[detail.url]!;
      expect(
        scrubProgress.chapterPath,
        manga.chapters.first.sourceUrl ?? manga.chapters.first.path,
      );
      expect(find.byType(ReaderChapterEnd), findsOneWidget);
      expect(find.text('Siguiente capítulo'), findsOneWidget);
      final memoryAfter = await MaintenancePlatform.channel.invokeMapMethod(
        'info',
      );
      expect(tester.takeException(), isNull);
      // Real Android persistence: a saved online work appears without downloading it.
      await library.addLibraryPath(folder.parent.path);
      await favorites.toggle(
        key: 'https://inmanga.com/manga/qa-saved-only',
        title: 'Guardado sin descargar',
      );
      await tester.pumpWidget(host(const LibraryScreen()));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Biblioteca'), findsOneWidget);
      await tester.ensureVisible(find.text('Favoritos (1)'));
      await tester.tap(find.text('Favoritos (1)'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<MangaCard>(find.byType(MangaCard)).title,
        'Guardado sin descargar',
      );
      await tester.tap(find.text('Descargados (1)'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<MangaCard>(find.byType(MangaCard)).title,
        'QA Android',
      );
      await tester.pumpWidget(host(const ProfileScreen()));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Ajustes'), findsOneWidget);
      await tester.tap(find.byTooltip('Ajustes'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Buscar ajustes'),
        'brillo',
      );
      await tester.pumpAndSettle();
      expect(
        tester.widget<EditableText>(find.byType(EditableText)).controller.text,
        'brillo',
      );
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await until(
        () => find.text('Brillo en la app').evaluate().isNotEmpty,
        seconds: 5,
      );
      expect(find.text('Brillo en la app'), findsOneWidget);
      expect(find.text('Densidad'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.pumpWidget(host(const AutomationScreen()));
      await until(
        () => find.text('Buscar capítulos nuevos').evaluate().isNotEmpty,
        seconds: 10,
      );
      expect(find.text('Buscar capítulos nuevos'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(
        host(const Scaffold(body: Text('Probando tareas programadas'))),
      );
      final copy = await RotatingBackupService.run(force: true);
      expect(copy, isNotNull);
      expect(
        (await BackupService.preview(copy!)).progress,
        greaterThanOrEqualTo(1),
      );
      await BackupService.importFromFile(copy, merge: true);
      expect((await BookmarkService.list(detail.url)).length, 1);
      await MaintenancePlatform.schedule(const AutomationSettings());
      // Dejar cerrar el servicio; WorkManager debe levantar su propio motor.
      await until(
        () async =>
            (await MaintenancePlatform.channel.invokeMapMethod(
              'info',
            ))?['host'] ==
            'idle',
        seconds: 30,
      );
      await MaintenancePlatform.channel.invokeMethod('runOnce');
      await until(() async {
        final states = await MaintenancePlatform.channel
            .invokeListMethod<String>('workState');
        return states?.contains('SUCCEEDED') == true;
      }, seconds: 60);
      expect(
        await (await LibraryStore.ensureInitialized()).getRecord(
          'maintenance',
          'last',
        ),
        isNotNull,
      );
      binding.reportData = {
        ...?binding.reportData,
        'device': info,
        'readerOpenMs': readerOpenMs,
        'memoryBefore': memoryBefore,
        'memoryAfter': memoryAfter,
        'imageRequests': requests,
        'verifiedPages': 8,
        'repairRequests': requests - before,
        'worker': 'SUCCEEDED',
        'ux': [
          'library_filters',
          'saved_without_download',
          'settings_search',
          'scrubber_commit',
          'chapter_end',
        ],
      };
    } finally {
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
      favorites.dispose();
      categories.dispose();
      density.dispose();
      profile.dispose();
      queue.dispose();
      library.dispose();
      settings.dispose();
      reads.dispose();
      await server.close(force: true);
    }
  });
}
