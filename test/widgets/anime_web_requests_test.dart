import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yomashi/data/app_database.dart';
import 'package:yomashi/data/library_store.dart';
import 'package:yomashi/features/anime/data/anime_controller.dart';
import 'package:yomashi/features/anime/data/anime_local_store.dart';
import 'package:yomashi/features/anime/data/anime_mal_client.dart';
import 'package:yomashi/features/anime/data/anime_web_request.dart';
import 'package:yomashi/features/anime/data/local_anime_downloads.dart';
import 'package:yomashi/features/anime/models/anime_models.dart';
import 'package:yomashi/features/anime/native_anime_screen.dart';
import 'package:yomashi/features/anime/screens/anime_detail_screen.dart';
import 'package:yomashi/features/anime/screens/anime_player_screen.dart';
import 'package:yomashi/providers/profile_provider.dart';

import '../unit/native_anime_test.dart' show TestAnimeSource;

/// Ficha con dos episodios de prueba.
class _Source extends TestAnimeSource {
  @override
  Future<Map<String, dynamic>> detail(String slug) async => {
    'anime': {'slug': slug, 'title': 'Frieren'},
    'episodes': [
      for (final (id, number) in [(135, '1'), (136, '2')])
        {'id': id, 'slug': slug, 'number': number, 'url': ''},
    ],
  };
}

/// Cola local simulada: recuerda lo pedido.
class _Transfers extends LocalAnimeDownloads {
  final queued = <String>[];
  @override
  Future<String> enqueue(
    AnimeTitle anime,
    AnimeEpisode episode,
    String language,
  ) async {
    queued.add('${anime.slug}:${episode.id}:$language');
    return 'added';
  }
}

/// Cliente de MAL de YomaTV que solo cuenta los envíos.
class _CountingMal extends AnimeMalClient {
  int flushes = 0;
  @override
  Future<void> flush() async => flushes++;
}

void main() {
  testWidgets(
    'lo que pide la web integrada lo hacen las pantallas de Flutter',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      late AnimeController app;
      final transfers = _Transfers();
      await tester.runAsync(() async {
        final db = await LibraryStore.initialize(
          database: AppDatabase.forTesting(NativeDatabase.memory()),
        );
        app = AnimeController(
          source: _Source(),
          store: AnimeLocalStore(database: () async => db),
          transfers: transfers,
          connectivity: () => const Stream.empty(),
        );
      });
      final key = GlobalKey<NativeAnimeScreenState>();
      await tester.pumpWidget(
        ChangeNotifierProvider(
          create: (_) => ProfileProvider(),
          child: MaterialApp(
            home: NativeAnimeScreen(
              key: key,
              active: true,
              home: () {},
              controller: app,
            ),
          ),
        ),
      );
      Future<void> settle() async {
        for (var i = 0; i < 8; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 30)),
          );
          await tester.pump(const Duration(milliseconds: 50));
        }
      }

      await settle();

      // «↓ Descargar» en la web: el episodio entra en la cola local.
      await tester.runAsync(
        () => key.currentState!.openFromWeb(
          AnimeWebRequest.parse({
            'action': 'download',
            'slug': 'frieren-2',
            'episode_id': 136,
            'language': 'LAT',
          })!,
        ),
      );
      await settle();
      expect(transfers.queued, ['frieren-2:136:LAT']);
      expect(find.text('Episodio añadido a Descargas.'), findsOneWidget);

      // «Capítulos para llevar»: la ficha de Flutter, con su selección.
      await tester.runAsync(
        () => key.currentState!.openFromWeb(
          AnimeWebRequest.parse({'action': 'episodes', 'slug': 'frieren-2'})!,
        ),
      );
      await settle();
      expect(find.byType(AnimeDetailScreen), findsOneWidget);

      // Reproducir: el reproductor de Flutter con ese episodio.
      await tester.runAsync(
        () => key.currentState!.openFromWeb(
          AnimeWebRequest.parse({
            'action': 'play',
            'slug': 'frieren-2',
            'episode_id': 135,
          })!,
        ),
      );
      await settle();
      expect(find.byType(AnimePlayerScreen), findsOneWidget);
      expect(
        tester
            .widget<AnimePlayerScreen>(find.byType(AnimePlayerScreen))
            .episode
            .id,
        135,
      );

      // Un episodio que ya no existe se explica, no rompe nada.
      tester
          .state<ScaffoldMessengerState>(find.byType(ScaffoldMessenger).first)
          .clearSnackBars();
      await tester.runAsync(
        () => key.currentState!.openFromWeb(
          AnimeWebRequest.parse({
            'action': 'download',
            'slug': 'frieren-2',
            'episode_id': 999,
          })!,
        ),
      );
      await settle();
      expect(transfers.queued, hasLength(1));
      expect(
        find.textContaining('ya no aparece en el listado'),
        findsOneWidget,
      );

      // El icono de descargas de la web lleva a la pestaña de Flutter.
      key.currentState!.showDownloads();
      await settle();
      // Espera a que terminen las animaciones de salida.
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(AnimePlayerScreen), findsNothing);
      expect(find.byType(AnimeDetailScreen), findsNothing);
      expect(app.tab, 3);

      await tester.pumpWidget(const SizedBox());
      await settle();
      app.dispose();
    },
  );

  testWidgets(
    'al volver a la app YomaTV envía a MAL aunque no esté a la vista',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final mal = _CountingMal();
      late AnimeController app;
      await tester.runAsync(() async {
        final db = await LibraryStore.initialize(
          database: AppDatabase.forTesting(NativeDatabase.memory()),
        );
        app = AnimeController(
          source: _Source(),
          mal: mal,
          store: AnimeLocalStore(database: () async => db),
          transfers: _Transfers(),
          connectivity: () => const Stream.empty(),
        );
      });
      await tester.pumpWidget(
        ChangeNotifierProvider(
          create: (_) => ProfileProvider(),
          child: MaterialApp(
            home: NativeAnimeScreen(
              active: false,
              home: () {},
              controller: app,
            ),
          ),
        ),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump();
      final before = mal.flushes;
      // La secuencia de Android al salir de la app y volver.
      for (final state in [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
        AppLifecycleState.hidden,
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(state);
      }
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
      expect(mal.flushes, before + 1);
      await tester.pumpWidget(const SizedBox());
      app.dispose();
    },
  );
}
