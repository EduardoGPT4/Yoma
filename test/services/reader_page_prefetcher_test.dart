import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:yomashi/services/image_repository.dart';
import 'package:yomashi/services/reader_page_prefetcher.dart';
import 'package:yomashi/services/source_http_client.dart';

List<String> pages(int count) =>
    List.generate(count, (i) => 'https://fixture.test/$i.png');
Future<void> drain() async {
  for (var i = 0; i < 20; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

class _RealHttp extends HttpOverrides {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'preloads exactly the five following pages with two simultaneous loads',
    () async {
      final calls = <String>[];
      var active = 0, peak = 0;
      final prefetch = ReaderPagePrefetcher(
        load: (url) async {
          calls.add(url);
          active++;
          if (active > peak) peak = active;
          await Future<void>.delayed(Duration.zero);
          active--;
        },
      );
      addTearDown(prefetch.dispose);
      final chapter = pages(20);
      prefetch.update(chapter, currentPage: 3);
      await drain();
      expect(calls, chapter.sublist(4, 9));
      expect(peak, 2);
      prefetch.update(chapter, currentPage: 3);
      await drain();
      expect(calls, hasLength(5));
      prefetch.update(chapter, currentPage: 4);
      await drain();
      expect(calls, chapter.sublist(4, 10));
    },
  );

  test('stops at the end of the chapter and ignores local files', () async {
    final calls = <String>[];
    final prefetch = ReaderPagePrefetcher(load: (url) async => calls.add(url));
    addTearDown(prefetch.dispose);
    final chapter = pages(5);
    prefetch.update(chapter, currentPage: 3);
    await drain();
    expect(calls, [chapter[4]]);
    prefetch.update(chapter, currentPage: 4);
    prefetch.update([], currentPage: 0);
    prefetch.update(chapter, currentPage: -1);
    prefetch.update(chapter, currentPage: 5);
    prefetch.update(['/local/1.png', '/local/2.png'], currentPage: 0);
    await drain();
    expect(calls, hasLength(1));
  });

  test(
    'a jump replaces queued pages while letting shared active loads finish',
    () async {
      final calls = <String>[];
      final first = Completer<void>(), second = Completer<void>();
      final chapter = pages(20);
      final prefetch = ReaderPagePrefetcher(
        load: (url) async {
          calls.add(url);
          if (url == chapter[1]) await first.future;
          if (url == chapter[2]) await second.future;
        },
      );
      addTearDown(prefetch.dispose);
      prefetch.update(chapter, currentPage: 0);
      expect(calls, chapter.sublist(1, 3));
      prefetch.update(chapter, currentPage: 9);
      first.complete();
      second.complete();
      await drain();
      expect(calls, [...chapter.sublist(1, 3), ...chapter.sublist(10, 15)]);
    },
  );

  test('advancing while a page is loading does not request it twice', () async {
    final calls = <String>[];
    final gate = Completer<void>();
    final chapter = pages(20);
    final prefetch = ReaderPagePrefetcher(
      load: (url) async {
        calls.add(url);
        await gate.future;
      },
    );
    addTearDown(prefetch.dispose);
    prefetch.update(chapter, currentPage: 0);
    prefetch.update(chapter, currentPage: 1);
    gate.complete();
    await drain();
    expect(calls, chapter.sublist(1, 7));
    expect(calls.toSet().length, calls.length);
  });

  test(
    'failed pages do not block the rest or cause a repeated window to loop',
    () async {
      final calls = <String>[], errors = <Object>[];
      final chapter = pages(10);
      final prefetch = ReaderPagePrefetcher(
        load: (url) async {
          calls.add(url);
          if (url == chapter[2]) throw const SocketException('fixture offline');
        },
        onError: errors.add,
      );
      addTearDown(prefetch.dispose);
      prefetch.update(chapter, currentPage: 0);
      await drain();
      prefetch.update(chapter, currentPage: 0);
      await drain();
      expect(calls, chapter.sublist(1, 6));
      expect(errors, hasLength(1));
    },
  );

  test(
    'stopping prevents queued loads and the same chapter can resume',
    () async {
      final calls = <String>[];
      final gate = Completer<void>();
      final chapter = pages(10);
      final prefetch = ReaderPagePrefetcher(
        load: (url) async {
          calls.add(url);
          await gate.future;
        },
      );
      addTearDown(prefetch.dispose);
      prefetch.update(chapter, currentPage: 0);
      prefetch.stop();
      gate.complete();
      await drain();
      expect(calls, hasLength(2));
      prefetch.update(chapter, currentPage: 0);
      await drain();
      expect(calls.skip(2), chapter.sublist(1, 6));
    },
  );

  test(
    'disposing prevents more loads after an active request finishes',
    () async {
      final calls = <String>[];
      final gate = Completer<void>();
      final prefetch = ReaderPagePrefetcher(
        load: (url) async {
          calls.add(url);
          await gate.future;
        },
      );
      prefetch.update(pages(10), currentPage: 0);
      prefetch.dispose();
      gate.complete();
      await drain();
      prefetch.update(pages(10), currentPage: 4);
      expect(calls, hasLength(2));
    },
  );

  test(
    'prefetched files are verified and reused by the image repository',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'reader-prefetch-',
      );
      final real = HttpOverrides.runWithHttpOverrides(
        HttpClient.new,
        _RealHttp(),
      );
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final requested = <String>[];
      final bytes = img.encodePng(img.Image(width: 2, height: 2));
      server.listen((request) async {
        requested.add(request.uri.path);
        request.response.headers.contentType = ContentType('image', 'png');
        request.response.add(bytes);
        await request.response.close();
      });
      final repository = ImageRepository(client: SourceHttpClient(client: real))
        ..cacheDirectory = directory
        ..latencyMs = 5000;
      final chapter = List.generate(
        8,
        (i) => 'http://127.0.0.1:${server.port}/$i.png',
      );
      final cached = <File>[];
      final loaded = Completer<void>();
      final errors = <Object>[];
      final prefetch = ReaderPagePrefetcher(
        load: (url) async {
          cached.add(await repository.resolve(url));
          if (cached.length == 5) loaded.complete();
        },
        onError: (error) {
          errors.add(error);
          if (!loaded.isCompleted) loaded.completeError(error);
        },
      );
      try {
        prefetch.update(chapter, currentPage: 0);
        await loaded.future.timeout(const Duration(seconds: 10));
        expect(errors, isEmpty);
        expect(requested.toSet(), {for (var i = 1; i <= 5; i++) '/$i.png'});
        for (final file in cached) {
          expect(await ImageRepository.valid(file), isTrue);
        }
        await repository.resolve(chapter[3]);
        expect(requested, hasLength(5));
      } finally {
        prefetch.dispose();
        real.close(force: true);
        await server.close(force: true);
        final path = directory.resolveSymbolicLinksSync();
        final temp = Directory.systemTemp.resolveSymbolicLinksSync();
        if (!path.startsWith('$temp${Platform.pathSeparator}') ||
            !directory.path.contains('reader-prefetch-')) {
          throw StateError('Unexpected test cache directory');
        }
        await directory.delete(recursive: true);
      }
    },
  );
}
