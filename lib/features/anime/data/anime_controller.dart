import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/anime_models.dart';
import 'anime_local_store.dart';
import 'anime_mal_client.dart';
import 'local_anime_downloads.dart';
import 'yomatv_source.dart';

class AnimeController extends ChangeNotifier {
  final AnimeMalClient mal;
  String? malError;
  final YomaTvSource source;
  final AnimeLocalStore store;
  final LocalAnimeDownloads transfers;
  AnimeController({
    YomaTvSource? source,
    AnimeMalClient? mal,
    AnimeLocalStore? store,
    LocalAnimeDownloads? transfers,
  }) : mal = mal ?? AnimeMalClient(),
       source = source ?? YomaTvSource(),
       store = store ?? AnimeLocalStore(),
       transfers = transfers ?? LocalAnimeDownloads();
  bool _disposed = false;
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
    unawaited(syncMal());
    changed();
    unawaited(loadFront());
    unawaited(search());
    unawaited(refreshDownloads());
  }

  void _sessionChanged() {
    if (!_disposed) unawaited(syncMal());
  }

  void setActive(bool active) {
    activity.value = active;
    _poll?.cancel();
    if (active && !_disposed) {
      unawaited(refreshDownloads());
      unawaited(syncMal());
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

  Future<AnimeDetail> detail(String slug, {bool refresh = false}) async {
    if (!refresh && details.containsKey(slug)) return details[slug]!;
    final cached = await store.cache('detail:$slug');
    if (!refresh && cached != null) {
      final detail = AnimeDetail.fromJson(animeMap(cached['data']));
      details[slug] = detail;
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
      await store.putCache('detail:$slug', data);
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
  List<Map<String, dynamic>> get continuing {
    final slugs = <String>{};
    return history
        .where(
          (e) =>
              e['watched'] != true &&
              animeInt(e['positionMs']) > 0 &&
              slugs.add('${e['slug']}'),
        )
        .toList();
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
        await mal.queueWatched(anime.slug, number);
        unawaited(syncMal());
        malError = null;
      } catch (error) {
        malError = 'Progreso local guardado; MAL pendiente: $error';
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
    mal.client.sessionChanges.removeListener(_sessionChanged);
    _poll?.cancel();
    source.close();
    activity.dispose();
    super.dispose();
  }
}
