import 'dart:async';

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

/// Aplica las reglas de `anime_update` del servidor
/// (server/private/yoma-anime-mal.php), incluido el deshacer explícito.
/// Es una simulación: no es MyAnimeList.
class Rules extends MyAnimeListClient {
  Rules(Credentials credentials) : super(credentials: credentials);
  int count = 2, total = 12;
  String status = 'watching';

  /// `false` imita un servidor anterior, sin deshacer.
  bool undo = true;
  bool offline = false;
  final updates = <Map<String, dynamic>>[];
  Map<String, List<Map<String, dynamic>>> lists = {};
  Future<void> Function()? onUpdate;

  Map<String, dynamic> get anime => {
    'id': 1,
    'title': 'Test',
    'episodes_watched': count,
    'num_episodes': total,
    'status': status,
  };

  @override
  Future<Map<String, dynamic>> request(
    Map<String, dynamic> input, {
    bool anonymous = false,
    int? expectedOwner,
  }) async {
    if (offline) throw const MalFailure('Sin conexión de prueba.');
    switch (input['action']) {
      case 'anime_capabilities':
        return {'anime': true, if (undo) 'decrease': true};
      case 'anime_library':
        return {'items': lists[input['status']] ?? const []};
      case 'anime_detail':
        return {'anime': anime};
      case 'anime_update':
        updates.add(Map.of(input));
        await onUpdate?.call();
        final wanted = input['episodes_watched'] as int;
        final expected = input['expected_episodes'] as int;
        if (wanted == count && wanted >= expected) return {'anime': anime};
        if (count != expected) {
          throw const MalFailure('El progreso cambió en MAL.', 409);
        }
        final lower = wanted < count;
        if (lower && !(undo && input['decrease'] == true)) {
          throw const MalFailure('No se reducirá el progreso.', 409);
        }
        if (total > 0 && wanted > total) {
          throw const MalFailure('Supera los episodios del anime.', 409);
        }
        if (lower) {
          if (status == 'completed') status = 'watching';
        } else if (!{'completed', 'on_hold', 'dropped'}.contains(status)) {
          status = total > 0 && wanted == total ? 'completed' : 'watching';
        }
        count = wanted;
        return {'anime': anime};
    }
    return {};
  }
}

/// Catálogo de YomaTV con índice público y búsqueda con ficha completa.
class Catalog extends TestAnimeSource {
  /// Título → datos de la ficha que devuelve la búsqueda.
  final titles = <String, Map<String, dynamic>>{};
  final searches = <String>[];

  /// Si se asigna, las búsquedas esperan a que se complete.
  Completer<void>? gate;

  void add(String title, {int episodes = 0, String year = ''}) {
    final slug = title.toLowerCase().replaceAll(' ', '-');
    titles[title] = {
      'slug': slug,
      'title': title,
      'cover': 'https://cdn.example/$slug.jpg',
      'episodes': episodes,
      'year': year,
    };
  }

  /// Publica el índice con los títulos añadidos (solo slug, título y
  /// categoría, como el real).
  void publishIndex() => index = {
    'version': 'test',
    'items': [
      for (final t in titles.values)
        {'slug': t['slug'], 'title': t['title'], 'category': 'TV Anime'},
    ],
  };

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
    await gate?.future;
    return {
      'items': [
        for (final entry in titles.entries)
          if (entry.key.toLowerCase().contains(search.toLowerCase()))
            entry.value,
      ],
      'page': 1,
      'pages': 1,
    };
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late LibraryStore db;
  late Credentials credentials;
  late Rules server;
  late AnimeMalClient mal;
  late Catalog source;
  late AnimeController app;

  final test1 = AnimeTitle.fromJson({'slug': 'test', 'title': 'Test'});
  AnimeEpisode episode(String number) => AnimeEpisode.fromJson({
    'id': (double.parse(number) * 10).round(),
    'slug': 'test',
    'number': number,
  });

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
      'anime_cache',
    ]) {
      await db.replaceRecords(ns, []);
    }
    credentials = Credentials();
    server = Rules(credentials);
    mal = AnimeMalClient(client: server, database: () async => db);
    source = Catalog();
    app = AnimeController(
      source: source,
      mal: mal,
      store: AnimeLocalStore(database: () async => db),
    );
  });
  tearDown(() {
    app.dispose();
    server.http.close(force: true);
  });

  /// Vinculado cuando MAL iba por el episodio 2.
  Future<void> linked() => mal.link(
    'test',
    MalAnimeEntry.fromJson({
      'id': 1,
      'title': 'Test',
      'episodes_watched': 2,
      'status': 'watching',
    }),
  );

  /// Espera a que termine toda sincronización en curso.
  Future<void> settle() async {
    for (var i = 0; i < 6; i++) {
      await app.syncMal();
      await Future<void>.delayed(const Duration(milliseconds: 5));
      if ((await mal.pending()).isEmpty) return;
    }
  }

  Future<void> mark(String number, bool watched) async {
    await app.mark(test1, episode(number), watched);
    await Future<void>.delayed(const Duration(milliseconds: 2));
  }

  group('deshacer en MAL al desmarcar un episodio ya enviado', () {
    test('MAL baja al episodio visto más alto que queda', () async {
      await linked();
      for (final n in ['3', '4', '5']) {
        await mark(n, true);
      }
      await settle();
      expect(server.count, 5);

      await mark('5', false);
      await settle();
      expect(server.count, 4);
      expect(server.updates.last['decrease'], true);
      expect(server.updates.last['expected_episodes'], 5);
      expect((await mal.linkOf('test'))!['remoteEpisodes'], 4);
      expect(app.malStatus, isNull);
    });

    test('nunca baja de lo que MAL tenía antes de usar Yoma', () async {
      await linked();
      await mark('3', true);
      await settle();
      expect(server.count, 3);
      // Se desmarca todo lo visto en Yoma: MAL vuelve a 2, no a 0.
      await mark('3', false);
      await settle();
      expect(server.count, 2);
      expect(server.updates.every((u) => u['episodes_watched'] != 0), isTrue);
    });

    test('un anime completado por Yoma vuelve a «Viendo»', () async {
      await linked();
      await mark('12', true);
      await settle();
      expect(server.status, 'completed');
      await mark('12', false);
      await settle();
      expect(server.count, 2);
      expect(server.status, 'watching');
      expect((await mal.linkOf('test'))!['status'], 'watching');
    });

    test('si MAL cambió desde entonces no se baja nada', () async {
      await linked();
      await mark('3', true);
      await settle();
      // Se vieron más episodios en otra app.
      server.count = 6;
      await mark('3', false);
      await settle();
      expect(server.count, 6);
      expect(await mal.pending(), isEmpty);
      expect((await mal.linkOf('test'))!['remoteEpisodes'], 6);
      expect(app.malNotice, contains('cambió desde entonces'));
      expect(app.malError, isNull);
      // El nuevo número de MAL pasa a ser el mínimo para futuros deshacer.
      await mal.retractWatched('test', 0);
      expect(await mal.pending(), isEmpty);
    });

    test('con un servidor sin deshacer se avisa y no se envía nada', () async {
      server.undo = false;
      await linked();
      await mark('3', true);
      await settle();
      final writes = server.updates.length;
      await mark('3', false);
      await settle();
      expect(server.count, 3);
      expect(server.updates.length, writes);
      expect(await mal.pending(), isEmpty);
      expect(app.malNotice, contains('conserva el episodio 3'));
      // Marcar otro episodio retira el aviso.
      await mark('4', true);
      expect(app.malNotice, isNull);
    });

    test('volver a marcar el episodio cancela el deshacer', () async {
      await linked();
      await mark('3', true);
      await settle();
      server.offline = true;
      await mark('3', false);
      final row = (await mal.pending()).single;
      expect(row['decrease'], true);
      expect(row['episodes'], 2);
      await mark('3', true);
      expect(await mal.pending(), isEmpty);
      server.offline = false;
      final writes = server.updates.length;
      await settle();
      expect(server.updates.length, writes);
      expect(server.count, 3);
    });

    test(
      'sin conexión el deshacer queda en cola y se envía al volver',
      () async {
        await linked();
        await mark('3', true);
        await mark('4', true);
        await settle();
        server.offline = true;
        await mark('4', false);
        await app.syncMal();
        expect((await mal.pending()).single['episodes'], 3);
        expect(server.count, 4);
        server.offline = false;
        await settle();
        expect(server.count, 3);
      },
    );

    test('una vinculación anterior a esta versión no deshace nada', () async {
      // Sin el dato de lo que MAL tenía por su cuenta no es seguro bajar.
      await db.putRecord('anime_mal_links', 'test', {
        'owner': 7,
        'malId': 1,
        'title': 'Test',
        'remoteEpisodes': 5,
        'status': 'watching',
        'version': 1,
      });
      await mal.retractWatched('test', 3);
      expect(await mal.pending(), isEmpty);
    });

    test('desmarcar mientras se envía deshace lo recién subido', () async {
      await linked();
      await mal.queueWatched('test', 7);
      server.onUpdate = () async {
        server.onUpdate = null;
        await mal.retractWatched('test', 3);
      };
      await mal.flush();
      expect(server.count, 7);
      final row = (await mal.pending()).single;
      expect(row['decrease'], true);
      expect(row['episodes'], 3);
      expect(row['expected_episodes'], 7);
      await mal.flush();
      expect(server.count, 3);
      expect(await mal.pending(), isEmpty);
    });
  });

  group('episodios decimales', () {
    test('cuentan su parte entera', () {
      expect(malEpisodeCount('12'), 12);
      expect(malEpisodeCount('12.5'), 12);
      expect(malEpisodeCount('0.5'), 0);
      expect(malEpisodeCount('0'), 0);
      expect(malEpisodeCount(''), 0);
      expect(malEpisodeCount('especial'), 0);
    });

    test('ver el especial 12.5 sincroniza hasta el episodio 12', () async {
      await linked();
      await mark('12.5', true);
      await settle();
      expect(server.count, 12);
    });

    test('un especial 0.5 no cuenta como episodio', () async {
      await linked();
      await mark('0.5', true);
      await settle();
      expect(server.updates, isEmpty);
    });
  });

  group('vinculación por nombre', () {
    late AnimeMalShelf shelf;
    setUp(
      () => shelf = AnimeMalShelf(
        mal: mal,
        source: source,
        database: () async => db,
      ),
    );

    MalAnimeEntry entry({int total = 0, int year = 0}) =>
        MalAnimeEntry.fromJson({
          'id': 1,
          'title': 'Uno',
          'num_episodes': total,
          'year': year,
        });
    AnimeTitle anime({int episodes = 0, String year = ''}) =>
        AnimeTitle.fromJson({
          'slug': 'uno',
          'title': 'Uno',
          'episodes': episodes,
          'year': year,
        });

    test('se descarta otra obra con el mismo título', () {
      // Una película (1 episodio en MAL) frente a una serie de 24.
      expect(
        AnimeMalShelf.compatible(entry(total: 1), anime(episodes: 24)),
        isFalse,
      );
      // Un remake estrenado años después.
      expect(
        AnimeMalShelf.compatible(entry(year: 2001), anime(year: '2019')),
        isFalse,
      );
      // Margen para un resumen numerado y para el cambio de año.
      expect(
        AnimeMalShelf.compatible(entry(total: 12), anime(episodes: 13)),
        isTrue,
      );
      expect(
        AnimeMalShelf.compatible(entry(year: 2025), anime(year: '2026')),
        isTrue,
      );
      // Sin datos no se descarta nada.
      expect(AnimeMalShelf.compatible(entry(), anime()), isTrue);
    });

    test('la lista no empareja una obra incompatible', () async {
      source.add('Uno', episodes: 24, year: '2019');
      server.lists = {
        'watching': [
          {'id': 1, 'title': 'Uno', 'num_episodes': 1, 'year': 2001},
        ],
      };
      final snapshot = await shelf.refresh(7);
      expect(snapshot.isEmpty, isTrue);
      // Se recuerda como ausente: no se busca en cada carga.
      await shelf.refresh(7);
      expect(source.searches, ['Uno']);
    });

    test('dos entradas de MAL con el mismo nombre no se vinculan', () async {
      source.add('Uno');
      server.lists = {
        'watching': [
          {'id': 1, 'title': 'Uno'},
        ],
        'plan_to_watch': [
          {'id': 5, 'title': 'Uno'},
          {'id': 6, 'title': 'Dos'},
        ],
      };
      source.add('Dos');
      final snapshot = await shelf.refresh(7);
      expect(snapshot.watching, isEmpty);
      expect(snapshot.planned.map((e) => e.entry.id), [6]);
    });

    test('una coincidencia guardada se vuelve a comprobar', () async {
      source.add('Uno', episodes: 24, year: '2019');
      server.lists = {
        'watching': [
          {'id': 1, 'title': 'Uno'},
        ],
      };
      // Sin datos de MAL (servidor anterior) coincide por nombre.
      expect((await shelf.refresh(7)).watching, hasLength(1));
      // Con el año de MAL se ve que es otra obra, sin buscar de nuevo.
      server.lists['watching']![0]['year'] = 2001;
      expect((await shelf.refresh(7)).watching, isEmpty);
      expect(source.searches, hasLength(1));
    });
  });

  group('lista larga con el índice público', () {
    late AnimeMalShelf shelf;
    setUp(() {
      shelf = AnimeMalShelf(mal: mal, source: source, database: () async => db);
      source
        ..add('Uno', episodes: 12)
        ..add('Tres', episodes: 24)
        ..publishIndex();
      server.lists = {
        'watching': [
          {'id': 1, 'title': 'Uno', 'num_episodes': 12},
        ],
        'plan_to_watch': [
          {'id': 2, 'title': 'Dos'},
          {'id': 3, 'title': 'Tres'},
          for (var i = 10; i < 60; i++) {'id': i, 'title': 'Ausente $i'},
        ],
      };
    });

    test('solo se buscan los títulos que existen en YomaTV', () async {
      final snapshot = await shelf.refresh(7);
      // 53 entradas en MAL: una consulta al índice y dos búsquedas.
      expect(source.indexCalls, 1);
      expect(source.searches..sort(), ['Tres', 'Uno']);
      expect(snapshot.watching.single.anime.slug, 'uno');
      expect(snapshot.planned.single.anime.slug, 'tres');
      // La ficha completa llega con la búsqueda.
      expect(snapshot.watching.single.anime.cover, isNotEmpty);
      expect(snapshot.partial, isFalse);

      // La segunda carga no consulta nada a YomaTV.
      await shelf.refresh(7);
      expect(source.indexCalls, 1);
      expect(source.searches, hasLength(2));
    });

    test('las coincidencias se muestran antes de pedir sus fichas', () async {
      source.gate = Completer<void>();
      final interim = <MalShelfSnapshot>[];
      final loading = shelf.refresh(7, onProgress: interim.add);
      for (var i = 0; i < 50 && interim.isEmpty; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      expect(interim.single.watching.single.anime.slug, 'uno');
      expect(interim.single.planned.single.anime.slug, 'tres');
      // Provisional: no se guarda en el teléfono.
      expect(await shelf.cached(7), isNull);
      source.gate!.complete();
      final snapshot = await loading;
      expect(snapshot.watching.single.anime.cover, isNotEmpty);
      expect((await shelf.cached(7))!.planned, hasLength(1));
    });

    test('lo provisional se ve pero no se vincula hasta comprobarlo', () async {
      source.gate = Completer<void>();
      final loading = app.loadMalShelf();
      for (var i = 0; i < 50 && app.malWatching.isEmpty; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      expect(app.malWatching.single.anime.slug, 'uno');
      expect(await app.malMatchFor('uno'), isNull);
      expect(
        await app.autoLinkMal('uno', app.malWatching.single.entry),
        isFalse,
      );
      expect(await mal.linkOf('uno'), isNull);
      source.gate!.complete();
      await loading;
      expect((await app.malMatchFor('uno'))!.id, 1);
      expect(app.malShelfSavedAt, isNotNull);
    });

    test('sin índice se busca título por título como antes', () async {
      source.index = null;
      server.lists['plan_to_watch'] = [
        {'id': 2, 'title': 'Dos'},
        {'id': 3, 'title': 'Tres'},
      ];
      final snapshot = await shelf.refresh(7);
      expect(source.searches..sort(), ['Dos', 'Tres', 'Uno']);
      expect(snapshot.planned.single.anime.slug, 'tres');
    });
  });

  group('aviso al pedir descargas', () {
    String notice(List<String> outcomes, {bool paused = false}) =>
        AnimeController.downloadNotice(outcomes, paused: paused);

    test('dice lo que pasó de verdad', () {
      expect(notice(['added']), 'Episodio añadido a Descargas.');
      expect(notice(['requeued']), 'Descarga puesta de nuevo en la cola.');
      expect(
        notice(['exists']),
        'Este episodio ya está en la cola de descargas.',
      );
      expect(notice(['done']), 'Este episodio ya está descargado.');
      expect(
        notice(['added', 'requeued', 'done', 'exists']),
        '2 episodios añadidos a Descargas. '
        '2 ya estaban en la cola o descargados.',
      );
      expect(
        notice(['done', 'added']),
        '1 episodio añadido a Descargas. 1 ya estaba en la cola o descargados.',
      );
      expect(
        notice(['done', 'done']),
        '2 ya estaban en la cola o descargados.',
      );
    });

    test('avisa de la pausa solo si algo quedó en la cola', () {
      expect(
        notice(['added'], paused: true),
        'Episodio añadido a Descargas. '
        'Las descargas están en pausa; reanúdalas en Descargas.',
      );
      expect(
        notice(['done'], paused: true),
        'Este episodio ya está descargado.',
      );
    });
  });
}
