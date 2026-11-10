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

  /// Algún título no se pudo buscar en YomaTV: la copia sirve, pero se
  /// vuelve a intentar pronto en vez de esperar a que caduque.
  final bool partial;
  const MalShelfSnapshot({
    required this.owner,
    required this.savedAt,
    required this.watching,
    required this.planned,
    this.partial = false,
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

  /// Una copia incompleta se vuelve a intentar pasado este tiempo.
  static const retryPartial = Duration(minutes: 5);

  /// Límite de seguridad por lista (20 páginas de 50).
  static const maxEntries = 1000;

  /// Búsquedas fallidas tras las que se deja de consultar YomaTV en esta
  /// carga: si la fuente no responde, no se espera un fallo por título.
  static const maxSearchFailures = 3;

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
      partial: row['partial'] == true,
    );
  }

  Future<void> _save(LibraryStore store, MalShelfSnapshot value) =>
      store.putRecord(namespace, 'shelf:${value.owner}', {
        'owner': value.owner,
        'savedAt': value.savedAt.millisecondsSinceEpoch,
        'partial': value.partial,
        'watching': value.watching.map((e) => e.toJson()).toList(),
        'planned': value.planned.map((e) => e.toJson()).toList(),
      });

  /// Refleja en la copia guardada el avance que MAL acaba de confirmar para
  /// [malId], sin volver a descargar las listas: actualiza los episodios
  /// vistos, pasa el anime de «Por ver» a «Viendo» y lo retira si se
  /// completó. Devuelve la copia nueva, o `null` si no cambia nada.
  Future<MalShelfSnapshot?> applyProgress(
    int owner,
    int malId,
    int watched,
    String status,
  ) async {
    final current = await cached(owner);
    if (current == null) return null;
    MalShelfItem? item;
    for (final candidate in [...current.watching, ...current.planned]) {
      if (candidate.entry.id == malId) item = candidate;
    }
    if (item == null) return null;
    final known = statuses.contains(status) || status.isEmpty;
    final entry = MalAnimeEntry.fromJson({
      ...item.entry.toJson(),
      'episodes_watched': watched,
      if (status.isNotEmpty) 'status': status,
    });
    if (entry.watched == item.entry.watched &&
        entry.status == item.entry.status) {
      return null;
    }
    final updated = MalShelfItem(entry, item.anime);
    List<MalShelfItem> list(List<MalShelfItem> items, String name) {
      final index = items.indexWhere((e) => e.entry.id == malId);
      final stays = known && entry.status == name;
      if (index >= 0) {
        return [
          for (var i = 0; i < items.length; i++)
            if (i != index) items[i] else if (stays) updated,
        ];
      }
      return stays ? [updated, ...items] : items;
    }

    final snapshot = MalShelfSnapshot(
      owner: owner,
      savedAt: current.savedAt,
      partial: current.partial,
      watching: list(current.watching, 'watching'),
      planned: list(current.planned, 'plan_to_watch'),
    );
    await _save(await database(), snapshot);
    return snapshot;
  }

  /// Descarga las dos listas, busca cada título en YomaTV y guarda el
  /// resultado. Las coincidencias ya conocidas no se vuelven a buscar.
  Future<MalShelfSnapshot> refresh(int owner) async {
    final store = await database();
    final lists = <String, List<MalShelfItem>>{};
    var failures = 0;
    for (final status in statuses) {
      final entries = <MalAnimeEntry>[];
      // La continuación la da el servidor; el tope de páginas solo protege
      // de una respuesta que nunca termina.
      int? offset = 0;
      for (var pages = 0; offset != null && pages < maxEntries ~/ 50; pages++) {
        final page = await mal.libraryPage(status: status, offset: offset);
        entries.addAll(page.items);
        offset = page.nextOffset;
      }
      // Tres búsquedas a la vez, igual que el máximo de conexiones a YomaTV;
      // se conserva el orden de la lista de MAL.
      final found = List<AnimeTitle?>.filled(entries.length, null);
      var next = 0;
      Future<void> worker() async {
        while (next < entries.length) {
          final index = next++;
          try {
            found[index] = await _match(
              store,
              entries[index],
              search: failures < maxSearchFailures,
            );
          } on _Unsearched {
            failures++;
          }
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
      partial: failures > 0,
    );
    await _save(store, snapshot);
    return snapshot;
  }

  /// Coincidencia guardada o buscada en YomaTV. Lanza [_Unsearched] si hay
  /// que buscar y no se puede (la fuente falla o [search] es `false`): ese
  /// título queda sin comprobar, no como «no existe».
  Future<AnimeTitle?> _match(
    LibraryStore store,
    MalAnimeEntry entry, {
    bool search = true,
  }) async {
    final key = 'match:${entry.id}';
    final known = animeMap(await store.getRecord(namespace, key));
    final checked = animeInt(known['checkedAt']);
    if (known['title'] == entry.title) {
      final anime = animeMap(known['anime']);
      if (anime.isNotEmpty) return AnimeTitle.fromJson(anime);
      final age = DateTime.now().millisecondsSinceEpoch - checked;
      if (age < retryMissing.inMilliseconds) return null;
    }
    if (!search) throw const _Unsearched();
    final AnimePage page;
    try {
      page = AnimePage.fromJson(await source.catalog(search: entry.title));
    } catch (_) {
      // Un fallo de YomaTV con un título no descarta la lista entera.
      throw const _Unsearched();
    }
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

/// Un título de MAL que no se pudo buscar en YomaTV en esta carga.
class _Unsearched implements Exception {
  const _Unsearched();
}
