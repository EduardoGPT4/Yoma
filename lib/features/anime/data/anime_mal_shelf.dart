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

  /// Toda la lista «Viendo» de MAL por id, coincida o no con un nombre de
  /// YomaTV: sirve para los animes vinculados a mano.
  final Map<int, MalAnimeEntry> watchingAll;
  const MalShelfSnapshot({
    required this.owner,
    required this.savedAt,
    required this.watching,
    required this.planned,
    this.partial = false,
    this.watchingAll = const {},
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
      watchingAll: _entries(row['watchingAll']),
    );
  }

  static Map<int, MalAnimeEntry> _entries(Object? value) => {
    for (final row in value as List? ?? const [])
      if (animeInt(animeMap(row)['id']) > 0)
        animeInt(animeMap(row)['id']): MalAnimeEntry.fromJson(animeMap(row)),
  };

  Future<void> _save(LibraryStore store, MalShelfSnapshot value) =>
      store.putRecord(namespace, 'shelf:${value.owner}', {
        'owner': value.owner,
        'savedAt': value.savedAt.millisecondsSinceEpoch,
        'partial': value.partial,
        'watching': value.watching.map((e) => e.toJson()).toList(),
        'planned': value.planned.map((e) => e.toJson()).toList(),
        'watchingAll': value.watchingAll.values.map((e) => e.toJson()).toList(),
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
    // Un anime vinculado a mano solo está en la lista completa.
    final listed = current.watchingAll[malId];
    final all = {...current.watchingAll};
    if (listed != null) {
      if (status.isEmpty || status == 'watching') {
        all[malId] = MalAnimeEntry.fromJson({
          ...listed.toJson(),
          'episodes_watched': watched,
        });
      } else {
        all.remove(malId);
      }
    }
    if (item == null) {
      if (listed == null || listed.watched == watched && status.isEmpty) {
        return null;
      }
      final snapshot = MalShelfSnapshot(
        owner: owner,
        savedAt: current.savedAt,
        partial: current.partial,
        watching: current.watching,
        planned: current.planned,
        watchingAll: all,
      );
      await _save(await database(), snapshot);
      return snapshot;
    }
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
      watchingAll: all,
    );
    await _save(await database(), snapshot);
    return snapshot;
  }

  /// Dos obras con el mismo título no son la misma si YomaTV ya publica más
  /// episodios de los que la obra tiene en MAL, o si se estrenaron con años
  /// de diferencia (un remake). Sin esos datos no se descarta nada.
  static bool compatible(MalAnimeEntry entry, AnimeTitle anime) {
    // Margen de 2: YomaTV a veces numera un resumen o un especial.
    if (entry.total > 0 && anime.episodes > entry.total + 2) return false;
    final year = int.tryParse(anime.year) ?? 0;
    if (entry.year > 0 && year > 0 && (entry.year - year).abs() > 1) {
      return false;
    }
    return true;
  }

  /// Título normalizado → animes del índice público de YomaTV: slug, título
  /// y categoría de todo el catálogo en una sola consulta. `null` si no
  /// está disponible; entonces se busca título por título.
  Future<Map<String, List<AnimeTitle>>?> _index() async {
    try {
      final items = (await source.publicIndex())['items'];
      if (items is! List || items.isEmpty) return null;
      final index = <String, List<AnimeTitle>>{};
      for (final row in items) {
        final anime = AnimeTitle.fromJson(animeMap(row));
        if (anime.slug.isEmpty) continue;
        (index[normalize(anime.title)] ??= []).add(anime);
      }
      return index;
    } catch (_) {
      return null;
    }
  }

  /// Descarga las dos listas, las empareja con YomaTV y guarda el resultado.
  ///
  /// Las coincidencias ya conocidas salen del teléfono. Para el resto, el
  /// índice público dice en una sola consulta qué títulos existen: los que
  /// no están no se buscan, y los que sí se muestran enseguida con
  /// [onProgress] mientras se pide su ficha (portada, episodios y año) para
  /// comprobar que es la misma obra.
  Future<MalShelfSnapshot> refresh(
    int owner, {
    void Function(MalShelfSnapshot interim)? onProgress,
  }) async {
    final store = await database();
    final lists = <String, List<MalAnimeEntry>>{};
    for (final status in statuses) {
      final entries = lists[status] = <MalAnimeEntry>[];
      // La continuación la da el servidor; el tope de páginas solo protege
      // de una respuesta que nunca termina.
      int? offset = 0;
      for (var pages = 0; offset != null && pages < maxEntries ~/ 50; pages++) {
        final page = await mal.libraryPage(status: status, offset: offset);
        entries.addAll(page.items);
        offset = page.nextOffset;
      }
    }
    MalShelfSnapshot build(
      Map<int, AnimeTitle> matches, {
      bool partial = false,
    }) {
      List<MalShelfItem> items(String status) => [
        for (final entry in lists[status]!)
          if (matches[entry.id] != null)
            MalShelfItem(entry, matches[entry.id]!),
      ];
      return MalShelfSnapshot(
        owner: owner,
        savedAt: DateTime.now(),
        watching: items('watching'),
        planned: items('plan_to_watch'),
        partial: partial,
        watchingAll: {for (final entry in lists['watching']!) entry.id: entry},
      );
    }

    // Id de MAL → anime de YomaTV comprobado.
    final found = <int, AnimeTitle>{};
    var pending = <MalAnimeEntry>[];
    for (final entry in [for (final status in statuses) ...lists[status]!]) {
      final known = await _known(store, entry);
      if (!known.settled) {
        pending.add(entry);
      } else if (known.anime != null) {
        found[entry.id] = known.anime!;
      }
    }
    var failures = 0;
    if (pending.isNotEmpty) {
      final index = await _index();
      if (index != null) {
        final interim = <int, AnimeTitle>{};
        final listed = <MalAnimeEntry>[];
        for (final entry in pending) {
          final candidates = index[normalize(entry.title)];
          if (candidates == null) {
            // No está en el catálogo: no hace falta buscarlo.
            await _remember(store, entry, null);
            continue;
          }
          if (candidates.length == 1) interim[entry.id] = candidates.single;
          listed.add(entry);
        }
        pending = listed;
        if (interim.isNotEmpty) {
          onProgress?.call(build({...found, ...interim}, partial: true));
        }
      }
      // Tres búsquedas a la vez, igual que el máximo de conexiones a YomaTV.
      var next = 0;
      Future<void> worker() async {
        while (next < pending.length) {
          final entry = pending[next++];
          if (failures >= maxSearchFailures) {
            failures++;
            continue;
          }
          try {
            final anime = await _search(store, entry);
            if (anime != null) found[entry.id] = anime;
          } on _Unsearched {
            failures++;
          }
        }
      }

      await Future.wait([for (var i = 0; i < 3; i++) worker()]);
    }
    // Dos entradas de la lista que apuntan al mismo anime de YomaTV: no se
    // puede saber cuál es, así que no se vincula ninguna.
    final uses = <String, int>{};
    for (final anime in found.values) {
      uses[anime.slug] = (uses[anime.slug] ?? 0) + 1;
    }
    found.removeWhere((_, anime) => uses[anime.slug]! > 1);
    if (await mal.owner() != owner) {
      throw StateError('La cuenta de MyAnimeList cambió durante la carga.');
    }
    final snapshot = build(found, partial: failures > 0);
    await _save(store, snapshot);
    return snapshot;
  }

  /// Lo que el teléfono ya sabe de [entry]: `settled` si no hay que volver a
  /// buscarlo (coincidencia guardada, o ausencia reciente).
  Future<({bool settled, AnimeTitle? anime})> _known(
    LibraryStore store,
    MalAnimeEntry entry,
  ) async {
    final known = animeMap(
      await store.getRecord(namespace, 'match:${entry.id}'),
    );
    if (known['title'] != entry.title) return (settled: false, anime: null);
    final anime = animeMap(known['anime']);
    if (anime.isNotEmpty) {
      // Una coincidencia guardada también debe seguir siendo la misma obra.
      final title = AnimeTitle.fromJson(anime);
      return (settled: true, anime: compatible(entry, title) ? title : null);
    }
    final age =
        DateTime.now().millisecondsSinceEpoch - animeInt(known['checkedAt']);
    return (settled: age < retryMissing.inMilliseconds, anime: null);
  }

  Future<void> _remember(
    LibraryStore store,
    MalAnimeEntry entry,
    AnimeTitle? found,
  ) => store.putRecord(namespace, 'match:${entry.id}', {
    'title': entry.title,
    'anime': found?.toJson(),
    'checkedAt': DateTime.now().millisecondsSinceEpoch,
  });

  /// Busca [entry] en YomaTV. Lanza [_Unsearched] si la fuente falla: ese
  /// título queda sin comprobar, no como «no existe».
  Future<AnimeTitle?> _search(LibraryStore store, MalAnimeEntry entry) async {
    final AnimePage page;
    try {
      page = AnimePage.fromJson(await source.catalog(search: entry.title));
    } catch (_) {
      // Un fallo de YomaTV con un título no descarta la lista entera.
      throw const _Unsearched();
    }
    final matches = [
      for (final item in page.items)
        if (sameName(entry.title, item) && compatible(entry, item)) item,
    ];
    // Varias obras de YomaTV con ese nombre: no se elige una al azar.
    final found = matches.length == 1 ? matches.single : null;
    await _remember(store, entry, found);
    return found;
  }
}

/// Un título de MAL que no se pudo buscar en YomaTV en esta carga.
class _Unsearched implements Exception {
  const _Unsearched();
}
