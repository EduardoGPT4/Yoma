part of 'anime_controller.dart';

// AnimeController y lo que se está viendo: los animes de «Viendo» y
// «Plan to watch» de MyAnimeList entran en la biblioteca con su estado y
// quedan vinculados, y de los que están en «Viendo» (en la biblioteca o en
// MAL) se descargan solos los próximos episodios sin ver.
extension AnimeControllerWatching on AnimeController {
  /// Episodios ya pedidos por la descarga automática: no se vuelven a pedir,
  /// aunque el usuario borre o cancele la descarga.
  static const autoNamespace = 'anime_auto_downloads';

  /// Animes de la lista de MAL que ya entraron en la biblioteca y con qué
  /// estado: si el usuario los quita después, no se vuelven a añadir.
  static const adoptedNamespace = 'anime_mal_adopted';

  bool get autoDownload => settings['auto_download'] != false;
  int get autoDownloadAhead =>
      animeInt(settings['auto_download_ahead'], 2).clamp(1, 3);

  Future<void> setAutoDownload({bool? enabled, int? ahead}) async {
    settings = {
      ...settings,
      'auto_download': ?enabled,
      'auto_download_ahead': ?ahead,
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
}
