import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yomashi/data/app_database.dart';
import 'package:yomashi/data/library_store.dart';
import 'package:yomashi/features/anime/data/anime_controller.dart';
import 'package:yomashi/features/anime/data/anime_local_store.dart';
import 'package:yomashi/features/anime/data/anime_mal_client.dart';
import 'package:yomashi/features/anime/data/anime_mal_shelf.dart';
import 'package:yomashi/features/anime/models/anime_models.dart';
import 'package:yomashi/services/myanimelist_client.dart';

import '../unit/native_anime_test.dart' show TestAnimeSource;
import 'anime_mal_test.dart' show Credentials;
import 'download_engine_regression_test.dart' show RealHttp;
import 'myanimelist_session_test.dart' show SessionCredential, session;

/// Servidor de MAL simulado: responde lo que cada prueba le indique y
/// anota las acciones recibidas. No es MyAnimeList ni el servidor de Yoma.
class Scripted extends MyAnimeListClient {
  Scripted(Credentials credentials) : super(credentials: credentials);
  final actions = <String>[];
  Map<String, dynamic> Function(Map<String, dynamic> input)? reply;
  @override
  Future<Map<String, dynamic>> request(
    Map<String, dynamic> input, {
    bool anonymous = false,
    int? expectedOwner,
  }) async {
    actions.add('${input['action']}');
    if (input['action'] == 'anime_capabilities') return {'anime': true};
    return reply!(input);
  }
}

/// Catálogo de YomaTV que falla con los títulos indicados.
class FlakySource extends TestAnimeSource {
  final failing = <String>{};
  final searches = <String>[];
  int detailCalls = 0;
  int episodes = 2;
  @override
  Future<Map<String, dynamic>> catalog({
    int page = 1,
    String search = '',
    String category = '',
    String season = '',
    String year = '',
    String genre = '',
    String order = 'recent',
    bool seasonal = false,
  }) async {
    searches.add(search);
    if (failing.contains(search)) {
      throw const SocketException('YomaTV de prueba sin respuesta');
    }
    return {
      'items': [
        if (search.isNotEmpty)
          {'slug': search.toLowerCase().replaceAll(' ', '-'), 'title': search},
      ],
      'page': 1,
      'pages': 1,
    };
  }

  @override
  Future<Map<String, dynamic>> detail(String slug) async {
    detailCalls++;
    return {
      'anime': {'slug': slug, 'title': slug},
      'episodes': [
        for (var i = 1; i <= episodes; i++)
          {'id': i, 'slug': slug, 'number': '$i'},
      ],
    };
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late LibraryStore db;
  late Credentials credentials;
  late Scripted server;
  late AnimeMalClient mal;

  Map<String, dynamic> confirm(Map<String, dynamic> input) => {
    'anime': {
      'id': input['id'],
      'episodes_watched': input['episodes_watched'],
      'status': 'watching',
    },
  };

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    db = await LibraryStore.initialize(
      database: AppDatabase.forTesting(NativeDatabase.memory()),
    );
  });

  setUp(() async {
    for (final ns in [
      AnimeMalShelf.namespace,
      'anime_mal_links',
      'anime_mal_pending',
      'anime_progress',
      'anime_library',
      'anime_cache',
    ]) {
      await db.replaceRecords(ns, []);
    }
    credentials = Credentials();
    server = Scripted(credentials)..reply = confirm;
    mal = AnimeMalClient(client: server, database: () async => db);
  });
  tearDown(() => server.http.close(force: true));

  Future<void> linked({int known = 2}) => mal.link(
    'test',
    MalAnimeEntry.fromJson({
      'id': 1,
      'title': 'Test',
      'episodes_watched': known,
      'status': 'watching',
    }),
  );

  group('confirmación de escritura', () {
    test('una respuesta sin confirmación no cuenta como guardada', () async {
      await linked();
      await mal.queueWatched('test', 3);
      server.reply = (_) => {};
      await expectLater(
        mal.flush(),
        throwsA(isA<MalFailure>().having((e) => e.status, 'status', 502)),
      );
      // El pendiente sigue ahí y el número conocido de MAL no avanza.
      expect((await mal.pending()).single['episodes'], 3);
      expect((await mal.linkOf('test'))!['remoteEpisodes'], 2);

      // Cuando el servidor confirma, se da por enviado.
      server.reply = confirm;
      await mal.flush();
      expect(await mal.pending(), isEmpty);
      expect((await mal.linkOf('test'))!['remoteEpisodes'], 3);
    });

    test('se rechaza la confirmación de otro anime o de otro número', () async {
      await linked();
      await mal.queueWatched('test', 3);
      server.reply = (input) => {
        'anime': {'id': 99, 'episodes_watched': input['episodes_watched']},
      };
      await expectLater(mal.flush(), throwsA(isA<MalFailure>()));
      server.reply = (input) => {
        'anime': {'id': input['id'], 'episodes_watched': 2},
      };
      await expectLater(mal.flush(), throwsA(isA<MalFailure>()));
      expect((await mal.pending()).single['episodes'], 3);
    });

    test('el estado confirmado por MAL se guarda y se notifica', () async {
      await linked();
      await mal.queueWatched('test', 12);
      server.reply = (input) => {
        'anime': {
          'id': input['id'],
          'episodes_watched': input['episodes_watched'],
          'status': 'completed',
        },
      };
      final seen = <String>[];
      mal.onRemoteProgress = (id, watched, status) =>
          seen.add('$id:$watched:$status');
      await mal.flush();
      expect(seen, ['1:12:completed']);
      expect((await mal.linkOf('test'))!['status'], 'completed');
    });
  });

  group('errores y red', () {
    test('sin episodios pendientes no se hace ninguna petición', () async {
      await linked();
      server.reply = (_) => throw const MalFailure('Sin conexión de prueba.');
      await mal.flush();
      expect(server.actions, isEmpty);

      final app = AnimeController(
        source: TestAnimeSource(),
        mal: mal,
        store: AnimeLocalStore(database: () async => db),
      );
      addTearDown(app.dispose);
      await app.syncMal();
      // Estar sin conexión sin nada que enviar no es un error.
      expect(app.malError, isNull);
    });

    test('la extensión de anime se comprueba una vez por sesión', () async {
      await linked();
      await mal.queueWatched('test', 3);
      await mal.flush();
      await mal.queueWatched('test', 4);
      await mal.flush();
      expect(
        server.actions.where((a) => a == 'anime_capabilities'),
        hasLength(1),
      );
      // Otra sesión vuelve a comprobarla.
      credentials.value = {
        'connected': true,
        'device_token': 'otra',
        'profile': {'id': 7},
      };
      expect(await mal.available(), isTrue);
      expect(
        server.actions.where((a) => a == 'anime_capabilities'),
        hasLength(2),
      );
    });

    test(
      'límite de peticiones y errores del servidor conservan la cola',
      () async {
        await linked();
        await mal.queueWatched('test', 3);
        for (final status in [429, 500, 502, 503]) {
          server.reply = (_) => throw MalFailure('Fallo $status', status);
          await expectLater(
            mal.flush(),
            throwsA(
              isA<MalFailure>().having((e) => e.status, 'status', status),
            ),
          );
          final row = (await mal.pending()).single;
          expect(row['episodes'], 3);
          // No es un conflicto: se reintenta en la siguiente sincronización.
          expect(row['conflict'], isNull);
        }
        server.reply = confirm;
        await mal.flush();
        expect(await mal.pending(), isEmpty);
      },
    );

    test(
      'el fallo de sincronización queda visible en el controlador',
      () async {
        final app = AnimeController(
          source: TestAnimeSource(),
          mal: mal,
          store: AnimeLocalStore(database: () async => db),
        );
        addTearDown(app.dispose);
        await linked();
        await mal.queueWatched('test', 3);
        server.reply = (_) => throw const MalFailure('Sin conexión de prueba.');
        await app.syncMal();
        expect(app.malError, contains('Sin conexión de prueba.'));
        server.reply = confirm;
        await app.syncMal();
        expect(app.malError, isNull);
      },
    );
  });

  group('lectura paginada', () {
    test(
      'sigue la continuación del servidor, no el tamaño de la página',
      () async {
        // El servidor puede devolver menos de 50 filas y aun así haber más.
        server.reply = (input) {
          final offset = input['offset'] as int;
          return {
            'items': [
              {'id': offset + 1, 'title': 'Anime ${offset + 1}'},
            ],
            'next_offset': offset < 100 ? offset + 50 : null,
          };
        };
        final first = await mal.libraryPage();
        expect(first.items.single.id, 1);
        expect(first.nextOffset, 50);

        final shelf = AnimeMalShelf(
          mal: mal,
          source: FlakySource(),
          database: () async => db,
        );
        final snapshot = await shelf.refresh(7);
        expect(snapshot.watching.map((e) => e.entry.id), [1, 51, 101]);
      },
    );

    test('una lista inválida no se toma por una lista vacía', () async {
      server.reply = (_) => {};
      await expectLater(mal.libraryPage(), throwsA(isA<MalFailure>()));
      // Una continuación que no avanza repetiría la misma página sin fin.
      server.reply = (_) => {'items': [], 'next_offset': 0};
      await expectLater(mal.libraryPage(), throwsA(isA<MalFailure>()));
      server.reply = (_) => {'items': [], 'next_offset': '50'};
      await expectLater(mal.libraryPage(), throwsA(isA<MalFailure>()));
    });
  });

  group('desmarcar un episodio', () {
    test('baja el pendiente al episodio visto más alto que queda', () async {
      await linked();
      await mal.queueWatched('test', 5);
      await mal.retractWatched('test', 4);
      expect((await mal.pending()).single['episodes'], 4);
      // Nunca por debajo de lo que MAL ya tiene: el pendiente desaparece.
      await mal.retractWatched('test', 2);
      expect(await mal.pending(), isEmpty);
      expect(server.actions, isEmpty);
    });

    test(
      'desde el controlador: marcar por error y desmarcar no sube nada',
      () async {
        final app = AnimeController(
          source: TestAnimeSource(),
          mal: mal,
          store: AnimeLocalStore(database: () async => db),
        );
        addTearDown(app.dispose);
        final anime = AnimeTitle.fromJson({'slug': 'test', 'title': 'Test'});
        AnimeEpisode episode(int n) =>
            AnimeEpisode.fromJson({'id': n, 'slug': 'test', 'number': '$n'});
        await linked();
        // Sin conexión, como al ver un episodio descargado.
        server.reply = (_) => throw const MalFailure('Sin conexión de prueba.');
        await app.mark(anime, episode(3), true);
        await app.mark(anime, episode(7), true);
        await app.syncMal();
        expect((await mal.pending()).single['episodes'], 7);

        await app.mark(anime, episode(7), false);
        expect((await mal.pending()).single['episodes'], 3);

        final sent = <int>[];
        server.reply = (input) {
          sent.add(input['episodes_watched'] as int);
          return confirm(input);
        };
        await app.syncMal();
        expect(sent, [3]);
      },
    );
  });

  group('copia de la lista de MyAnimeList', () {
    late FlakySource source;
    late AnimeMalShelf shelf;
    setUp(() {
      source = FlakySource();
      shelf = AnimeMalShelf(mal: mal, source: source, database: () async => db);
      server.reply = (input) {
        if (input['action'] == 'anime_update') return confirm(input);
        return {
          'items': input['status'] == 'watching'
              ? [
                  {
                    'id': 1,
                    'title': 'Uno',
                    'episodes_watched': 2,
                    'num_episodes': 12,
                    'status': 'watching',
                  },
                ]
              : [
                  {'id': 2, 'title': 'Dos', 'status': 'plan_to_watch'},
                  {'id': 3, 'title': 'Tres', 'status': 'plan_to_watch'},
                ],
        };
      };
    });

    test(
      'un fallo de YomaTV con un título no descarta toda la lista',
      () async {
        source.failing.add('Dos');
        final first = await shelf.refresh(7);
        expect(first.partial, isTrue);
        expect(first.watching.single.anime.slug, 'uno');
        expect(first.planned.map((e) => e.anime.slug), ['tres']);
        expect((await shelf.cached(7))!.partial, isTrue);

        // Al responder YomaTV solo se busca lo que faltó.
        source.failing.clear();
        source.searches.clear();
        final second = await shelf.refresh(7);
        expect(source.searches, ['Dos']);
        expect(second.partial, isFalse);
        expect(second.planned.map((e) => e.anime.slug), ['dos', 'tres']);
      },
    );

    test('con YomaTV caído se deja de buscar tras unos fallos', () async {
      server.reply = (input) => {
        'items': input['status'] == 'watching'
            ? [
                for (var i = 1; i <= 20; i++) {'id': i, 'title': 'Anime $i'},
              ]
            : [],
      };
      source.failing.addAll([for (var i = 1; i <= 20; i++) 'Anime $i']);
      final snapshot = await shelf.refresh(7);
      expect(snapshot.partial, isTrue);
      expect(snapshot.isEmpty, isTrue);
      // Tres búsquedas en paralelo: como mucho unas pocas fallan antes de parar.
      expect(source.searches.length, lessThanOrEqualTo(6));
    });

    test('una copia incompleta se reintenta pronto', () async {
      source.failing.add('Dos');
      final app = AnimeController(
        source: source,
        mal: mal,
        store: AnimeLocalStore(database: () async => db),
      );
      addTearDown(app.dispose);
      await app.loadMalShelf();
      expect(app.malShelfPartial, isTrue);
      expect(app.malShelfError, contains('se volverá a intentar'));
      expect(app.malWatching.single.anime.slug, 'uno');
      // Recién guardada no se repite la carga…
      final before = server.actions.length;
      await app.loadMalShelf();
      expect(server.actions.length, before);
      // …pero pasado el plazo corto sí, sin esperar las 12 horas.
      final row = await db.getRecord(AnimeMalShelf.namespace, 'shelf:7');
      await db.putRecord(AnimeMalShelf.namespace, 'shelf:7', {
        ...animeMap(row),
        'savedAt': DateTime.now()
            .subtract(AnimeMalShelf.retryPartial)
            .millisecondsSinceEpoch,
      });
      source.failing.clear();
      final fresh = AnimeController(
        source: source,
        mal: mal,
        store: AnimeLocalStore(database: () async => db),
      );
      addTearDown(fresh.dispose);
      await fresh.loadMalShelf();
      expect(fresh.malShelfPartial, isFalse);
      expect(fresh.malShelfError, isNull);
      expect(fresh.malPlanned.map((e) => e.anime.slug), ['dos', 'tres']);
    });

    test('un avance confirmado se refleja sin volver a descargar', () async {
      await shelf.refresh(7);
      // «Por ver» pasa a «Viendo» con su número de episodios.
      final started = await shelf.applyProgress(7, 2, 1, 'watching');
      expect(started!.watching.map((e) => e.entry.id), [2, 1]);
      expect(started.watching.first.entry.watched, 1);
      expect(started.planned.map((e) => e.entry.id), [3]);
      // «Viendo» actualiza su número en el mismo sitio.
      final advanced = await shelf.applyProgress(7, 1, 5, 'watching');
      expect(advanced!.watching.last.entry.watched, 5);
      // Completado sale de las dos listas.
      final done = await shelf.applyProgress(7, 1, 12, 'completed');
      expect(done!.watching.map((e) => e.entry.id), [2]);
      // Sin cambios o un anime que no está en la copia: nada que guardar.
      expect(await shelf.applyProgress(7, 2, 1, 'watching'), isNull);
      expect(await shelf.applyProgress(7, 99, 1, 'watching'), isNull);
      expect(await shelf.applyProgress(8, 2, 3, 'watching'), isNull);
      final stored = await shelf.cached(7);
      expect(stored!.watching.single.entry.watched, 1);
      expect(stored.planned.single.entry.id, 3);
    });

    test(
      'ver un episodio actualiza la sección de MyAnimeList al momento',
      () async {
        final app = AnimeController(
          source: source,
          mal: mal,
          store: AnimeLocalStore(database: () async => db),
        );
        addTearDown(app.dispose);
        await app.loadMalShelf();
        expect(app.malPlanned.map((e) => e.anime.slug), ['dos', 'tres']);
        final calls = server.actions.where((a) => a == 'anime_library').length;

        await app.progress(
          AnimeTitle.fromJson({'slug': 'dos', 'title': 'Dos'}),
          AnimeEpisode.fromJson({'id': 1, 'slug': 'dos', 'number': '1'}),
          1000,
          1000,
          watched: true,
        );
        await app.syncMal();
        for (var i = 0; i < 50 && app.malPlanned.length == 2; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
        expect(app.malPlanned.map((e) => e.anime.slug), ['tres']);
        expect(app.malWatching.map((e) => e.anime.slug), ['dos', 'uno']);
        expect(app.malWatching.first.entry.watched, 1);
        // Sin descargar otra vez las listas de MAL.
        expect(server.actions.where((a) => a == 'anime_library').length, calls);
      },
    );
  });

  group('sesión real por HTTP contra un servidor local simulado', () {
    late HttpServer http;
    late HttpClient raw;
    late SessionCredential store;
    late MyAnimeListClient client;
    late AnimeMalClient anime;
    final received = <Map<String, dynamic>>[];
    final headers = <String?>[];
    late int status;
    late Object body;

    setUp(() async {
      received.clear();
      headers.clear();
      status = 200;
      body = {'anime': true};
      http = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      http.listen((request) async {
        final input =
            jsonDecode(await utf8.decoder.bind(request).join())
                as Map<String, dynamic>;
        received.add(input);
        headers.add(request.headers.value('x-yomashi-token'));
        request.response.statusCode = input['action'] == 'anime_capabilities'
            ? 200
            : status;
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          input['action'] == 'anime_capabilities'
              ? '{"anime":true}'
              : body is String
              ? body as String
              : jsonEncode(body),
        );
        await request.response.close();
      });
      raw = HttpOverrides.runWithHttpOverrides(() => HttpClient(), RealHttp());
      store = SessionCredential(session('a', 7));
      client = MyAnimeListClient(
        api: Uri.parse('http://127.0.0.1:${http.port}/api'),
        http: raw,
        credentials: store,
      );
      anime = AnimeMalClient(client: client, database: () async => db);
      await anime.link(
        'test',
        MalAnimeEntry.fromJson({
          'id': 1,
          'title': 'Test',
          'episodes_watched': 2,
        }),
      );
      await anime.queueWatched('test', 3);
    });
    tearDown(() async {
      raw.close(force: true);
      await http.close(force: true);
    });

    test(
      'la escritura lleva la credencial, la cuenta y el número esperado',
      () async {
        body = {
          'anime': {'id': 1, 'episodes_watched': 3, 'status': 'watching'},
        };
        await anime.flush();
        final update = received.last;
        expect(update['action'], 'anime_update');
        expect(update['id'], 1);
        expect(update['episodes_watched'], 3);
        expect(update['expected_episodes'], 2);
        // El servidor rechaza escrituras sin la cuenta confirmada.
        expect(update['owner_id'], 7);
        expect(headers.last, 'a' * 64);
        expect(await anime.pending(), isEmpty);
      },
    );

    test(
      'una sesión caducada desconecta y conserva el avance pendiente',
      () async {
        var events = 0;
        client.sessionChanges.addListener(() => events++);
        status = 401;
        body = {'error': 'Vuelve a conectar MyAnimeList.'};
        await expectLater(
          anime.flush(),
          throwsA(isA<MalFailure>().having((e) => e.status, 'status', 401)),
        );
        expect(store.value, isNull);
        expect(events, 1);
        expect(await db.readRecords('anime_mal_pending'), hasLength(1));
        // Sin sesión no se intenta nada más.
        final before = received.length;
        await anime.flush();
        expect(received.length, before);

        // Al volver a conectar la misma cuenta, el pendiente se envía.
        store.value = session('b', 7);
        status = 200;
        body = {
          'anime': {'id': 1, 'episodes_watched': 3},
        };
        await anime.flush();
        expect(headers.last, 'b' * 64);
        expect(await db.readRecords('anime_mal_pending'), isEmpty);
      },
    );

    test('el avance de una cuenta no se envía con otra', () async {
      store.value = session('b', 8);
      await anime.flush();
      expect(received.where((r) => r['action'] == 'anime_update'), isEmpty);
      expect(await db.readRecords('anime_mal_pending'), hasLength(1));
    });

    test('una respuesta que no es JSON es un error, no un éxito', () async {
      body = '<html>502 Bad Gateway</html>';
      await expectLater(anime.flush(), throwsA(isA<MalFailure>()));
      expect(await db.readRecords('anime_mal_pending'), hasLength(1));
    });

    test('con el servidor caído el avance queda en cola', () async {
      await http.close(force: true);
      await expectLater(anime.flush(), throwsA(isA<MalFailure>()));
      expect(await db.readRecords('anime_mal_pending'), hasLength(1));
    });
  });
}
