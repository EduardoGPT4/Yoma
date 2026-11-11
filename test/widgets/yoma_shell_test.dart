import 'dart:io';
import 'package:drift/native.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yomashi/data/app_database.dart';
import 'package:yomashi/data/library_store.dart';
import 'package:yomashi/features/anime/data/anime_controller.dart';
import 'package:yomashi/features/anime/screens/anime_mal_screen.dart';
import '../unit/native_anime_test.dart' show TestAnimeSource;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:yomashi/home/yoma_shell.dart';
import 'package:yomashi/providers/profile_provider.dart';
import 'myanimelist_test.dart' show FakeMal, MemoryCredential;

void main() {
  testWidgets(
    'selector shows both experiences and keeps anime mounted on return',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      // Barra de gestos de Android: las rutas internas deben respetarla.
      tester.view.padding = const FakeViewPadding(bottom: 48);
      addTearDown(tester.view.resetPadding);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = MemoryCredential();
      final client = FakeMal(store);
      final profile = ProfileProvider(malClient: client);
      SharedPreferences.setMockInitialValues({});
      await tester.runAsync(
        () => LibraryStore.initialize(
          database: AppDatabase.forTesting(NativeDatabase.memory()),
        ),
      );
      final anime = AnimeController(source: TestAnimeSource());
      addTearDown(anime.dispose);
      final boundary = GlobalKey();
      await tester.runAsync(() async {
        final font = File(
          '${Platform.environment['WINDIR'] ?? 'C:/Windows'}/Fonts/segoeui.ttf',
        );
        if (await font.exists()) {
          final loader = FontLoader('Roboto')
            ..addFont(
              font.readAsBytes().then((bytes) => ByteData.sublistView(bytes)),
            );
          await loader.load();
        }
        final icons = FontLoader('MaterialIcons')
          ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
        await icons.load();
      });
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: profile,
          child: MaterialApp(
            theme: ThemeData.dark(useMaterial3: true),
            home: RepaintBoundary(
              key: boundary,
              child: YomaShell(animeController: anime),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Manga'), findsOneWidget);
      expect(find.text('Anime'), findsOneWidget);
      expect(find.text('Conectar MyAnimeList'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.runAsync(() async {
        for (final asset in ['3-AniManga.png', '2-Manga.png', '1-Anime.png']) {
          await precacheImage(
            AssetImage('assets/branding/$asset'),
            boundary.currentContext!,
          );
        }
      });
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        final image =
            await (boundary.currentContext!.findRenderObject()
                    as RenderRepaintBoundary)
                .toImage();
        final png = await image.toByteData(format: ui.ImageByteFormat.png);
        // La captura es un resultado de la prueba, no un archivo del repo.
        await Directory('build/test_screenshots').create(recursive: true);
        await File(
          'build/test_screenshots/selector.png',
        ).writeAsBytes(png!.buffer.asUint8List());
        image.dispose();
      });
      await tester.tap(find.text('Anime'));
      await tester.pumpAndSettle();
      expect(find.text('Explorar'), findsOneWidget);
      await tester.tap(find.text('Explorar'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(TextButton, 'Ir a Manga'), findsOneWidget);
      // MyAnimeList se abre desde el perfil, arriba en «Más».
      await tester.tap(find.text('Más'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Tu espacio local'));
      await tester.pumpAndSettle();
      // Dentro de una ruta interna la barra de secciones no tapa el contenido.
      expect(find.widgetWithText(TextButton, 'Ir a Manga'), findsNothing);
      expect(
        MediaQuery.paddingOf(
          tester.element(find.byType(AnimeMalScreen)),
        ).bottom,
        48,
        reason: 'Sin barra de secciones, la ruta conserva el área segura.',
      );
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.widgetWithText(TextButton, 'Ir a Manga'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'Yoma'));
      await tester.pumpAndSettle();
      expect(find.text('Manga'), findsOneWidget);
      store.value = {
        'connected': true,
        'device_token': 'a' * 64,
        'profile': {'id': 7, 'name': 'Mi cuenta MAL'},
      };
      await profile.reloadMyAnimeListIdentity();
      await tester.pumpAndSettle();
      expect(find.text('Mi cuenta MAL'), findsOneWidget);
      expect(find.text('Conectar MyAnimeList'), findsNothing);
      store.value = null;
      await profile.reloadMyAnimeListIdentity();
      await tester.pumpAndSettle();
      expect(find.text('Conectar MyAnimeList'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      profile.dispose();
      client.http.close(force: true);
    },
  );
}
