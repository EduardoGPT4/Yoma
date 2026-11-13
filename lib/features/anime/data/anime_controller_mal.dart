part of 'anime_controller.dart';

// AnimeController y MyAnimeList: la lista de MAL (estantería), los vínculos de
// cada anime y los episodios vistos en ambos sentidos. Comparte el estado del
// controlador y notifica con changed().
extension AnimeControllerMal on AnimeController {
  void _applyMalShelf(MalShelfSnapshot? value) {
    malWatching = value?.watching ?? [];
    malPlanned = value?.planned ?? [];
    malShelfSavedAt = value?.savedAt;
    malShelfPartial = value?.partial ?? false;
    _malWatchingAll = value?.watchingAll ?? const {};
    _malShelfInterim = false;
    // También sin coincidencias por nombre: puede haber vínculos a mano.
    if (value != null && (!value.isEmpty || value.watchingAll.isNotEmpty)) {
      unawaited(_syncWatchedFromShelf());
    }
  }

  /// Entrada de MAL («Viendo» o «Plan to watch») que coincide por nombre
  /// exacto con [slug]; usa la copia guardada si aún no se ha cargado.
  Future<MalAnimeEntry?> malMatchFor(String slug) async {
    MalAnimeEntry? find(List<MalShelfItem> items) {
      for (final item in items) {
        if (item.anime.slug == slug) return item.entry;
      }
      return null;
    }

    if (_malShelfInterim) return null;
    final known = find(malWatching) ?? find(malPlanned);
    if (known != null || malShelfSavedAt != null) return known;
    final cached = await malShelf.cached(await mal.owner());
    if (cached == null) return null;
    return find(cached.watching) ?? find(cached.planned);
  }

  /// Vincula [slug] con su anime de la lista de MAL si aún no lo está.
  Future<bool> _ensureMalLink(String slug) async {
    if (await mal.linkOf(slug) != null) return true;
    final entry = await malMatchFor(slug);
    if (entry == null) return false;
    return mal.autoLink(slug, entry);
  }

  /// Episodio vistos más alto guardado en el teléfono para [slug].
  int _localWatched(String slug) {
    var watched = 0;
    for (final row in positions.values) {
      if (row['slug'] != slug || row['watched'] != true) continue;
      final number = malEpisodeCount('${animeMap(row['episode'])['number']}');
      if (number > watched) watched = number;
    }
    return watched;
  }

  /// Animes de la lista de MAL que ya se vieron en YomaTV sin vincular: se
  /// vinculan y se envía el avance local. MAL nunca baja: si allí hay más
  /// episodios vistos, se conserva su número.
  Future<void> _syncWatchedFromShelf() async {
    if (_syncingShelf || _disposed) return;
    _syncingShelf = true;
    try {
      // Primero lo que MAL ya tiene visto pasa al teléfono; después lo visto
      // solo en el teléfono sube a MAL.
      await _pullWatchedFromShelf();
      var queued = false;
      for (final item in [...malWatching, ...malPlanned]) {
        final slug = item.anime.slug;
        final watched = _localWatched(slug);
        if (watched <= item.entry.watched) continue;
        if (await mal.linkOf(slug) == null &&
            !await mal.autoLink(slug, item.entry)) {
          continue;
        }
        await mal.queueWatched(slug, watched);
        queued = true;
      }
      if (queued) await syncMal();
    } catch (error) {
      malError = '${AnimeController._malUnsent} $error';
      changed();
    } finally {
      _syncingShelf = false;
    }
  }

  /// Los animes de «Viendo» en MAL quedan vinculados y sus episodios vistos
  /// en MAL se marcan como vistos en YomaTV. Solo añade: nunca desmarca lo
  /// visto en el teléfono, no toca los episodios que el usuario desmarcó y
  /// no actúa si hay un envío a MAL pendiente (lo del teléfono es más nuevo).
  Future<void> _pullWatchedFromShelf() async {
    if (_malShelfInterim) return;
    // Coincidencias por nombre y, además, los animes vinculados a mano cuya
    // entrada está en «Viendo» aunque el nombre no coincida.
    final targets = <String, MalAnimeEntry>{
      for (final item in malWatching) item.anime.slug: item.entry,
    };
    try {
      for (final link in (await mal.linkedIds()).entries) {
        final entry = _malWatchingAll[link.value];
        if (entry != null) targets.putIfAbsent(link.key, () => entry);
      }
    } catch (error) {
      debugPrint('Vínculos de MAL sin leer: $error');
    }
    for (final target in targets.entries) {
      if (_disposed) return;
      try {
        await applyMalProgress(target.key, target.value);
      } catch (error) {
        // Sin red la ficha no se obtiene: se reintenta en la próxima carga.
        debugPrint('MAL → YomaTV sin aplicar para ${target.key}: $error');
      }
    }
  }

  /// Marca como vistos en YomaTV los episodios de [slug] que [entry] (su
  /// entrada de MAL) ya tiene vistos, y lo vincula si aún no lo está. No
  /// hace nada si [slug] está vinculado con otra entrada o si hay un envío
  /// pendiente. Devuelve cuántos episodios se marcaron.
  Future<int> applyMalProgress(String slug, MalAnimeEntry entry) async {
    final count = entry.watched;
    if (count <= 0) return 0;
    final link = await mal.linkOf(slug);
    if (link != null && animeInt(link['malId']) != entry.id) return 0;
    if (await mal.hasPending(slug)) return 0;
    if (link == null) {
      if (!await mal.autoLink(slug, entry)) return 0;
    } else {
      await mal.observeRemote(slug, count);
    }
    if (!_missingFromMal(slug, count)) return 0;
    final detail = await this.detail(slug);
    final episodes = [
      for (final episode in detail.episodes)
        if (_countsAsWatched(episode.number, count) &&
            positions[episode.key]?['watched'] != true &&
            positions[episode.key]?['unmarked'] != true)
          episode,
    ];
    if (episodes.isEmpty) return 0;
    final rows = await store.markWatchedFromMal(detail.anime, episodes);
    for (final row in rows) {
      positions[AnimeEpisode.fromJson(animeMap(row['episode'])).key] = row;
    }
    if (rows.isNotEmpty) changed();
    return rows.length;
  }

  /// El episodio [number] queda dentro de los [count] vistos en MAL.
  static bool _countsAsWatched(String number, int count) {
    final value = double.tryParse(number);
    return value != null && value >= 1 && value <= count;
  }

  /// Falta en el teléfono algún episodio que MAL ya tiene visto.
  bool _missingFromMal(String slug, int count) {
    final seen = <int>{};
    for (final row in positions.values) {
      if (row['slug'] != slug) continue;
      final value = double.tryParse('${animeMap(row['episode'])['number']}');
      if (value == null || value != value.floorToDouble()) continue;
      if (row['watched'] == true || row['unmarked'] == true) {
        seen.add(value.toInt());
      }
    }
    for (var n = 1; n <= count; n++) {
      if (!seen.contains(n)) return true;
    }
    return false;
  }

  /// Muestra al instante la copia guardada y solo consulta MAL si tiene más
  /// de [maxAge] (por defecto [AnimeMalShelf.maxAge]) o si se pide con
  /// [force].
  Future<void> loadMalShelf({bool force = false, Duration? maxAge}) async {
    try {
      final owner = await mal.owner();
      if (_disposed) return;
      if (owner <= 0) {
        if (_malShelfOwner != 0 || malShelfSavedAt != null) {
          _malShelfOwner = 0;
          _applyMalShelf(null);
          changed();
        }
        return;
      }
      if (owner != _malShelfOwner) {
        _malShelfOwner = owner;
        _applyMalShelf(await malShelf.cached(owner));
        malShelfError = null;
        changed();
      }
      final saved = malShelfSavedAt;
      // Una copia a la que le faltan búsquedas se completa pronto.
      final fresh =
          saved != null &&
          DateTime.now().difference(saved) <
              (malShelfPartial
                  ? AnimeMalShelf.retryPartial
                  : maxAge ?? AnimeMalShelf.maxAge);
      if (fresh && !force) return;
      await (_malShelfTask ??= _refreshMalShelf(
        owner,
      ).whenComplete(() => _malShelfTask = null));
    } catch (e) {
      malShelfError = e.toString();
      changed();
    }
  }

  Future<void> _refreshMalShelf(int owner) async {
    malShelfLoading = true;
    changed();
    try {
      if (!await mal.available()) return;
      final snapshot = await malShelf.refresh(
        owner,
        onProgress: (interim) {
          // Solo en la primera carga: lo ya guardado no se sustituye por
          // una lista a medio comprobar.
          if (_disposed ||
              _malShelfOwner != owner ||
              malShelfSavedAt != null ||
              interim.isEmpty) {
            return;
          }
          malWatching = interim.watching;
          malPlanned = interim.planned;
          _malShelfInterim = true;
          changed();
        },
      );
      if (_disposed || _malShelfOwner != owner) return;
      _applyMalShelf(snapshot);
      malShelfError = snapshot.partial
          ? 'YomaTV no respondió al buscar algunos animes de tu lista; '
                'se volverá a intentar.'
          : null;
    } catch (e) {
      // La copia guardada sigue visible aunque MAL o YomaTV no respondan.
      malShelfError = 'No se pudo actualizar tu lista de MyAnimeList: $e';
      // Una lista a medio comprobar no se deja en pantalla.
      if (_malShelfInterim) {
        malWatching = [];
        malPlanned = [];
        _malShelfInterim = false;
      }
    } finally {
      malShelfLoading = false;
      changed();
    }
  }

  /// Vincula [slug] con su anime de MAL al empezar a verlo desde la sección
  /// de MyAnimeList, para que los episodios vistos se sincronicen. Devuelve
  /// `true` si se creó una vinculación nueva; nunca sustituye una existente.
  Future<bool> autoLinkMal(String slug, MalAnimeEntry entry) async {
    if (_malShelfInterim || await mal.linkOf(slug) != null) return false;
    if (!await mal.autoLink(slug, entry)) return false;
    final watched = _localWatched(slug);
    if (watched > 0) {
      await mal.queueWatched(slug, watched);
      await syncMal();
    }
    return true;
  }

  /// Quita el vínculo de [slug] con MyAnimeList (ver [AnimeMalClient.unlink]).
  Future<void> unlinkMal(String slug) async {
    await mal.unlink(slug);
    malLinkChanges.value++;
    changed();
  }
}
