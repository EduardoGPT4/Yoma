import 'dart:async';

import '../data/library_store.dart';
import '../models/manga.dart';
import 'mal_reading_sync.dart';
import 'mal_source_matcher.dart';
import 'myanimelist_client.dart';
import 'myanimelist_service.dart';

/// Vincula sola con MyAnimeList cada obra de la biblioteca que aún no tenga
/// vínculo, buscándola en todo MAL (no solo en tu lista).
///
/// Solo vincula si un resultado tiene exactamente el mismo nombre, en su
/// título principal o en uno alternativo (sin contar mayúsculas, acentos ni
/// signos), y es el único así. Respeta los vínculos manuales y nunca vuelve a
/// vincular una obra que el usuario desvinculó. Cada obra se busca una vez;
/// si no hubo coincidencia se vuelve a probar pasados [retryAfter].
class MalAutoLink {
  static final shared = MalAutoLink(MyAnimeListService.shared);

  static const namespace = 'mal_auto_search';
  static const retryAfter = Duration(days: 14);

  /// Búsquedas por pasada: el puente de MAL es lento y compartido.
  static const maxSearches = 8;

  /// Resultados cuya ficha se consulta para leer sus títulos alternativos
  /// (la búsqueda de MAL solo trae el principal).
  static const detailsPerSearch = 3;

  final MyAnimeListService service;
  final Future<LibraryStore> Function() database;
  MalAutoLink(this.service, {Future<LibraryStore> Function()? database})
    : database = database ?? LibraryStore.ensureInitialized;

  MyAnimeListClient get client => service.client;
  Future<int>? _running;

  Future<int> _owner() async {
    final auth = await client.credentials.load();
    final owner = (auth?['profile'] as Map?)?['id'];
    return auth?['connected'] == true && owner is int && owner > 0 ? owner : 0;
  }

  /// Busca y vincula las obras de [library]. Devuelve cuántas vinculó.
  Future<int> run(List<Manga> library) {
    final pending = _running;
    if (pending != null) return pending;
    final work = _run(library);
    _running = work;
    return work.whenComplete(() => _running = null);
  }

  Future<int> _run(List<Manga> library) async {
    final owner = await _owner();
    if (owner <= 0) return 0;
    final store = await database();
    var searches = 0, linked = 0;
    for (final manga in library) {
      if (searches >= maxSearches || await _owner() != owner) break;
      final title = manga.title.trim();
      if (title.length < 3 ||
          title.length > 64 ||
          MalSourceMatcher.titleKey(title).isEmpty) {
        continue;
      }
      final key = '$owner:${MyAnimeListService.mangaKey(manga)}';
      final last = await store.getRecord(namespace, key);
      final now = DateTime.now().millisecondsSinceEpoch;
      if (last is Map &&
          now - (last['at'] as int? ?? 0) < retryAfter.inMilliseconds) {
        continue;
      }
      if (await service.linkFor(manga) != null ||
          await service.unlinkedByUser(manga)) {
        continue;
      }
      searches++;
      MalManga? found;
      try {
        found = await find(manga);
      } on MalFailure catch (error) {
        // Sin conexión o puente caído: se reintenta en la próxima pasada.
        if (error.status == 0 || error.status >= 500) break;
      }
      await store.putRecord(namespace, key, {'at': now, 'malId': found?.id});
      if (found == null) continue;
      if (await service.linkFor(manga) != null) continue;
      await service.link(manga, found, automatic: true, expectedOwner: owner);
      linked++;
    }
    return linked;
  }

  /// La única obra de MAL con exactamente el nombre de [manga], o `null`.
  Future<MalManga?> find(Manga manga) async {
    final results = await client.search(manga.title.trim());
    final direct = MalReadingSync.match(manga, results);
    if (direct != null) return direct;
    // El nombre puede coincidir con un título alternativo: se consulta la
    // ficha de los primeros resultados, que sí los trae.
    final wanted = MalSourceMatcher.titleKey(manga.title);
    if (results.any((mal) => MalSourceMatcher.titleKey(mal.title) == wanted)) {
      // Hay coincidencia en el título principal pero ambigua o incompatible.
      return null;
    }
    final detailed = <MalManga>[];
    for (final mal in results.take(detailsPerSearch)) {
      detailed.add(
        mal.alternativeTitles.isNotEmpty ? mal : await client.detail(mal.id),
      );
    }
    return MalReadingSync.match(manga, detailed);
  }
}
