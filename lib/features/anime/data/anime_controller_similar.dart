part of 'anime_controller.dart';

// AnimeController y los animes similares de una ficha: la búsqueda del
// catálogo de YomaTV (la misma de Explorar) trae los candidatos y
// [AnimeSimilarity] elige los que tienen un nombre parecido al anime abierto.
extension AnimeControllerSimilar on AnimeController {
  /// Prefijo en `anime_cache` de la última lista encontrada de cada anime.
  static const cachePrefix = 'similar:';

  /// Animes con nombre parecido al de [detail], del más parecido al menos.
  /// No incluye el propio anime ni lo que su ficha ya muestra en
  /// «Temporadas y entregas». Se busca una vez por sesión; sin conexión se
  /// usa la lista guardada. No falla: si no encuentra nada, queda vacía.
  Future<List<AnimeTitle>> similar(AnimeDetail detail) async {
    final seasons = {for (final season in detail.seasons) season.slug};
    final found = await (_similar[detail.anime.slug] ??= _findSimilar(
      detail.anime,
    ));
    // Las temporadas se excluyen aquí: una ficha actualizada puede traer
    // otras distintas de las que había al buscar.
    return found
        .where((anime) => !seasons.contains(anime.slug))
        .take(AnimeSimilarity.limit)
        .toList();
  }

  /// Hasta [_kept] candidatos ordenados; [similar] quita las temporadas.
  static const _kept = 60;

  static const _cardFields = [
    'slug',
    'title',
    'cover',
    'category',
    'year',
    'episodes',
    'alternative_titles',
  ];

  Future<List<AnimeTitle>> _findSimilar(AnimeTitle anime) async {
    final key = '${AnimeControllerSimilar.cachePrefix}${anime.slug}';
    // Lo que ya está cargado también cuenta, sin coste.
    final candidates = <AnimeTitle>[
      ...catalogItems,
      ...?front?.items,
      ...schedule,
    ];
    var reached = false;
    for (final query in AnimeSimilarity.queries(anime)) {
      try {
        candidates.addAll(
          AnimePage.fromJson(await source.catalog(search: query)).items,
        );
        reached = true;
      } catch (_) {
        // Sin la búsqueda quedan la lista guardada y lo ya cargado.
      }
    }
    try {
      if (!reached) {
        final cached = await store.cache(key);
        final items = animeMap(cached?['data'])['items'];
        if (items is List) {
          candidates.addAll(items.map((e) => AnimeTitle.fromJson(animeMap(e))));
        }
      }
      final ranked = AnimeSimilarity.rank(
        anime,
        candidates,
        limit: AnimeControllerSimilar._kept,
      );
      if (!reached) {
        // La próxima vez que se abra la ficha se vuelve a buscar.
        _similar.remove(anime.slug);
      } else if (ranked.isNotEmpty) {
        // Una lista vacía no se guarda: no aporta nada sin conexión.
        await store.putCache(key, {
          // Solo lo que usa la tarjeta, no la sinopsis.
          'items': [
            for (final item in ranked)
              {
                for (final field in AnimeControllerSimilar._cardFields)
                  if (item.raw[field] != null) field: item.raw[field],
              },
          ],
        });
      }
      return ranked;
    } catch (_) {
      _similar.remove(anime.slug);
      return AnimeSimilarity.rank(
        anime,
        candidates,
        limit: AnimeControllerSimilar._kept,
      );
    }
  }
}
