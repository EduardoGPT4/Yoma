import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yomashi/data/app_database.dart';
import 'package:yomashi/data/library_store.dart';
import 'package:yomashi/features/anime/data/anime_controller.dart';
import 'package:yomashi/features/anime/data/anime_local_store.dart';
import 'package:yomashi/features/anime/data/anime_mal_client.dart';
import 'package:yomashi/features/anime/data/local_anime_downloads.dart';
import 'package:yomashi/features/anime/models/anime_models.dart';
import 'package:yomashi/features/anime/screens/anime_detail_screen.dart';
import 'package:yomashi/features/anime/screens/anime_mal_screen.dart';
import 'package:yomashi/providers/profile_provider.dart';
import 'package:yomashi/services/myanimelist_client.dart';

import '../services/anime_mal_test.dart' show Credentials;
import 'native_anime_test.dart' show TestAnimeSource;

/// Fuente con una ficha cuyo número de episodios puede cambiar, como un
/// anime en emisión.
class AiringSource extends TestAnimeSource {
  int episodes = 4, detailCalls = 0;
  bool offline = false;
  @override
  Future<Map<String, dynamic>> detail(String slug) async {
    detailCalls++;
    if (offline) throw const FormatException('Sin red de prueba');
    return {
      'anime': {'slug': slug, 'title': 'Anime $slug'},
      'episodes': [
        for (var i = 1; i <= episodes; i++)
          {'id': i, 'slug': slug, 'number': '$i'},
      ],
    };
  }
}

/// MAL simulado que no acepta ninguna sincronización.
class FailingMal extends MyAnimeListClient {
  FailingMal(Credentials credentials) : super(credentials: credentials);
  @override
  Future<Map<String, dynamic>> request(
    Map<String, dynamic> input, {
    bool anonymous = false,
    int? expectedOwner,
  }) async {
    if (input['action'] == 'anime_capabilities') return {'anime': true};
    if (input['action'] == 'anime_library') return {'items': []};
    throw const MalFailure('Sin conexión de prueba.');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late LibraryStore db;
  late AiringSource source;
  late AnimeController app;

  AnimeTitle title(String slug) =>
      AnimeTitle.fromJson({'slug': slug, 'title': 'Anime $slug'});
  AnimeEpisode episode(String slug, int number) =>
      AnimeEpisode.fromJson({'id': number, 'slug': slug, 'number': '$number'});

  /// Guarda progreso con una marca de tiempo distinta en cada llamada.
  Future<void> watch(
    String slug,
    int number, {
    required int position,
    bool? watched,
  }) async {
    await app.progress(
      title(slug),
      episode(slug, number),
      position,
      1000,
      watched: watched,
    );
    await Future<void>.delayed(const Duration(milliseconds: 3));
  }

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    db = await LibraryStore.initialize(
      database: AppDatabase.forTesting(NativeDatabase.memory()),
    );
  });

  setUp(() async {
    for (final ns in [
      'anime_cache',
      'anime_progress',
      'anime_library',
      'anime_mal_links',
      'anime_mal_pending',
    ]) {
      await db.replaceRecords(ns, []);
    }
    source = AiringSource();
    app = AnimeController(
      source: source,
      store: AnimeLocalStore(database: () async => db),
      mal: AnimeMalClient(
        client: FailingMal(Credentials()..value = null),
        database: () async => db,
      ),
    );
  });
  tearDown(() {
    app.mal.client.http.close(force: true);
    app.dispose();
  });

  group('continuar viendo', () {
    test(
      'un episodio anterior a medias no reaparece tras terminar otro',
      () async {
        await watch('a', 1, position: 500);
        expect(app.continuing.single['episode']['number'], '1');
        // Se salta al episodio 2 y se termina.
        await watch('a', 2, position: 1000, watched: true);
        expect(app.continuing, isEmpty);
        // El 3 queda a medias: es por donde se continúa.
        await watch('a', 3, position: 300);
        expect(app.continuing.single['episode']['number'], '3');
      },
    );

    test('un anime por fila, el más reciente primero', () async {
      await watch('a', 1, position: 400);
      await watch('b', 5, position: 200);
      await watch('a', 2, position: 100);
      expect(
        app.continuing.map(
          (e) => '${e['slug']}:${animeMap(e['episode'])['number']}',
        ),
        ['a:2', 'b:5'],
      );
    });

    test('el progreso se recupera al reabrir la aplicación', () async {
      await watch('a', 2, position: 640);
      await watch('a', 1, position: 1000, watched: true);
      final reopened = AnimeController(
        source: source,
        store: AnimeLocalStore(database: () async => db),
        mal: app.mal,
        connectivity: () => const Stream.empty(),
      );
      await reopened.initialize();
      expect(reopened.positions['a:2']!['positionMs'], 640);
      expect(reopened.positions['a:2']!['watched'], false);
      expect(reopened.positions['a:1']!['watched'], true);
      reopened.dispose();
    });
  });

  group('«Reproducir» en la ficha', () {
    late AnimeDetail detail;
    setUp(() async => detail = await app.detail('a'));

    test('sin historial empieza por el primer episodio', () {
      expect(app.resumeEpisode(detail)!.number, '1');
    });

    test('reanuda el episodio que quedó a medias', () async {
      await watch('a', 2, position: 500);
      expect(app.resumeEpisode(detail)!.number, '2');
    });

    test('tras terminar un episodio sigue con el siguiente sin ver', () async {
      await watch('a', 1, position: 1000, watched: true);
      expect(app.resumeEpisode(detail)!.number, '2');
      // El 3 ya estaba visto: después del 2 toca el 4.
      await watch('a', 3, position: 1000, watched: true);
      await watch('a', 2, position: 1000, watched: true);
      expect(app.resumeEpisode(detail)!.number, '4');
    });

    test('con todo visto se queda en el último abierto', () async {
      for (var i = 1; i <= 4; i++) {
        await watch('a', i, position: 1000, watched: true);
      }
      expect(app.resumeEpisode(detail)!.number, '4');
    });

    test('el historial de otro anime no cuenta', () async {
      await watch('b', 3, position: 1000, watched: true);
      expect(app.resumeEpisode(detail)!.number, '1');
    });

    testWidgets('el botón abre el episodio siguiente al último visto', (
      tester,
    ) async {
      app.positions['a:1'] = {
        'slug': 'a',
        'episode': episode('a', 1).toJson(),
        'positionMs': 1000,
        'durationMs': 1000,
        'watched': true,
        'updatedAt': 10,
      };
      AnimeEpisode? played;
      await tester.pumpWidget(
        MaterialApp(
          home: AnimeDetailScreen(
            controller: app,
            slug: 'a',
            play: (_, episode) => played = episode,
            openSeason: (_) {},
            openWeb: () {},
          ),
        ),
      );
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Reproducir'));
      expect(played!.number, '2');
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('ficha de un anime en emisión', () {
    test('una ficha reciente no se vuelve a pedir', () async {
      await app.detail('a');
      await app.detail('a');
      expect(source.detailCalls, 1);
    });

    test('pasado el plazo se actualiza en segundo plano', () async {
      final airing = AnimeController(
        source: source,
        store: AnimeLocalStore(database: () async => db),
        mal: app.mal,
        detailMaxAge: Duration.zero,
      );
      addTearDown(airing.dispose);
      expect((await airing.detail('a')).episodes, hasLength(4));
      // Sale un episodio nuevo con la aplicación abierta.
      source.episodes = 5;
      var notified = 0;
      airing.addListener(() => notified++);
      // La ficha conocida se devuelve al instante…
      expect((await airing.detail('a')).episodes, hasLength(4));
      for (
        var i = 0;
        i < 50 && airing.details['a']!.episodes.length == 4;
        i++
      ) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      // …y se sustituye por la nueva, avisando a la pantalla.
      expect(airing.details['a']!.episodes, hasLength(5));
      expect(notified, greaterThan(0));
    });

    test('sin red la ficha conocida sigue disponible', () async {
      final airing = AnimeController(
        source: source,
        store: AnimeLocalStore(database: () async => db),
        mal: app.mal,
        detailMaxAge: Duration.zero,
      );
      addTearDown(airing.dispose);
      await airing.detail('a');
      source.offline = true;
      expect((await airing.detail('a')).episodes, hasLength(4));
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(airing.details['a']!.episodes, hasLength(4));

      // Y tras reiniciar, sale de la copia guardada en el teléfono.
      final reopened = AnimeController(
        source: source,
        store: AnimeLocalStore(database: () async => db),
        mal: app.mal,
      );
      addTearDown(reopened.dispose);
      expect((await reopened.detail('a')).episodes, hasLength(4));
    });

    test('sin red ni copia guardada el error llega a la pantalla', () async {
      source.offline = true;
      await expectLater(app.detail('nuevo'), throwsA(isA<FormatException>()));
    });
  });

  group('mensajes de error', () {
    test('los fallos de Android muestran su mensaje, no el tipo', () {
      expect(
        animeErrorText(
          PlatformException(
            code: 'anime_local',
            message: 'Pausa las descargas antes de eliminar un archivo.',
          ),
        ),
        'Pausa las descargas antes de eliminar un archivo.',
      );
      expect(
        animeErrorText(PlatformException(code: 'anime_local')),
        'No se pudo completar la operación en el dispositivo.',
      );
      expect(
        animeErrorText(const MalFailure('Sin conexión.')),
        'Sin conexión.',
      );
    });

    testWidgets('un avance que no llegó a MAL se ve en su pantalla', (
      tester,
    ) async {
      final credentials = Credentials();
      final client = FailingMal(credentials);
      addTearDown(() => client.http.close(force: true));
      final mal = AnimeMalClient(client: client, database: () async => db);
      final controller = AnimeController(
        source: source,
        store: AnimeLocalStore(database: () async => db),
        mal: mal,
      );
      addTearDown(controller.dispose);
      final profile = ProfileProvider(malClient: client);
      addTearDown(profile.dispose);
      await tester.runAsync(() async {
        await mal.link(
          'a',
          MalAnimeEntry.fromJson({
            'id': 1,
            'title': 'Anime a',
            'episodes_watched': 0,
          }),
        );
        await controller.mark(title('a'), episode('a', 1), true);
        await controller.syncMal();
      });
      expect(controller.malError, contains('Sin conexión de prueba.'));
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: profile,
          child: MaterialApp(
            home: AnimeMalScreen(controller: controller, home: () {}),
          ),
        ),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
      expect(
        find.textContaining('No se pudo enviar a MyAnimeList'),
        findsOneWidget,
      );
      expect(find.text('Sincronizar ahora'), findsOneWidget);
      expect(
        find.textContaining('Por enviar: hasta el episodio 1'),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox());
    });
  });
}
