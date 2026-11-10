// Animación de entrada del selector: guarda fotogramas en
// build/test_screenshots/intro/ para revisarla.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yomashi/data/app_database.dart';
import 'package:yomashi/data/library_store.dart';
import 'package:yomashi/design/yoma_theme.dart';
import 'package:yomashi/design/yoma_tokens.dart';
import 'package:yomashi/features/anime/data/anime_controller.dart';
import 'package:yomashi/home/selector_intro.dart';
import 'package:yomashi/home/yoma_shell.dart';
import 'package:yomashi/providers/profile_provider.dart';
import 'package:yomashi/widgets/app_metrics.dart';

import '../unit/native_anime_test.dart' show TestAnimeSource;
import 'myanimelist_test.dart' show FakeMal, MemoryCredential;

void main() {
  late ProfileProvider profile;
  late FakeMal client;
  late AnimeController anime;
  final boundary = GlobalKey();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await LibraryStore.initialize(
      database: AppDatabase.forTesting(NativeDatabase.memory()),
    );
  });

  Future<void> open(WidgetTester tester, {bool reduceMotion = false}) async {
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    client = FakeMal(MemoryCredential());
    profile = ProfileProvider(malClient: client);
    anime = AnimeController(source: TestAnimeSource());
    addTearDown(anime.dispose);
    addTearDown(() {
      profile.dispose();
      client.http.close(force: true);
    });
    await tester.runAsync(() async {
      final font = File(
        '${Platform.environment['WINDIR'] ?? 'C:/Windows'}/Fonts/segoeui.ttf',
      );
      if (await font.exists()) {
        await (FontLoader(
          'Roboto',
        )..addFont(font.readAsBytes().then(ByteData.sublistView))).load();
      }
      final mono = File(
        '${Platform.environment['WINDIR'] ?? 'C:/Windows'}/Fonts/consola.ttf',
      );
      if (await mono.exists()) {
        await (FontLoader(
          'monospace',
        )..addFont(mono.readAsBytes().then(ByteData.sublistView))).load();
      }
      await (FontLoader(
        'MaterialIcons',
      )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    });
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: profile,
        child: MaterialApp(
          theme: buildYomaTheme(YomaColors.accent, AppMetrics.compact),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(disableAnimations: reduceMotion),
            child: child!,
          ),
          home: RepaintBoundary(
            key: boundary,
            child: YomaShell(animeController: anime),
          ),
        ),
      ),
    );
    await tester.runAsync(() async {
      for (final asset in ['3-AniManga.png', '2-Manga.png', '1-Anime.png']) {
        await precacheImage(
          AssetImage('assets/branding/$asset'),
          boundary.currentContext!,
        );
      }
    });
  }

  Future<void> capture(WidgetTester tester, String name) async {
    await tester.runAsync(() async {
      final image =
          await (boundary.currentContext!.findRenderObject()
                  as RenderRepaintBoundary)
              .toImage();
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      final folder = Directory('build/test_screenshots/intro');
      await folder.create(recursive: true);
      await File(
        '${folder.path}/$name.png',
      ).writeAsBytes(png!.buffer.asUint8List());
      image.dispose();
    });
  }


  testWidgets('the selector is written, drawn and resolved once', (
    tester,
  ) async {
    await open(tester);
    expect(find.byType(IntroScreenOverlay), findsOneWidget);
    var elapsed = 0;
    for (final ms in [
      150,
      450,
      750,
      950,
      1250,
      1450,
      1650,
      1900,
      2350,
      2500,
      2800,
      3050,
    ]) {
      await tester.pump(Duration(milliseconds: ms - elapsed));
      elapsed = ms;
      await capture(tester, '${ms.toString().padLeft(4, '0')}ms');
      expect(tester.takeException(), isNull, reason: '$ms ms');
    }
    expect(find.textContaining('YomaShi'), findsWidgets);
    await tester.pump(const Duration(milliseconds: 400));
    await capture(tester, 'final');
    // Al terminar no queda ninguna capa: es el selector original.
    expect(find.byType(IntroScreenOverlay), findsNothing);
    expect(find.byType(CardBuildOverlay), findsNothing);
    expect(find.byType(TypedReveal), findsNothing);
    expect(find.text('Manga'), findsOneWidget);
    expect(find.text('Conectar MyAnimeList'), findsOneWidget);

    // Volver al selector desde un módulo no repite la animación.
    await tester.tap(find.text('Anime'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Yoma'));
    await tester.pump();
    expect(find.byType(IntroScreenOverlay), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('buttons work while the intro is running', (tester) async {
    await open(tester);
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.byType(IntroScreenOverlay), findsOneWidget);
    await tester.tap(find.text('Anime'), warnIfMissed: false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Ir a Manga'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('reduced motion shows the final selector immediately', (
    tester,
  ) async {
    await open(tester, reduceMotion: true);
    await tester.pump();
    expect(find.byType(IntroScreenOverlay), findsNothing);
    expect(find.byType(CardBuildOverlay), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  test('timeline ends with every annotation hidden', () {
    const end = SelectorIntro(1);
    expect(end.done, isTrue);
    final card = end.card(SelectorIntro.animeStart);
    expect(card.fill, 1);
    expect(card.building, 0);
    expect(card.annotation, 0);
    expect(card.markers, 0);
    expect(const SelectorIntro(0).at(.5, 1), 0);
  });
}
