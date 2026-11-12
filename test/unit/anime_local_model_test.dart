import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player/video_player.dart';
import 'package:yomashi/data/app_database.dart';
import 'package:yomashi/data/library_store.dart';
import 'package:yomashi/features/anime/data/anime_local_store.dart';
import 'package:yomashi/features/anime/data/anime_web_request.dart';
import 'package:yomashi/features/anime/widgets/anime_video_stage.dart';
import 'package:yomashi/services/picture_in_picture.dart';

/// YomaTV usa solo el modelo local: la web integrada pide pantallas de
/// Flutter y la cola local; nada abre ya las actividades de la cuenta web.
void main() {
  group('peticiones de la web integrada', () {
    test('acepta reproducir, descargar y elegir episodios', () {
      final play = AnimeWebRequest.parse(
        '{"action":"play","slug":"frieren-2","episode_id":135}',
      )!;
      expect(play.action, 'play');
      expect(play.slug, 'frieren-2');
      expect(play.episodeId, 135);

      final download = AnimeWebRequest.parse({
        'action': 'download',
        'slug': 'frieren-2',
        'episode_id': 7,
        'language': 'lat',
      })!;
      expect(download.language, 'LAT');

      final episodes = AnimeWebRequest.parse(
        '{"action":"episodes","slug":"frieren-2","episode_id":9}',
      )!;
      expect(episodes.episodeId, isNull);
    });

    test('rechaza lo que no es una petición válida', () {
      for (final raw in [
        null,
        'no es json',
        '[]',
        '{"action":"delete","slug":"x","episode_id":1}',
        '{"action":"play","slug":"../x","episode_id":1}',
        '{"action":"play","slug":"x"}',
        '{"action":"play","slug":"x","episode_id":0}',
        '{"action":"play","slug":"x","episode_id":"1"}',
        '{"action":"download","slug":"x","episode_id":1,"language":"ES"}',
      ]) {
        expect(AnimeWebRequest.parse(raw), isNull, reason: '$raw');
      }
    });
  });

  test('la web integrada ya no abre las pantallas de la cuenta web', () {
    final script = File(
      'android/app/src/main/assets/native-integration.js',
    ).readAsStringSync();
    expect(script, isNot(contains('offline_plan')));
    expect(script, isNot(contains('play_online')));
    expect(script, isNot(contains("type:'plan'")));
    // «Ver capítulo» de la ficha web abre el reproductor de la app.
    expect(script, contains("closest('#dialog [data-play]')"));
    for (final action in ['play', 'download', 'episodes']) {
      expect(script, contains("type:'open',action:'$action'"));
    }
    final bridge = File(
      'android/app/src/main/kotlin/app/yomashi/reader/NativeAnimeBridge.kt',
    ).readAsStringSync();
    expect(bridge, isNot(contains('MainActivity::class')));
    expect(bridge, isNot(contains('PlayerActivity::class')));
    expect(bridge, isNot(contains('Queue.start(')));
    expect(bridge, contains('"open" ->'));
  });

  group('imagen en imagen', () {
    tearDown(() => PictureInPicture.active.value = false);

    test('el video no se pausa al entrar ni mientras se ve pequeño', () {
      expect(PictureInPicture.shouldPause(AppLifecycleState.resumed), isFalse);
      expect(PictureInPicture.shouldPause(AppLifecycleState.inactive), isTrue);
      PictureInPicture.active.value = true;
      expect(PictureInPicture.shouldPause(AppLifecycleState.inactive), isFalse);
      // Cerrar la ventana pequeña deja la app sin verse: se pausa.
      expect(PictureInPicture.shouldPause(AppLifecycleState.hidden), isTrue);
      expect(PictureInPicture.shouldPause(AppLifecycleState.paused), isTrue);
    });

    testWidgets('botón en los controles y solo el video en la ventana', (
      tester,
    ) async {
      final controller =
          VideoPlayerController.networkUrl(Uri.parse('https://example.invalid'))
            ..value = const VideoPlayerValue(
              duration: Duration(minutes: 24),
              position: Duration(minutes: 5),
              isInitialized: true,
              size: Size(1920, 1080),
            );
      var opened = 0;
      Widget stage({VoidCallback? pip}) => MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            height: 225,
            child: AnimeVideoStage(
              video: controller,
              onToggleFullscreen: () {},
              onPictureInPicture: pip,
            ),
          ),
        ),
      );
      await tester.pumpWidget(stage());
      expect(find.byTooltip('Imagen en imagen'), findsNothing);

      await tester.pumpWidget(stage(pip: () => opened++));
      await tester.tap(find.byTooltip('Imagen en imagen'));
      expect(opened, 1);

      PictureInPicture.active.value = true;
      await tester.pump();
      expect(find.byTooltip('Imagen en imagen'), findsNothing);
      expect(find.byTooltip('Pantalla completa'), findsNothing);
      expect(find.byType(VideoPlayer), findsOneWidget);

      PictureInPicture.active.value = false;
      await tester.pump();
      expect(find.byTooltip('Pantalla completa'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });
  });

  test('el progreso de la cuenta web no pisa el del teléfono', () async {
    SharedPreferences.setMockInitialValues({});
    final db = await LibraryStore.initialize(
      database: AppDatabase.forTesting(NativeDatabase.memory()),
    );
    final store = AnimeLocalStore(database: () async => db);
    await db.putRecord('anime_progress', 'frieren-2:2', {
      'positionMs': 99,
      'watched': false,
    });
    final written = await store.importWebProgress([
      {
        'slug': 'frieren-2',
        'title': 'Frieren',
        'episode_id': 135,
        'number': '1',
        'position': 1400000,
        'duration': 1420000,
        'watched': true,
      },
      {
        'slug': 'frieren-2',
        'title': 'Frieren',
        'episode_id': 136,
        'number': '2',
        'position': 50000,
        'duration': 1420000,
        'watched': true,
      },
      {'slug': '', 'number': '3'},
    ]);
    expect(written, hasLength(1));
    final first = await db.getRecord('anime_progress', 'frieren-2:1') as Map;
    expect(first['watched'], isTrue);
    expect(first['positionMs'], 1400000);
    expect(first['durationMs'], 1420000);
    expect((first['anime'] as Map)['title'], 'Frieren');
    expect((first['episode'] as Map)['id'], 135);
    final kept = await db.getRecord('anime_progress', 'frieren-2:2') as Map;
    expect(kept['positionMs'], 99);
    expect(kept['watched'], isFalse);
  });
}
