import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yomashi/data/app_database.dart';
import 'package:yomashi/data/library_store.dart';
import 'package:yomashi/features/anime/data/anime_controller.dart';
import 'package:yomashi/features/anime/data/anime_episode_watch.dart';
import 'package:yomashi/features/anime/data/anime_local_store.dart';
import 'package:yomashi/features/anime/data/anime_mal_client.dart';
import 'package:yomashi/features/anime/data/anime_mal_shelf.dart';
import 'package:yomashi/features/anime/data/next_episode_countdown.dart';
import 'package:yomashi/features/anime/models/anime_models.dart';
import 'package:yomashi/features/anime/screens/anime_detail_screen.dart';
import 'package:yomashi/models/manga.dart';
import 'package:yomashi/providers/chapter_read_provider.dart';
import 'package:yomashi/services/mal_reading_sync.dart';
import 'package:yomashi/services/myanimelist_client.dart';
import 'package:yomashi/services/myanimelist_service.dart';
import 'package:yomashi/services/rotating_backup_service.dart';
import 'package:yomashi/utils/backup_service.dart';

import 'anime_mal_test.dart' show Credentials;
import 'mal_pull_watched_test.dart' show Catalog, WatchingMal;
import 'mal_reading_sync_test.dart' show ReadingMal, chapters;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late LibraryStore db;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    db = await LibraryStore.initialize(
      database: AppDatabase.forTesting(NativeDatabase.memory()),
    );
  });

  Future<void> clear() async {
    for (final ns in [
      AnimeMalShelf.namespace,
      AnimeEpisodeWatch.namespace,
      AnimeMalClient.unlinkedNamespace,
      MalReadingSync.namespace,
      MyAnimeListService.unlinkedNamespace,
      ChapterReadProvider.unmarkedNamespace,
      ChapterReadProvider.fromMalNamespace,
      'anime_mal_links',
      'anime_mal_pending',
      'anime_progress',
      'anime_library',
      'anime_settings',
      'anime_cache',
      'mal_links',
      'mal_pending',
      'mal_sync',
    ]) {
      await db.replaceRecords(ns, []);
    }
    await db.replaceReadChapterKeys({});
  }

  group('YomaTV: quitar el vínculo con MAL', () {
    late Credentials credentials;
    late WatchingMal server;
    late AnimeMalClient mal;
    late Catalog source;
    setUp(() async {
      await clear();
      credentials = Credentials();
      server = WatchingMal(credentials);
      mal = AnimeMalClient(client: server, database: () async => db);
      source = Catalog();
    });
    tearDown(() => server.http.close(force: true));

    AnimeController controller() {
      final app = AnimeController(
        source: source,
        mal: mal,
        store: AnimeLocalStore(database: () async => db),
        connectivity: () => const Stream.empty(),
      );
      addTearDown(app.dispose);
      return app;
    }

    Future<void> settle(AnimeController app) async {
      await app.loadMalShelf(force: true);
      await Future<void>.delayed(const Duration(milliseconds: 80));
    }

    test(
      'no se vuelve a vincular solo, y vincular a mano lo deshace',
      () async {
        final app = controller();
        await settle(app);
        expect((await mal.linkOf('uno'))!['malId'], 1);

        await app.unlinkMal('uno');
        expect(await mal.linkOf('uno'), isNull);
        expect(await mal.pending(), isEmpty);
        // Lo visto en el teléfono se queda.
        expect(app.positions['uno:5']!['watched'], true);
        // La siguiente carga no lo vuelve a vincular.
        await settle(app);
        expect(await mal.linkOf('uno'), isNull);
        expect(
          await app.autoLinkMal(
            'uno',
            MalAnimeEntry.fromJson({'id': 1, 'title': 'Uno'}),
          ),
          isFalse,
        );
        // Vincularlo a mano sí vale, y vuelve a sincronizar solo.
        await mal.link(
          'uno',
          MalAnimeEntry.fromJson({
            'id': 1,
            'title': 'Uno',
            'episodes_watched': 5,
          }),
        );
        await app.unlinkMal('uno');
        await mal.link(
          'uno',
          MalAnimeEntry.fromJson({
            'id': 1,
            'title': 'Uno',
            'episodes_watched': 5,
          }),
        );
        expect((await mal.linkOf('uno'))!['malId'], 1);
      },
    );

    testWidgets('la ficha muestra el vínculo y permite quitarlo', (
      tester,
    ) async {
      final app = controller();
      await tester.runAsync(() async {
        await mal.link(
          'uno',
          MalAnimeEntry.fromJson({
            'id': 1,
            'title': 'Uno MAL',
            'episodes_watched': 3,
          }),
        );
        await app.detail('uno');
        await app.store.markWatchedFromMal(
          AnimeTitle.fromJson({'slug': 'uno', 'title': 'Uno'}),
          [
            AnimeEpisode.fromJson({'id': 101, 'slug': 'uno', 'number': '1'}),
          ],
        );
        await app.initialize();
      });
      await tester.pumpWidget(
        MaterialApp(
          home: AnimeDetailScreen(
            controller: app,
            slug: 'uno',
            play: (_, _) {},
            openSeason: (_) {},
            openWeb: () {},
            openMal: () {},
          ),
        ),
      );
      for (var i = 0; i < 5; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
      }
      expect(find.text('MyAnimeList: Uno MAL'), findsOneWidget);
      // Al abrir, la lista «Viendo» de MAL (va por el 5) pone al día el
      // vínculo.
      expect(find.text('5 episodios vistos en MyAnimeList'), findsOneWidget);
      final list = find.byType(Scrollable).first;
      await tester.scrollUntilVisible(
        find.text('Episodio 1'),
        200,
        scrollable: list,
      );
      // Del 1 al 5 vienen de MAL.
      expect(find.text('Visto en MAL'), findsWidgets);
      expect(find.text('Visto'), findsNothing);

      await tester.scrollUntilVisible(
        find.text('Quitar vínculo'),
        -200,
        scrollable: list,
      );
      await tester.tap(find.text('Quitar vínculo'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Quitar vínculo'));
      for (var i = 0; i < 5; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
      }
      expect(find.text('Sin vincular con MyAnimeList'), findsOneWidget);
      expect(find.text('Vincular'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('YomaShi: quitar el vínculo y «Leído en MAL»', () {
    late ReadingMal server;
    late MalReadingSync sync;
    late ChapterReadProvider reads;
    final local = Manga(
      title: 'Uno',
      path: '/x/Uno',
      chapters: chapters('/x/Uno', [for (var i = 1; i <= 6; i++) '$i']),
    );
    setUp(() async {
      await clear();
      server = ReadingMal(Credentials());
      sync = MalReadingSync(
        MyAnimeListService(server),
        database: () async => db,
      );
      reads = ChapterReadProvider();
      await reads.load();
    });
    tearDown(() {
      reads.dispose();
      server.http.close(force: true);
    });

    test('lo traído de MAL se distingue de lo leído aquí', () async {
      await reads.markRead('/x/Uno/6');
      await sync.run([local], reads);
      expect(reads.isFromMal('/x/Uno/2'), isTrue);
      expect(reads.isFromMal('/x/Uno/6'), isFalse);
      // Se recuerda al reiniciar.
      final reopened = ChapterReadProvider();
      addTearDown(reopened.dispose);
      await reopened.load();
      expect(reopened.isFromMal('/x/Uno/2'), isTrue);
      // Desmarcado ya no cuenta como de MAL.
      await reads.markUnread('/x/Uno/2');
      expect(reads.isFromMal('/x/Uno/2'), isFalse);
    });

    test('un vínculo quitado no se vuelve a crear solo', () async {
      await sync.run([local], reads);
      expect(await sync.service.linkFor(local), isNotNull);
      await sync.service.unlink(local);
      expect(await sync.service.unlinkedByUser(local), isTrue);
      await sync.run([local], reads, force: true);
      expect(await sync.service.linkFor(local), isNull);
      // Vincularlo a mano lo deshace.
      await sync.service.link(
        local,
        MalManga.fromMap(ReadingMal.manga(1, 'Uno', read: 5)),
        automatic: true,
      );
      expect(await sync.service.unlinkedByUser(local), isFalse);
    });

    test('la lista se vuelve a pedir pasado el plazo indicado', () async {
      await sync.reading();
      final calls = server.actions.where((a) => a == 'library').length;
      await sync.reading(age: const Duration(hours: 1));
      expect(server.actions.where((a) => a == 'library').length, calls);
      await sync.reading(age: Duration.zero);
      expect(server.actions.where((a) => a == 'library').length, calls + 1);
    });
  });

  test(
    'YomaTV: la lista de MAL se renueva al volver si tiene más de una hora',
    () async {
      await clear();
      final server = WatchingMal(Credentials());
      addTearDown(() => server.http.close(force: true));
      final mal = AnimeMalClient(client: server, database: () async => db);
      final app = AnimeController(
        source: Catalog(),
        mal: mal,
        store: AnimeLocalStore(database: () async => db),
        connectivity: () => const Stream.empty(),
      );
      addTearDown(app.dispose);
      await app.loadMalShelf();
      final row = await db.getRecord(AnimeMalShelf.namespace, 'shelf:7');
      // Copia de hace dos horas: con la regla de 12 h no se renovaría.
      await db.putRecord(AnimeMalShelf.namespace, 'shelf:7', {
        ...animeMap(row),
        'savedAt': DateTime.now()
            .subtract(const Duration(hours: 2))
            .millisecondsSinceEpoch,
      });
      final fresh = AnimeController(
        source: Catalog(),
        mal: mal,
        store: AnimeLocalStore(database: () async => db),
        connectivity: () => const Stream.empty(),
      );
      addTearDown(fresh.dispose);
      await fresh.loadMalShelf();
      final before = server.libraryCalls;
      await fresh.loadMalShelf(maxAge: AnimeController.resumeMaxAge);
      expect(server.libraryCalls, greaterThan(before));
    },
  );

  group('siguiente episodio', () {
    testWidgets('cuenta atrás de 5 s, cancelable', (tester) async {
      final countdown = NextEpisodeCountdown();
      addTearDown(countdown.dispose);
      var done = 0;
      countdown.start(() => done++);
      expect(countdown.value, 5);
      await tester.pump(const Duration(seconds: 3));
      expect(countdown.value, 2);
      await tester.pump(const Duration(seconds: 2));
      expect(done, 1);
      expect(countdown.running, isFalse);

      countdown.start(() => done++);
      await tester.pump(const Duration(seconds: 2));
      countdown.cancel();
      await tester.pump(const Duration(seconds: 10));
      expect(done, 1);
    });

    test('solo al llegar al final y parado', () {
      bool ended(bool playing, int position) => NextEpisodeCountdown.ended(
        playing: playing,
        positionMs: position,
        durationMs: 10000,
      );
      expect(ended(false, 10000), isTrue);
      expect(ended(false, 9600), isTrue);
      expect(ended(true, 10000), isFalse);
      expect(ended(false, 9000), isFalse);
      expect(
        NextEpisodeCountdown.ended(
          playing: false,
          positionMs: 0,
          durationMs: 0,
        ),
        isFalse,
      );
    });
  });

  group('episodios nuevos', () {
    late WatchingMal server;
    late AnimeMalClient mal;
    late Catalog source;
    late AnimeEpisodeWatch watch;
    setUp(() async {
      await clear();
      server = WatchingMal(Credentials());
      mal = AnimeMalClient(client: server, database: () async => db);
      source = Catalog();
      watch = AnimeEpisodeWatch(
        source: source,
        mal: mal,
        database: () async => db,
      );
      await AnimeMalShelf(
        mal: mal,
        source: source,
        database: () async => db,
      ).refresh(7);
    });
    tearDown(() => server.http.close(force: true));

    test('la primera vez solo anota; después avisa de lo nuevo', () async {
      expect(await watch.check(), isEmpty);
      expect(await watch.check(), isEmpty);
      source.published = 10;
      final news = await watch.check();
      expect(news.single.slug, 'uno');
      expect(news.single.added, 2);
      expect(news.single.latest, '10');
      // La ficha descargada queda guardada para abrirla ya actualizada.
      final cached = await AnimeLocalStore(
        database: () async => db,
      ).cache('detail:uno');
      expect((cached!['data']['episodes'] as List), hasLength(10));
      // No se repite el aviso.
      expect(await watch.check(), isEmpty);
    });

    test('lo visto en la ficha no se avisa como nuevo', () async {
      await watch.check();
      source.published = 9;
      final app = AnimeController(
        source: source,
        mal: mal,
        store: AnimeLocalStore(database: () async => db),
        connectivity: () => const Stream.empty(),
      );
      addTearDown(app.dispose);
      await app.detail('uno', refresh: true);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(await watch.check(), isEmpty);
    });

    test('también los vinculados a mano; nada sin cuenta', () async {
      server.watching
        ..clear()
        ..add({'id': 3, 'title': 'Otro nombre', 'episodes_watched': 1});
      await mal.link(
        'uno',
        MalAnimeEntry.fromJson({'id': 3, 'title': 'Otro nombre'}),
      );
      await AnimeMalShelf(
        mal: mal,
        source: source,
        database: () async => db,
      ).refresh(7);
      await watch.check();
      source.published = 9;
      expect((await watch.check()).single.title, 'Uno');

      (server.credentials as Credentials).value = null;
      source.published = 12;
      expect(await watch.check(), isEmpty);
    });

    test('el aviso resume uno o varios animes', () {
      final one = AnimeEpisodeWatch.notice([
        const NewEpisodes('a', 'Uno', '9', 1),
      ]);
      expect(one.title, 'Episodio nuevo');
      expect(one.text, 'Uno · episodio 9');
      final many = AnimeEpisodeWatch.notice([
        for (final t in ['A', 'B', 'C', 'D', 'E']) NewEpisodes(t, t, '1', 2),
      ]);
      expect(many.title, 'Episodios nuevos');
      expect(many.text, '5 animes que estás viendo: A, B, C y 2 más');
    });
  });

  group('copias de seguridad', () {
    late Directory dir;
    setUp(() async {
      await clear();
      dir = await Directory.systemTemp.createTemp('yoma_backup_test');
      addTearDown(() => dir.delete(recursive: true));
    });

    test('guardan YomaTV y las marcas de MAL, y se restauran', () async {
      await db.putRecord('anime_progress', 'uno:3', {
        'slug': 'uno',
        'episode': {'id': 103, 'slug': 'uno', 'number': '3'},
        'watched': true,
        'positionMs': 0,
        'updatedAt': 10,
      });
      await db.putRecord('anime_library', 'uno', {
        'slug': 'uno',
        'saved': true,
      });
      await db.putRecord('anime_mal_links', 'uno', {
        'owner': 7,
        'malId': 1,
        'remoteEpisodes': 3,
        'version': 1,
      });
      await db.putRecord('anime_mal_pending', 'uno', {'episodes': 4});
      await db.putRecord(ChapterReadProvider.unmarkedNamespace, '/x/3', {
        'at': 1,
      });
      final file = await BackupService.exportToFile(directory: dir);
      await BackupService.preview(file);

      await clear();
      await BackupService.importFromFile(
        file,
        recoveryDirectory: await dir.createTemp('recovery'),
      );
      expect((await db.getRecord('anime_progress', 'uno:3'))['watched'], true);
      expect((await db.getRecord('anime_library', 'uno'))['saved'], true);
      expect((await db.getRecord('anime_mal_links', 'uno'))['malId'], 1);
      // Los envíos pendientes no viajan: podrían repetirse en otro teléfono.
      expect(await db.getRecord('anime_mal_pending', 'uno'), isNull);
      expect(
        await db.getRecord(ChapterReadProvider.unmarkedNamespace, '/x/3'),
        isNotNull,
      );
    });

    test('al combinar gana el progreso más reciente', () async {
      await db.putRecord('anime_progress', 'uno:1', {
        'slug': 'uno',
        'positionMs': 100,
        'updatedAt': 10,
      });
      final file = await BackupService.exportToFile(directory: dir);
      await db.putRecord('anime_progress', 'uno:1', {
        'slug': 'uno',
        'positionMs': 900,
        'updatedAt': 20,
      });
      await BackupService.importFromFile(
        file,
        merge: true,
        recoveryDirectory: await dir.createTemp('recovery'),
      );
      expect(
        (await db.getRecord('anime_progress', 'uno:1'))['positionMs'],
        900,
      );
    });

    test('una copia con datos de YomaTV mal formados se rechaza', () async {
      final file = File(p.join(dir.path, 'yomashi_backup_1.json'));
      await file.writeAsString(
        '{"version":5,"progress":{},"favorites":[],"readChapters":[],'
        '"categories":[],"readingStats":{},"yomaTv":{"progress":[{"x":1}]}}',
      );
      await expectLater(BackupService.preview(file), throwsStateError);
    });

    test('dos copias a la vez solo crean una', () async {
      // Simula la app y el mantenimiento a la vez: no comparten memoria,
      // solo el archivo de bloqueo.
      final lock = File(p.join(dir.path, '.yomashi_backup.lock'));
      await lock.create();
      expect(await RotatingBackupService.run(directory: dir), isNull);
      expect(await RotatingBackupService.files(directory: dir), isEmpty);
      // Un bloqueo que quedó de una copia interrumpida caduca.
      final made = await RotatingBackupService.run(
        directory: dir,
        now: DateTime.now().add(RotatingBackupService.staleLock * 2),
      );
      expect(made, isNotNull);
      expect(await lock.exists(), isFalse);
      // Con una copia reciente no se hace otra.
      expect(await RotatingBackupService.run(directory: dir), isNull);
      expect(await RotatingBackupService.files(directory: dir), hasLength(1));
    });
  });
}
