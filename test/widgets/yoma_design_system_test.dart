// Comprueba la unificación visual de YomaShi y YomaTV con el tema real y
// guarda capturas en build/test_screenshots/design/ para revisarlas.
import 'dart:convert';
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
import 'package:yomashi/design/yoma_components.dart';
import 'package:yomashi/design/yoma_theme.dart';
import 'package:yomashi/design/yoma_tokens.dart';
import 'package:yomashi/features/anime/data/anime_controller.dart';
import 'package:yomashi/features/anime/models/anime_models.dart';
import 'package:yomashi/home/yoma_shell.dart';
import 'package:yomashi/models/catalog_page.dart';
import 'package:yomashi/models/online_manga.dart';
import 'package:yomashi/providers/categories_provider.dart';
import 'package:yomashi/providers/chapter_read_provider.dart';
import 'package:yomashi/providers/density_provider.dart';
import 'package:yomashi/providers/download_queue_provider.dart';
import 'package:yomashi/providers/favorites_provider.dart';
import 'package:yomashi/providers/library_provider.dart';
import 'package:yomashi/providers/profile_provider.dart';
import 'package:yomashi/providers/reader_settings_provider.dart';
import 'package:yomashi/providers/source_provider.dart';
import 'package:yomashi/providers/theme_accent_provider.dart';
import 'package:yomashi/services/manga_source_adapter.dart';
import 'package:yomashi/services/online_catalog_service.dart';
import 'package:yomashi/widgets/app_metrics.dart';

import '../unit/native_anime_test.dart' show TestAnimeSource;
import 'package:yomashi/widgets/mal_login_prompt.dart';

/// Catálogo auditado de YomaTV (docs/yoma/source-audit) sin red.
class _AuditedAnimeSource extends TestAnimeSource {
  final Map<String, dynamic> page;
  _AuditedAnimeSource(this.page);
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
  }) async => this.page;
}

Map<String, dynamic> _auditedCatalog() {
  final body = animeMap(
    jsonDecode(File('docs/yoma/source-audit/catalog.json').readAsStringSync()),
  );
  final data = animeMap(animeMap(body['data'])['catalog']);
  return data.isNotEmpty ? data : animeMap(body['catalog']);
}

const _mangaTitles = [
  'Sousou no Frieren',
  'Kaguya-sama wa Kokurasetai',
  'Chainsaw Man',
  'Dandadan',
  'Kagurabachi',
  'Ao no Hako',
  'One Punch-Man',
  'Spy x Family',
  'Blue Lock',
];

Future<void> _loadFonts() async {
  final font = File(
    '${Platform.environment['WINDIR'] ?? 'C:/Windows'}/Fonts/segoeui.ttf',
  );
  if (await font.exists()) {
    final loader = FontLoader('Roboto')
      ..addFont(font.readAsBytes().then((b) => ByteData.sublistView(b)));
    await loader.load();
  }
  final icons = FontLoader('MaterialIcons')
    ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
  await icons.load();
}

void main() {
  late Map<String, MangaSourceAdapter> originalAdapters;

  setUp(() {
    // El motor de descargas escucha la conectividad; aquí no hay plugin nativo.
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/connectivity'),
      (_) async => ['wifi'],
    );
    messenger.setMockStreamHandler(
      const EventChannel('dev.fluttercommunity.plus/connectivity_status'),
      MockStreamHandler.inline(onListen: (_, sink) => sink.success(['wifi'])),
    );
    SharedPreferences.setMockInitialValues({
      // La propuesta de entrar con MAL tiene su propia prueba.
      MalLoginPrompt.askedKey: true,
      'welcome_notice_seen_v1': true,
      'onboarding_completed_v1': true,
      'active_manga_source_v1': 'mangadex',
    });
    originalAdapters = Map.of(OnlineCatalogService.adapters);
    for (final entry in originalAdapters.entries) {
      final items = [
        for (final title in _mangaTitles)
          OnlineMangaSummary(
            title: title,
            url: 'https://example.invalid/${entry.key}/$title',
            sourceId: entry.key,
          ),
      ];
      OnlineCatalogService.adapters[entry.key] = CallbackSourceAdapter(
        id: entry.key,
        catalogRequest: (_, _, _) async =>
            CatalogPage(items: items, totalPages: 1),
        feedRequest: () async => items.take(5).toList(),
        detailRequest: entry.value.detail,
        pagesRequest: entry.value.pages,
      );
    }
  });

  tearDown(() {
    OnlineCatalogService.adapters
      ..clear()
      ..addAll(originalAdapters);
  });

  test('legacy accents migrate once to the Yoma coral', () async {
    SharedPreferences.setMockInitialValues({'theme_accent_v1': 0xFFDC2626});
    final first = ThemeAccentProvider();
    await first.load();
    expect(first.primary, YomaColors.accent);
    await first.setAccent(const Color(0xFFDC2626));
    // Una elección hecha después de la migración se respeta.
    final second = ThemeAccentProvider();
    await second.load();
    expect(second.primary.toARGB32(), 0xFFDC2626);

    SharedPreferences.setMockInitialValues({'theme_accent_v1': 0xFF2563EB});
    final blue = ThemeAccentProvider();
    await blue.load();
    expect(blue.primary.toARGB32(), 0xFF2563EB);
  });

  test('Yoma palette keeps text and accent readable', () {
    final theme = buildYomaTheme(YomaColors.accent, AppMetrics.compact);
    for (final background in [
      YomaColors.background,
      YomaColors.surface,
      YomaColors.surfaceHigh,
    ]) {
      expect(contrastRatio(YomaColors.textPrimary, background), greaterThan(7));
      expect(
        contrastRatio(YomaColors.textSecondary, background),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        contrastRatio(theme.colorScheme.primary, background),
        greaterThanOrEqualTo(4.5),
      );
    }
    final filled = theme.filledButtonTheme.style!;
    expect(
      contrastRatio(
        filled.foregroundColor!.resolve({})!,
        filled.backgroundColor!.resolve({})!,
      ),
      greaterThanOrEqualTo(4.5),
    );
    expect(theme.scaffoldBackgroundColor, YomaColors.background);
    expect(theme.textTheme.bodySmall!.color, YomaColors.textSecondary);
  });

  for (final (name, size, scale) in [
    ('phone', const Size(412, 915), 1.0),
    ('small-large-text', const Size(360, 740), 1.3),
  ]) {
    testWidgets('Manga and Anime share one visual language ($name)', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.runAsync(() async {
        await LibraryStore.initialize(
          database: AppDatabase.forTesting(NativeDatabase.memory()),
        );
        await _loadFonts();
      });
      final anime = AnimeController(
        source: _AuditedAnimeSource(_auditedCatalog()),
      );
      addTearDown(anime.dispose);
      final boundary = GlobalKey();

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider(
              create: (_) => ThemeAccentProvider()..load(),
            ),
            ChangeNotifierProvider(create: (_) => DensityProvider()..load()),
            ChangeNotifierProvider(create: (_) => SourceProvider()..load()),
            ChangeNotifierProvider(create: (_) => ProfileProvider()..load()),
            ChangeNotifierProvider(create: (_) => LibraryProvider()..load()),
            ChangeNotifierProvider(
              create: (_) => DownloadQueueProvider()..load(),
            ),
            ChangeNotifierProvider(
              create: (_) => ReaderSettingsProvider()..load(),
            ),
            ChangeNotifierProvider(create: (_) => FavoritesProvider()..load()),
            ChangeNotifierProvider(create: (_) => CategoriesProvider()..load()),
            ChangeNotifierProvider(
              create: (_) => ChapterReadProvider()..load(),
            ),
          ],
          child: Consumer<ThemeAccentProvider>(
            builder: (context, accent, _) => MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: buildYomaTheme(accent.primary, AppMetrics.compact),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(scale)),
                child: child!,
              ),
              home: RepaintBoundary(
                key: boundary,
                child: YomaShell(animeController: anime),
              ),
            ),
          ),
        ),
      );

      Future<void> settle() async {
        for (var i = 0; i < 6; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 40)),
          );
          await tester.pump(const Duration(milliseconds: 100));
        }
      }

      Future<void> capture(String file) async {
        await settle();
        expect(tester.takeException(), isNull, reason: file);
        await tester.runAsync(() async {
          final image =
              await (boundary.currentContext!.findRenderObject()
                      as RenderRepaintBoundary)
                  .toImage();
          final png = await image.toByteData(format: ui.ImageByteFormat.png);
          final folder = Directory('build/test_screenshots/design');
          await folder.create(recursive: true);
          await File(
            '${folder.path}/$name-$file.png',
          ).writeAsBytes(png!.buffer.asUint8List());
          image.dispose();
        });
      }

      await tester.runAsync(() async {
        for (final asset in ['3-AniManga.png', '2-Manga.png', '1-Anime.png']) {
          await precacheImage(
            AssetImage('assets/branding/$asset'),
            boundary.currentContext!,
          );
        }
        await precacheImage(
          const AssetImage('assets/brand/yomashi_wordmark.png'),
          boundary.currentContext!,
        );
      });
      // La entrada del selector dura unos 3 s; la captura es del resultado.
      await tester.pump(const Duration(seconds: 4));
      await capture('01-selector');

      await tester.tap(find.text('Manga'));
      await capture('02-manga-home');
      final mangaBar = tester.getSize(find.byType(NavigationBar));
      final mangaPrimary = Theme.of(
        tester.element(find.byType(NavigationBar)),
      ).colorScheme.primary;
      final mangaSwitch = tester.getSize(
        find.widgetWithText(TextButton, 'Ir a Anime'),
      );

      await tester.tap(find.widgetWithText(TextButton, 'Ir a Anime'));
      await capture('03-anime-home');
      final animeBar = tester.getSize(find.byType(NavigationBar).last);
      final animePrimary = Theme.of(
        tester.element(find.byType(NavigationBar).last),
      ).colorScheme.primary;
      final animeSwitch = tester.getSize(
        find.widgetWithText(TextButton, 'Ir a Manga'),
      );

      // Misma altura de navegación, mismo acento y misma barra global.
      expect(animeBar.height, mangaBar.height);
      expect(animePrimary, mangaPrimary);
      expect(animeSwitch.height, mangaSwitch.height);

      // Al desplazar hacia abajo se pliegan las dos barras; al subir vuelven.
      double barsHeight() => tester
          .widgetList<YomaHideOnScroll>(find.byType(YomaHideOnScroll))
          .map((w) => tester.getSize(find.byWidget(w)).height)
          .fold(0.0, (a, b) => a + b);
      // YomaTV recuerda la última pestaña; la prueba se sitúa en Inicio.
      await tester.tap(find.text('Inicio').last);
      await tester.pump(const Duration(milliseconds: 400));
      final shown = barsHeight();
      expect(shown, greaterThan(animeBar.height));
      // Única lista vertical visible: el Inicio de YomaTV.
      final home = find.byType(CustomScrollView);
      await tester.drag(home, const Offset(0, -300));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(barsHeight(), lessThan(1));
      await capture('03b-anime-bars-hidden');
      await tester.drag(home, const Offset(0, 120));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(barsHeight(), closeTo(shown, 0.5));

      await tester.tap(find.text('Explorar'));
      await capture('04-anime-explore');
      // Las descargas se agrupan por anime, con los episodios en orden.
      AnimeDownload job(
        String slug,
        String title,
        String number,
        String state,
      ) => AnimeDownload({
        'key': '$slug:$number:SUB',
        'slug': slug,
        'title': title,
        'number': number,
        'state': state,
        'file': state == 'done' ? '/x/$slug-$number.mp4' : '',
        'bytes': 50 * 1024 * 1024,
        'total': 100 * 1024 * 1024,
        'language': 'SUB',
      });
      anime.downloads = [
        job('demons-crest', "Demons' Crest", '2', 'done'),
        job('dark-machine', 'Dark Machine: The Animation', '1', 'done'),
        job('demons-crest', "Demons' Crest", '1', 'done'),
        job('demons-crest', "Demons' Crest", '3', 'downloading'),
      ];
      anime.changed();
      await tester.tap(find.text('Descargas').last);
      await capture('05-anime-downloads');
      // En la pantalla pequeña con texto grande los grupos quedan bajo el
      // borde; ahí solo se comprueba que nada se desborde.
      if (name == 'phone') {
        expect(find.text("Demons' Crest"), findsOneWidget);
        expect(
          find.textContaining('3 episodios · 2 descargados'),
          findsOneWidget,
        );
        expect(find.text('Episodio 3 · Subtitulado'), findsOneWidget);
        final first = tester
            .getTopLeft(find.text('Episodio 1 · Subtitulado'))
            .dy;
        final second = tester
            .getTopLeft(find.text('Episodio 2 · Subtitulado'))
            .dy;
        expect(first, lessThan(second));
        // Al plegar un grupo queda a la vista el siguiente; un grupo de un
        // solo episodio se muestra abierto y se pliega al tocarlo.
        await tester.tap(find.text("Demons' Crest"));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pump();
        expect(find.text('Episodio 3 · Subtitulado'), findsNothing);
        expect(find.text('Dark Machine: The Animation'), findsOneWidget);
        expect(find.text('Episodio 1 · Subtitulado'), findsOneWidget);
        await tester.tap(find.text('Dark Machine: The Animation'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.text('Episodio 1 · Subtitulado'), findsNothing);
      }
      await tester.tap(find.text('Más').last);
      await capture('06-anime-more');

      await tester.tap(find.widgetWithText(TextButton, 'Ir a Manga'));
      await tester.pump();
      await tester.tap(find.text('Perfil').last);
      await capture('07-manga-profile');
      await tester.tap(find.text('Descargas').last);
      await capture('08-manga-downloads');

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
    });
  }
}
