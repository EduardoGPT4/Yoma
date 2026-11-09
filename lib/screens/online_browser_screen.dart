import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import '../utils/app_failure.dart';
import '../services/source_http_client.dart';
import '../models/content_identity.dart';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/chapter.dart';
import '../models/manga_list_filters.dart';
import '../models/manga_source.dart';
import '../models/reading_progress.dart';
import '../models/online_manga.dart';
import '../providers/favorites_provider.dart';
import '../providers/library_provider.dart';
import '../providers/source_provider.dart';
import '../services/hitomi_service.dart';
import '../services/online_catalog_service.dart';
import '../models/catalog_page.dart';
import '../utils/catalog_cache.dart';
import '../utils/manga_filter_utils.dart';
import '../utils/network_errors.dart';
import '../utils/time_format.dart';
import '../utils/title_sanitizer.dart';
import '../widgets/category_assign_sheet.dart';
import '../widgets/contextual_tip.dart';
import '../widgets/continue_reading_section.dart';
import '../widgets/home_content_layout.dart';
import '../widgets/filter_icon_button.dart';
import '../widgets/hitomi_search_panel.dart';
import '../widgets/manga_card.dart';
import '../widgets/manga_filter_sheet.dart';
import '../widgets/search_bar_field.dart';
import '../widgets/section_header.dart';
import 'reader_screen.dart';
import 'online_manga_detail_screen.dart';

class OnlineBrowserScreen extends StatefulWidget {
  /// Si se indica, el explorador queda fijo en esa fuente y no cambia la fuente global.
  final String? lockedSourceId;

  /// Distingue cachés del apartado fijo, por ejemplo el idioma de Hitomi.la.
  final String? catalogKey;

  const OnlineBrowserScreen({super.key, this.lockedSourceId, this.catalogKey});

  @override
  State<OnlineBrowserScreen> createState() => OnlineBrowserScreenState();
}

class OnlineBrowserScreenState extends State<OnlineBrowserScreen> {
  final TextEditingController _searchController = TextEditingController();
  final GlobalKey<HitomiSearchPanelState> _hitomiSearchKey =
      GlobalKey<HitomiSearchPanelState>();
  final ScrollController _scrollController = ScrollController();
  Timer? _debounce;
  bool _loadingHome = true;
  bool _refreshing = false;
  bool _loadingSearch = false;
  bool _loadingMore = false;
  String? _error;
  String _query = '';
  int _homePage = 1;
  bool _homeHasMore = false;
  List<OnlineMangaSummary> _trending = <OnlineMangaSummary>[];
  List<OnlineMangaSummary> _updated = <OnlineMangaSummary>[];
  List<SourceSearchResult> _globalSearch = <SourceSearchResult>[];
  String? _continueEntriesKey;
  Future<List<ContinueReadingEntry>>? _continueEntriesFuture;
  MangaListFilters _filters = MangaListFilters.empty;
  String? _boundSourceId;
  String? _boundLanguageKey;

  int _catalogGen = 0;
  int _searchGen = 0;
  CancellationToken _searchCancellation = CancellationToken();
  Set<String>? _searchSources;
  DateTime? _catalogSavedAt;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    unawaited(
      SharedPreferences.getInstance().then((prefs) {
        if (!mounted) return;
        final saved = prefs.getStringList('search_sources_v1')?.toSet();
        setState(() => _searchSources = saved);
      }),
    );
  }

  @override
  void didUpdateWidget(OnlineBrowserScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    final locked = widget.lockedSourceId;
    if (locked == null) return;
    final key = widget.catalogKey ?? '';
    if (locked != _boundSourceId || key != _boundLanguageKey) {
      _boundSourceId = locked;
      _boundLanguageKey = key;
      _searchController.clear();
      _query = '';
      _hitomiSearchKey.currentState?.clear(notify: false);
      unawaited(_loadHome(force: true));
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final locked = widget.lockedSourceId;
    if (locked != null) {
      if (_boundSourceId == null) {
        _boundSourceId = locked;
        _boundLanguageKey = widget.catalogKey ?? '';
        unawaited(_loadHome());
      }
      return;
    }
    final source = context.watch<SourceProvider>();
    if (!source.isLoaded) {
      return;
    }
    final sourceId = source.activeId;
    final languageKey = source.mangaDexLanguages.join(',');
    OnlineCatalogService.setActiveSourceId(sourceId);
    if (_boundSourceId == null) {
      _boundSourceId = sourceId;
      _boundLanguageKey = languageKey;
      unawaited(_loadHome());
      return;
    }
    final sourceChanged = _boundSourceId != sourceId;
    final languagesChanged =
        sourceId == 'mangadex' && _boundLanguageKey != languageKey;
    if (sourceChanged || languagesChanged) {
      _boundSourceId = sourceId;
      _boundLanguageKey = languageKey;
      _searchController.clear();
      _query = '';
      unawaited(_loadHome());
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCancellation.cancel();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) {
      return;
    }

    final position = _scrollController.position;
    if (position.extentAfter > 500) {
      return;
    }

    unawaited(_loadMoreIfNeeded());
  }

  Future<void> refresh() {
    if (widget.lockedSourceId == 'hitomi') {
      HitomiService.invalidateListings();
    }
    if (_query.isEmpty) {
      return _loadHome(force: true);
    }
    return _runSearch(_query);
  }

  Future<void> _loadHome({bool force = false}) async {
    final gen = ++_catalogGen;
    final sourceId = _boundSourceId ?? OnlineCatalogService.activeSourceId;
    _debounce?.cancel();
    _searchCancellation.cancel();
    _searchGen++;
    _loadingMore = false;
    _loadingSearch = false;
    _loadingHome = true;
    _homePage = 1;
    _homeHasMore = false;
    _catalogSavedAt = null;
    _trending = [];
    _updated = [];
    _globalSearch = [];
    final languageKey = widget.lockedSourceId != null
        ? (widget.catalogKey ?? _boundLanguageKey ?? '')
        : context.read<SourceProvider>().mangaDexLanguages.join(',');
    final cachedHome = await CatalogCache.loadHome(
      sourceId: sourceId,
      languageKey: languageKey,
    );
    final cachedUpdated = await CatalogCache.loadUpdated(
      sourceId: sourceId,
      languageKey: languageKey,
    );
    if (!mounted || gen != _catalogGen) {
      return;
    }

    _catalogSavedAt = await CatalogCache.savedAt(
      sourceId: sourceId,
      languageKey: languageKey,
    );
    if (!mounted || gen != _catalogGen) return;
    final hasCache = cachedHome.isNotEmpty || cachedUpdated.isNotEmpty;
    setState(() {
      if (hasCache) {
        _trending = cachedHome;
        _updated = cachedUpdated;
        _homePage = 1;
        _homeHasMore = cachedHome.length >= _pageSize;
        _loadingHome = false;
        _refreshing = true;
      } else {
        _loadingHome = true;
        _refreshing = false;
      }
      _error = null;
    });

    if (hasCache &&
        !force &&
        await CatalogCache.isFresh(
          sourceId: sourceId,
          languageKey: languageKey,
        )) {
      if (mounted && gen == _catalogGen) setState(() => _refreshing = false);
      return;
    }
    try {
      CatalogPage? homePage;
      List<OnlineMangaSummary>? updated;
      Object? loadError;

      final first = OnlineCatalogService.fetchCatalogPageForSource(
        sourceId,
        page: 1,
        postsPerPage: _pageSize,
      );
      await Future.wait<void>([
        first.then(
          (value) {
            homePage = value;
          },
          onError: (Object error) {
            loadError ??= error;
          },
        ),
        (sourceId == 'mangadex'
                ? first.then((page) => page.items)
                : OnlineCatalogService.fetchUpdated(sourceId: sourceId))
            .then(
              (value) {
                updated = value;
              },
              onError: (Object error) {
                loadError ??= error;
              },
            ),
      ]);
      if (!mounted || gen != _catalogGen) {
        return;
      }
      if (homePage == null && updated == null) {
        throw loadError ?? StateError('No se pudo cargar el catalogo.');
      }
      final loadedHome = homePage;
      final loadedUpdated = updated;
      final resolvedError = loadError;
      if (loadedHome != null) {
        await CatalogCache.saveHome(
          loadedHome.items,
          sourceId: sourceId,
          languageKey: languageKey,
        );
      }
      if (loadedUpdated != null) {
        await CatalogCache.saveUpdated(
          loadedUpdated,
          sourceId: sourceId,
          languageKey: languageKey,
        );
      }
      if (!mounted || gen != _catalogGen) {
        return;
      }
      setState(() {
        if (loadedHome != null) {
          _trending = loadedHome.items;
          _homePage = 1;
          _homeHasMore = loadedHome.hasNext;
        }
        if (loadedUpdated != null) {
          _updated = loadedUpdated;
        }
        _loadingHome = false;
        _refreshing = false;
        _catalogSavedAt = DateTime.now();
        _error = resolvedError == null
            ? null
            : NetworkErrors.friendly(resolvedError);
      });
    } catch (error) {
      if (gen != _catalogGen) {
        return;
      }
      if (!mounted) {
        return;
      }
      if (hasCache) {
        setState(() {
          _loadingHome = false;
          _refreshing = false;
          _error =
              '${NetworkErrors.friendly(error)} Mostrando catalogo en cache.';
        });
        return;
      }
      setState(() {
        _error = NetworkErrors.friendly(error);
        _loadingHome = false;
        _refreshing = false;
      });
    }
  }

  Future<void> _loadMoreIfNeeded() async {
    if (_loadingMore || _loadingHome) {
      return;
    }

    if (!_scrollController.hasClients) {
      return;
    }

    final position = _scrollController.position;
    if (position.extentAfter > 500) {
      return;
    }

    if (_query.isEmpty) {
      if (!_homeHasMore) {
        return;
      }
      await _loadMoreHome();
      return;
    }

    return;
  }

  static const _pageSize = 12;

  Future<void> _loadMoreHome() async {
    if (_loadingMore || !_homeHasMore) {
      return;
    }

    final gen = _catalogGen;
    final sourceId = _boundSourceId ?? OnlineCatalogService.activeSourceId;
    setState(() {
      _loadingMore = true;
      _error = null;
    });

    // Contador local: no confiar en currentPage del backend (evita re-pedir pág. 1).
    final nextPage = _homePage + 1;

    try {
      final page = await OnlineCatalogService.fetchCatalogPageForSource(
        sourceId,
        page: nextPage,
        postsPerPage: _pageSize,
      );
      if (!mounted || gen != _catalogGen) {
        return;
      }
      setState(() {
        // Solo APPEND al final: los mangas nuevos quedan abajo al scrollear.
        final existing = _trending.map((item) => item.url).toSet();
        final appended = page.items
            .where((item) => !existing.contains(item.url))
            .toList();
        if (appended.isNotEmpty) {
          _trending = [..._trending, ...appended];
        }
        _homePage = nextPage;
        // Hay más si el backend lo dice o si trajo página llena de resultados.
        _homeHasMore =
            page.hasNext && page.items.isNotEmpty && appended.isNotEmpty;
      });
    } catch (error) {
      if (!mounted || gen != _catalogGen) {
        return;
      }
      setState(() {
        _error = NetworkErrors.friendly(error);
      });
    } finally {
      if (mounted && gen == _catalogGen) {
        setState(() {
          _loadingMore = false;
        });
      }
    }
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _searchCancellation.cancel();
    _searchGen++;
    final query = value.trim();
    if (!mounted) {
      return;
    }

    setState(() {
      _query = query;
      _globalSearch = [];
      _loadingSearch = query.isNotEmpty;
      _error = null;
    });

    if (query.isEmpty) {
      setState(() {
        _globalSearch = <SourceSearchResult>[];
        _loadingSearch = false;
      });
      return;
    }

    _debounce = Timer(const Duration(milliseconds: 400), () {
      _runSearch(query);
    });
  }

  List<String> get _enabledSearchSources {
    final locked = widget.lockedSourceId;
    if (locked != null) return [locked];
    final known = OnlineCatalogService.searchableSourceIds;
    final selected = known
        .where((id) => _searchSources == null || _searchSources!.contains(id))
        .toList();
    return selected.isEmpty ? known : selected;
  }

  String get _searchScopeLabel {
    final sources = _enabledSearchSources;
    if (sources.length == OnlineCatalogService.searchableSourceIds.length) {
      return 'Todas las fuentes';
    }
    if (sources.length == 1) return MangaSources.shortLabel(sources.single);
    return '${sources.length} fuentes seleccionadas';
  }

  Future<void> _chooseSearchSources() async {
    final enabled = {..._enabledSearchSources};
    final selected = await showDialog<Set<String>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: const Text('Fuentes de búsqueda'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final id in OnlineCatalogService.searchableSourceIds)
                  CheckboxListTile(
                    title: Text(MangaSources.byId(id).name),
                    value: enabled.contains(id),
                    onChanged: (value) => update(() {
                      if (value == true) {
                        enabled.add(id);
                      } else if (enabled.length > 1) {
                        enabled.remove(id);
                      }
                    }),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, enabled),
              child: const Text('Aplicar'),
            ),
          ],
        ),
      ),
    );
    if (selected == null || !mounted) return;
    setState(() => _searchSources = selected);
    await (await SharedPreferences.getInstance()).setStringList(
      'search_sources_v1',
      selected.toList(),
    );
    if (mounted && _query.isNotEmpty) unawaited(_runSearch(_query));
  }

  Future<void> _runSearch(String query) async {
    _searchCancellation.cancel();
    _searchCancellation = CancellationToken();
    final gen = ++_searchGen;
    if (!mounted) return;
    setState(() {
      _loadingSearch = true;
      _error = null;
      _globalSearch = [
        for (final id in _enabledSearchSources)
          SourceSearchResult(sourceId: id, loading: true),
      ];
    });
    await Future.wait(
      _enabledSearchSources.map((id) => _searchPage(id, query, gen, 1)),
    );
    if (mounted && gen == _searchGen) setState(() => _loadingSearch = false);
  }

  Future<void> _searchPage(String id, String query, int gen, int number) async {
    final previous = _globalSearch.firstWhere((e) => e.sourceId == id);
    setState(
      () => _globalSearch = [
        for (final bucket in _globalSearch)
          if (bucket.sourceId == id)
            SourceSearchResult(
              sourceId: id,
              items: previous.items,
              currentPage: previous.currentPage,
              hasMore: previous.hasMore,
              loading: true,
            )
          else
            bucket,
      ],
    );
    SourceSearchResult result;
    try {
      final page = await SourceHttpClient.withCancellation(
        _searchCancellation,
        () => OnlineCatalogService.fetchCatalogPageForSource(
          id,
          page: number,
          postsPerPage: _pageSize,
          search: query,
        ),
      );
      final seen = previous.items.map((e) => e.url).toSet();
      final additions = page.items
          .where((e) => seen.add(e.url))
          .map((e) => e.copyWith(sourceId: id))
          .toList();
      result = SourceSearchResult(
        sourceId: id,
        items: [...previous.items, ...additions],
        currentPage: number,
        hasMore: page.hasNext && additions.isNotEmpty,
      );
    } catch (error) {
      result = SourceSearchResult(
        sourceId: id,
        items: previous.items,
        error: error,
        currentPage: previous.currentPage,
        hasMore: previous.hasMore,
      );
    }
    if (!mounted || gen != _searchGen || query != _query) return;
    setState(
      () => _globalSearch = [
        for (final bucket in _globalSearch)
          if (bucket.sourceId == id) result else bucket,
      ],
    );
  }

  void _openDetail(OnlineMangaSummary summary) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => OnlineMangaDetailScreen(mangaUrl: summary.url),
      ),
    );
  }

  List<OnlineMangaSummary> _applyFilters(
    List<OnlineMangaSummary> items,
    FavoritesProvider favorites,
  ) {
    return MangaFilterUtils.filterOnlineMangas(
      items: items,
      filters: _query.isNotEmpty
          ? _filters
          : _filters.copyWith(
              clearType: !OnlineCatalogService.adapter(
                _boundSourceId ?? OnlineCatalogService.activeSourceId,
              ).capabilities.typeFilter,
              clearStatus: !OnlineCatalogService.adapter(
                _boundSourceId ?? OnlineCatalogService.activeSourceId,
              ).capabilities.statusFilter,
            ),
      favorites: favorites,
    );
  }

  List<OnlineMangaSummary> _onlineFavorites(FavoritesProvider favorites) {
    final locked = widget.lockedSourceId;
    return favorites.entries
        .where((entry) => entry.key.startsWith('http'))
        .where((entry) {
          final adult = HitomiService.isReference(entry.key);
          return locked == 'hitomi' ? adult : !adult;
        })
        .map(
          (entry) => OnlineMangaSummary(
            title: entry.title,
            url: entry.key,
            coverUrl: entry.coverPath,
          ),
        )
        .toList();
  }

  Future<void> _openFilters() async {
    await MangaFilterSheet.show(
      context: context,
      initialFilters: _filters,
      isOnline: true,
      allowType:
          _query.isNotEmpty ||
          OnlineCatalogService.adapter(
            _boundSourceId ?? OnlineCatalogService.activeSourceId,
          ).capabilities.typeFilter,
      allowStatus:
          _query.isNotEmpty ||
          OnlineCatalogService.adapter(
            _boundSourceId ?? OnlineCatalogService.activeSourceId,
          ).capabilities.statusFilter,
      showHitomiTags: widget.lockedSourceId == 'hitomi',
      onApply: (filters) {
        setState(() => _filters = filters);
        final hasQuery = _query.isNotEmpty;
        if (hasQuery) {
          unawaited(_runSearch(_query));
        }
      },
    );
  }

  Widget _buildFilterButton() {
    return FilterIconButton(
      active: _filters.hasActiveFilters,
      onPressed: () => unawaited(_openFilters()),
    );
  }

  Widget _buildOnlineMangaCard(
    OnlineMangaSummary item, {
    String? badge,
    bool showSource = true,
    required FavoritesProvider favorites,
  }) {
    return MangaCard(
      title: item.title,
      coverPath: item.coverUrl,
      badge:
          badge ??
          (!showSource || item.sourceId == null || item.sourceId!.isEmpty
              ? null
              : MangaSources.shortLabel(item.sourceId!)),
      isFavorite: favorites.isFavorite(item.url),
      onFavoriteToggle: () {
        unawaited(
          favorites.toggle(
            key: item.url,
            title: item.title,
            coverPath: item.coverUrl,
          ),
        );
      },
      onLongPress: () {
        unawaited(
          CategoryAssignSheet.show(
            context: context,
            mangaKey: item.url,
            mangaTitle: item.title,
          ),
        );
      },
      onTap: () => _openDetail(item),
    );
  }

  bool _isRemoteProgress(ReadingProgress progress) {
    return ContentIdentity.isRemote(progress.mangaPath);
  }

  bool _matchesActiveSource(ReadingProgress progress, String sourceId) {
    final wanted = OnlineCatalogService.normalizeSourceId(sourceId);
    final stored = progress.sourceId;
    if (stored != null && stored.isNotEmpty) {
      return OnlineCatalogService.normalizeSourceId(stored) == wanted;
    }
    return OnlineCatalogService.belongsToSource(progress.mangaPath, wanted) ||
        OnlineCatalogService.belongsToSource(progress.chapterPath, wanted);
  }

  List<ReadingProgress> _remoteRecentProgress(
    LibraryProvider library,
    String sourceId,
  ) {
    return library
        .getRecentProgress()
        .where(_isRemoteProgress)
        .where((progress) => _matchesActiveSource(progress, sourceId))
        .take(5)
        .toList();
  }

  String _continueEntriesSignature(List<ReadingProgress> items) {
    return items
        .map(
          (progress) =>
              '${progress.mangaPath}|${progress.updatedAt}|${progress.coverPath ?? ''}',
        )
        .join(';;');
  }

  String _chapterLabel(String raw) => TitleSanitizer.chapterLabel(raw);

  Future<List<ContinueReadingEntry>> _loadContinueEntries(
    List<ReadingProgress> items,
  ) async {
    final entries = <ContinueReadingEntry>[];
    for (final progress in items) {
      String? coverPath = progress.coverPath;
      var progressValue = 0.0;

      if (coverPath == null || coverPath.isEmpty) {
        try {
          final detail = await OnlineCatalogService.fetchMangaDetail(
            progress.mangaPath,
          );
          coverPath = detail.coverUrl;
          Chapter? matchedChapter;
          for (final item in detail.chapters) {
            if (item.path == progress.chapterPath) {
              matchedChapter = item;
              break;
            }
          }
          if (matchedChapter != null && matchedChapter.pageCount > 0) {
            progressValue = (progress.pageIndex + 1) / matchedChapter.pageCount;
          }
        } catch (_) {
          coverPath = null;
        }
      }

      entries.add(
        ContinueReadingEntry(
          title: progress.mangaTitle.isNotEmpty ? progress.mangaTitle : 'Manga',
          chapterLabel: _chapterLabel(progress.chapterTitle),
          pageNumber: progress.pageIndex + 1,
          progress: progressValue,
          timeAgo: formatTimeAgo(progress.updatedAt),
          coverPath: coverPath,
          onTap: () => unawaited(_continueReading(progress)),
        ),
      );
    }
    return entries;
  }

  Future<void> _continueReading(ReadingProgress progress) async {
    try {
      var detail = await OnlineCatalogService.fetchMangaDetail(
        progress.mangaPath,
      );
      detail = await OnlineCatalogService.resolveChapter(
        detail,
        progress.chapterPath,
      );
      if (!mounted) {
        return;
      }

      final chapterIndex = detail.chapters.indexWhere(
        (chapter) => chapter.path == progress.chapterPath,
      );

      final safeChapterIndex = chapterIndex < 0 ? 0 : chapterIndex;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ReaderScreen(
            manga: detail.toOfflineManga(),
            initialChapterIndex: safeChapterIndex,
            initialPageIndex: progress.pageIndex,
          ),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo continuar la lectura: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final library = context.watch<LibraryProvider>();
    final favorites = context.watch<FavoritesProvider>();
    final sourceId =
        widget.lockedSourceId ?? context.watch<SourceProvider>().activeId;
    final remoteProgress = _remoteRecentProgress(library, sourceId);
    final favoriteItems = _onlineFavorites(favorites);
    final filteredTrending = _applyFilters(_trending, favorites);
    final filteredUpdated = _applyFilters(_updated, favorites);
    final continueKey =
        '$sourceId::${_continueEntriesSignature(remoteProgress)}';
    if (continueKey != _continueEntriesKey) {
      _continueEntriesKey = continueKey;
      _continueEntriesFuture = remoteProgress.isEmpty
          ? Future<List<ContinueReadingEntry>>.value(<ContinueReadingEntry>[])
          : _loadContinueEntries(remoteProgress);
    }

    // CustomScrollView + SliverGrid: al paginar solo se añaden celdas al final
    // (abajo). Un ListView+GridView shrinkWrap reconstruía todo y parecía que
    // los mangas nuevos entraban por arriba.
    return Column(
      children: [
        if (_refreshing) const LinearProgressIndicator(minHeight: 2),
        Expanded(
          child: RefreshIndicator(
            onRefresh: refresh,
            color: theme.colorScheme.primary,
            child: CustomScrollView(
              controller: _scrollController,
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                const SliverToBoxAdapter(child: SizedBox(height: 10)),
                if (_catalogSavedAt != null && _query.isEmpty)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Text(
                        'Catálogo guardado ${formatTimeAgo(_catalogSavedAt!.millisecondsSinceEpoch)}',
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  ),

                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  sliver: SliverToBoxAdapter(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (widget.lockedSourceId == 'hitomi')
                          HitomiSearchPanel(
                            key: _hitomiSearchKey,
                            showPopular: _filters.showPopularTags,
                            onQueryChanged: _onSearchChanged,
                            trailing: _buildFilterButton(),
                          )
                        else ...[
                          SearchBarField(
                            controller: _searchController,
                            hintText: _searchScopeLabel == 'Todas las fuentes'
                                ? 'Buscar en todas las fuentes'
                                : 'Buscar en $_searchScopeLabel',
                            onChanged: _onSearchChanged,
                            onClear: () {
                              _searchController.clear();
                              _onSearchChanged('');
                              setState(() {});
                            },
                          ),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 8,
                            runSpacing: 4,
                            alignment: WrapAlignment.spaceBetween,
                            children: [
                              if (widget.lockedSourceId == null)
                                TextButton.icon(
                                  onPressed: () =>
                                      unawaited(_chooseSearchSources()),
                                  icon: const Icon(
                                    Icons.travel_explore,
                                    size: 18,
                                  ),
                                  label: Text(
                                    _query.isEmpty
                                        ? 'Buscar: $_searchScopeLabel'
                                        : 'Búsqueda: $_searchScopeLabel',
                                  ),
                                )
                              else
                                const SizedBox.shrink(),
                              _buildFilterButton(),
                            ],
                          ),
                        ],
                        if (widget.lockedSourceId == 'hitomi')
                          const ContextualTip(
                            id: 'hitomi_tags',
                            message:
                                'Escribe y pulsa las etiquetas para combinarlas: artista, grupo, serie, personaje, género (female o male), tipo e idioma. Ejemplo: female:big_breasts language:spanish male:dilf. En Filtros puedes mostrar las más buscadas. La tecla de buscar usa el texto como título.',
                          ),
                        if (_query.isEmpty)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Text(
                              widget.lockedSourceId == 'hitomi'
                                  ? 'Catálogo ${HitomiService.languageLabel(widget.catalogKey)}'
                                  : 'Catálogo de ${MangaSources.byId(sourceId).name}',
                              style: theme.textTheme.labelMedium,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),

                // —— Continuar leyendo ——
                if (remoteProgress.isNotEmpty && _query.isEmpty)
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(
                      12,
                      HomeContentLayout.sectionSpacing,
                      20,
                      0,
                    ),
                    sliver: SliverToBoxAdapter(
                      child: FutureBuilder<List<ContinueReadingEntry>>(
                        future: _continueEntriesFuture,
                        builder: (context, snapshot) {
                          final entries =
                              snapshot.data ?? <ContinueReadingEntry>[];
                          if (entries.isEmpty) {
                            return const SizedBox.shrink();
                          }
                          return ContinueReadingSection(entries: entries);
                        },
                      ),
                    ),
                  ),

                // —— Favoritos ——
                if (favoriteItems.isNotEmpty &&
                    !_filters.favoritesOnly &&
                    _query.isEmpty)
                  ..._sliverCatalogSection(
                    title: 'Favoritos',
                    icon: Icons.favorite_rounded,
                    items: favoriteItems,
                    favorites: favorites,
                  ),

                if (_error != null && _query.isEmpty)
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(12, 16, 20, 0),
                    sliver: SliverToBoxAdapter(
                      child: _MessageCard(
                        icon: Icons.wifi_off_rounded,
                        message: _error!,
                        isError: true,
                      ),
                    ),
                  ),

                // —— Búsqueda o catálogo ——
                if (_query.isNotEmpty) ...[
                  ..._sliverGlobalSearch(favorites),
                ] else if (_loadingHome)
                  const SliverToBoxAdapter(child: _CatalogSkeleton())
                else if (_trending.isEmpty && _updated.isEmpty)
                  const SliverPadding(
                    padding: EdgeInsets.fromLTRB(12, 28, 20, 0),
                    sliver: SliverToBoxAdapter(child: _CatalogEmptyState()),
                  )
                else if (filteredTrending.isEmpty && filteredUpdated.isEmpty)
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(12, 28, 20, 0),
                    sliver: SliverToBoxAdapter(
                      child: _MessageCard(
                        icon: Icons.filter_alt_off_rounded,
                        message:
                            'No hay mangas que coincidan con los filtros activos.',
                      ),
                    ),
                  )
                else ...[
                  if (filteredUpdated.isNotEmpty)
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(
                        20,
                        HomeContentLayout.sectionSpacing,
                        20,
                        0,
                      ),
                      sliver: SliverToBoxAdapter(
                        child: _buildHorizontalUpdated(
                          filteredUpdated,
                          favorites,
                        ),
                      ),
                    ),
                  ..._sliverCatalogSection(
                    title: 'Mangas',
                    icon: Icons.auto_stories_outlined,
                    items: filteredTrending,
                    favorites: favorites,
                  ),
                ],

                if (_loadingMore)
                  const SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 20),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                  ),

                const SliverToBoxAdapter(child: SizedBox(height: 24)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  List<Widget> _sliverGlobalSearch(FavoritesProvider favorites) {
    final slivers = <Widget>[];
    final unavailable = <({String name, VoidCallback retry})>[];
    var anyItems = false;
    var anyError = false;
    var catalogResponded = false;

    for (final bucket in _globalSearch) {
      final source = MangaSources.byId(bucket.sourceId);
      final filtered = _applyFilters(bucket.items, favorites);
      final bucketError = bucket.error;
      final stillLoading = bucket.loading && bucket.items.isEmpty;
      if (stillLoading) {
        slivers.add(
          SliverToBoxAdapter(
            child: ListTile(
              title: Text(source.name),
              subtitle: const Text('Buscando…'),
              trailing: const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          ),
        );
        continue;
      }
      if (bucketError != null && filtered.isEmpty) {
        anyError = true;
        catalogResponded = true;
        unavailable.add((
          name: source.name,
          retry: () => unawaited(
            _searchPage(
              bucket.sourceId,
              _query,
              _searchGen,
              bucket.currentPage,
            ),
          ),
        ));
        continue;
      }
      catalogResponded = true;
      if (filtered.isEmpty) {
        continue;
      }
      anyItems = true;
      slivers.addAll(
        _sliverCatalogSection(
          title: source.name,
          icon: source.icon,
          items: filtered,
          favorites: favorites,
        ),
      );
      if (bucket.hasMore || bucket.error != null) {
        slivers.add(
          SliverToBoxAdapter(
            child: TextButton.icon(
              onPressed: bucket.loading
                  ? null
                  : () => unawaited(
                      _searchPage(
                        bucket.sourceId,
                        _query,
                        _searchGen,
                        bucket.currentPage + 1,
                      ),
                    ),
              icon: const Icon(Icons.expand_more),
              label: Text(
                bucket.loading
                    ? 'Cargando…'
                    : 'Más resultados de ${source.name}',
              ),
            ),
          ),
        );
      }
    }

    if (!anyItems && !_loadingSearch && (catalogResponded || anyError)) {
      slivers.add(
        SliverPadding(
          padding: const EdgeInsets.all(12),
          sliver: SliverToBoxAdapter(
            child: _MessageCard(
              icon: anyError
                  ? Icons.wifi_off_rounded
                  : Icons.search_off_rounded,
              message: anyError
                  ? (_error ?? 'No se pudo buscar en las fuentes.')
                  : (_filters.hasActiveFilters
                        ? 'No hay resultados que coincidan con los filtros activos.'
                        : 'No se encontraron resultados para "$_query".'),
            ),
          ),
        ),
      );
    }

    if (_loadingSearch && anyItems) {
      slivers.add(
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(child: CircularProgressIndicator()),
          ),
        ),
      );
    }

    if (unavailable.isNotEmpty) {
      slivers.add(
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(12, 20, 12, 4),
          sliver: SliverToBoxAdapter(
            child: _SearchSourceNotice(sources: unavailable),
          ),
        ),
      );
    }

    return slivers;
  }

  /// Sección con header + [SliverGrid] (los ítems nuevos se agregan al final).
  List<Widget> _sliverCatalogSection({
    required String title,
    required IconData icon,
    required List<OnlineMangaSummary> items,
    required FavoritesProvider favorites,
  }) {
    if (items.isEmpty) {
      return const <Widget>[];
    }
    return [
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(
          12,
          HomeContentLayout.sectionSpacing,
          20,
          10,
        ),
        sliver: SliverToBoxAdapter(
          child: SectionHeader(
            icon: icon,
            title: title,
            trailing: '${items.length}',
          ),
        ),
      ),
      SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        sliver: SliverMangaGrid(
          delegate: SliverChildBuilderDelegate(
            (context, index) {
              final item = items[index];
              return KeyedSubtree(
                key: ValueKey<String>('online-card-${item.url}'),
                child: _buildOnlineMangaCard(
                  item,
                  favorites: favorites,
                  showSource: _query.isEmpty,
                ),
              );
            },
            childCount: items.length,
            addAutomaticKeepAlives: true,
            addRepaintBoundaries: true,
          ),
        ),
      ),
    ];
  }

  /// Carrusel horizontal de actualizados (no compite con el scroll infinito).
  Widget _buildHorizontalUpdated(
    List<OnlineMangaSummary> items,
    FavoritesProvider favorites,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          icon: Icons.new_releases_outlined,
          title: widget.lockedSourceId == null
              ? 'Actualizados'
              : OnlineCatalogService.adapter(
                  widget.lockedSourceId!,
                ).capabilities.feedLabel,
          trailing: '${items.length}',
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: MangaCardLayout.heightForWidth(context, 120),
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: items.length.clamp(0, 24),
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              final item = items[index];
              return SizedBox(
                width: 120,
                child: KeyedSubtree(
                  key: ValueKey<String>('updated-${item.url}'),
                  child: _buildOnlineMangaCard(
                    item,
                    badge: 'Nuevo',
                    favorites: favorites,
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _CatalogSkeleton extends StatelessWidget {
  const _CatalogSkeleton();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fill = theme.colorScheme.surfaceContainerHighest;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 22, 20, 0),
      child: Column(
        children: [
          Row(
            children: List.generate(3, (index) {
              return Expanded(
                child: Padding(
                  padding: EdgeInsets.only(
                    left: index == 0 ? 0 : 7,
                    right: index == 2 ? 0 : 7,
                  ),
                  child: AspectRatio(
                    aspectRatio: MangaCardLayout.gridAspectRatio,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: fill,
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 14),
          Row(
            children: List.generate(3, (index) {
              return Expanded(
                child: Padding(
                  padding: EdgeInsets.only(
                    left: index == 0 ? 0 : 7,
                    right: index == 2 ? 0 : 7,
                  ),
                  child: AspectRatio(
                    aspectRatio: MangaCardLayout.gridAspectRatio,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: fill,
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }
}

class _CatalogEmptyState extends StatelessWidget {
  const _CatalogEmptyState();

  @override
  Widget build(BuildContext context) {
    return const _MessageCard(
      icon: Icons.menu_book_outlined,
      title: 'Catálogo vacío',
      message: 'No hay mangas para mostrar. Desliza hacia abajo para recargar.',
    );
  }
}

/// Aviso compacto de una fuente que no pudo buscar. Va al final de los resultados.
class _SearchSourceNotice extends StatelessWidget {
  final List<({String name, VoidCallback retry})> sources;

  const _SearchSourceNotice({required this.sources});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outline.withAlpha(170)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 8, 12, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (sources.length > 1) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(2, 2, 2, 6),
                child: Text(
                  'Fuentes que no respondieron',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: scheme.onSurface.withAlpha(150),
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.1,
                  ),
                ),
              ),
            ],
            for (var i = 0; i < sources.length; i++) ...[
              if (i > 0)
                Divider(height: 12, color: scheme.outline.withAlpha(120)),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: scheme.errorContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: SizedBox(
                      width: 32,
                      height: 32,
                      child: Icon(
                        Icons.cloud_off_outlined,
                        size: 16,
                        color: scheme.error,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          sources[i].name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            height: 1.2,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'No se pudo buscar en esta fuente. Puedes reintentarlo.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurface.withAlpha(160),
                            height: 1.25,
                          ),
                        ),
                        TextButton.icon(
                          onPressed: sources[i].retry,
                          icon: const Icon(Icons.refresh, size: 18),
                          label: const Text('Reintentar búsqueda'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _MessageCard extends StatelessWidget {
  final IconData icon;
  final String message;
  final String? title;
  final bool isError;

  const _MessageCard({
    required this.icon,
    required this.message,
    this.title,
    this.isError = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = isError
        ? theme.colorScheme.error
        : theme.colorScheme.primary;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 24),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isError
              ? theme.colorScheme.error.withAlpha(60)
              : theme.colorScheme.onSurface.withAlpha(18),
        ),
      ),
      child: Column(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: accent.withAlpha(28),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: accent, size: 26),
          ),
          if (title != null) ...[
            const SizedBox(height: 12),
            Text(
              title!,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
              textAlign: TextAlign.center,
            ),
          ],
          const SizedBox(height: 8),
          Text(
            message,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: isError
                  ? theme.colorScheme.error
                  : theme.colorScheme.onSurface.withAlpha(170),
              fontWeight: FontWeight.w600,
              height: 1.4,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
