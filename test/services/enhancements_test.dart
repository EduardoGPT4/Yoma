import 'dart:convert';
import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yomashi/data/app_database.dart';
import 'package:yomashi/data/library_store.dart';
import 'package:yomashi/data/download_storage.dart';
import 'package:yomashi/models/automation_settings.dart';
import 'package:yomashi/models/catalog_page.dart';
import 'package:yomashi/models/chapter_batch.dart';
import 'package:yomashi/models/chapter.dart';
import 'package:yomashi/models/favorite_entry.dart';
import 'package:yomashi/models/online_manga.dart';
import 'package:yomashi/providers/reader_settings_provider.dart';
import 'package:yomashi/services/alternative_chapter_service.dart';
import 'package:yomashi/services/bookmark_service.dart';
import 'package:yomashi/services/download_engine.dart';
import 'package:yomashi/services/image_repository.dart';
import 'package:yomashi/services/maintenance_service.dart';
import 'package:yomashi/services/reader_crop_service.dart';
import 'package:yomashi/services/repair_service.dart';
import 'package:yomashi/services/rotating_backup_service.dart';
import 'package:yomashi/services/source_http_client.dart';
import 'package:yomashi/services/manga_source_adapter.dart';
import 'package:yomashi/services/online_catalog_service.dart';
import 'package:yomashi/utils/backup_service.dart';
import 'download_engine_regression_test.dart'
    show MemoryQueue, RealHttp, eventually;

class RecordingEngine extends DownloadEngine {
  final selections = <Set<int>>[];
  @override
  String get downloadRoot => 'fixture';
  @override
  Future<void> enqueueManga(
    OnlineMangaDetail manga, {
    Set<int>? chapterIndexes,
    bool automatic = false,
    int? maxBytes,
    String? destinationRoot,
  }) async {
    selections.add(chapterIndexes!);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late LibraryStore store;
  late Directory root;
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    store = await LibraryStore.initialize(
      database: AppDatabase.forTesting(NativeDatabase.memory()),
    );
  });
  setUp(() async {
    root = await Directory.systemTemp.createTemp('yomashi-enhancements-');
    for (final namespace in [
      'bookmarks',
      'reader',
      'automation',
      'favorite_updates',
      'automatic_chapters',
    ]) {
      await store.replaceRecords(namespace, []);
    }
    await store.replaceFavoritesMap({});
  });
  tearDown(() async => root.delete(recursive: true));
  test(
    'concurrent UI and service transactions preserve every update in WAL',
    () async {
      final file = File('${root.path}/concurrent.sqlite');
      final a = AppDatabase.forTesting(NativeDatabase.createInBackground(file));
      final b = AppDatabase.forTesting(NativeDatabase.createInBackground(file));
      final first = LibraryStore(a), second = LibraryStore(b);
      try {
        await first.putRecord('counter', 'value', {'n': 0});
        // Abrir la segunda conexión antes de iniciar las escrituras simultáneas.
        await second.getRecord('counter', 'value');
        Future<void> increment(LibraryStore store) async {
          for (var i = 0; i < 20; i++) {
            await store.transaction(() async {
              final value = await store.getRecord('counter', 'value');
              await Future<void>.delayed(const Duration(milliseconds: 2));
              await store.putRecord('counter', 'value', {
                'n': (value['n'] as int) + 1,
              });
            });
          }
        }

        await Future.wait([increment(first), increment(second)]);
        expect((await first.getRecord('counter', 'value'))['n'], 40);
      } finally {
        await a.close();
        await b.close();
      }
    },
  );

  test('automation rejects disallowed network, battery and charging', () {
    const s = AutomationSettings(chargingOnly: true);
    final good = <String, dynamic>{
      'connected': true,
      'wifi': true,
      'charging': true,
      'battery': 50,
    };
    expect(MaintenancePlatform.allowed(s, good), isTrue);
    for (final bad in [
      {'wifi': false},
      {'connected': false},
      {'charging': false},
      {'battery': 19},
    ]) {
      expect(MaintenancePlatform.allowed(s, {...good, ...bad}), isFalse);
    }
    expect(
      MaintenancePlatform.allowed(const AutomationSettings(wifiOnly: false), {
        ...good,
        'wifi': false,
      }),
      isTrue,
    );
  });
  test('automation bounds corrupt numeric preferences', () {
    final s = AutomationSettings.fromMap({
      'aheadCount': 99,
      'budgetMiB': -1,
      'batteryMinimum': 0,
      'backupRetention': 100,
    });
    expect(
      [s.aheadCount, s.budgetMiB, s.batteryMinimum, s.backupRetention],
      [10, 32, 10, 30],
    );
  });
  Chapter chapter({
    String title = 'Capítulo 1',
    String? number,
    String? language,
    String? volume,
  }) => Chapter(
    title: title,
    path: title,
    pages: [],
    number: number,
    language: language,
    volume: volume,
  );

  test(
    'alternative lookup survives a failed source and loads next chapter batch',
    () async {
      final original = Map<String, MangaSourceAdapter>.from(
        OnlineCatalogService.adapters,
      );
      const title = 'Alternative pagination fixture';
      const ref = 'https://mangadex.org/title/alternative-fixture';
      try {
        for (final id in original.keys) {
          OnlineCatalogService.adapters[id] = CallbackSourceAdapter(
            id: id,
            catalogRequest: (p, n, q) async {
              if (id == 'lectortmo') throw const HttpException('fixture');
              return CatalogPage(
                items: id == 'mangadex'
                    ? [const OnlineMangaSummary(title: title, url: ref)]
                    : [],
              );
            },
            feedRequest: () async => [],
            detailRequest: (r) async => OnlineMangaDetail(
              title: title,
              url: r,
              chapters: [chapter(number: '1')],
              hasMoreChapters: true,
              nextChapterCursor: 1,
            ),
            chapterRequest: (r, c) async => ChapterBatch(
              chapters: [chapter(title: 'Chapter 2', number: '2')],
              nextCursor: 2,
              hasMore: false,
            ),
            pagesRequest: (r) async => [],
          );
        }
        final matches = await AlternativeChapterService.find(
          title,
          'https://inmanga.com/original',
          chapter(number: '2'),
        );
        expect(matches.single.sourceId, 'mangadex');
        expect(matches.single.chapter.number, '2');
      } finally {
        OnlineCatalogService.adapters
          ..clear()
          ..addAll(original);
      }
    },
  );
  test(
    'next chapter preparation selects exactly N following chapters',
    () async {
      final engine = RecordingEngine();
      addTearDown(engine.dispose);
      final detail = OnlineMangaDetail(
        title: 'Ahead',
        url: 'https://example.com/ahead',
        chapters: [for (var i = 0; i < 6; i++) chapter(title: '$i')],
      );
      final service = MaintenanceService(engine, detail: (_) async => detail);
      await const AutomationSettings(aheadCount: 2).save();
      await service.ahead(detail.url, '2');
      expect(engine.selections.single, {3, 4});
      await const AutomationSettings(aheadCount: 0).save();
      await service.ahead(detail.url, '2');
      expect(engine.selections.length, 1);
    },
  );
  test(
    'partial catalog metadata keeps downloaded chapters from older batches',
    () async {
      final storage = DownloadStorage(),
          folder = Directory('${root.path}/manga');
      await storage.saveManga(
        folder,
        OnlineMangaDetail(
          title: 'A',
          url: 'a',
          chapters: [
            chapter(title: '1'),
            chapter(title: '2'),
          ],
        ),
      );
      await storage.saveManga(
        folder,
        OnlineMangaDetail(
          title: 'A updated',
          url: 'a',
          chapters: [chapter(title: '1')],
        ),
      );
      final data = await DownloadStorage.readJson(
        File('${folder.path}/${DownloadStorage.mangaManifest}'),
      );
      expect((data!['chapters'] as List).length, 2);
      expect(data['title'], 'A updated');
    },
  );
  test('alternative chapters normalize decimals and reject wrong editions', () {
    final wanted = chapter(number: '1', language: 'es', volume: '2');
    expect(
      AlternativeChapterService.sameChapter(
        wanted,
        chapter(number: '1.00', language: 'es', volume: '2'),
      ),
      isTrue,
    );
    expect(
      AlternativeChapterService.sameChapter(
        wanted,
        chapter(number: '1', language: 'en'),
      ),
      isFalse,
    );
    expect(
      AlternativeChapterService.sameChapter(
        wanted,
        chapter(number: '1', volume: '3'),
      ),
      isFalse,
    );
    expect(
      AlternativeChapterService.sameChapter(wanted, chapter(number: '1.5')),
      isFalse,
    );
    expect(
      AlternativeChapterService.sameChapter(
        chapter(title: 'Extra A'),
        chapter(title: 'Extra B'),
      ),
      isFalse,
    );
    expect(
      AlternativeChapterService.sameChapter(
        chapter(title: 'Capítulo 12'),
        chapter(title: 'Chapter 12.0'),
      ),
      isTrue,
    );
  });
  Future<bool> bookmark(int page) => BookmarkService.toggle(
    manga: 'https://example.com/a',
    title: 'A',
    chapter: 'https://example.com/1',
    chapterTitle: '1',
    page: page,
  );
  test(
    'bookmark removal preserves other pages and concurrent toggles',
    () async {
      expect(await bookmark(0), isTrue);
      await bookmark(1);
      expect(await bookmark(0), isFalse);
      expect(
        (await BookmarkService.list('https://example.com/a')).single['page'],
        1,
      );
      await Future.wait([bookmark(2), bookmark(2)]);
      expect((await BookmarkService.list('https://example.com/a')).length, 1);
    },
  );
  test('per-manga crop and orientation do not leak to another title', () async {
    final s = ReaderSettingsProvider();
    await s.load();
    await s.setCropWhite(false);
    await s.setOrientation('system');
    await s.bindManga('a');
    await s.setCropWhite(true);
    await s.setOrientation('landscape');
    await s.bindManga('b');
    expect(s.cropWhite, isFalse);
    expect(s.orientation, 'system');
    await s.bindManga('a');
    expect(s.cropWhite, isTrue);
    expect(s.orientation, 'landscape');
    await s.unbindManga();
    expect(s.cropWhite, isFalse);
    expect(s.orientation, 'system');
    s.dispose();
  });
  test(
    'backup restores bookmarks, automation and per-title crop settings',
    () async {
      await bookmark(3);
      await const AutomationSettings(aheadCount: 3, budgetMiB: 256).save();
      await store.putRecord('reader', 'a', {
        'cropWhite': true,
        'orientation': 'portrait',
      });
      final file = await BackupService.exportToFile(directory: root);
      await store.replaceRecords('bookmarks', []);
      await const AutomationSettings().save();
      await BackupService.importFromFile(file, recoveryDirectory: root);
      expect(
        (await BookmarkService.list('https://example.com/a')).single['page'],
        3,
      );
      expect((await AutomationSettings.load()).aheadCount, 3);
      expect((await store.getRecord('reader', 'a'))['cropWhite'], true);
    },
  );
  test('invalid new backup fields cannot partly overwrite data', () async {
    await bookmark(4);
    final file = await BackupService.exportToFile(directory: root);
    final data = jsonDecode(await file.readAsString()) as Map;
    data['bookmarks'][0]['page'] = -2;
    await file.writeAsString(jsonEncode(data));
    await expectLater(
      BackupService.importFromFile(file, recoveryDirectory: root),
      throwsA(anything),
    );
    expect(
      (await BookmarkService.list('https://example.com/a')).single['page'],
      4,
    );
  });
  test('rotating backups keep requested retention and wait a day', () async {
    for (var i = 0; i < 4; i++) {
      await RotatingBackupService.run(force: true, retain: 2, directory: root);
    }
    final copies = await RotatingBackupService.files(directory: root);
    expect(copies.length, 2);
    expect(await RotatingBackupService.run(directory: root), isNull);
    expect(
      await RotatingBackupService.run(
        directory: root,
        now: DateTime.now().add(const Duration(days: 2)),
      ),
      isNotNull,
    );
  });
  test('crop trims white borders while preserving source bytes', () async {
    final image = img.Image(width: 100, height: 140);
    img.fill(image, color: img.ColorRgb8(255, 255, 255));
    img.fillRect(
      image,
      x1: 10,
      y1: 15,
      x2: 89,
      y2: 124,
      color: img.ColorRgb8(0, 0, 0),
    );
    final file = File('${root.path}/page.png');
    final original = img.encodePng(image);
    await file.writeAsBytes(original);
    final cropped = img.decodePng(ReaderCropService.process(file.path)!)!;
    expect([cropped.width, cropped.height], [80, 110]);
    expect(await file.readAsBytes(), original);
  });
  test('crop preserves all-white and full-bleed pages', () async {
    final image = img.Image(width: 50, height: 100);
    final file = File('${root.path}/page.png');
    for (final v in [0, 255]) {
      img.fill(image, color: img.ColorRgb8(v, v, v));
      await file.writeAsBytes(img.encodePng(image));
      expect(ReaderCropService.process(file.path), isNull);
    }
  });
  test(
    'favorite checks establish baseline, detect additions and retain pending downloads',
    () async {
      final engine = RecordingEngine();
      addTearDown(engine.dispose);
      var chapters = 1, wifi = true;
      final service = MaintenanceService(
        engine,
        detail: (ref) async => OnlineMangaDetail(
          title: 'A',
          url: ref,
          chapters: [for (var i = 0; i < chapters; i++) chapter(title: '$i')],
        ),
        conditions: () async => {
          'connected': true,
          'wifi': wifi,
          'charging': true,
          'battery': 100,
        },
      );
      await store.setFavorite(
        const FavoriteEntry(key: 'https://example.com/a', title: 'A'),
      );
      await const AutomationSettings(
        updates: true,
        autoDownload: true,
        backups: false,
      ).save();
      await service.run();
      expect(engine.selections, isEmpty);
      chapters = 2;
      wifi = false;
      await service.run(manual: true);
      expect(engine.selections, isEmpty);
      expect(
        (await store.getRecord(
          'favorite_updates',
          'https://example.com/a',
        ))['new'],
        ['1'],
      );
      wifi = true;
      await service.run();
      expect(engine.selections.single, {1});
      expect((await store.getRecord('maintenance', 'last'))['new'], 0);
    },
  );
  test(
    'automatic quota includes partial files and prevents extra enqueue',
    () async {
      final partial = Directory('${root.path}/chapter');
      await partial.create();
      await File('${partial.path}/000.image').writeAsBytes([1, 2, 3, 4]);
      await MaintenanceService.rememberAutomatic(partial.path, 'a');
      final engine = RecordingEngine();
      addTearDown(engine.dispose);
      final service = MaintenanceService(engine);
      expect(await service.automaticBytes(), 4);
      final file = await File(
        '${partial.path}/001.image',
      ).open(mode: FileMode.write);
      await file.truncate(32 * 1024 * 1024);
      await file.close();
      await service.enqueueAutomatic(
        OnlineMangaDetail(title: 'A', url: 'a', chapters: [chapter()]),
        {0},
        const AutomationSettings(budgetMiB: 32),
      );
      expect(engine.selections, isEmpty);
    },
  );
  test(
    'repair downloads only missing page, retaining valid pages and manifests',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final raw = HttpOverrides.runWithHttpOverrides(
        () => HttpClient(),
        RealHttp(),
      );
      final png = img.encodePng(img.Image(width: 8, height: 8));
      var requests = 0;
      server.listen((r) async {
        requests++;
        r.response.headers.contentType = ContentType('image', 'png');
        r.response.add(png);
        await r.response.close();
      });
      final pages = [
        for (var i = 0; i < 3; i++) 'http://127.0.0.1:${server.port}/$i',
      ];
      final manga = OnlineMangaDetail(
        title: 'Fixture',
        url: 'https://inmanga.com/repair-fixture',
        chapters: [
          Chapter(title: '1', path: 'https://inmanga.com/ch1', pages: pages),
        ],
      );
      final engine = DownloadEngine(
        persistence: MemoryQueue(),
        images: ImageRepository(client: SourceHttpClient(client: raw)),
        canDownload: (_) async => true,
      );
      try {
        await engine.setDownloadRoot(root.path);
        await engine.load();
        await engine.enqueueManga(manga);
        await eventually(() => engine.archive.isNotEmpty);
        expect(requests, 3);
        final storage = DownloadStorage(),
            folder = DownloadStorage().mangaFolder(root.path, manga);
        final ch = storage.chapterFolder(folder, manga.chapters.single);
        final good = storage.pageFile(ch, 0),
            stamp = await storage.pageFile(ch, 0).lastModified();
        await storage.pageFile(ch, 1).delete();
        final report = await RepairService.inspect(folder.path);
        expect(report.damaged, {0});
        expect(report.missingPages, 1);
        await engine.repair(folder.path);
        await eventually(() => engine.archive.length == 2);
        expect(requests, 4);
        expect(await good.lastModified(), stamp);
        expect((await RepairService.inspect(folder.path)).damaged, isEmpty);
      } finally {
        engine.dispose();
        await engine.waitForIdle();
        await server.close(force: true);
        raw.close(force: true);
      }
    },
  );
  test(
    'reader limits page download concurrency and budget failure cleans parts',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final raw = HttpOverrides.runWithHttpOverrides(
        () => HttpClient(),
        RealHttp(),
      );
      final png = img.encodePng(img.Image(width: 8, height: 8));
      var active = 0, peak = 0;
      server.listen((r) async {
        active++;
        if (active > peak) peak = active;
        await Future<void>.delayed(const Duration(milliseconds: 60));
        try {
          r.response.headers.contentType = ContentType('image', 'png');
          r.response.add(png);
          await r.response.close();
        } catch (_) {
        } finally {
          active--;
        }
      });
      final manga = OnlineMangaDetail(
        title: 'Fixture',
        url: 'https://inmanga.com/priority',
        chapters: [
          Chapter(
            title: '1',
            path: 'https://inmanga.com/pri1',
            pages: [
              for (var i = 0; i < 8; i++) 'http://127.0.0.1:${server.port}/$i',
            ],
          ),
        ],
      );
      final engine = DownloadEngine(
        persistence: MemoryQueue(),
        images: ImageRepository(client: SourceHttpClient(client: raw)),
        canDownload: (_) async => true,
      );
      try {
        await engine.setDownloadRoot(root.path);
        await engine.load();
        await engine.setDownloadThreads(8);
        engine.setReaderActive(true);
        await engine.enqueueManga(manga);
        await eventually(() => engine.archive.isNotEmpty);
        expect(peak, 2);
        final other = OnlineMangaDetail(
          title: 'Other',
          url: 'https://inmanga.com/budget',
          chapters: manga.chapters,
        );
        await engine.enqueueManga(other, maxBytes: 1);
        await eventually(() => engine.jobs.any((j) => j.error != null));
        await engine.waitForIdle();
        expect(
          root
              .listSync(recursive: true)
              .whereType<File>()
              .where((f) => f.path.endsWith('.part')),
          isEmpty,
        );
      } finally {
        engine.dispose();
        await engine.waitForIdle();
        await server.close(force: true);
        raw.close(force: true);
      }
    },
  );
}
