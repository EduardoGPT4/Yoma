import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import '../models/anime_models.dart';
import 'anime_local_store.dart';
import 'anime_mal_client.dart';
import 'anime_mal_shelf.dart';
import 'local_anime_downloads.dart';
import 'yomatv_source.dart';

class AnimeController extends ChangeNotifier {
  final AnimeMalClient mal;
  String? malError;
  final YomaTvSource source;
  final AnimeLocalStore store;
  final LocalAnimeDownloads transfers;

  /// Avisa de cada cambio de red con `true` si hay conexión; al volver la
  /// conexión se envían a MAL los episodios vistos sin internet.
  final Stream<bool> Function() connectivity;

  /// Tiempo tras el que una ficha ya abierta en esta sesión se vuelve a
  /// pedir a YomaTV en segundo plano (episodios nuevos de un anime en emisión).
  final Duration detailMaxAge;

  AnimeController({
    YomaTvSource? source,
    AnimeMalClient? mal,
    AnimeLocalStore? store,
    LocalAnimeDownloads? transfers,
    Stream<bool> Function()? connectivity,
    this.detailMaxAge = const Duration(minutes: 10),
  }) : connectivity = connectivity ?? _deviceConnectivity,
       mal = mal ?? AnimeMalClient(),
       source = source ?? YomaTvSource(),
       store = store ?? AnimeLocalStore(),
       transfers = transfers ?? LocalAnimeDownloads() {
    this.mal.onRemoteProgress = _malProgressConfirmed;
  }
  bool _disposed = false;

  /// MAL confirmó un avance: la sección de MyAnimeList lo refleja al
  /// instante en vez de esperar a la próxima descarga de las listas.
  void _malProgressConfirmed(int malId, int watched, String status) {
    if (_disposed) return;
    unawaited(() async {
      try {
        final owner = await mal.owner();
        final updated = await malShelf.applyProgress(
          owner,
          malId,
          watched,
          status,
        );
        if (updated == null || _disposed || owner != _malShelfOwner) return;
        malWatching = updated.watching;
        malPlanned = updated.planned;
        changed();
      } catch (error) {
        debugPrint('Lista de MAL sin actualizar: $error');
      }
    }());
  }

  StreamSubscription<bool>? _network;

  static Stream<bool> _deviceConnectivity() => Connectivity()
      .onConnectivityChanged
      .map((results) => results.any((r) => r != ConnectivityResult.none));

  /// «Viendo» y «Plan to watch» de MAL que existen en YomaTV.
  late final AnimeMalShelf malShelf = AnimeMalShelf(mal: mal, source: source);
  List<MalShelfItem> malWatching = [], malPlanned = [];
  DateTime? malShelfSavedAt;
  bool malShelfPartial = false;
  bool malShelfLoading = false;
  String? malShelfError;
  int _malShelfOwner = 0;
  Future<void>? _malShelfTask;
  final activity = ValueNotifier<bool>(true);
  String? _lastSnapshot;
  bool loading = true, searching = false, loadingMore = false;
  bool supportedDownloads = false, paused = false, wifiOnly = true;
  String? error, downloadError;
  AnimePage? catalog, front;
  final List<AnimeTitle> catalogItems = [];
  final Map<String, Map<String, dynamic>> saved = {}, positions = {};
  final Map<String, AnimeDetail> details = {};
  List<AnimeDownload> downloads = [];
  Map<String, dynamic> settings = {};
  String query = '',
      category = '',
      season = '',
      year = '',
      genre = '',
      order = 'recent';
  bool seasonal = false;
  int tab = 0, _generation = 0;
  Timer? _poll;
  bool _snapshotBusy = false;
  void changed() {
    if (!_disposed) notifyListeners();
  }

  Future<void> initialize() async {
    try {
      final rows = await store.library();
      for (final row in rows) {
        saved['${row['slug']}'] = row;
      }
      final history = await store.progress();
      for (final row in history) {
        final ep = AnimeEpisode.fromJson(animeMap(row['episode']));
        positions[ep.key] = row;
      }
      settings = await store.settings();
      final nav = await store.navigation();
      query = '${nav['query'] ?? ''}';
      category = '${nav['category'] ?? ''}';
      season = '${nav['season'] ?? ''}';
      year = '${nav['year'] ?? ''}';
      genre = '${nav['genre'] ?? ''}';
      order = '${nav['order'] ?? 'recent'}';
      seasonal = nav['seasonal'] == true;
      tab = animeInt(nav['tab']).clamp(0, 4);
      final cached = await store.cache('front');
      if (cached != null) front = AnimePage.fromJson(animeMap(cached['data']));
    } catch (e) {
      error = 'No se pudieron abrir algunos datos locales: $e';
    }
    if (_disposed) return;
    loading = false;
    mal.client.sessionChanges.addListener(_sessionChanged);
    _listenForNetwork();
    unawaited(syncMal());
    unawaited(loadMalShelf());
    changed();
    unawaited(loadFront());
    unawaited(search());
    unawaited(_migrateDownloads());
  }

  /// Los episodios pasan una vez a Yoma/YomaTV/Anime; después se actualiza la
  /// lista para que muestre la ubicación nueva.
  Future<void> _migrateDownloads() async {
    String? failure;
    try {
      await transfers.migrate();
    } catch (e) {
      failure = 'No se pudieron mover los episodios a Yoma/YomaTV: $e';
    }
    await refreshDownloads();
    // La actualización limpia los errores; el de la migración se conserva.
    if (failure != null && !_disposed) {
      downloadError = failure;
      changed();
    }
  }

  /// Los episodios vistos sin conexión (por ejemplo en Descargas) quedan en
  /// la cola de MAL del teléfono; se suben solos cuando vuelve internet.
  void _listenForNetwork() {
    try {
      _network = connectivity().listen((online) {
        if (online && !_disposed) unawaited(syncMal());
      }, onError: (Object error) => debugPrint('Conectividad: $error'));
    } catch (error) {
      debugPrint('Conectividad opcional: $error');
    }
  }

  void _sessionChanged() {
    if (_disposed) return;
    unawaited(syncMal());
    unawaited(loadMalShelf());
  }

  void _applyMalShelf(MalShelfSnapshot? value) {
    malWatching = value?.watching ?? [];
    malPlanned = value?.planned ?? [];
    malShelfSavedAt = value?.savedAt;
    malShelfPartial = value?.partial ?? false;
    if (value != null && !value.isEmpty) unawaited(_syncWatchedFromShelf());
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
    await mal.link(slug, entry);
    return true;
  }

  /// Episodio vistos más alto guardado en el teléfono para [slug].
  int _localWatched(String slug) {
    var watched = 0;
    for (final row in positions.values) {
      if (row['slug'] != slug || row['watched'] != true) continue;
      final number = int.tryParse('${animeMap(row['episode'])['number']}') ?? 0;
      if (number > watched) watched = number;
    }
    return watched;
  }

  bool _syncingShelf = false;

  /// Animes de la lista de MAL que ya se vieron en YomaTV sin vincular: se
  /// vinculan y se envía el avance local. MAL nunca baja: si allí hay más
  /// episodios vistos, se conserva su número.
  Future<void> _syncWatchedFromShelf() async {
    if (_syncingShelf || _disposed) return;
    _syncingShelf = true;
    try {
      var queued = false;
      for (final item in [...malWatching, ...malPlanned]) {
        final slug = item.anime.slug;
        final watched = _localWatched(slug);
        if (watched <= item.entry.watched) continue;
        if (await mal.linkOf(slug) == null) await mal.link(slug, item.entry);
        await mal.queueWatched(slug, watched);
        queued = true;
      }
      if (queued) await syncMal();
    } catch (error) {
      malError = 'Progreso local guardado; MAL pendiente: $error';
      changed();
    } finally {
      _syncingShelf = false;
    }
  }

  /// Muestra al instante la copia guardada y solo consulta MAL si tiene más
  /// de [AnimeMalShelf.maxAge] o si se pide con [force].
  Future<void> loadMalShelf({bool force = false}) async {
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
                  : AnimeMalShelf.maxAge);
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
      final snapshot = await malShelf.refresh(owner);
      if (_disposed || _malShelfOwner != owner) return;
      _applyMalShelf(snapshot);
      malShelfError = snapshot.partial
          ? 'YomaTV no respondió al buscar algunos animes de tu lista; '
                'se volverá a intentar.'
          : null;
    } catch (e) {
      // La copia guardada sigue visible aunque MAL o YomaTV no respondan.
      malShelfError = 'No se pudo actualizar tu lista de MyAnimeList: $e';
    } finally {
      malShelfLoading = false;
      changed();
    }
  }

  /// Vincula [slug] con su anime de MAL al empezar a verlo desde la sección
  /// de MyAnimeList, para que los episodios vistos se sincronicen. Devuelve
  /// `true` si se creó una vinculación nueva; nunca sustituye una existente.
  Future<bool> autoLinkMal(String slug, MalAnimeEntry entry) async {
    if (await mal.linkOf(slug) != null) return false;
    await mal.link(slug, entry);
    final watched = _localWatched(slug);
    if (watched > 0) {
      await mal.queueWatched(slug, watched);
      await syncMal();
    }
    return true;
  }

  void setActive(bool active) {
    activity.value = active;
    _poll?.cancel();
    if (active && !_disposed) {
      unawaited(refreshDownloads());
      unawaited(syncMal());
      unawaited(loadMalShelf());
    }
  }

  void _scheduleDownloads() {
    _poll?.cancel();
    if (_disposed ||
        !activity.value ||
        paused ||
        !downloads.any(
          (d) =>
              {'queued', 'retry', 'downloading', 'verifying'}.contains(d.state),
        )) {
      return;
    }
    _poll = Timer.periodic(
      const Duration(seconds: 2),
      (_) => unawaited(refreshDownloads()),
    );
  }

  Future<void> loadFront() async {
    try {
      final data = await source.catalog();
      if (_disposed) return;
      front = AnimePage.fromJson(data);
      await store.putCache('front', data);
      changed();
    } catch (e) {
      if (!_disposed) {
        error = e.toString();
        changed();
      }
    }
  }

  Map<String, dynamic> get navigation => {
    'tab': tab,
    'query': query,
    'category': category,
    'season': season,
    'year': year,
    'genre': genre,
    'order': order,
    'seasonal': seasonal,
  };
  Future<void> remember() async => store.saveNavigation(navigation);
  void selectTab(int value) {
    tab = value;
    unawaited(remember());
    changed();
  }

  Future<void> search() async {
    final generation = ++_generation;
    searching = true;
    error = null;
    catalogItems.clear();
    changed();
    final snapshot = navigation;
    final key = store.queryKey({...snapshot}..remove('tab'));
    try {
      final cache = await store.cache('catalog:$key');
      if (cache != null && generation == _generation && !_disposed) {
        catalog = AnimePage.fromJson(animeMap(cache['data']));
        catalogItems.addAll(catalog!.items);
        changed();
      }
      final data = await source.catalog(
        search: '${snapshot['query']}',
        category: '${snapshot['category']}',
        season: '${snapshot['season']}',
        year: '${snapshot['year']}',
        genre: '${snapshot['genre']}',
        order: '${snapshot['order']}',
        seasonal: snapshot['seasonal'] == true,
      );
      if (generation != _generation || _disposed) return;
      catalog = AnimePage.fromJson(data);
      catalogItems
        ..clear()
        ..addAll(catalog!.items);
      await store.putCache('catalog:$key', data);
    } catch (e) {
      if (generation == _generation && !_disposed) error = e.toString();
    } finally {
      if (generation == _generation && !_disposed) {
        searching = false;
        changed();
      }
    }
    unawaited(remember());
  }

  Future<void> more() async {
    if (loadingMore ||
        searching ||
        catalog == null ||
        catalog!.page >= catalog!.pages) {
      return;
    }
    loadingMore = true;
    final generation = _generation;
    changed();
    try {
      final data = await source.catalog(
        page: catalog!.page + 1,
        search: query,
        category: category,
        season: season,
        year: year,
        genre: genre,
        order: order,
        seasonal: seasonal,
      );
      if (generation != _generation || _disposed) return;
      final page = AnimePage.fromJson(data);
      final ids = catalogItems.map((e) => e.slug).toSet();
      catalogItems.addAll(page.items.where((e) => ids.add(e.slug)));
      catalog = page;
    } catch (e) {
      if (!_disposed) error = e.toString();
    } finally {
      if (!_disposed) {
        loadingMore = false;
        changed();
      }
    }
  }

  /// Última vez que se pidió cada ficha a YomaTV en esta sesión.
  final Map<String, DateTime> _detailChecked = {};

  Future<AnimeDetail> detail(String slug, {bool refresh = false}) async {
    final known = details[slug];
    if (!refresh && known != null) {
      // La ficha en memoria se muestra al instante, pero no para siempre:
      // un anime en emisión recibe episodios con la app abierta durante días.
      final checked = _detailChecked[slug];
      if (checked == null ||
          DateTime.now().difference(checked) >= detailMaxAge) {
        _detailChecked[slug] = DateTime.now();
        unawaited(detail(slug, refresh: true).catchError((Object _) => known));
      }
      return known;
    }
    final cached = await store.cache('detail:$slug');
    if (!refresh && cached != null) {
      final detail = AnimeDetail.fromJson(animeMap(cached['data']));
      details[slug] = detail;
      _detailChecked[slug] = DateTime.now();
      // Return persistent metadata immediately, including when the device is offline.
      unawaited(
        this.detail(slug, refresh: true).catchError((Object _) => detail),
      );
      return detail;
    }
    try {
      final data = await source.detail(slug);
      final detail = AnimeDetail.fromJson(data);
      details[slug] = detail;
      _detailChecked[slug] = DateTime.now();
      await store.putCache('detail:$slug', data);
      if (refresh) changed();
      return detail;
    } catch (e) {
      if (cached != null) {
        final detail = AnimeDetail.fromJson(animeMap(cached['data']));
        details[slug] = detail;
        return detail;
      }
      rethrow;
    }
  }

  bool isSaved(String slug) => saved[slug]?['saved'] == true;
  bool isFavorite(String slug) => saved[slug]?['favorite'] == true;
  List<Map<String, dynamic>> get history =>
      positions.values
          .where((e) => animeInt(e['positionMs']) > 0 || e['watched'] == true)
          .toList()
        ..sort(
          (a, b) =>
              animeInt(b['updatedAt']).compareTo(animeInt(a['updatedAt'])),
        );

  /// Un episodio a medias por anime, y solo si es lo último que se abrió de
  /// él: si después se terminó otro episodio, uno anterior que quedó a
  /// medias ya no es por donde se continúa.
  List<Map<String, dynamic>> get continuing {
    final slugs = <String>{};
    return history
        .where(
          (e) =>
              slugs.add('${e['slug']}') &&
              e['watched'] != true &&
              animeInt(e['positionMs']) > 0,
        )
        .toList();
  }

  /// Episodio con el que sigue «Reproducir» en la ficha: el último que se
  /// abrió o, si ya se vio completo, el siguiente que falta por ver.
  AnimeEpisode? resumeEpisode(AnimeDetail detail) {
    final episodes = detail.episodes;
    if (episodes.isEmpty) return null;
    for (final row in history) {
      if (row['slug'] != detail.anime.slug) continue;
      final last = AnimeEpisode.fromJson(animeMap(row['episode']));
      var index = episodes.indexWhere((e) => e.id == last.id);
      if (index < 0) {
        index = episodes.indexWhere((e) => e.number == last.number);
      }
      if (index < 0) break;
      if (row['watched'] != true) return episodes[index];
      for (final next in episodes.skip(index + 1)) {
        if (positions[next.key]?['watched'] != true) return next;
      }
      return episodes[index];
    }
    return episodes.first;
  }

  Future<void> updateLibrary(
    AnimeTitle anime, {
    bool? savedValue,
    bool? favorite,
    String? status,
    int? score,
    String? notes,
  }) async {
    final old = saved[anime.slug] ?? {};
    final item = {
      'slug': anime.slug,
      'anime': anime.toJson(),
      'saved': savedValue ?? old['saved'] == true,
      'favorite': favorite ?? old['favorite'] == true,
      'status': status ?? old['status'] ?? 'planned',
      'score': score ?? old['score'] ?? 0,
      'notes': notes ?? old['notes'] ?? '',
    };
    await store.saveLibrary(
      anime,
      saved: item['saved'] == true,
      favorite: item['favorite'] == true,
      status: '${item['status']}',
      score: animeInt(item['score']),
      notes: '${item['notes']}',
    );
    saved[anime.slug] = item;
    changed();
  }

  Future<void> progress(
    AnimeTitle anime,
    AnimeEpisode episode,
    int position,
    int duration, {
    bool? watched,
  }) async {
    final oldPosition = positions[episode.key];
    await store.saveProgress(
      anime,
      episode,
      positionMs: position,
      durationMs: duration,
      watched: watched,
    );
    final previous = positions[episode.key] ?? {};
    positions[episode.key] = {
      ...previous,
      'slug': anime.slug,
      'anime': anime.toJson(),
      'episode': episode.toJson(),
      'positionMs': position,
      'durationMs': duration,
      'watched': watched ?? previous['watched'] == true,
      'updatedAt': DateTime.now().millisecondsSinceEpoch,
    };
    if (watched != null ||
        oldPosition == null ||
        animeInt(oldPosition['positionMs']) == 0) {
      changed();
    }
    final number = int.tryParse(episode.number);
    if (watched == true && number != null && number > 0) {
      try {
        // Sin vinculación guardada se usa la coincidencia con la lista de
        // MAL, entre a la ficha desde donde se entre.
        await _ensureMalLink(anime.slug);
        await mal.queueWatched(anime.slug, number);
        unawaited(syncMal());
        malError = null;
      } catch (error) {
        malError = 'Progreso local guardado; MAL pendiente: $error';
        changed();
      }
    } else if (watched == false && number != null) {
      // Desmarcado antes de enviarse: el pendiente baja al episodio visto
      // más alto que queda, para no subir a MAL uno que ya no cuenta.
      try {
        await mal.retractWatched(anime.slug, _localWatched(anime.slug));
      } catch (error) {
        malError = 'No se pudo actualizar el pendiente de MAL: $error';
        changed();
      }
    }
  }

  Future<void> syncMal() async {
    try {
      await mal.flush();
      malError = null;
    } catch (error) {
      malError = 'Progreso local guardado; MAL pendiente: $error';
    }
    changed();
  }

  Future<void> mark(
    AnimeTitle anime,
    AnimeEpisode episode,
    bool watched,
  ) async {
    final p = positions[episode.key] ?? {};
    await progress(
      anime,
      episode,
      animeInt(p['positionMs']),
      animeInt(p['durationMs']),
      watched: watched,
    );
  }

  Future<void> saveSetting(String key, dynamic value) async {
    settings = {...settings, key: value};
    await store.saveSettings(settings);
    changed();
  }

  Future<void> refreshDownloads() async {
    if (_snapshotBusy || _disposed) return;
    _snapshotBusy = true;
    try {
      final data = await transfers.snapshot();
      if (_disposed) return;
      final fingerprint = data.toString();
      if (fingerprint == _lastSnapshot) return;
      _lastSnapshot = fingerprint;
      downloads = (data['items'] as List? ?? [])
          .map((e) => AnimeDownload(animeMap(e)))
          .toList();
      supportedDownloads = data['supported'] == true;
      paused = data['paused'] == true;
      wifiOnly = data['wifiOnly'] != false;
      downloadError = null;
      changed();
    } catch (e) {
      if (!_disposed) {
        downloadError = e.toString();
        changed();
      }
    } finally {
      _snapshotBusy = false;
      _scheduleDownloads();
    }
  }

  AnimeDownload? downloaded(AnimeEpisode episode, String language) {
    for (final d in downloads) {
      if (d.slug == episode.slug &&
          d.number == episode.number &&
          d.language == language) {
        return d;
      }
    }
    return null;
  }

  AnimeDownload? readyDownload(AnimeEpisode episode) {
    for (final d in downloads) {
      if (d.slug == episode.slug && d.number == episode.number && d.ready) {
        return d;
      }
    }
    return null;
  }

  Future<void> enqueue(
    AnimeTitle anime,
    AnimeEpisode ep,
    String language,
  ) async {
    await transfers.enqueue(anime, ep, language);
    await updateLibrary(anime, savedValue: true);
    await refreshDownloads();
  }

  Future<void> downloadControl(
    String action, {
    String? key,
    bool? value,
  }) async {
    await transfers.control(action, key: key, value: value);
    await refreshDownloads();
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_network?.cancel());
    if (mal.onRemoteProgress == _malProgressConfirmed) {
      mal.onRemoteProgress = null;
    }
    mal.client.sessionChanges.removeListener(_sessionChanged);
    _poll?.cancel();
    source.close();
    activity.dispose();
    super.dispose();
  }
}
