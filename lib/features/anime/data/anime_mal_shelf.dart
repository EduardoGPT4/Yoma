import '../../../data/library_store.dart';
import '../models/anime_models.dart';
import 'anime_mal_client.dart';
import 'yomatv_source.dart';

/// Un anime de la lista de MyAnimeList que existe en YomaTV con el mismo nombre.
class MalShelfItem {
  final MalAnimeEntry entry;
  final AnimeTitle anime;
  const MalShelfItem(this.entry, this.anime);
  Map<String, dynamic> toJson() => {
    'entry': entry.toJson(),
    'anime': anime.toJson(),
  };
  MalShelfItem.fromJson(Map<String, dynamic> json)
    : entry = MalAnimeEntry.fromJson(animeMap(json['entry'])),
      anime = AnimeTitle.fromJson(animeMap(json['anime']));
}

class MalShelfSnapshot {
  final int owner;
  final DateTime savedAt;
  final List<MalShelfItem> watching, planned;
  const MalShelfSnapshot({
    required this.owner,
    required this.savedAt,
    required this.watching,
    required this.planned,
  });
  bool get isEmpty => watching.isEmpty && planned.isEmpty;
}

/// Listas «Viendo» y «Plan to watch» de MAL emparejadas con YomaTV.
///
/// Todo se guarda en el teléfono (espacio propio, que «Limpiar caché del
/// catálogo» no borra): la sección aparece al instante y solo se consulta a
/// MAL cuando la copia es antigua o se pide actualizar.
class AnimeMalShelf {
  static const namespace = 'anime_mal_shelf';
  static const statuses = ['watching', 'plan_to_watch'];

  /// Antigüedad a partir de la cual se actualiza en segundo plano.
  static const maxAge = Duration(hours: 12);

  /// Un anime sin coincidencia se vuelve a buscar pasado este tiempo, por si
  /// YomaTV lo añadió después.
  static const retryMissing = Duration(days: 3);

  /// Límite de seguridad por lista (20 páginas de 50).
  static const maxEntries = 1000;

  final AnimeMalClient mal;
  final YomaTvSource source;
  final Future<LibraryStore> Function() database;
  AnimeMalShelf({
    required this.mal,
    required this.source,
    Future<LibraryStore> Function()? database,
  }) : database = database ?? LibraryStore.ensureInitialized;

  /// Comparación exacta de nombres; solo unifica mayúsculas, espacios,
  /// comillas y guiones tipográficos.
  static String normalize(String title) => title
      .toLowerCase()
      .replaceAll(RegExp('[‘’ʼ`´]'), "'")
      .replaceAll(RegExp('[“”]'), '"')
      .replaceAll(RegExp('[‐-―]'), '-')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  static bool sameName(String malTitle, AnimeTitle anime) {
    final wanted = normalize(malTitle);
    if (wanted.isEmpty) return false;
    return [
      anime.title,
      ...anime.alternatives,
    ].any((name) => normalize(name) == wanted);
  }

  Future<MalShelfSnapshot?> cached(int owner) async {
    if (owner <= 0) return null;
    final row = animeMap(
      await (await database()).getRecord(namespace, 'shelf:$owner'),
    );
    if (row['owner'] != owner) return null;
    List<MalShelfItem> items(Object? value) => (value as List? ?? [])
        .map((e) => MalShelfItem.fromJson(animeMap(e)))
        .where((e) => e.anime.slug.isNotEmpty)
        .toList();
    return MalShelfSnapshot(
      owner: owner,
      savedAt: DateTime.fromMillisecondsSinceEpoch(animeInt(row['savedAt'])),
      watching: items(row['watching']),
      planned: items(row['planned']),
    );
  }

  /// Descarga las dos listas, busca cada título en YomaTV y guarda el
  /// resultado. Las coincidencias ya conocidas no se vuelven a buscar.
  Future<MalShelfSnapshot> refresh(int owner) async {
    final store = await database();
    final lists = <String, List<MalShelfItem>>{};
    for (final status in statuses) {
      final entries = <MalAnimeEntry>[];
      for (var offset = 0; offset < maxEntries; offset += 50) {
        final page = await mal.library(status: status, offset: offset);
        entries.addAll(page);
        if (page.length < 50) break;
      }
      // Tres búsquedas a la vez, igual que el máximo de conexiones a YomaTV;
      // se conserva el orden de la lista de MAL.
      final found = List<AnimeTitle?>.filled(entries.length, null);
      var next = 0;
      Future<void> worker() async {
        while (next < entries.length) {
          final index = next++;
          found[index] = await _match(store, entries[index]);
        }
      }

      await Future.wait([for (var i = 0; i < 3; i++) worker()]);
      lists[status] = [
        for (var i = 0; i < entries.length; i++)
          if (found[i] != null) MalShelfItem(entries[i], found[i]!),
      ];
    }
    if (await mal.owner() != owner) {
      throw StateError('La cuenta de MyAnimeList cambió durante la carga.');
    }
    final now = DateTime.now();
    final snapshot = MalShelfSnapshot(
      owner: owner,
      savedAt: now,
      watching: lists['watching']!,
      planned: lists['plan_to_watch']!,
    );
    await store.putRecord(namespace, 'shelf:$owner', {
      'owner': owner,
      'savedAt': now.millisecondsSinceEpoch,
      'watching': snapshot.watching.map((e) => e.toJson()).toList(),
      'planned': snapshot.planned.map((e) => e.toJson()).toList(),
    });
    return snapshot;
  }

  Future<AnimeTitle?> _match(LibraryStore store, MalAnimeEntry entry) async {
    final key = 'match:${entry.id}';
    final known = animeMap(await store.getRecord(namespace, key));
    final checked = animeInt(known['checkedAt']);
    if (known['title'] == entry.title) {
      final anime = animeMap(known['anime']);
      if (anime.isNotEmpty) return AnimeTitle.fromJson(anime);
      final age = DateTime.now().millisecondsSinceEpoch - checked;
      if (age < retryMissing.inMilliseconds) return null;
    }
    final page = AnimePage.fromJson(await source.catalog(search: entry.title));
    AnimeTitle? found;
    for (final item in page.items) {
      if (sameName(entry.title, item)) {
        found = item;
        break;
      }
    }
    await store.putRecord(namespace, key, {
      'title': entry.title,
      'anime': found?.toJson(),
      'checkedAt': DateTime.now().millisecondsSinceEpoch,
    });
    return found;
  }
}
