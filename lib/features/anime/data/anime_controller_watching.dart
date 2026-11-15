part of 'anime_controller.dart';

// AnimeController y lo que se está viendo: los animes de «Viendo» y
// «Plan to watch» de MyAnimeList entran en la biblioteca con su estado y
// quedan vinculados, de los que están en «Viendo» (en la biblioteca o en
// MAL) se descargan solos los próximos episodios sin ver, y las descargas
// de episodios vistos se borran solas una semana después.
extension AnimeControllerWatching on AnimeController {
  /// Episodios ya pedidos por la descarga automática: no se vuelven a pedir,
  /// aunque el usuario borre o cancele la descarga.
  static const autoNamespace = 'anime_auto_downloads';

  /// Animes de la lista de MAL que ya entraron en la biblioteca y con qué
  /// estado: si el usuario los quita después, no se vuelven a añadir.
  static const adoptedNamespace = 'anime_mal_adopted';

  /// Desde cuándo está visto el episodio de cada descarga.
  static const watchedNamespace = 'anime_watched_downloads';

  /// Tiempo que se conserva una descarga ya vista.
  static const keepWatched = Duration(days: 7);

  bool get autoDownload => settings['auto_download'] != false;
  bool get autoDeleteWatched => settings['auto_delete_watched'] != false;
  int get autoDownloadAhead =>
      animeInt(settings['auto_download_ahead'], 2).clamp(1, 3);

  Future<void> setAutoDownload({
    bool? enabled,
    int? ahead,
    bool? deleteWatched,
  }) async {
    settings = {
      ...settings,
      'auto_download': ?enabled,
      'auto_download_ahead': ?ahead,
      'auto_delete_watched': ?deleteWatched,
    };
    await store.saveSettings(settings);
    changed();
    _scheduleWatching();
  }

  /// Los próximos [autoDownloadAhead] episodios sin ver de [detail], después
  /// del más alto visto aquí o en MAL ([malWatched]).
  List<AnimeEpisode> autoDownloadCandidates(
    AnimeDetail detail, [
    int malWatched = 0,
  ]) {
    var highest = malWatched.toDouble();
    for (final row in positions.values) {
      if (row['slug'] != detail.anime.slug || row['watched'] != true) continue;
      final value = double.tryParse('${animeMap(row['episode'])['number']}');
      if (value != null && value > highest) highest = value;
    }
    return [
      for (final episode in detail.episodes)
        if ((double.tryParse(episode.number) ?? -1) > highest &&
            positions[episode.key]?['watched'] != true)
          episode,
    ].take(autoDownloadAhead).toList();
  }

  /// Vincula la lista de MAL con la biblioteca y pide las descargas de lo
  /// que se está viendo. Devuelve cuántos episodios se pidieron.
  Future<int> syncWatching() async {
    if (_disposed) return 0;
    if (_watchingBusy) {
      _watchingAgain = true;
      return 0;
    }
    _watchingBusy = true;
    try {
      await _adoptMalShelf();
      await _removeOldWatched();
      return await _downloadWatching();
    } finally {
      _watchingBusy = false;
      if (_watchingAgain && !_disposed) {
        _watchingAgain = false;
        unawaited(syncWatching());
      }
    }
  }

  /// «Viendo» y «Plan to watch» de MAL pasan a la biblioteca con ese estado
  /// y se vinculan con su entrada de MAL. Un anime de la biblioteca solo
  /// sube de Planeado a Viendo; nunca se cambia a la baja ni se vuelve a
  /// añadir uno que el usuario quitó.
  Future<void> _adoptMalShelf() async {
    if (_malShelfInterim) return;
    try {
      final owner = await mal.owner();
      if (owner <= 0) return;
      final db = await store.database();
      for (final (items, status) in [
        (malWatching, 'watching'),
        (malPlanned, 'planned'),
      ]) {
        for (final item in [...items]) {
          if (_disposed) return;
          final slug = item.anime.slug;
          if (await mal.linkOf(slug) == null) {
            await mal.autoLink(slug, item.entry);
          }
          final known = animeMap(await db.getRecord(adoptedNamespace, slug));
          final seen = animeInt(known['owner']) == owner;
          if (seen && known['status'] == status) continue;
          final row = saved[slug];
          if (row == null || row['saved'] != true) {
            if (!seen) {
              await updateLibrary(item.anime, savedValue: true, status: status);
            }
          } else if (status == 'watching' && row['status'] == 'planned') {
            await updateLibrary(item.anime, status: 'watching');
          }
          await db.putRecord(adoptedNamespace, slug, {
            'owner': owner,
            'status': status,
          });
        }
      }
    } catch (error) {
      debugPrint('Lista de MAL sin pasar a la biblioteca: $error');
    }
  }

  Future<int> _downloadWatching() async {
    if (!autoDownload || !supportedDownloads || !_downloadsKnown) return 0;
    final targets = <String, int>{
      for (final row in saved.values)
        if (row['saved'] == true && row['status'] == 'watching')
          '${row['slug']}': 0,
    };
    if (!_malShelfInterim) {
      for (final item in malWatching) {
        final slug = item.anime.slug;
        targets[slug] = max(targets[slug] ?? 0, item.entry.watched);
      }
    }
    final db = await store.database();
    final language = '${settings['language'] ?? 'SUB'}';
    var queued = 0;
    String? failure;
    for (final target in targets.entries) {
      if (_disposed || !autoDownload) break;
      final AnimeDetail detail;
      try {
        detail = await this.detail(target.key);
      } catch (error) {
        // Sin red no hay ficha: se intenta en la próxima ocasión.
        debugPrint('Ficha sin cargar para descargar ${target.key}: $error');
        continue;
      }
      for (final episode in autoDownloadCandidates(detail, target.value)) {
        if (await db.getRecord(autoNamespace, episode.key) != null) continue;
        if (downloads.any(
          (d) => d.slug == episode.slug && d.number == episode.number,
        )) {
          continue;
        }
        try {
          final outcome = await transfers.enqueue(
            detail.anime,
            episode,
            language,
          );
          await db.putRecord(autoNamespace, episode.key, {
            'at': DateTime.now().millisecondsSinceEpoch,
            'outcome': outcome,
          });
          queued++;
        } catch (error) {
          failure = animeErrorText(error);
        }
      }
    }
    if (queued > 0) {
      _lastSnapshot = null;
      await refreshDownloads();
    }
    if (failure != null && !_disposed) {
      downloadError = 'No se pudo descargar solo lo que estás viendo: $failure';
      changed();
    }
    return queued;
  }

  /// Borra las descargas de episodios vistos hace [keepWatched] o más.
  /// La semana cuenta desde que el teléfono ve el episodio como visto con
  /// su descarga: justo después de marcarlo aquí, o al recibirlo de MAL u
  /// otro dispositivo. Lo visto antes de esta versión empieza a contar al
  /// actualizar, así no se borra todo de golpe. Devuelve cuántas borró.
  Future<int> _removeOldWatched() async {
    if (!autoDeleteWatched || !supportedDownloads || !_downloadsKnown) {
      return 0;
    }
    final db = await store.database();
    final now = clock().millisecondsSinceEpoch;
    final old = <AnimeDownload>[];
    for (final d in [...downloads]) {
      final row = positions['${d.slug}:${d.number}'];
      final record = animeMap(await db.getRecord(watchedNamespace, d.key));
      if (row == null || row['watched'] != true) {
        // Desmarcado: vuelve a contar desde cero si se ve otra vez.
        if (record.isNotEmpty) await db.deleteRecord(watchedNamespace, d.key);
        continue;
      }
      var since = animeInt(record['since']);
      if (since <= 0) {
        since = now;
        await db.putRecord(watchedNamespace, d.key, {'since': since});
      }
      if (now - since >= keepWatched.inMilliseconds) old.add(d);
    }
    if (old.isEmpty) return 0;
    try {
      await removeDownloads(old);
      for (final d in old) {
        await db.deleteRecord(watchedNamespace, d.key);
      }
      return old.length;
    } catch (error) {
      if (!_disposed) {
        downloadError =
            'No se pudieron borrar los episodios vistos: '
            '${animeErrorText(error)}';
        changed();
      }
      return 0;
    }
  }

  /// Un episodio desmarcado deja de contar como visto para el borrado.
  Future<void> _forgetWatched(AnimeEpisode episode) async {
    final db = await store.database();
    for (final d in downloads) {
      if (d.slug == episode.slug && d.number == episode.number) {
        await db.deleteRecord(watchedNamespace, d.key);
      }
    }
  }
}
