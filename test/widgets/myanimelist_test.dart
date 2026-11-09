import 'dart:convert';
import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yomashi/data/app_database.dart';
import 'package:yomashi/data/library_store.dart';
import 'package:yomashi/models/chapter.dart';
import 'package:yomashi/models/manga.dart';
import 'package:yomashi/screens/myanimelist_screen.dart';
import 'package:yomashi/services/myanimelist_client.dart';
import 'package:yomashi/services/myanimelist_service.dart';
import 'package:yomashi/utils/backup_service.dart';
import '../services/download_engine_regression_test.dart' show RealHttp;

class MemoryCredential extends MalCredentialStore {
  Map<String, dynamic>? value = {
    'device_token': 'a' * 64,
    'connected': true,
    'profile': {'id': 7, 'name': 'MangaTester'},
  };
  @override
  Future<Map<String, dynamic>?> load() async => value;
  @override
  Future<void> save(Map<String, dynamic> v) async => value = v;
  @override
  Future<void> clear() async => value = null;
}

const selected = MalManga(
  id: 2,
  title: 'Berserk',
  chaptersRead: 0,
  totalChapters: 100,
  status: 'reading',
  publishingStatus: 'finished',
);
final manga = Manga(
  title: 'Berserk local',
  path: '/downloads/berserk',
  sourceUrl: 'https://inmanga.com/manga/berserk',
  chapters: [
    Chapter(
      title: 'Capítulo 2',
      path: '/downloads/berserk/2',
      sourceUrl: 'https://inmanga.com/chapter/2',
    ),
    Chapter(
      title: 'Capítulo 10',
      number: '10',
      path: '/downloads/berserk/10',
      sourceUrl: 'https://inmanga.com/chapter/10',
    ),
    Chapter(
      title: 'Especial',
      number: '10.5',
      path: '/downloads/berserk/extra',
    ),
  ],
);

class FakeMal extends MyAnimeListClient {
  FakeMal(MemoryCredential store) : super(credentials: store);
  final sent = <int>[];
  bool failing = false;
  Future<void> Function()? duringSend;
  @override
  Future<Map<String, dynamic>?> account() => credentials.load();
  @override
  Future<List<MalManga>> search(String query) async => [selected];
  @override
  Future<MalManga> detail(int id) async => selected;
  @override
  Future<MalManga> update(
    int id,
    int chapters,
    String status, {
    bool automatic = false,
    int? expectedOwner,
  }) async {
    expect(expectedOwner, 7);
    if (failing) throw const MalFailure('Sin conexión');
    sent.add(chapters);
    await duringSend?.call();
    return selected;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late LibraryStore store;
  late MemoryCredential credential;
  late FakeMal fake;
  late MyAnimeListService service;
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    store = await LibraryStore.initialize(
      database: AppDatabase.forTesting(NativeDatabase.memory()),
    );
  });
  setUp(() async {
    credential = MemoryCredential();
    fake = FakeMal(credential);
    service = MyAnimeListService(fake);
    for (final ns in ['mal_links', 'mal_pending', 'mal_chapters']) {
      await store.replaceRecords(ns, []);
    }
    await store.replaceReadChapterKeys({});
  });
  tearDown(() => fake.http.close(force: true));

  test(
    'accepts manga ID and official manga URL; excludes anime and foreign URLs',
    () {
      expect(MyAnimeListClient.parseId(' 2 '), 2);
      expect(
        MyAnimeListClient.parseId('https://myanimelist.net/manga/2/Berserk'),
        2,
      );
      for (final input in [
        '0',
        '-2',
        '1000000000',
        'https://myanimelist.net/anime/2',
        'https://evil.test/manga/2',
        'https://user@myanimelist.net/manga/2',
      ]) {
        expect(MyAnimeListClient.parseId(input), isNull);
      }
    },
  );
  test('only whole numbered chapters count, including Spanish titles', () {
    expect(MyAnimeListService.chapterNumber(manga.chapters[0]), 2);
    expect(MyAnimeListService.chapterNumber(manga.chapters[1]), 10);
    expect(MyAnimeListService.chapterNumber(manga.chapters[2]), isNull);
    for (final value in ['0', '-1', 'NaN', 'Infinity', '100001']) {
      expect(
        MyAnimeListService.chapterNumber(
          Chapter(title: 'Extra', path: 'x', number: value),
        ),
        isNull,
      );
    }
    expect(
      MyAnimeListService.chapterNumber(Chapter(title: 'Cap. 012.0', path: 'x')),
      12,
    );
    expect(
      MyAnimeListService.chapterNumber(
        Chapter(title: 'Especial de navidad', path: 'x'),
      ),
      isNull,
    );
  });
  test('automatic sync requires an explicit link and opt-in', () async {
    await service.queueRead(manga.chapters.first.path);
    expect(await store.readRecords('mal_pending'), isEmpty);
    await service.link(manga, selected, automatic: false);
    await service.queueRead(manga.chapters.first.path);
    await service.flush();
    expect(fake.sent, isEmpty);
  });
  test(
    'local/online aliases coalesce highest chapter; decimal specials are skipped',
    () async {
      await service.link(manga, selected, automatic: true);
      await service.queueRead(manga.chapters[1].sourceUrl!);
      await service.queueRead(manga.chapters[0].path);
      await service.queueRead(manga.chapters[2].path);
      expect((await store.readRecords('mal_pending')).single['chapters'], 10);
      await service.flush();
      expect(fake.sent, [10]);
      expect(await store.readRecords('mal_pending'), isEmpty);
    },
  );
  test(
    'linking existing reads starts from highest confirmed chapter',
    () async {
      await store.replaceReadChapterKeys({
        manga.chapters[0].path,
        manga.chapters[1].path,
      });
      await service.link(manga, selected, automatic: true);
      expect((await store.readRecords('mal_pending')).single['chapters'], 10);
    },
  );
  test('offline retains jobs with backoff; manual retry sends them', () async {
    await service.link(manga, selected, automatic: true);
    await service.queueRead(manga.chapters.first.path);
    fake.failing = true;
    await service.flush();
    final job = (await store.readRecords('mal_pending')).single;
    expect(job['tries'], 1);
    expect(job['error'], 'Sin conexión');
    fake.failing = false;
    await service.flush();
    expect(fake.sent, isEmpty);
    await service.flush(force: true);
    expect(fake.sent, [2]);
    expect(await store.readRecords('mal_pending'), isEmpty);
  });
  test(
    'another account cannot receive the old account pending progress',
    () async {
      await service.link(manga, selected, automatic: true);
      await service.queueRead(manga.chapters.first.path);
      credential.value = {
        ...credential.value!,
        'profile': {'id': 8, 'name': 'Other'},
      };
      await service.flush(force: true);
      expect(fake.sent, isEmpty);
      expect(await store.readRecords('mal_pending'), hasLength(1));
      credential.value = null;
      await service.flush(force: true);
      expect(fake.sent, isEmpty);
    },
  );
  test('relink/unlink cancels stale pending work', () async {
    await service.link(manga, selected, automatic: true);
    await service.queueRead(manga.chapters.first.path);
    await service.link(manga, selected, automatic: false);
    expect(await store.readRecords('mal_pending'), isEmpty);
    await service.unlink(manga);
    expect(await service.linkFor(manga), isNull);
  });
  test('ineligible jobs do not block later eligible progress', () async {
    for (var i = 0; i < 12; i++) {
      await store.putRecord('mal_pending', 'aaa-$i', {
        'id': 'aaa-$i',
        'owner': 8,
        'lease': 0,
      });
    }
    await service.link(manga, selected, automatic: true);
    await service.queueRead(manga.chapters.first.path);
    await service.flush();
    expect(fake.sent, [2]);
    expect(await store.readRecords('mal_pending'), hasLength(12));
  });
  test('progress queued during a send survives and is sent next', () async {
    await service.link(manga, selected, automatic: true);
    await service.queueRead(manga.chapters.first.path);
    fake.duringSend = () async {
      fake.duringSend = null;
      await service.queueRead(manga.chapters[1].path);
    };
    await service.flush();
    expect(fake.sent, [2, 10]);
    expect(await store.readRecords('mal_pending'), isEmpty);
  });
  test('parallel service flushes claim a single persistent lease', () async {
    await service.link(manga, selected, automatic: true);
    await service.queueRead(manga.chapters.first.path);
    final other = MyAnimeListService(fake);
    fake.duringSend = () async =>
        Future<void>.delayed(const Duration(milliseconds: 30));
    await Future.wait([service.flush(), other.flush()]);
    expect(fake.sent, [2]);
  });
  test(
    'backup v4 restores links, excludes credentials, rejects unsafe link fields',
    () async {
      final root = await Directory.systemTemp.createTemp('yomashi-mal-backup-');
      try {
        await service.link(manga, selected, automatic: true);
        final file = await BackupService.exportToFile(directory: root);
        final text = await file.readAsString();
        final map = jsonDecode(text) as Map;
        expect(map['version'], 4);
        expect(map['malLinks'], hasLength(1));
        expect(text, isNot(contains('device_token')));
        expect(text, isNot(contains('a' * 64)));
        await service.unlink(manga);
        await BackupService.importFromFile(file, recoveryDirectory: root);
        expect((await service.linkFor(manga))!['owner'], 7);
        map['malLinks'][0]['device_token'] = 'forbidden';
        await file.writeAsString(jsonEncode(map));
        await expectLater(
          BackupService.importFromFile(file, recoveryDirectory: root),
          throwsStateError,
        );
        expect((await service.linkFor(manga))!['malId'], 2);
      } finally {
        await root.delete(recursive: true);
      }
    },
  );

  group('HTTP client', () {
    late HttpServer server;
    late HttpClient raw;
    late MyAnimeListClient client;
    late Future<void> Function(HttpRequest) respond;
    final requests = <Map<String, dynamic>>[];
    final node = {
      'id': 2,
      'title': 'Berserk',
      'num_chapters': 100,
      'chapters_read': 2,
      'status': 'reading',
      'publishing_status': 'finished',
    };
    setUp(() async {
      requests.clear();
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      raw = HttpOverrides.runWithHttpOverrides(() => HttpClient(), RealHttp());
      client = MyAnimeListClient(
        api: Uri.parse('http://127.0.0.1:${server.port}/api'),
        http: raw,
        credentials: credential,
        solveHostCookie: (values) async {
          expect(values, hasLength(3));
          return 'f' * 32;
        },
      );
      respond = (r) async {
        final body = await utf8.decoder.bind(r).join();
        expect(r.headers.contentLength, utf8.encode(body).length);
        final m = jsonDecode(body) as Map<String, dynamic>;
        requests.add(m);
        expect(r.headers.value('authorization'), 'Bearer ${'a' * 64}');
        r.response.headers.contentType = ContentType.json;
        r.response.write(
          jsonEncode(
            m['action'] == 'search'
                ? {
                    'items': [node],
                  }
                : {'manga': node},
          ),
        );
        await r.response.close();
      };
      server.listen((r) async {
        expect(r.headers.value('X-YomaShi-Token'), 'a' * 64);
        expect(r.headers.contentLength, greaterThan(0));
        expect(r.headers.value(HttpHeaders.transferEncodingHeader), isNull);
        expect(r.persistentConnection, isFalse);
        await respond(r);
      });
    });
    tearDown(() async {
      raw.close(force: true);
      await server.close(force: true);
    });
    test('search name, ID and URL use manga-only requests', () async {
      expect((await client.search('Berserk')).single.id, 2);
      await client.search('2');
      await client.search('https://myanimelist.net/manga/2/Berserk');
      expect(requests.map((r) => r['action']), ['search', 'detail', 'detail']);
      await expectLater(
        client.search('https://myanimelist.net/anime/2'),
        throwsA(isA<MalFailure>()),
      );
      await expectLater(client.search('ab'), throwsA(isA<MalFailure>()));
      expect(requests, hasLength(3));
    });
    test(
      'update includes only the requested manga fields and owner guard',
      () async {
        await client.update(2, 20, 'on_hold', expectedOwner: 7);
        expect(requests.single, {
          'action': 'update',
          'id': 2,
          'chapters_read': 20,
          'status': 'on_hold',
          'automatic': false,
          'owner_id': 7,
        });
        await expectLater(
          client.update(2, 30, 'reading', expectedOwner: 8),
          throwsA(isA<MalFailure>()),
        );
        expect(requests, hasLength(1));
      },
    );
    test(
      'UTF-8 manga names use the encoded byte count for Content-Length',
      () async {
        expect((await client.search('ベルセルク')).single.id, 2);
        expect(requests.single['query'], 'ベルセルク');
      },
    );
    test('expired authorization forgets the local credential', () async {
      respond = (r) async {
        await r.drain<void>();
        r.response.statusCode = 401;
        r.response.write('{"error":"Reconecta"}');
        await r.response.close();
      };
      await expectLater(client.detail(2), throwsA(isA<MalFailure>()));
      expect(credential.value, isNull);
    });
    test(
      'ordinary first-party hosting handshake retries once and caches cookie',
      () async {
        final normal = respond;
        var calls = 0;
        respond = (r) async {
          if (calls++ == 0) {
            await r.drain<void>();
            r.response.write(
              'slowAES.decrypt __test toNumbers("${'a' * 32}") toNumbers("${'b' * 32}") toNumbers("${'c' * 32}")',
            );
            await r.response.close();
          } else {
            expect(r.headers.value('cookie'), '__test=${'f' * 32}');
            await normal(r);
          }
        };
        await client.detail(2);
        await client.detail(2);
        expect(calls, 3);
      },
    );
    test(
      'malformed or redirected hosting responses fail without following them',
      () async {
        respond = (r) async {
          await r.drain<void>();
          r.response.statusCode = 302;
          r.response.headers.set('location', 'https://evil.test');
          r.response.write('invalid');
          await r.response.close();
        };
        await expectLater(client.detail(2), throwsA(isA<MalFailure>()));
      },
    );
  });
  testWidgets(
    'MAL screen shows account, search, selected status and chapter controls',
    (tester) async {
      tester.view.physicalSize = const Size(400, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: MyAnimeListScreen(manga: manga, service: service),
        ),
      );
      await tester.runAsync(
        () async => Future<void>.delayed(const Duration(milliseconds: 60)),
      );
      await tester.pumpAndSettle();
      expect(find.text('Conectado como MangaTester'), findsOneWidget);
      await tester.tap(find.text('Buscar manga'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Berserk'));
      await tester.tap(find.text('Berserk'));
      await tester.pumpAndSettle();
      expect(find.text('Estado de lectura'), findsOneWidget);
      expect(find.text('Capítulos leídos'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
