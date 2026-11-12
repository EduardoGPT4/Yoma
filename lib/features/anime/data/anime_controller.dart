import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import '../models/anime_models.dart';
import 'anime_episode_watch.dart';
import 'anime_local_store.dart';
import 'anime_mal_client.dart';
import 'anime_mal_shelf.dart';
import 'local_anime_downloads.dart';
import 'anime_sync.dart';
import 'yomatv_source.dart';

class AnimeController extends ChangeNotifier {
  final AnimeMalClient mal;
  String? malError;

  /// Aviso de MAL que no es un fallo (un deshacer que ya no procede). Se
  /// conserva hasta el siguiente episodio marcado o desmarcado, para que
  /// una sincronización posterior sin novedades no lo borre sin leerse.
  String? malNotice;

  static const _malUnsent =
      'Tu progreso está guardado en el teléfono. '
      'No se pudo enviar a MyAnimeList:';

  /// Lo que hay que contar al usuario sobre la sincronización, si algo.
  String? get malStatus => malError ?? malNotice;
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
    AnimeSync? accountSync,
    this.detailMaxAge = const Duration(minutes: 10),
  }) : _accountSync = accountSync,
       connectivity = connectivity ?? _deviceConnectivity,
       mal = mal ?? AnimeMalClient(),
       source = source ?? YomaTvSource(),
       store = store ?? AnimeLocalStore(),
       transfers = transfers ?? LocalAnimeDownloads() {
    this.mal.onRemoteProgress = _malProgressConfirmed;
  }
  bool _disposed = false;

  /// Biblioteca y progreso compartidos con los otros dispositivos y la web
  /// de la misma cuenta de MyAnimeList (ver [AnimeSync]).
  late final AnimeSync accountSync =
      _accountSync ?? AnimeSync(client: mal.client, database: store.database);
  final AnimeSync? _accountSync;
  String? accountSyncError;
  DateTime? accountSyncedAt;
  bool accountSyncing = false;
  Timer? _accountSyncTimer;

  /// Espera tras un cambio antes de subirlo: durante la reproducción el
  /// progreso se guarda cada pocos segundos.
  static const accountSyncDelay = Duration(seconds: 20);

  /// Sube lo cambiado aquí y aplica lo cambiado en otros sitios.
  Future<void> syncAccount() async {
    if (_disposed) return;
    _accountSyncTimer?.cancel();
    accountSyncing = true;
    try {
      final result = await accountSync.sync();
      if (_disposed) return;
      if (result.received > 0) await _reloadLocal();
      if (result.ran) accountSyncedAt = DateTime.now();
      accountSyncError = null;
    } catch (e) {
      accountSyncError = 'No se pudo sincronizar con tu cuenta: $e';
    } finally {
      accountSyncing = false;
      if (!_disposed) changed();
    }
  }

  void _scheduleAccountSync() {
    if (_disposed) return;
    _accountSyncTimer?.cancel();
    _accountSyncTimer = Timer(accountSyncDelay, () => unawaited(syncAccount()));
  }

  /// Vuelve a leer biblioteca y progreso tras recibir cambios.
  Future<void> _reloadLocal() async {
    final rows = await store.library();
    final history = await store.progress();
    if (_disposed) return;
    saved
      ..clear()
      ..addEntries(rows.map((row) => MapEntry('${row['slug']}', row)));
    positions
      ..clear()
      ..addEntries(
        history.map(
          (row) => MapEntry(
            AnimeEpisode.fromJson(animeMap(row['episode'])).key,
            row,
          ),
        ),
      );
  }

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
        _malWatchingAll = updated.watchingAll;
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

  /// Toda la lista «Viendo» de MAL por id (también lo que no coincide por
  /// nombre con YomaTV).
  Map<int, MalAnimeEntry> _malWatchingAll = const {};
  DateTime? malShelfSavedAt;
  bool malShelfPartial = false;

  /// La sección muestra coincidencias del índice de YomaTV aún sin
  /// comprobar; sirven para verlas ya, no para vincular con MAL.
  bool _malShelfInterim = false;
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

  /// Horario de la temporada: anime en emisión con su día (1 = lunes …
  /// 7 = domingo), como el apartado Temporada de la web.
  List<AnimeTitle> schedule = [];
  bool scheduleLoading = false;
  String? scheduleError;
  DateTime? scheduleSavedAt;
  static const _schedulePages = 10;
  static const scheduleMaxAge = Duration(hours: 6);
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
    unawaited(syncAccount());
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
      await adoptWebDownloads();
    } catch (e) {
      failure = 'No se pudieron pasar las descargas de la cuenta web: $e';
    }
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

  /// La cola de la cuenta web ya no se usa: sus episodios pasan a la cola
  /// local y su progreso al historial del teléfono (sin pisar el de aquí).
  Future<void> adoptWebDownloads() async {
    final outcome = await transfers.adoptWeb();
    final rows = (outcome['progress'] as List? ?? []).map(animeMap).toList();
    if (rows.isEmpty) return;
    for (final row in await store.importWebProgress(rows)) {
      final ep = AnimeEpisode.fromJson(animeMap(row['episode']));
      positions[ep.key] = row;
    }
    changed();
  }

  /// Los episodios vistos sin conexión (por ejemplo en Descargas) quedan en
  /// la cola de MAL del teléfono; se suben solos cuando vuelve internet.
  void _listenForNetwork() {
    try {
      _network = connectivity().listen((online) {
        if (online && !_disposed) {
          unawaited(syncMal());
          unawaited(syncAccount());
        }
      }, onError: (Object error) => debugPrint('Conectividad: $error'));
    } catch (error) {
      debugPrint('Conectividad opcional: $error');
    }
  }

  void _sessionChanged() {
    if (_disposed) return;
    unawaited(syncMal());
    unawaited(syncAccount());
    unawaited(loadMalShelf());
  }

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

  bool _syncingShelf = false;

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
      malError = '$_malUnsent $error';
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

  /// Avisa a la ficha de que cambió el vínculo con MAL.
  final malLinkChanges = ValueNotifier<int>(0);

  /// Quita el vínculo de [slug] con MyAnimeList (ver [AnimeMalClient.unlink]).
  Future<void> unlinkMal(String slug) async {
    await mal.unlink(slug);
    malLinkChanges.value++;
    changed();
  }

  void setActive(bool active) {
    activity.value = active;
    _poll?.cancel();
    if (active && !_disposed) {
      unawaited(refreshDownloads());
      unawaited(syncMal());
      unawaited(syncAccount());
      // Al volver a YomaTV, lo visto en la web de MAL aparece en una hora
      // como mucho.
      unawaited(loadMalShelf(maxAge: resumeMaxAge));
    }
  }

  /// Antigüedad máxima de la lista de MAL al volver a la app o a YomaTV.
  static const resumeMaxAge = Duration(hours: 1);

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

  /// Anime en emisión del día [weekday] (1 = lunes), ordenados por nombre.
  List<AnimeTitle> scheduleFor(int weekday) =>
      schedule.where((a) => a.weekday == weekday).toList()..sort(
        (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
      );

  /// Carga el horario: primero el guardado (también sin conexión) y después
  /// el catálogo público de temporada completo, que no necesita cuenta.
  Future<void> loadSchedule({bool refresh = false}) async {
    if (scheduleLoading) return;
    scheduleLoading = true;
    scheduleError = null;
    changed();
    try {
      final cached = await store.cache('schedule');
      if (cached != null && schedule.isEmpty) {
        schedule = _scheduleItems(animeMap(cached['data'])['items']);
        scheduleSavedAt = DateTime.fromMillisecondsSinceEpoch(
          animeInt(cached['savedAt']),
        );
        changed();
      }
      final fresh =
          scheduleSavedAt != null &&
          DateTime.now().difference(scheduleSavedAt!) < scheduleMaxAge;
      if (!refresh && fresh && schedule.isNotEmpty) return;
      final items = <dynamic>[];
      var page = 1, pages = 1;
      do {
        final data = await source.catalog(page: page, seasonal: true);
        items.addAll(data['items'] as List? ?? const []);
        pages = animeInt(data['pages'], 1);
        page++;
      } while (page <= pages && page <= _schedulePages && !_disposed);
      if (_disposed) return;
      schedule = _scheduleItems(items);
      scheduleSavedAt = DateTime.now();
      await store.putCache('schedule', {'items': items});
    } catch (e) {
      scheduleError = schedule.isEmpty
          ? 'No se pudo cargar el horario. $e'
          : 'Horario guardado; no se pudo actualizar.';
    } finally {
      scheduleLoading = false;
      if (!_disposed) changed();
    }
  }

  static List<AnimeTitle> _scheduleItems(Object? items) {
    final seen = <String>{};
    return [
      for (final raw in items is List ? items : const [])
        if (AnimeTitle.fromJson(animeMap(raw)) case final anime
            when anime.active &&
                anime.weekday >= 1 &&
                anime.weekday <= 7 &&
                seen.add(anime.slug))
          anime,
    ];
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
      // Lo que se ve en la ficha ya no se avisa como nuevo.
      unawaited(
        store
            .database()
            .then((db) => AnimeEpisodeWatch.remember(db, detail))
            .catchError((Object _) {}),
      );
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

  /// Lo reproducido o marcado en el teléfono. Lo que solo vino de
  /// MyAnimeList no se reprodujo aquí y no aparece.
  List<Map<String, dynamic>> get history =>
      positions.values
          .where(
            (e) =>
                e['source'] != 'mal' &&
                (animeInt(e['positionMs']) > 0 || e['watched'] == true),
          )
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
    // Sin nada reproducido aquí: el primero sin ver (lo visto en MAL ya
    // cuenta como visto).
    for (final episode in episodes) {
      if (positions[episode.key]?['watched'] != true) return episode;
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
    _scheduleAccountSync();
  }

  Future<void> progress(
    AnimeTitle anime,
    AnimeEpisode episode,
    int position,
    int duration, {
    bool? watched,
  }) async {
    final oldPosition = positions[episode.key];
    _scheduleAccountSync();
    await store.saveProgress(
      anime,
      episode,
      positionMs: position,
      durationMs: duration,
      watched: watched,
    );
    final previous = positions[episode.key] ?? {};
    positions[episode.key] = AnimeLocalStore.progressRow(
      previous,
      anime,
      episode,
      positionMs: position,
      durationMs: duration,
      watched: watched,
    );
    if (watched != null ||
        oldPosition == null ||
        animeInt(oldPosition['positionMs']) == 0) {
      changed();
    }
    if (watched != null) malNotice = null;
    // Un especial «12.5» cuenta en MAL como haber visto hasta el 12.
    final number = malEpisodeCount(episode.number);
    if (watched == true && number > 0) {
      try {
        // Sin vinculación guardada se usa la coincidencia con la lista de
        // MAL, entre a la ficha desde donde se entre.
        await _ensureMalLink(anime.slug);
        await mal.queueWatched(anime.slug, number);
        unawaited(syncMal());
        malError = null;
      } catch (error) {
        malError = '$_malUnsent $error';
        changed();
      }
    } else if (watched == false) {
      // Desmarcado: MAL debe quedar en el episodio visto más alto que
      // queda. Si aún no se envió baja el pendiente; si ya se envió, se
      // deshace en MAL.
      try {
        await mal.retractWatched(anime.slug, _localWatched(anime.slug));
        unawaited(syncMal());
      } catch (error) {
        malError = 'No se pudo actualizar el pendiente de MAL: $error';
        changed();
      }
    }
  }

  Future<void> syncMal() async {
    try {
      await mal.flush();
      // Un deshacer que MAL ya no admite se explica; no es un fallo.
      malNotice = mal.takeNotice() ?? malNotice;
      malError = null;
    } catch (error) {
      malError = '$_malUnsent $error';
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

  /// Devuelve el resultado de [LocalAnimeDownloads.enqueue].
  Future<String> enqueue(
    AnimeTitle anime,
    AnimeEpisode ep,
    String language,
  ) async {
    final outcome = await transfers.enqueue(anime, ep, language);
    await updateLibrary(anime, savedValue: true);
    await refreshDownloads();
    return outcome;
  }

  /// Mensaje para el usuario tras pedir una o varias descargas: dice lo que
  /// pasó de verdad, no siempre «añadido».
  static String downloadNotice(
    Iterable<String> outcomes, {
    required bool paused,
  }) {
    final all = outcomes.toList();
    final queued = all.where((o) => o == 'added' || o == 'requeued').length;
    final String text;
    if (all.length == 1) {
      text = switch (all.single) {
        'requeued' => 'Descarga puesta de nuevo en la cola.',
        'exists' => 'Este episodio ya está en la cola de descargas.',
        'done' => 'Este episodio ya está descargado.',
        _ => 'Episodio añadido a Descargas.',
      };
    } else {
      final already = all.length - queued;
      text = [
        if (queued > 0)
          '$queued ${queued == 1 ? 'episodio añadido' : 'episodios añadidos'} a Descargas.',
        if (already > 0)
          '$already ya ${already == 1 ? 'estaba' : 'estaban'} en la cola o descargados.',
      ].join(' ');
    }
    return paused && queued > 0
        ? '$text Las descargas están en pausa; reanúdalas en Descargas.'
        : text;
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
    _accountSyncTimer?.cancel();
    unawaited(_network?.cancel());
    if (mal.onRemoteProgress == _malProgressConfirmed) {
      mal.onRemoteProgress = null;
    }
    mal.client.sessionChanges.removeListener(_sessionChanged);
    _poll?.cancel();
    source.close();
    activity.dispose();
    malLinkChanges.dispose();
    super.dispose();
  }
}
