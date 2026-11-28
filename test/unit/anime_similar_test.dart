import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yomashi/data/app_database.dart';
import 'package:yomashi/data/library_store.dart';
import 'package:yomashi/features/anime/data/anime_controller.dart';
import 'package:yomashi/features/anime/data/anime_local_store.dart';
import 'package:yomashi/features/anime/data/anime_similar.dart';
import 'package:yomashi/features/anime/data/yomatv_source.dart';
import 'package:yomashi/features/anime/models/anime_models.dart';

import 'native_anime_test.dart' show TestAnimeSource;

AnimeTitle _anime(
  String title, {
  String? slug,
  String year = '',
  String category = 'TV Anime',
}) => AnimeTitle.fromJson({
  'slug': slug ?? AnimeSimilarity.normalize(title).replaceAll(' ', '-'),
  'title': title,
  'year': year,
  'category': category,
  'cover': 'https://cdn.example/${title.hashCode}.jpg',
});

/// Búsqueda del catálogo que responde con los títulos que contienen el
/// texto buscado, como `title_key LIKE %…%` en el servidor.
class SimilarSource extends TestAnimeSource {
  final List<AnimeTitle> titles;
  final searches = <String>[];
  bool offline = false;
  SimilarSource(this.titles);

  static String _key(String text) =>
      AnimeSimilarity.normalize(text).replaceAll(' ', '');

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
    if (offline) throw const AnimeSourceFailure('Sin red de prueba.');
    return {
      'items': [
        for (final anime in titles)
          if (_key(anime.title).contains(_key(search))) anime.toJson(),
      ],
      'page': 1,
      'pages': 1,
    };
  }
}

void main() {
  group('nombre base', () {
    test('sin acentos, signos ni mayúsculas', () {
      expect(
        AnimeSimilarity.normalize('¡Pokémon: Mewtwo Contraataca!'),
        'pokemon mewtwo contraataca',
      );
      expect(
        AnimeSimilarity.normalize('Shūmatsu no Valkyrie'),
        'shumatsu no valkyrie',
      );
    });

    test('quita temporadas, partes, formatos y números del final', () {
      for (final title in [
        'Shingeki no Kyojin',
        'Shingeki no Kyojin Season 2',
        'Shingeki no Kyojin Season 3 Part 2',
        'Shingeki no Kyojin 2nd Season',
        'Shingeki no Kyojin: The Final Season Part 2',
        'Shingeki no Kyojin Movie: Kanketsu-hen - The Last Attack',
        'Shingeki no Kyojin OVA',
        'Shingeki no Kyojin 3',
        'Shingeki no Kyojin II',
        'Shingeki no Kyojin (2026)',
        'Gekijouban Shingeki no Kyojin',
        'Shingeki no Kyojin 2da Temporada',
      ]) {
        expect(AnimeSimilarity.base(title), [
          'shingeki',
          'no',
          'kyojin',
        ], reason: title);
      }
    });

    test('«Re:Zero» no se corta por los dos puntos sin espacio', () {
      expect(
        AnimeSimilarity.base(
          'Re:Zero kara Hajimeru Isekai Seikatsu 2nd Season',
        ),
        ['re', 'zero', 'kara', 'hajimeru', 'isekai', 'seikatsu'],
      );
    });

    test('un título que es solo un número no se queda vacío', () {
      expect(AnimeSimilarity.base('86'), ['86']);
      expect(AnimeSimilarity.base('Movie'), ['movie']);
    });
  });

  group('parecido', () {
    double score(String a, String b) => AnimeSimilarity.nameScore(a, b);

    test('misma franquicia: parecido máximo', () {
      expect(score('Kimetsu no Yaiba', 'Kimetsu no Yaiba: Yuukaku-hen'), 1);
      expect(score('Kimetsu no Yaiba', 'Kimetsu no Yaiba Movie: Mugen'), 1);
      expect(score('Re:Zero', 'Re Zero'), 1);
    });

    test('un nombre que empieza por el otro queda muy cerca', () {
      final value = score('Naruto', 'Naruto Shippuden');
      expect(value, greaterThan(0.8));
      expect(value, lessThan(1));
      // Pero no a media palabra: «Gate» no es «Gatekeepers».
      expect(score('Gate', 'Gatekeepers'), lessThan(AnimeSimilarity.threshold));
    });

    test('palabras en común dan un parecido parcial', () {
      final value = score('Dragon Ball Super', 'Dragon Ball Daima');
      expect(value, greaterThanOrEqualTo(AnimeSimilarity.threshold));
      expect(value, lessThan(0.8));
    });

    test('las coletillas y los tratamientos no acercan obras distintas', () {
      for (final (a, b) in [
        ('Shingeki no Kyojin Season 3 Part 2', 'Kengan Ashura Season 2 Part 2'),
        ('Sasaki to Pii-chan Season 2', 'Dorohedoro Season 2'),
        ('Sasaki to Pii-chan', 'A-Channel'),
        ('Boku no Hero Academia', 'Boku no Pico'),
      ]) {
        expect(score(a, b), lessThan(AnimeSimilarity.threshold), reason: b);
      }
    });

    test('cuenta el mejor de los títulos alternativos', () {
      final anime = AnimeTitle.fromJson({
        'slug': 'kny',
        'title': 'Kimetsu no Yaiba',
        'alternative_titles': ['Demon Slayer'],
      });
      expect(
        AnimeSimilarity.score(anime, _anime('Demon Slayer: Hashira Training')),
        1,
      );
    });
  });

  group('lista de similares', () {
    final open = _anime('Kimetsu no Yaiba', slug: 'kny', year: '2019');

    test('sin el propio anime, sin repetidos y sin lo excluido', () {
      final ranked = AnimeSimilarity.rank(
        open,
        [
          open,
          _anime('Kimetsu no Yaiba: Yuukaku-hen', slug: 'kny-3'),
          _anime('Kimetsu no Yaiba: Yuukaku-hen', slug: 'kny-3'),
          _anime('Kimetsu no Yaiba: Mugen Ressha-hen', slug: 'kny-2'),
          _anime('Spy x Family', slug: 'spy'),
        ],
        exclude: {'kny-2'},
      );
      expect(ranked.map((a) => a.slug), ['kny-3']);
    });

    test('del más parecido al menos; a igual parecido, por año', () {
      final ranked = AnimeSimilarity.rank(open, [
        _anime('Kimetsu no Ha', slug: 'partial'),
        _anime('Kimetsu no Yaiba Movie', slug: 'movie', year: '2020'),
        _anime('Kimetsu no Yaiba: Yuukaku-hen', slug: 'tv', year: '2021'),
        _anime('Kimetsu no Yaiba Gakuen', slug: 'prefix', year: '2018'),
      ]);
      expect(ranked.map((a) => a.slug), ['movie', 'tv', 'prefix', 'partial']);
    });

    test('como mucho doce', () {
      final ranked = AnimeSimilarity.rank(open, [
        for (var i = 0; i < 30; i++)
          _anime('Kimetsu no Yaiba Movie $i', slug: 'm$i'),
      ]);
      expect(ranked, hasLength(AnimeSimilarity.limit));
    });

    test('búsquedas: la franquicia y su palabra más larga', () {
      expect(AnimeSimilarity.queries(_anime('Shingeki no Kyojin Season 3')), [
        'shingeki no kyojin',
        'shingeki',
      ]);
      expect(AnimeSimilarity.queries(_anime('Naruto Movie 2')), ['naruto']);
    });

    test('con el índice real de YomaTV agrupa la franquicia primero', () {
      final items =
          (jsonDecode(
                    File(
                      'docs/yoma/source-audit/catalog-public.json',
                    ).readAsStringSync(),
                  )['items']
                  as List)
              .map((e) => AnimeTitle.fromJson(animeMap(e)))
              .toList();
      AnimeTitle find(String title) =>
          items.firstWhere((a) => a.title == title);

      final aot = AnimeSimilarity.rank(
        find('Shingeki no Kyojin Season 3 Part 2'),
        items,
      );
      // Las diez entregas de la serie, con películas y OVAs, van delante.
      expect(
        aot.take(10).every((a) => a.title.startsWith('Shingeki no Kyojin')),
        isTrue,
      );
      expect(aot.map((a) => a.category), containsAll(['OVA', 'Película']));
      expect(aot.any((a) => a.title.contains('Kengan')), isFalse);

      final pii = AnimeSimilarity.rank(
        find('Sasaki to Pii-chan Season 2'),
        items,
      );
      expect(pii.first.title, 'Sasaki to Pii-chan');
      expect(pii.every((a) => a.title.contains('Sasaki')), isTrue);
    });
  });

  group('AnimeController.similar', () {
    late LibraryStore db;
    late AnimeLocalStore store;
    setUpAll(() async {
      SharedPreferences.setMockInitialValues({});
      db = await LibraryStore.initialize(
        database: AppDatabase.forTesting(NativeDatabase.memory()),
      );
      store = AnimeLocalStore(database: () async => db);
    });
    setUp(() => db.replaceRecords('anime_cache', []));

    final titles = [
      _anime('Kimetsu no Yaiba', slug: 'kny'),
      _anime('Kimetsu no Yaiba: Mugen Ressha-hen', slug: 'kny-2'),
      _anime('Kimetsu no Yaiba Movie: Mugen Ressha-hen', slug: 'kny-movie'),
      _anime('Kimetsu Gakuen', slug: 'gakuen'),
      _anime('Spy x Family', slug: 'spy'),
    ];
    final detail = AnimeDetail.fromJson({
      'anime': titles.first.toJson(),
      'seasons': [
        {'slug': 'kny', 'title': 'Kimetsu no Yaiba'},
        {'slug': 'kny-2', 'title': 'Mugen Ressha-hen'},
      ],
    });

    AnimeController controller(SimilarSource source) => AnimeController(
      source: source,
      store: store,
      connectivity: () => const Stream.empty(),
    );

    test(
      'busca en el catálogo y deja fuera las temporadas de la ficha',
      () async {
        final source = SimilarSource(titles);
        final app = controller(source);
        addTearDown(app.dispose);
        final found = await app.similar(detail);
        expect(found.map((a) => a.slug), ['kny-movie', 'gakuen']);
        expect(source.searches, ['kimetsu no yaiba', 'kimetsu']);
        // En la misma sesión no se vuelve a buscar.
        await app.similar(detail);
        expect(source.searches, hasLength(2));
      },
    );

    test('sin conexión usa la última lista guardada', () async {
      final first = controller(SimilarSource(titles));
      await first.similar(detail);
      first.dispose();

      final source = SimilarSource(titles)..offline = true;
      final app = controller(source);
      addTearDown(app.dispose);
      final found = await app.similar(detail);
      expect(found.map((a) => a.slug), ['kny-movie', 'gakuen']);
      expect(found.first.cover, isNotEmpty);
      // Al volver la conexión se busca de nuevo.
      source.offline = false;
      await app.similar(detail);
      expect(source.searches, hasLength(4));
    });

    test('sin conexión ni lista guardada queda vacía, sin fallar', () async {
      final app = controller(SimilarSource(titles)..offline = true);
      addTearDown(app.dispose);
      expect(await app.similar(detail), isEmpty);
    });
  });
}
