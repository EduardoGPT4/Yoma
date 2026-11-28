// «Animes similares» en la ficha de YomaTV. Guarda una captura en
// build/test_screenshots/design/ para revisarla.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yomashi/data/app_database.dart';
import 'package:yomashi/data/library_store.dart';
import 'package:yomashi/design/yoma_theme.dart';
import 'package:yomashi/design/yoma_tokens.dart';
import 'package:yomashi/features/anime/data/anime_controller.dart';
import 'package:yomashi/features/anime/data/anime_local_store.dart';
import 'package:yomashi/features/anime/models/anime_models.dart';
import 'package:yomashi/features/anime/screens/anime_detail_screen.dart';
import 'package:yomashi/widgets/app_metrics.dart';

import '../unit/anime_similar_test.dart' show SimilarSource;

AnimeTitle _anime(String slug, String title, String category, String year) =>
    AnimeTitle.fromJson({
      'slug': slug,
      'title': title,
      'category': category,
      'year': year,
      'episodes': category == 'TV Anime' ? 12 : 1,
      'cover': 'https://cdn.example/$slug.jpg',
    });

final _catalog = [
  _anime('kny', 'Kimetsu no Yaiba', 'TV Anime', '2019'),
  _anime('kny-2', 'Kimetsu no Yaiba: Yuukaku-hen', 'TV Anime', '2021'),
  _anime(
    'kny-movie',
    'Kimetsu no Yaiba Movie: Mugen Ressha-hen',
    'Película',
    '2020',
  ),
  _anime(
    'kny-movie-1',
    'Kimetsu no Yaiba Movie 1: Mugenjou-hen - Akaza Sairai',
    'Película',
    '2025',
  ),
  _anime('kny-gakuen', 'Kimetsu Gakuen', 'Especial', '2020'),
  _anime('spy', 'Spy x Family', 'TV Anime', '2022'),
];

/// Ficha con «Temporadas y entregas»; el resto del catálogo, por búsqueda.
class _DetailSource extends SimilarSource {
  _DetailSource(super.titles);
  @override
  Future<Map<String, dynamic>> detail(String slug) async => {
    'anime': {
      ...titles.firstWhere((a) => a.slug == slug).toJson(),
      'synopsis': 'Tanjirou se une a los cazadores de demonios.',
      'genres': ['Acción', 'Fantasía'],
    },
    'episodes': [
      for (var i = 1; i <= 3; i++) {'id': i, 'slug': slug, 'number': '$i'},
    ],
    'seasons': slug == 'kny'
        ? [
            {'slug': 'kny', 'label': 'Kimetsu no Yaiba'},
            {'slug': 'kny-2', 'label': 'Yuukaku-hen'},
          ]
        : [],
  };
}

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
  late AnimeController app;
  late _DetailSource source;

  Future<void> pumpDetail(
    WidgetTester tester,
    String slug, {
    GlobalKey? boundary,
    ValueChanged<String>? open,
  }) async {
    await tester.runAsync(() async {
      final detail = await app.detail(slug);
      await app.similar(detail);
    });
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildYomaTheme(YomaColors.accent, AppMetrics.compact),
        home: RepaintBoundary(
          key: boundary,
          child: AnimeDetailScreen(
            controller: app,
            slug: slug,
            play: (_, _) {},
            openSeason: open ?? (_) {},
            openWeb: () {},
          ),
        ),
      ),
    );
    // Las fichas y los similares ya calculados se resolvieron fuera de la
    // zona de la prueba: se les deja terminar en tiempo real.
    for (var i = 0; i < 4; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  late LibraryStore db;
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    db = await LibraryStore.initialize(
      database: AppDatabase.forTesting(NativeDatabase.memory()),
    );
  });

  Future<void> createController(WidgetTester tester) async {
    await tester.runAsync(() async {
      await db.replaceRecords('anime_cache', []);
      source = _DetailSource(_catalog);
      app = AnimeController(
        source: source,
        store: AnimeLocalStore(database: () async => db),
        connectivity: () => const Stream.empty(),
      );
    });
    addTearDown(app.dispose);
  }

  testWidgets('la ficha muestra los similares antes de los episodios', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.runAsync(_loadFonts);
    await createController(tester);
    final boundary = GlobalKey();
    String? opened;
    await pumpDetail(
      tester,
      'kny',
      boundary: boundary,
      open: (s) => opened = s,
    );

    final section = find.text('Animes similares');
    await tester.scrollUntilVisible(
      section,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(section, findsOneWidget);
    expect(
      tester.getTopLeft(section).dy,
      lessThan(tester.getTopLeft(find.text('Episodios')).dy),
    );
    // La misma franquicia (con sus películas) y luego lo parecido; sin la
    // propia ficha, sin lo que ya está en «Temporadas y entregas» y sin
    // títulos sin relación.
    final row = find.byKey(const PageStorageKey('anime-similar:kny'));
    Finder card(String title) =>
        find.descendant(of: row, matching: find.text(title));
    expect(card('Kimetsu no Yaiba Movie: Mugen Ressha-hen'), findsOneWidget);
    expect(card('Kimetsu Gakuen'), findsOneWidget);
    expect(card('Kimetsu no Yaiba: Yuukaku-hen'), findsNothing);
    expect(card('Kimetsu no Yaiba'), findsNothing);
    expect(card('Spy x Family'), findsNothing);
    expect(
      tester.getTopLeft(card('Kimetsu no Yaiba Movie: Mugen Ressha-hen')).dx,
      lessThan(tester.getTopLeft(card('Kimetsu Gakuen')).dx),
    );
    // Los chips de temporadas siguen en su sitio.
    expect(find.widgetWithText(ChoiceChip, 'Yuukaku-hen'), findsOneWidget);

    expect(tester.takeException(), isNull);
    await tester.runAsync(() async {
      final image =
          await (boundary.currentContext!.findRenderObject()
                  as RenderRepaintBoundary)
              .toImage();
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      final folder = Directory('build/test_screenshots/design');
      await folder.create(recursive: true);
      await File(
        '${folder.path}/anime-detail-similar.png',
      ).writeAsBytes(png!.buffer.asUint8List());
      image.dispose();
    });

    await tester.tap(card('Kimetsu Gakuen'));
    expect(opened, 'kny-gakuen');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('sin animes parecidos no aparece la sección', (tester) async {
    await createController(tester);
    await pumpDetail(tester, 'spy');
    await tester.scrollUntilVisible(
      find.text('Episodios'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Animes similares'), findsNothing);
    expect(source.searches, isNotEmpty);
    await tester.pumpWidget(const SizedBox());
  });
}
