import 'dart:async';

import '../data/library_store.dart';
import '../models/chapter.dart';
import '../models/favorite_entry.dart';
import '../models/manga.dart';
import '../models/reading_progress.dart';
import 'mal_source_matcher.dart';
import 'myanimelist_client.dart';
import 'myanimelist_service.dart';

/// Lo que hace falta saber de los capítulos leídos en el teléfono.
abstract class ReadChapters {
  bool isRead(String path);

  /// El usuario lo desmarcó: MyAnimeList no lo vuelve a marcar.
  bool isUnmarked(String path);
  Future<void> markReadFromMal(Iterable<String> paths);
}

/// «Reading» de MyAnimeList → YomaShi.
///
/// Los mangas de la biblioteca con el mismo nombre que una obra de
/// «Reading» quedan vinculados, y los capítulos que MAL ya tiene leídos se
/// marcan como leídos en el teléfono. Solo añade: nunca desmarca nada, no
/// toca los capítulos que el usuario desmarcó y no reenvía nada a MAL.
class MalReadingSync {
  static final shared = MalReadingSync(MyAnimeListService.shared);

  static const namespace = 'mal_reading';
  static const maxAge = Duration(hours: 12);

  /// Límite de seguridad (20 páginas de 50).
  static const maxEntries = 1000;

  final MyAnimeListService service;
  final Future<LibraryStore> Function() database;
  MalReadingSync(this.service, {Future<LibraryStore> Function()? database})
    : database = database ?? LibraryStore.ensureInitialized;

  MyAnimeListClient get client => service.client;
  Future<void>? _running;

  Future<int> _owner() async {
    final auth = await client.credentials.load();
    final owner = (auth?['profile'] as Map?)?['id'];
    return auth?['connected'] == true && owner is int && owner > 0 ? owner : 0;
  }

  /// La lista «Reading» de la cuenta conectada. Sale del teléfono si tiene
  /// menos de [maxAge]; si MAL no responde se usa la copia aunque sea vieja.
  Future<List<MalManga>> reading({
    bool force = false,
    Duration age = maxAge,
  }) async {
    final owner = await _owner();
    if (owner <= 0) return const [];
    final store = await database();
    final saved = await store.getRecord(namespace, 'list:$owner');
    List<MalManga>? cached;
    if (saved is Map && saved['owner'] == owner) {
      try {
        cached = [
          for (final row in saved['items'] as List? ?? const [])
            MalManga.fromMap(Map<String, dynamic>.from(row as Map)),
        ];
      } catch (_) {
        cached = null;
      }
      final elapsed =
          DateTime.now().millisecondsSinceEpoch -
          (saved['savedAt'] as int? ?? 0);
      if (cached != null && !force && elapsed < age.inMilliseconds) {
        return cached;
      }
    }
    try {
      final items = <MalManga>[];
      int? offset = 0;
      for (var pages = 0; offset != null && pages < maxEntries ~/ 50; pages++) {
        final page = await client.library(
          status: 'reading',
          offset: offset,
          expectedOwner: owner,
        );
        items.addAll(page.items);
        offset = page.nextOffset;
      }
      if (await _owner() != owner) {
        throw const MalFailure('La cuenta de MyAnimeList cambió.', 409);
      }
      await store.putRecord(namespace, 'list:$owner', {
        'owner': owner,
        'savedAt': DateTime.now().millisecondsSinceEpoch,
        'items': [for (final manga in items) manga.toMap()],
      });
      return items;
    } catch (_) {
      if (cached != null) return cached;
      rethrow;
    }
  }

  /// Mangas de la biblioteca: descargados (con sus capítulos), favoritos y
  /// con progreso de lectura. Uno por obra.
  static List<Manga> candidates({
    Iterable<Manga> library = const [],
    Iterable<FavoriteEntry> favorites = const [],
    Iterable<ReadingProgress> progress = const [],
  }) {
    final byKey = <String, Manga>{};
    for (final manga in library) {
      byKey.putIfAbsent(MyAnimeListService.mangaKey(manga), () => manga);
    }
    Manga remote(String key, String title) => Manga(
      title: title,
      path: key,
      sourceUrl: key.startsWith('http') ? key : null,
      chapters: const [],
    );
    for (final favorite in favorites) {
      if (favorite.key.isEmpty) continue;
      final manga = remote(favorite.key, favorite.title);
      byKey.putIfAbsent(MyAnimeListService.mangaKey(manga), () => manga);
    }
    for (final row in progress) {
      if (row.mangaPath.isEmpty) continue;
      final manga = remote(row.mangaPath, row.mangaTitle);
      byKey.putIfAbsent(MyAnimeListService.mangaKey(manga), () => manga);
    }
    return byKey.values.toList();
  }

  /// La obra de MAL y el manga del teléfono pueden ser la misma: el manga
  /// no tiene más capítulos de los que la obra tiene en MAL (margen de 2).
  static bool compatible(MalManga mal, Manga manga) {
    if (mal.totalChapters <= 0) return true;
    var highest = 0;
    for (final chapter in manga.chapters) {
      final number = MyAnimeListService.chapterNumber(chapter) ?? 0;
      if (number > highest) highest = number;
    }
    return highest <= mal.totalChapters + 2;
  }

  /// La obra de «Reading» con el mismo nombre que [manga], si hay una sola.
  static MalManga? match(Manga manga, List<MalManga> reading) {
    final key = MalSourceMatcher.titleKey(manga.title);
    if (key.isEmpty) return null;
    MalManga? found;
    for (final mal in reading) {
      final names = MalSourceMatcher.titles(mal).map(MalSourceMatcher.titleKey);
      if (!names.contains(key)) continue;
      // Dos obras de la lista con ese nombre: no se elige una al azar.
      if (found != null && found.id != mal.id) return null;
      found = mal;
    }
    return found != null && compatible(found, manga) ? found : null;
  }

  /// Vincula [manga] con su obra de «Reading» si aún no tiene vínculo.
  /// Devuelve la obra vinculada (nueva o existente), o `null`.
  Future<MalManga?> _ensureLink(
    Manga manga,
    List<MalManga> reading,
    int owner,
  ) async {
    final link = await service.linkFor(manga);
    if (link != null) {
      if (link['owner'] != owner) return null;
      for (final mal in reading) {
        if (mal.id == link['malId']) return mal;
      }
      return null;
    }
    final mal = match(manga, reading);
    if (mal == null) return null;
    if (await service.unlinkedByUser(manga)) return null;
    await service.link(manga, mal, automatic: true, expectedOwner: owner);
    return mal;
  }

  /// Capítulos de [chapters] que MAL tiene leídos (números 1 a [count]) y
  /// en el teléfono no, sin los que el usuario desmarcó.
  static List<String> missing(
    Iterable<Chapter> chapters,
    int count,
    ReadChapters reads,
  ) => [
    for (final chapter in chapters)
      if ((MyAnimeListService.chapterNumber(chapter) ?? 0) >= 1 &&
          MyAnimeListService.chapterNumber(chapter)! <= count &&
          chapter.path.isNotEmpty &&
          !reads.isRead(chapter.path) &&
          !(chapter.sourceUrl != null && reads.isRead(chapter.sourceUrl!)) &&
          !reads.isUnmarked(chapter.path))
        chapter.path,
  ];

  /// Aplica la lista «Reading» a [manga] con sus [chapters] (por ejemplo, al
  /// abrir su ficha). Devuelve cuántos capítulos se marcaron.
  Future<int> apply(
    Manga manga,
    Iterable<Chapter> chapters,
    ReadChapters reads,
  ) async {
    final owner = await _owner();
    if (owner <= 0) return 0;
    final list = await reading();
    final mal = await _ensureLink(
      Manga(
        title: manga.title,
        path: manga.path,
        sourceUrl: manga.sourceUrl,
        chapters: chapters.toList(),
      ),
      list,
      owner,
    );
    if (mal == null || mal.chaptersRead <= 0) return 0;
    final paths = missing(chapters, mal.chaptersRead, reads);
    if (paths.isNotEmpty) await reads.markReadFromMal(paths);
    return paths.length;
  }

  /// Vincula la biblioteca con «Reading» y marca los capítulos ya leídos en
  /// MAL de los mangas cuyos capítulos conoce el teléfono. Las fichas online
  /// se completan al abrirlas con [apply].
  Future<void> run(
    List<Manga> library,
    ReadChapters reads, {
    bool force = false,
    Duration age = maxAge,
  }) {
    final pending = _running;
    if (pending != null) return pending;
    final work = _run(library, reads, force: force, age: age);
    _running = work;
    return work.whenComplete(() => _running = null);
  }

  Future<void> _run(
    List<Manga> library,
    ReadChapters reads, {
    required bool force,
    required Duration age,
  }) async {
    final owner = await _owner();
    if (owner <= 0) return;
    final list = await reading(force: force, age: age);
    if (list.isEmpty) return;
    for (final manga in library) {
      if (await _owner() != owner) return;
      final mal = await _ensureLink(manga, list, owner);
      if (mal == null || mal.chaptersRead <= 0 || manga.chapters.isEmpty) {
        continue;
      }
      final paths = missing(manga.chapters, mal.chaptersRead, reads);
      if (paths.isNotEmpty) await reads.markReadFromMal(paths);
    }
  }
}
