import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_player/video_player.dart';
import 'package:yomashi/features/anime/widgets/anime_video_stage.dart';

/// Video simulado: solo su estado; no reproduce nada.
VideoPlayerController video({
  Duration position = const Duration(seconds: 30),
  bool playing = false,
}) =>
    VideoPlayerController.networkUrl(Uri.parse('https://example.invalid/v'))
      ..value = VideoPlayerValue(
        duration: const Duration(minutes: 23, seconds: 39),
        position: position,
        isInitialized: true,
        isPlaying: playing,
        size: const Size(1920, 1080),
      );

void main() {
  late List<Duration> seeks;
  late int fullscreen;

  Future<void> pump(
    WidgetTester tester,
    VideoPlayerController controller, {
    bool full = false,
    Size size = const Size(400, 225),
  }) async {
    seeks = [];
    fullscreen = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox.fromSize(
              size: size,
              child: AnimeVideoStage(
                video: controller,
                full: full,
                seek: (position) async => seeks.add(position),
                onToggleFullscreen: () => fullscreen++,
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Toca el video lejos del botón central.
  Future<void> tapVideo(WidgetTester tester) => tester.tapAt(
    tester.getRect(find.byKey(const ValueKey('anime-video-surface'))).topLeft +
        const Offset(30, 30),
  );

  double opacity(WidgetTester tester) =>
      tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity)).opacity;

  testWidgets('en pausa los controles se quedan visibles', (tester) async {
    final controller = video();
    addTearDown(controller.dispose);
    await pump(tester, controller);
    await tester.pump(const Duration(seconds: 10));
    expect(opacity(tester), 1);
    expect(find.byTooltip('Reproducir'), findsOneWidget);
    expect(find.text('0:30 / 23:39'), findsOneWidget);
  });

  testWidgets('reproduciendo se ocultan solos y vuelven al tocar', (
    tester,
  ) async {
    final controller = video();
    addTearDown(controller.dispose);
    await pump(tester, controller);
    controller.value = controller.value.copyWith(isPlaying: true);
    await tester.pump(const Duration(seconds: 2));
    expect(opacity(tester), 1);
    await tester.pump(const Duration(seconds: 2));
    expect(opacity(tester), 0);
    // Ocultos no se pueden pulsar por accidente.
    expect(
      tester
          .widgetList<IgnorePointer>(
            find.ancestor(
              of: find.byType(AnimatedOpacity),
              matching: find.byType(IgnorePointer),
            ),
          )
          .first
          .ignoring,
      isTrue,
    );

    // Tocar el video los muestra, y vuelven a ocultarse.
    await tapVideo(tester);
    await tester.pump();
    expect(opacity(tester), 1);
    await tester.pump(const Duration(seconds: 4));
    expect(opacity(tester), 0);

    // Tocar otra vez con los controles visibles los oculta.
    await tapVideo(tester);
    await tester.pump();
    await tapVideo(tester);
    await tester.pump();
    expect(opacity(tester), 0);

    // Al pausar vuelven y se quedan.
    controller.value = controller.value.copyWith(isPlaying: false);
    await tester.pump(const Duration(seconds: 10));
    expect(opacity(tester), 1);
  });

  testWidgets('«Saltar opening» avanza 85 s', (tester) async {
    final controller = video();
    addTearDown(controller.dispose);
    await pump(tester, controller);
    await tester.tap(find.text('Saltar opening'));
    expect(seeks, [const Duration(seconds: 115)]);
  });

  testWidgets('desaparece a los 3 minutos de episodio', (tester) async {
    final controller = video(position: const Duration(minutes: 2, seconds: 59));
    addTearDown(controller.dispose);
    await pump(tester, controller);
    expect(find.text('Saltar opening'), findsOneWidget);
    controller.value = controller.value.copyWith(
      position: const Duration(minutes: 3),
    );
    await tester.pump();
    expect(find.text('Saltar opening'), findsNothing);
  });

  test('no se ofrece si no queda video después', () {
    VideoPlayerValue at(Duration position, Duration duration) =>
        VideoPlayerValue(
          duration: duration,
          position: position,
          isInitialized: true,
        );
    expect(
      AnimeVideoStage.canSkipOpening(
        at(const Duration(seconds: 10), const Duration(seconds: 80)),
      ),
      isFalse,
    );
    expect(
      AnimeVideoStage.canSkipOpening(
        at(Duration.zero, const Duration(minutes: 24)),
      ),
      isTrue,
    );
    expect(
      AnimeVideoStage.canSkipOpening(
        const VideoPlayerValue(duration: Duration(minutes: 24)),
      ),
      isFalse,
    );
  });

  testWidgets('retroceder y avanzar no salen del video', (tester) async {
    final controller = video(position: const Duration(seconds: 4));
    addTearDown(controller.dispose);
    await pump(tester, controller);
    await tester.tap(find.byTooltip('Retroceder 10 segundos'));
    await tester.tap(find.byTooltip('Avanzar 10 segundos'));
    expect(seeks, [Duration.zero, const Duration(seconds: 14)]);
  });

  testWidgets('pantalla completa: ocupa todo y el botón la cierra', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(2400, 1080);
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(left: 120);
    addTearDown(tester.view.reset);
    final controller = video();
    addTearDown(controller.dispose);
    await pump(tester, controller, full: true, size: const Size(2400, 1080));
    // El fondo negro cubre todo, incluido el hueco de la cámara.
    expect(
      tester.getRect(find.byType(AnimeVideoStage)),
      const Rect.fromLTWH(0, 0, 2400, 1080),
    );
    // Los controles sí respetan ese hueco.
    expect(
      tester.getTopLeft(find.byTooltip('Retroceder 10 segundos')).dx,
      greaterThanOrEqualTo(120),
    );
    await tester.tap(find.byTooltip('Salir de pantalla completa'));
    expect(fullscreen, 1);
  });

  testWidgets('sin video muestra la carga', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AnimeVideoStage(
          video: null,
          loading: true,
          onToggleFullscreen: () {},
        ),
      ),
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byType(AnimatedOpacity), findsNothing);
  });
}
