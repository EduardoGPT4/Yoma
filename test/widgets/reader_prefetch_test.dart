import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yomashi/data/app_database.dart';
import 'package:yomashi/data/library_store.dart';
import 'package:yomashi/models/chapter.dart';
import 'package:yomashi/models/content_identity.dart';
import 'package:yomashi/models/manga.dart';
import 'package:yomashi/providers/chapter_read_provider.dart';
import 'package:yomashi/providers/library_provider.dart';
import 'package:yomashi/providers/reader_settings_provider.dart';
import 'package:yomashi/screens/reader_screen.dart';
import 'package:yomashi/services/image_repository.dart';
import 'package:yomashi/services/manga_source_adapter.dart';
import 'package:yomashi/services/online_catalog_service.dart';

class _RealHttp extends HttpOverrides {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory folder;
  late HttpServer server;
  late ImageRepository repository;
  late Directory? previousCache;
  late double previousLatency;
  final requested = <String>[];
  final gates = <String, Completer<void>>{};
  final bytes = img.encodePng(img.Image(width: 2, height: 2));

  setUpAll(() async {
    folder = await Directory.systemTemp.createTemp('reader-prefetch-widget-');
    repository = HttpOverrides.runWithHttpOverrides(
      () => ImageRepository.shared,
      _RealHttp(),
    );
    previousCache = repository.cacheDirectory;
    previousLatency = repository.latencyMs;
    repository.cacheDirectory = Directory(p.join(folder.path, 'cache'));
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      requested.add(request.uri.path);
      await gates[request.uri.path]?.future;
      request.response.headers.contentType = ContentType('image', 'png');
      request.response.contentLength = bytes.length;
      request.response.persistentConnection = false;
      request.response.add(bytes);
      await request.response.close();
    });
    SharedPreferences.setMockInitialValues({
      'reader_volume_navigation_v1': false,
    });
    await LibraryStore.initialize(
      database: AppDatabase.forTesting(NativeDatabase.memory()),
    );
  });

  tearDownAll(() async {
    repository.cacheDirectory = previousCache;
    repository.latencyMs = previousLatency;
    repository.client.close(force: true);
    await server.close(force: true);
    final path = folder.resolveSymbolicLinksSync();
    final temp = Directory.systemTemp.resolveSymbolicLinksSync();
    if (!p.isWithin(temp, path) ||
        !p.basename(path).startsWith('reader-prefetch-widget-')) {
      throw StateError('Unexpected test cache directory');
    }
    for (var attempt = 0; attempt < 20; attempt++) {
      try {
        if (await folder.exists()) await folder.delete(recursive: true);
        break;
      } on FileSystemException {
        if (attempt == 19) rethrow;
        await Future<void>.delayed(const Duration(milliseconds: 25));
      }
    }
  });

  for (final mode in [
    'online-hitomi',
    'online-hitomi-double',
    'online-inmanga',
    'offline-hitomi',
  ]) {
    testWidgets(
      '$mode keeps five-page prefetch limited to its intended online reader',
      (tester) async {
        requested.clear();
        gates.clear();
        SharedPreferences.setMockInitialValues({
          'reader_volume_navigation_v1': false,
        });
        repository.latencyMs =
            5000; // The existing adaptive decoded preload is off.
        final sourceId = mode.contains('inmanga') ? 'inmanga' : 'hitomi';
        final original = OnlineCatalogService.adapters[sourceId]!;
        final online = !mode.startsWith('offline');
        final initialPage = mode == 'online-hitomi-double' ? 2 : 6;
        final pageLabel = '${initialPage + 1}/12';
        final remote = List.generate(
          12,
          (i) => 'http://127.0.0.1:${server.port}/$mode/$i.png',
        );
        final local = Directory(p.join(folder.path, mode));
        local.createSync();
        for (var i = 0; i < 12; i++) {
          File(
            p.join(local.path, '${i.toString().padLeft(2, '0')}.png'),
          ).writeAsBytesSync(bytes);
        }
        final chapterPath = online
            ? 'https://${sourceId == 'hitomi' ? 'hitomi.la' : 'inmanga.com'}/reader/fixture-$mode'
            : local.path;
        OnlineCatalogService.adapters[sourceId] = CallbackSourceAdapter(
          id: sourceId,
          catalogRequest: (a, b, c) =>
              original.catalog(page: a, pageSize: b, query: c),
          feedRequest: original.feed,
          detailRequest: original.detail,
          pagesRequest: (_) async => remote,
        );
        if (mode == 'online-hitomi') {
          gates['/$mode/7.png'] = Completer<void>();
          gates['/$mode/8.png'] = Completer<void>();
        }
        final library = LibraryProvider();
        final settings = ReaderSettingsProvider();
        final reads = ChapterReadProvider();
        await settings.load();
        await reads.load();

        Future<void> waitFor(bool Function() ready) async {
          for (var attempt = 0; attempt < 150; attempt++) {
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 20)),
            );
            await tester.pump();
            if (ready()) return;
          }
          fail('Reader did not finish its fixture work: $requested');
        }

        File cached(int page) => File(
          p.join(
            repository.cacheDirectory!.path,
            '${ContentIdentity.id(remote[page])}.image',
          ),
        );

        try {
          await tester.pumpWidget(
            MultiProvider(
              providers: [
                ChangeNotifierProvider.value(value: library),
                ChangeNotifierProvider.value(value: settings),
                ChangeNotifierProvider.value(value: reads),
              ],
              child: MaterialApp(
                home: ReaderScreen(
                  manga: Manga(
                    title: 'Fixture $mode',
                    path:
                        'https://${sourceId == 'hitomi' ? 'hitomi.la' : 'inmanga.com'}/gallery/fixture-$mode',
                    sourceUrl:
                        'https://${sourceId == 'hitomi' ? 'hitomi.la' : 'inmanga.com'}/gallery/fixture-$mode',
                    chapters: [
                      Chapter(
                        title: 'Fixture',
                        path: chapterPath,
                        pageCount: 12,
                      ),
                    ],
                  ),
                  initialChapterIndex: 0,
                  initialPageIndex: initialPage,
                ),
              ),
            ),
          );
          await waitFor(() => find.text(pageLabel).evaluate().isNotEmpty);
          if (mode == 'online-hitomi-double') {
            await waitFor(() => cached(7).existsSync());
            expect(requested, isNot(contains('/$mode/8.png')));
            await settings.setCoverAlone(false);
            await settings.setDoublePage(true);
            await tester.pump();
            await waitFor(() => cached(8).existsSync());
            expect(requested, isNot(contains('/$mode/9.png')));
          } else if (mode == 'online-hitomi') {
            await waitFor(
              () =>
                  requested.contains('/$mode/7.png') &&
                  requested.contains('/$mode/8.png'),
            );
            tester.binding.handleAppLifecycleStateChanged(
              AppLifecycleState.inactive,
            );
            for (final gate in gates.values) {
              gate.complete();
            }
            await waitFor(
              () => cached(7).existsSync() && cached(8).existsSync(),
            );
            expect(requested, isNot(contains('/$mode/9.png')));
            tester.binding.handleAppLifecycleStateChanged(
              AppLifecycleState.resumed,
            );
            await waitFor(() => cached(11).existsSync());
            for (var i = 7; i <= 11; i++) {
              expect(
                await tester.runAsync(() => ImageRepository.valid(cached(i))),
                isTrue,
              );
              expect(
                requested.where((path) => path == '/$mode/$i.png'),
                hasLength(1),
              );
            }
          } else if (online) {
            await waitFor(() => cached(6).existsSync());
            expect(requested, isNot(contains('/$mode/11.png')));
          } else {
            expect(requested, isEmpty);
          }
          // Finish the actual image codecs before unmounting the reader, so
          // Windows file handles do not outlive this test's temporary files.
          await waitFor(
            () =>
                PaintingBinding.instance.imageCache.pendingImageCount == 0 &&
                tester
                    .widgetList<RawImage>(find.byType(RawImage))
                    .any((image) => image.image != null),
          );
          expect(reads.isRead(chapterPath), isFalse);
          expect(find.text(pageLabel), findsOneWidget);
          expect(tester.takeException(), isNull);
        } finally {
          for (final gate in gates.values) {
            if (!gate.isCompleted) gate.complete();
          }
          await tester.runAsync(library.flushStats);
          await tester.pumpWidget(const SizedBox());
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.resumed,
          );
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 100)),
          );
          await tester.pump(const Duration(seconds: 2));
          library.dispose();
          settings.dispose();
          reads.dispose();
          OnlineCatalogService.adapters[sourceId] = original;
          PaintingBinding.instance.imageCache.clear();
          PaintingBinding.instance.imageCache.clearLiveImages();
        }
      },
    );
  }
}
