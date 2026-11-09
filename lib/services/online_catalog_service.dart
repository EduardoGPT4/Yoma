import '../models/manga_source.dart';
import '../models/online_manga.dart';
import '../models/chapter.dart';
import '../utils/app_failure.dart';
import 'manga_source_adapter.dart';
import 'hitomi_service.dart';
import 'inmanga_service.dart';
import 'mangadex_service.dart';
import 'manhwaweb_service.dart';
import 'tmo_service.dart';
import 'zonatmo_to_service.dart';
import 'source_http_client.dart';

class OnlineCatalogService {
  static String _activeSourceId = MangaSources.defaultId;
  static String get activeSourceId => _activeSourceId;
  static void setActiveSourceId(String id) =>
      _activeSourceId = normalizeSourceId(id);
  static bool get isMangaDexActive => activeSourceId == 'mangadex';
  static bool get isInMangaActive => activeSourceId == 'inmanga';
  static bool get isManhwaWebActive => activeSourceId == 'manhwaweb';
  static bool get isTmoActive => activeSourceId == 'lectortmo';
  static bool get isZonatmoToActive => activeSourceId == 'zonatmo_to';
  static String normalizeSourceId(String id) => switch (id) {
    'tmo' => 'lectortmo',
    'yupmanga' => 'manhwaweb',
    _ => id,
  };
  static final Map<String, MangaSourceAdapter> adapters = {
    'lectortmo': CallbackSourceAdapter(
      id: 'lectortmo',
      catalogRequest: (p, n, q) =>
          TmoService.fetchCatalogPage(page: p, postsPerPage: n, search: q),
      feedRequest: TmoService.fetchUpdated,
      detailRequest: TmoService.fetchMangaDetail,
      pagesRequest: TmoService.fetchChapterPages,
      capabilities: const SourceCapabilities(feedLabel: 'Nuevas obras'),
    ),
    'zonatmo_to': CallbackSourceAdapter(
      id: 'zonatmo_to',
      catalogRequest: (p, n, q) => ZonatmoToService.fetchCatalogPage(
        page: p,
        postsPerPage: n,
        search: q,
      ),
      feedRequest: ZonatmoToService.fetchUpdated,
      detailRequest: (ref) =>
          ZonatmoToService.fetchMangaDetail(ref, initialChaptersOnly: true),
      chapterRequest: ZonatmoToService.fetchChapterBatch,
      pagesRequest: ZonatmoToService.fetchChapterPages,
      capabilities: const SourceCapabilities(
        feedLabel: 'Populares del mes',
        typeFilter: false,
      ),
    ),
    'mangadex': CallbackSourceAdapter(
      id: 'mangadex',
      catalogRequest: (p, n, q) =>
          MangaDexService.fetchCatalogPage(page: p, postsPerPage: n, search: q),
      feedRequest: MangaDexService.fetchUpdated,
      detailRequest: (ref) =>
          MangaDexService.fetchMangaDetail(ref, initialChaptersOnly: true),
      chapterRequest: MangaDexService.fetchChapterBatch,
      pagesRequest: MangaDexService.fetchChapterPages,
    ),
    'inmanga': CallbackSourceAdapter(
      id: 'inmanga',
      catalogRequest: (p, n, q) =>
          InMangaService.fetchCatalogPage(page: p, postsPerPage: n, search: q),
      feedRequest: InMangaService.fetchUpdated,
      detailRequest: InMangaService.fetchMangaDetail,
      pagesRequest: InMangaService.fetchChapterPages,
      capabilities: const SourceCapabilities(typeFilter: false),
    ),
    'manhwaweb': CallbackSourceAdapter(
      id: 'manhwaweb',
      catalogRequest: (p, n, q) => ManhwaWebService.fetchCatalogPage(
        page: p,
        postsPerPage: n,
        search: q,
      ),
      feedRequest: ManhwaWebService.fetchUpdated,
      detailRequest: ManhwaWebService.fetchMangaDetail,
      pagesRequest: ManhwaWebService.fetchChapterPages,
      capabilities: const SourceCapabilities(feedLabel: 'Nuevas obras'),
    ),
    'hitomi': CallbackSourceAdapter(
      id: 'hitomi',
      catalogRequest: (p, n, q) =>
          HitomiService.fetchCatalogPage(page: p, postsPerPage: n, search: q),
      feedRequest: HitomiService.fetchUpdated,
      detailRequest: HitomiService.fetchMangaDetail,
      pagesRequest: HitomiService.fetchChapterPages,
      capabilities: const SourceCapabilities(
        feedLabel: 'Populares',
        typeFilter: false,
        statusFilter: false,
      ),
    ),
  };
  static const Set<String> _separateSourceIds = {'hitomi'};
  static List<String> get searchableSourceIds => List.unmodifiable(
    adapters.keys.where((id) => !_separateSourceIds.contains(id)),
  );
  static MangaSourceAdapter adapter(String id) {
    final value = adapters[normalizeSourceId(id)];
    if (value == null) {
      throw const AppFailure(FailureKind.parsing, 'Fuente no disponible.');
    }
    return value;
  }

  static String? sourceIdForRef(String? ref) {
    if (ref == null || ref.trim().isEmpty) return null;
    final uri = Uri.tryParse(ref.trim());
    if (uri == null) return null;
    final scheme = uri.scheme.toLowerCase();
    if (scheme == 'hitomi') return 'hitomi';
    if (['md', 'mangadex'].contains(scheme)) return 'mangadex';
    if (['tmo', 'lectortmo'].contains(scheme)) return 'lectortmo';
    if (['inmanga', 'manhwaweb', 'zonatmo_to', 'zonatmoto'].contains(scheme)) {
      return scheme == 'zonatmoto' ? 'zonatmo_to' : scheme;
    }
    final host = uri.host.toLowerCase();
    bool domain(String name) => host == name || host.endsWith('.$name');
    if (domain('hitomi.la')) return 'hitomi';
    if (domain('mangadex.org') || domain('mangadex.network')) return 'mangadex';
    if (domain('inmanga.com') || domain('intomanga.com')) return 'inmanga';
    if (domain('manhwaweb.com') ||
        domain('img1mw.xyz') ||
        domain('img2mw.xyz')) {
      return 'manhwaweb';
    }
    if (domain('zonatmo.to')) return 'zonatmo_to';
    if ([
      'zonatmo.org',
      'zonatmo.com',
      'zonatmo.net',
      'lectortmo.com',
      'lectortmo.org',
      'visortmo.com',
      'tmofans.com',
      'tumangaonline.com',
    ].any(domain)) {
      return 'lectortmo';
    }
    if (!uri.hasScheme) {
      if (ref.startsWith('/view_uploads/')) return 'lectortmo';
      if (ref.startsWith('/chapter/chapterIndexControls') ||
          ref.startsWith('/ver/manga/')) {
        return 'inmanga';
      }
    }
    return null;
  }

  static bool belongsToSource(String? ref, String id) =>
      sourceIdForRef(ref) == normalizeSourceId(id);
  static Map<String, String>? imageRequestHeaders(String url) {
    if (ManhwaWebService.needsHotlinkHeaders(url)) {
      return ManhwaWebService.imageHeaders;
    }
    if (ZonatmoToService.needsImageHeaders(url)) {
      return ZonatmoToService.imageHeaders;
    }
    if (HitomiService.needsImageHeaders(url)) return HitomiService.imageHeaders;
    if (TmoService.needsImageHeaders(url)) return TmoService.imageHeaders;
    if (sourceIdForRef(url) == 'inmanga') {
      return const {'Referer': 'https://inmanga.com/'};
    }
    return null;
  }

  static final Map<String, Future<dynamic>> _pending = {};
  static Future<T> _single<T>(String key, Future<T> Function() work) async {
    if (SourceHttpClient.currentCancellation != null) return work();
    final current = _pending[key];
    if (current != null) return await current as T;
    final future = work();
    _pending[key] = future;
    try {
      return await future;
    } finally {
      _pending.remove(key);
    }
  }

  static Future<CatalogPage> fetchCatalogPage({
    int page = 1,
    int postsPerPage = 12,
    String orderBy = 'last_chapter_date',
    String order = 'desc',
    String? search,
  }) => fetchCatalogPageForSource(
    activeSourceId,
    page: page,
    postsPerPage: postsPerPage,
    search: search,
    orderBy: orderBy,
    order: order,
  );
  static Future<CatalogPage> fetchCatalogPageForSource(
    String sourceId, {
    int page = 1,
    int postsPerPage = 12,
    String orderBy = 'last_chapter_date',
    String order = 'desc',
    String? search,
  }) {
    final id = normalizeSourceId(sourceId);
    final languages = MangaDexService.preferredLanguages.join(',');
    final key =
        'catalog:$id:$languages:$page:$postsPerPage:$orderBy:$order:$search';
    return _single(
      key,
      () => adapter(
        id,
      ).catalog(page: page, pageSize: postsPerPage, query: search),
    );
  }

  static Future<List<OnlineMangaSummary>> fetchUpdated({String? sourceId}) {
    final id = sourceId ?? activeSourceId;
    return _single(
      'feed:$id:${MangaDexService.preferredLanguages.join(',')}',
      () => adapter(id).feed(),
    );
  }

  static Future<List<OnlineMangaSummary>> search(String query) async =>
      (await fetchCatalogPage(search: query)).items;
  static Future<List<SourceSearchResult>> searchAll(
    String query, {
    int postsPerPage = 12,
  }) => Future.wait(
    searchableSourceIds.map((id) async {
      try {
        final page = await fetchCatalogPageForSource(
          id,
          search: query,
          postsPerPage: postsPerPage,
        );
        return SourceSearchResult(
          sourceId: id,
          items: page.items.map((e) => e.copyWith(sourceId: id)).toList(),
          currentPage: page.currentPage,
          hasMore: page.hasNext,
        );
      } catch (error) {
        return SourceSearchResult(sourceId: id, error: error);
      }
    }),
  );
  static final Map<String, ({DateTime time, OnlineMangaDetail detail})>
  _details = {};
  static Future<OnlineMangaDetail> fetchMangaDetail(
    String ref, {
    String? sourceId,
    bool refresh = false,
  }) async {
    final id = sourceIdForRef(ref) ?? sourceId ?? activeSourceId;
    final key =
        'detail:$id:$ref:${MangaDexService.preferredLanguages.join(',')}';
    final cached = _details[key];
    if (!refresh &&
        cached != null &&
        DateTime.now().difference(cached.time) < const Duration(minutes: 5)) {
      _details.remove(key);
      _details[key] = cached;
      return cached.detail;
    }
    final detail = await _single(key, () => adapter(id).detail(ref));
    SourceHttpClient.currentCancellation?.check();
    _details.remove(key);
    _details[key] = (time: DateTime.now(), detail: detail);
    while (_details.length > 12) {
      _details.remove(_details.keys.first);
    }
    return detail;
  }

  static Future<OnlineMangaDetail> loadMoreChapters(
    OnlineMangaDetail detail,
  ) async {
    if (!detail.hasMoreChapters) return detail;
    final id = sourceIdForRef(detail.url) ?? activeSourceId;
    final batch = await adapter(
      id,
    ).chapterBatch(detail.url, detail.nextChapterCursor);
    if (batch.hasMore && batch.nextCursor <= detail.nextChapterCursor) {
      throw const AppFailure(
        FailureKind.parsing,
        'El origen no avanzó la paginación de capítulos.',
      );
    }
    String key(Chapter chapter) => id == 'mangadex' && chapter.number != null
        ? '${chapter.volume ?? ''}|${chapter.number!}'
        : chapter.path;
    final merged = {
      for (final chapter in detail.chapters) key(chapter): chapter,
    };
    for (final chapter in batch.chapters) {
      final old = merged[key(chapter)];
      if (old == null) {
        merged[key(chapter)] = chapter;
      } else if (id == 'mangadex') {
        final languages = MangaDexService.preferredLanguages;
        int rank(String? language) {
          final index = languages.indexOf(language ?? '');
          return index < 0 ? 999 : index;
        }

        if (rank(chapter.language) < rank(old.language)) {
          merged[key(chapter)] = chapter;
        }
      }
    }
    return OnlineMangaDetail.fromMap({
      ...detail.toMap(),
      'chapters': merged.values.map((c) => c.toMap()).toList(),
      'hasMoreChapters': batch.hasMore,
      'nextChapterCursor': batch.nextCursor,
    });
  }

  static Future<OnlineMangaDetail> resolveChapter(
    OnlineMangaDetail detail,
    String chapterPath,
  ) async {
    var next = detail;
    while (next.hasMoreChapters &&
        !next.chapters.any((c) => c.path == chapterPath)) {
      next = await loadMoreChapters(next);
    }
    if (!next.chapters.any((c) => c.path == chapterPath)) {
      throw const AppFailure(
        FailureKind.parsing,
        'El capítulo guardado ya no está disponible en la fuente.',
      );
    }
    return next;
  }

  static Future<OnlineMangaDetail> completeDetail(
    OnlineMangaDetail detail,
  ) async {
    var next = detail;
    while (next.hasMoreChapters) {
      next = await loadMoreChapters(next);
    }
    return next;
  }

  static Future<List<String>> fetchChapterPages(
    String ref, {
    String? sourceId,
    bool? dataSaver,
  }) async {
    final id = sourceIdForRef(ref) ?? sourceId ?? activeSourceId;
    final saver = dataSaver ?? MangaDexService.dataSaver;
    final pages = await _single(
      'pages:$id:$ref:$saver',
      () => id == 'mangadex' && dataSaver != null
          ? MangaDexService.fetchChapterPages(ref, useDataSaver: saver)
          : adapter(id).pages(ref),
    );
    if (pages.isEmpty) {
      throw const AppFailure(
        FailureKind.parsing,
        'El capítulo no contiene páginas.',
      );
    }
    return pages;
  }

  static Future<List<int>> downloadBytes(String url, {String? referer}) {
    if (HitomiService.needsImageHeaders(url) ||
        HitomiService.isReference(referer)) {
      return HitomiService.downloadBytes(url, referer: referer);
    }
    final id = sourceIdForRef(referer) ?? sourceIdForRef(url);
    return switch (id) {
      'mangadex' => MangaDexService.downloadBytes(url),
      'inmanga' => InMangaService.downloadBytes(url, referer: referer),
      'manhwaweb' => ManhwaWebService.downloadBytes(url, referer: referer),
      'zonatmo_to' => ZonatmoToService.downloadBytes(url, referer: referer),
      _ => TmoService.downloadBytes(url, referer: referer),
    };
  }
}

class SourceSearchResult {
  final String sourceId;
  final List<OnlineMangaSummary> items;
  final Object? error;
  final int currentPage;
  final bool hasMore;
  final bool loading;
  const SourceSearchResult({
    required this.sourceId,
    this.items = const [],
    this.error,
    this.currentPage = 1,
    this.hasMore = false,
    this.loading = false,
  });
}
