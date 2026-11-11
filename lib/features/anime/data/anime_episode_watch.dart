import '../../../data/library_store.dart';
import '../models/anime_models.dart';
import 'anime_local_store.dart';
import 'anime_mal_client.dart';
import 'anime_mal_shelf.dart';
import 'yomatv_source.dart';

/// Un anime de «Viendo» con episodios nuevos en YomaTV.
class NewEpisodes {
  final String slug, title;

  /// Número del episodio más reciente publicado.
  final String latest;
  final int added;
  const NewEpisodes(this.slug, this.title, this.latest, this.added);
}

/// Comprueba si los animes de «Viendo» en MyAnimeList (los que coinciden
/// por nombre y los vinculados a mano) tienen episodios nuevos en YomaTV.
///
/// La primera vez solo anota cuántos hay: nunca avisa de todo lo publicado.
/// Lo que el usuario ya vio en la ficha también se anota, para no avisar de
/// algo que ya conoce.
class AnimeEpisodeWatch {
  static const namespace = 'anime_episode_watch';

  /// Límite de animes revisados en cada comprobación.
  static const maxAnime = 40;

  final YomaTvSource source;
  final AnimeMalClient mal;
  final Future<LibraryStore> Function() database;
  AnimeEpisodeWatch({
    YomaTvSource? source,
    AnimeMalClient? mal,
    Future<LibraryStore> Function()? database,
  }) : source = source ?? YomaTvSource(),
       mal = mal ?? AnimeMalClient(),
       database = database ?? LibraryStore.ensureInitialized;

  /// Episodios publicados de [detail]: los distintos números que tiene.
  static int count(AnimeDetail detail) =>
      detail.episodes.map((e) => e.number).toSet().length;

  /// Anota lo publicado en [detail] como ya conocido.
  static Future<void> remember(LibraryStore store, AnimeDetail detail) async {
    final slug = detail.anime.slug;
    if (slug.isEmpty || detail.episodes.isEmpty) return;
    final known = animeInt(
      animeMap(await store.getRecord(namespace, slug))['count'],
    );
    final current = count(detail);
    if (current <= known) return;
    await store.putRecord(namespace, slug, {
      'count': current,
      'checkedAt': DateTime.now().millisecondsSinceEpoch,
    });
  }

  /// Animes a revisar: slug → título.
  Future<Map<String, String>> _targets() async {
    final owner = await mal.owner();
    if (owner <= 0) return const {};
    final shelf = await AnimeMalShelf(
      mal: mal,
      source: source,
      database: database,
    ).cached(owner);
    if (shelf == null) return const {};
    final targets = <String, String>{
      for (final item in shelf.watching) item.anime.slug: item.anime.title,
    };
    for (final link in (await mal.linkedIds()).entries) {
      final entry = shelf.watchingAll[link.value];
      if (entry != null) targets.putIfAbsent(link.key, () => entry.title);
    }
    return targets;
  }

  /// Revisa los animes y devuelve los que tienen episodios nuevos. La ficha
  /// descargada se guarda, así que al abrirla ya aparecen.
  Future<List<NewEpisodes>> check() async {
    final store = await database();
    final cache = AnimeLocalStore(database: database);
    final found = <NewEpisodes>[];
    for (final target in (await _targets()).entries.take(maxAnime)) {
      try {
        final data = await source.detail(target.key);
        final detail = AnimeDetail.fromJson(data);
        if (detail.episodes.isEmpty) continue;
        await cache.putCache('detail:${target.key}', data);
        final row = animeMap(await store.getRecord(namespace, target.key));
        final current = count(detail);
        if (row.isNotEmpty && current > animeInt(row['count'])) {
          found.add(
            NewEpisodes(
              target.key,
              detail.anime.title.isEmpty ? target.value : detail.anime.title,
              detail.episodes.last.number,
              current - animeInt(row['count']),
            ),
          );
        }
        await store.putRecord(namespace, target.key, {
          'count': current,
          'checkedAt': DateTime.now().millisecondsSinceEpoch,
        });
      } catch (_) {
        // Un anime que no responde no impide revisar los demás.
        continue;
      }
    }
    return found;
  }

  /// Título y texto del aviso.
  static ({String title, String text}) notice(List<NewEpisodes> news) {
    if (news.length == 1) {
      final only = news.single;
      return (
        title: only.added == 1 ? 'Episodio nuevo' : 'Episodios nuevos',
        text: '${only.title} · episodio ${only.latest}',
      );
    }
    final names = news.map((n) => n.title).take(3).join(', ');
    final more = news.length > 3 ? ' y ${news.length - 3} más' : '';
    return (
      title: 'Episodios nuevos',
      text: '${news.length} animes que estás viendo: $names$more',
    );
  }
}
