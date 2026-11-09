import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yomashi/data/app_database.dart';
import 'package:yomashi/data/library_store.dart';
import 'package:yomashi/data/download_storage.dart';
import 'package:yomashi/models/chapter.dart';
import 'package:yomashi/models/download_job.dart';
import 'package:yomashi/models/online_manga.dart';
import 'package:yomashi/services/download_engine.dart';
import 'package:yomashi/services/image_repository.dart';
import 'package:yomashi/services/storage_transfer.dart';
import 'package:yomashi/services/source_http_client.dart';
import 'package:yomashi/utils/app_failure.dart';
import 'package:yomashi/utils/fs_scanner.dart';

class MemoryQueue implements DownloadPersistence {
  List<Map<String, dynamic>> queue = [], archive = [];
  @override
  Future<List<Map<String, dynamic>>> readJobs() async => queue;
  @override
  Future<List<Map<String, dynamic>>> readArchive() async => archive;
  @override
  Future<void> writeJobs(List<Map<String, dynamic>> jobs) async {
    queue = jobs;
  }

  @override
  Future<void> writeArchive(List<Map<String, dynamic>> values) async {
    archive = values;
  }
}

class RealHttp extends HttpOverrides {}

Future<void> eventually(bool Function() predicate) async {
  final until = DateTime.now().add(const Duration(seconds: 8));
  while (!predicate()) {
    if (DateTime.now().isAfter(until)) {
      fail('La operación no terminó a tiempo.');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late HttpServer server;
  late HttpClient raw;
  late ImageRepository images;
  late MemoryQueue queue;
  late DownloadEngine engine;
  late Future<void> Function(HttpRequest) respond;
  final png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jN1kAAAAASUVORK5CYII=',
  );
  String url(String path) => 'http://127.0.0.1:${server.port}/$path';
  OnlineMangaDetail manga(String id, {int chapters = 1}) => OnlineMangaDetail(
    title: 'Same title',
    url: 'https://inmanga.com/$id',
    chapters: [
      for (var i = 0; i < chapters; i++)
        Chapter(title: 'Chapter $i', path: url('$id-$i'), pages: []),
    ],
  );
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await LibraryStore.initialize(
      database: AppDatabase.forTesting(NativeDatabase.memory()),
    );
  });
  setUp(() async {
    root = await Directory.systemTemp.createTemp('yomashi-regression-');
    queue = MemoryQueue();
    raw = HttpOverrides.runWithHttpOverrides(() => HttpClient(), RealHttp());
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    respond = (request) async {
      request.response.headers.contentType = ContentType('image', 'png');
      request.response.contentLength = png.length;
      request.response.add(png);
      await request.response.close();
    };
    server.listen((request) async {
      try {
        await respond(request);
      } catch (_) {}
    });
    images = ImageRepository(client: SourceHttpClient(client: raw));
    engine = DownloadEngine(
      persistence: queue,
      images: images,
      canDownload: (_) async => true,
      fetchPages: (path) async => ['$path/1', '$path/2'],
    );
    await engine.setDownloadRoot(root.path);
    await engine.load();
  });
  tearDown(() async {
    engine.dispose();
    await engine.waitForIdle();
    await server.close(force: true);
    raw.close(force: true);
    await root.delete(recursive: true);
  });
  test('preemption never confirms a canceled page', () async {
    final entered = Completer<void>();
    final release = Completer<void>();
    var requests = 0;
    final standard = respond;
    respond = (request) async {
      if (request.uri.path == '/a-0/1' && ++requests == 1) {
        entered.complete();
        await release.future;
      }
      await standard(request);
    };
    final a = manga('a'), b = manga('b');
    await engine.setDownloadThreads(1);
    await engine.enqueueManga(a);
    final aId = engine.jobs.single.id;
    await entered.future;
    await engine.enqueueManga(b);
    final bId = engine.jobs.last.id;
    engine.prioritizeJob(bId);
    await eventually(() => engine.archive.any((e) => e.id == bId));
    release.complete();
    await eventually(() => engine.archive.any((e) => e.id == aId));
    final chapter = DownloadStorage().chapterFolder(
      DownloadStorage().mangaFolder(root.path, a),
      a.chapters.single,
    );
    expect(
      await DownloadStorage().verifiedPages(chapter, [
        url('a-0/1'),
        url('a-0/2'),
      ]),
      {0, 1},
    );
    expect(engine.archive.firstWhere((e) => e.id == aId).completedPages, 2);
  });
  test('restart verifies only selected chapters and derives counts', () async {
    final detail = manga('selection', chapters: 4);
    final seed = DownloadJob(
      id: 'seed',
      manga: detail,
      chapterIndexes: {1, 3},
      destinationRoot: root.path,
      completedChapters: 1,
      currentChapterIndex: 2,
      completedChapterIndexes: {1},
    );
    engine.dispose();
    await engine.waitForIdle();
    queue.queue = [seed.toMap()];
    engine = DownloadEngine(
      persistence: queue,
      images: images,
      canDownload: (_) async => true,
      fetchPages: (path) async => ['$path/1'],
    );
    await engine.load();
    await eventually(() => engine.archive.isNotEmpty);
    expect(engine.archive.single.completedChapters, 2);
    expect(engine.archive.single.completedTitles, ['Chapter 1', 'Chapter 3']);
    expect(engine.archive.single.completedPages, 2);
  });
  test('manual pause releases worker and stays paused', () async {
    final entered = Completer<void>(), release = Completer<void>();
    final standard = respond;
    respond = (request) async {
      if (request.uri.path.startsWith('/pause-')) {
        if (!entered.isCompleted) entered.complete();
        await release.future;
      }
      await standard(request);
    };
    await engine.enqueueManga(manga('pause'));
    final id = engine.jobs.single.id;
    await entered.future;
    engine.pauseJob(id);
    await engine.enqueueManga(manga('other'));
    await eventually(() => engine.archive.isNotEmpty);
    expect(engine.jobs.single.status, DownloadJobStatus.paused);
    expect(engine.jobs.single.completedChapters, 0);
    release.complete();
    await engine.waitForIdle();
  });
  test('empty chapter fails permanently and next job completes', () async {
    engine.dispose();
    engine = DownloadEngine(
      persistence: queue,
      images: images,
      canDownload: (_) async => true,
      fetchPages: (path) async => path.contains('empty') ? [] : ['$path/1'],
    );
    await engine.load();
    await engine.enqueueManga(manga('empty'));
    await engine.enqueueManga(manga('good'));
    await eventually(() => engine.archive.isNotEmpty);
    expect(engine.jobs.single.status, DownloadJobStatus.failed);
    expect(engine.jobs.single.automaticRetry, isFalse);
    expect(engine.jobs.single.completedChapters, 0);
  });
  test('storage creation failure releases the queue', () async {
    final blocker = await File('${root.path}/blocked').writeAsString('file');
    final bad = DownloadJob(
      id: 'bad-storage',
      manga: manga('bad'),
      destinationRoot: blocker.path,
    );
    engine.dispose();
    await engine.waitForIdle();
    queue.queue = [bad.toMap()];
    engine = DownloadEngine(
      persistence: queue,
      images: images,
      canDownload: (_) async => true,
      fetchPages: (path) async => ['$path/1'],
    );
    await engine.load();
    await engine.enqueueManga(manga('next'));
    await eventually(() => engine.archive.isNotEmpty);
    expect(engine.jobs.single.status, DownloadJobStatus.failed);
    expect(engine.jobs.single.automaticRetry, isFalse);
  });
  test('changing root preserves destination of queued work', () async {
    engine.dispose();
    await engine.waitForIdle();
    queue.queue = [
      DownloadJob(
        id: 'old',
        manga: manga('old'),
        destinationRoot: root.path,
        status: DownloadJobStatus.paused,
      ).toMap(),
    ];
    engine = DownloadEngine(
      persistence: queue,
      images: images,
      canDownload: (_) async => true,
    );
    await engine.load();
    await engine.setDownloadRoot('${root.path}/new');
    expect(engine.jobs.single.destinationRoot, root.path);
  });
  test(
    'same title across sources and renamed titles retain stable identity',
    () {
      final a = manga('identity');
      final renamed = OnlineMangaDetail(
        title: 'Different name',
        url: a.url,
        chapters: a.chapters,
      );
      final other = OnlineMangaDetail(
        title: a.title,
        url: 'https://mangadex.org/title/identity',
        chapters: a.chapters,
      );
      final storage = DownloadStorage();
      expect(
        storage.mangaFolder(root.path, a).path,
        storage.mangaFolder(root.path, renamed).path,
      );
      expect(
        storage.mangaFolder(root.path, a).path,
        isNot(storage.mangaFolder(root.path, other).path),
      );
    },
  );
  test('HTML 200 cannot become a downloaded image', () async {
    respond = (request) async {
      request.response.headers.contentType = ContentType.html;
      request.response.write('<html>Challenge</html>');
      await request.response.close();
    };
    final target = File('${root.path}/invalid.image');
    await expectLater(
      images.download(url('html'), target),
      throwsA(isA<AppFailure>()),
    );
    expect(await target.exists(), isFalse);
    expect(await File('${target.path}.part').exists(), isFalse);
  });
  test('truncated existing image is rejected', () async {
    final target = await File(
      '${root.path}/broken.image',
    ).writeAsBytes(png.sublist(0, 40));
    expect(await ImageRepository.valid(target), isFalse);
  });
  test('404 is permanent, 429 and 503 retain retry metadata', () async {
    for (final status in [404, 429, 503]) {
      respond = (request) async {
        request.response.statusCode = status;
        request.response.headers.set('retry-after', '17');
        await request.response.close();
      };
      try {
        await images.download(
          url(status.toString()),
          File('${root.path}/error.image'),
        );
        fail('Expected HTTP error');
      } on AppFailure catch (error) {
        expect(error.statusCode, status);
        expect(error.retryable, status != 404);
        expect(error.retryAfter, const Duration(seconds: 17));
      }
    }
  });
  test('canceling a streamed image leaves no final or partial file', () async {
    final entered = Completer<void>(), release = Completer<void>();
    respond = (request) async {
      request.response.headers.contentType = ContentType('image', 'png');
      request.response.add(png.sublist(0, 32));
      await request.response.flush();
      entered.complete();
      await release.future;
      request.response.add(png.sublist(32));
      await request.response.close();
    };
    final token = CancellationToken();
    final target = File('${root.path}/cancel.image');
    final pending = images.download(url('stream'), target, cancellation: token);
    final result = expectLater(pending, throwsA(isA<AppFailure>()));
    await entered.future;
    token.cancel();
    await result;
    release.complete();
    expect(await target.exists(), isFalse);
    expect(await File('${target.path}.part').exists(), isFalse);
  });
  test(
    'migration preserves the old files and verifies the new destination',
    () async {
      final detail = manga('migration');
      await engine.enqueueManga(detail);
      await eventually(() => engine.archive.isNotEmpty);
      final original = DownloadStorage().mangaFolder(root.path, detail);
      final target = DownloadStorage().mangaFolder(
        '${root.path}/second',
        detail,
      );
      await StorageTransfer.copyVerified(original, target);
      expect(await original.exists(), isTrue);
      final chapter = DownloadStorage().chapterFolder(
        target,
        detail.chapters.single,
      );
      expect(
        await DownloadStorage().verifiedPages(chapter, [
          url('migration-0/1'),
          url('migration-0/2'),
        ]),
        {0, 1},
      );
      await expectLater(
        StorageTransfer.copyVerified(original, target),
        throwsA(isA<AppFailure>()),
      );
    },
  );
  test('gzip transfer validates decompressed image bytes', () async {
    respond = (request) async {
      final compressed = gzip.encode(png);
      request.response.headers.contentType = ContentType('image', 'png');
      request.response.headers.set('content-encoding', 'gzip');
      request.response.contentLength = compressed.length;
      request.response.add(compressed);
      await request.response.close();
    };
    final file = File('${root.path}/gzip.image');
    await images.download(url('gzip'), file);
    expect(await ImageRepository.valid(file), isTrue);
  });
  test(
    'shared cache deduplicates concurrent requests and enforces its quota',
    () async {
      images.cacheDirectory = Directory('${root.path}/cache');
      var requests = 0;
      final standard = respond;
      respond = (request) async {
        requests++;
        await Future<void>.delayed(const Duration(milliseconds: 30));
        await standard(request);
      };
      final files = await Future.wait([
        for (var i = 0; i < 8; i++) images.resolve(url('same-cache-image')),
      ]);
      expect(requests, 1);
      expect(files.map((f) => f.path).toSet().length, 1);
      images.quotaBytes = png.length;
      await images.resolve(url('another-cache-image'));
      await images.trim();
      expect(await images.cacheSize(), lessThanOrEqualTo(png.length));
    },
  );
  test('partial local chapters preserve the original page indexes', () async {
    final detail = manga('partial-indexes');
    final storage = DownloadStorage();
    final folder = storage.mangaFolder(root.path, detail);
    final chapter = storage.chapterFolder(folder, detail.chapters.single);
    await storage.saveManga(folder, detail);
    await storage.saveChapter(chapter, detail.chapters.single, 0, [
      'one',
      'two',
      'three',
    ], complete: false);
    await storage.pageFile(chapter, 1).writeAsBytes(png);
    final pages = FsScanner.loadChapterPages(chapter.path);
    expect(pages.length, 3);
    expect(await File(pages[0]).exists(), isFalse);
    expect(await File(pages[1]).exists(), isTrue);
    final indexed = FsScanner.scanMangaFolder(folder.path)!;
    expect((indexed['chapters'] as List).single['complete'], isFalse);
    expect((indexed['chapters'] as List).single['pageCount'], 3);
  });
}
