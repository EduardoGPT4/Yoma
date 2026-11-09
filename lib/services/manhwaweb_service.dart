import 'source_http_client.dart';
import 'dart:convert';
import 'dart:io';

import '../models/chapter.dart';
import '../models/online_manga.dart';
import '../utils/title_sanitizer.dart';
import '../models/catalog_page.dart';

/// Cliente de ManhwaWeb (https://www.manhwaweb.com).
///
/// Usa el backend JSON público (mismo que la extensión Mihon/Keiyoushi):
/// - Catálogo / búsqueda: `GET /manhwa/library`
/// - Recientes: `GET /latest/new-manhwa`
/// - Detalle + capítulos: `GET /manhwa/see/{slug}`
/// - Páginas: `GET /chapters/see/{chapterSlug}`
///
/// Las imágenes en `img1mw.xyz` / `img2mw.xyz` exigen Referer del sitio.
class ManhwaWebService {
  static const String siteUrl = 'https://www.manhwaweb.com';
  static const String apiUrl =
      'https://manhwawebbackend-production.up.railway.app';

  static const Map<String, String> imageHeaders = <String, String>{
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    'Accept': 'image/avif,image/webp,image/apng,image/*,*/*;q=0.8',
    'Referer': '$siteUrl/',
  };

  static const List<String> _cdnHosts = <String>[
    'img2mw.xyz',
    'img1mw.xyz',
    'uploads.manhwaweb.com',
  ];

  static const Map<String, String> _defaultHeaders = <String, String>{
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    'Accept': 'application/json, text/plain, */*',
    'Accept-Language': 'es-ES,es;q=0.9,en;q=0.8',
    'Referer': '$siteUrl/',
    'Origin': siteUrl,
  };

  static final SourceHttpClient _httpClient = SourceHttpClient()
    ..idleTimeout = const Duration(seconds: 30)
    ..connectionTimeout = const Duration(seconds: 25);

  /// `real_id` histórico: `nombre_{epoch ms}`. El prefijo admite `--` y `-_`.
  static final RegExp _seriesIdPattern = RegExp(r'_\d{10,}$');
  static final RegExp _chapterIdPattern = RegExp(r'_\d{10,}-');
  static final RegExp _seriesFromChapterPattern = RegExp(r'^(.+_\d{10,})-');

  /// Capítulo al final del slug: `-12_01` o `-139.5_01`.
  /// El id de serie puede ser largo y terminar en dígitos (`nombre-4185442`).
  static final RegExp _chapterSuffixPattern = RegExp(
    r'^(.+)-(\d+(?:\.\d+)?)_([A-Za-z0-9]+)$',
  );
  static final RegExp _chapterNumberRestPattern = RegExp(
    r'^\d+(?:\.\d+)?(?:_[A-Za-z0-9]+)?$',
  );

  /// Slug público. Sin tope corto: títulos largos usan el segmento entero.
  static const int _maxSlugLength = 8192;
  static final RegExp _publicSlugPattern = RegExp(
    r'^[A-Za-z0-9][A-Za-z0-9._-]*$',
  );

  static bool needsHotlinkHeaders(String? url) {
    if (url == null || url.isEmpty) {
      return false;
    }
    final lower = url.toLowerCase();
    return lower.contains('img1mw.xyz') ||
        lower.contains('img2mw.xyz') ||
        lower.contains('manhwaweb.com') ||
        lower.contains('manhwawebbackend');
  }

  static bool isManhwaWebRef(String? value) {
    if (value == null || value.trim().isEmpty) {
      return false;
    }
    final v = value.toLowerCase();
    return v.contains('manhwaweb.com') ||
        v.contains('manhwawebbackend') ||
        v.contains('img1mw.xyz') ||
        v.contains('img2mw.xyz') ||
        v.startsWith('manhwaweb:');
  }

  static String seriesUrl(String slug) => '$siteUrl/manhwa/$slug';

  static String? extractSeriesSlug(String urlOrSlug) {
    final cleaned = urlOrSlug.trim();
    if (cleaned.isEmpty) {
      return null;
    }
    if (cleaned.toLowerCase().startsWith('manhwaweb:')) {
      return extractSeriesSlug(cleaned.substring('manhwaweb:'.length));
    }

    if (!cleaned.contains('/') && !cleaned.contains('?')) {
      return _seriesFromLooseToken(cleaned);
    }

    final uri = Uri.tryParse(
      cleaned.startsWith('http')
          ? cleaned
          : '$siteUrl${cleaned.startsWith('/') ? cleaned : '/$cleaned'}',
    );
    if (uri != null) {
      final host = uri.host.toLowerCase();
      final onSite =
          host.isEmpty ||
          host == 'manhwaweb.com' ||
          host.endsWith('.manhwaweb.com');
      final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
      for (var i = 0; i < segments.length; i++) {
        final segment = segments[i].toLowerCase();
        if ((segment == 'manhwa' || segment == 'manga') &&
            i + 1 < segments.length) {
          final token = segments[i + 1];
          if (onSite && _looksLikePublicSlug(token)) {
            return token;
          }
          return _idFromPathSegment(token);
        }
        if (segment == 'leer' && i + 1 < segments.length) {
          return _seriesSlugFromChapterSlug(segments[i + 1]);
        }
      }
    }

    final last = cleaned.split('/').last.split('?').first;
    if (_containsManhwaHost(cleaned) && _looksLikePublicSlug(last)) {
      return _seriesFromLooseToken(last) ?? last;
    }
    return _idFromPathSegment(last);
  }

  static String? extractChapterSlug(String pathOrUrl) {
    final cleaned = pathOrUrl.trim();
    if (cleaned.isEmpty) {
      return null;
    }
    if (cleaned.toLowerCase().startsWith('manhwaweb:')) {
      return extractChapterSlug(cleaned.substring('manhwaweb:'.length));
    }

    final uri = Uri.tryParse(
      cleaned.startsWith('http')
          ? cleaned
          : '$siteUrl${cleaned.startsWith('/') ? cleaned : '/$cleaned'}',
    );
    if (uri != null) {
      final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
      final leerIndex = segments.indexWhere((s) => s.toLowerCase() == 'leer');
      if (leerIndex >= 0 && leerIndex + 1 < segments.length) {
        return segments[leerIndex + 1];
      }
    }

    final last = cleaned.split('/').last.split('?').first;
    if (_looksLikeChapterSlug(last) || _chapterSuffixPattern.hasMatch(last)) {
      return last;
    }
    return null;
  }

  static bool _containsManhwaHost(String value) {
    return value.toLowerCase().contains('manhwaweb.com');
  }

  static bool _looksLikePublicSlug(String value) {
    if (value.isEmpty || value.length > _maxSlugLength) {
      return false;
    }
    return _publicSlugPattern.hasMatch(value);
  }

  static bool _looksLikeSeriesSlug(String value) {
    return _seriesIdPattern.hasMatch(value) &&
        !value.contains('/') &&
        !_looksLikeChapterSlug(value);
  }

  static bool _looksLikeChapterSlug(String value) {
    return _chapterIdPattern.hasMatch(value) && !value.contains('/');
  }

  /// Token suelto: id histórico, capítulo, o `real_id` público con dígitos.
  static String? _seriesFromLooseToken(String token) {
    final value = token.trim();
    if (value.isEmpty || value.contains('/')) {
      return null;
    }
    if (_looksLikeSeriesSlug(value)) {
      return value;
    }
    final fromChapter = _seriesSlugFromChapterSlug(value);
    if (fromChapter != null) {
      return fromChapter;
    }
    if (_looksLikePublicSlug(value) && RegExp(r'\d').hasMatch(value)) {
      return value;
    }
    return null;
  }

  static String? _idFromPathSegment(String segment) {
    if (_looksLikeSeriesSlug(segment)) {
      return segment;
    }
    if (_looksLikeChapterSlug(segment)) {
      return _seriesSlugFromChapterSlug(segment);
    }
    return null;
  }

  static String? _seriesSlugFromChapterSlug(String chapterSlug) {
    final suffixed = _chapterSuffixPattern.firstMatch(chapterSlug);
    if (suffixed != null) {
      final series = suffixed.group(1) ?? '';
      if (series.isNotEmpty && _looksLikePublicSlug(series)) {
        return series;
      }
    }

    final old = _seriesFromChapterPattern.firstMatch(chapterSlug);
    if (old == null) {
      return null;
    }
    final series = old.group(1) ?? '';
    if (series.isEmpty) {
      return null;
    }
    final rest = chapterSlug.substring(series.length + 1);
    if (_chapterNumberRestPattern.hasMatch(rest)) {
      return series;
    }
    return null;
  }

  static Uri _apiSeeUri(String path, String id) {
    return Uri.parse('$apiUrl$path/${Uri.encodeComponent(id)}');
  }

  static Future<dynamic> _getJson(Uri uri) async {
    final request = await _httpClient.getUrl(uri);
    _defaultHeaders.forEach(request.headers.set);
    final response = await request.close().timeout(const Duration(seconds: 40));
    final bytes = await response.fold<List<int>>(<int>[], (buffer, chunk) {
      buffer.addAll(chunk);
      return buffer;
    });
    final text = utf8.decode(bytes);
    if (response.statusCode >= 400) {
      throw HttpException('ManhwaWeb HTTP ${response.statusCode} for $uri');
    }
    return jsonDecode(text);
  }

  static Map<String, String> _headersForImage(String url) {
    if (needsHotlinkHeaders(url)) {
      return imageHeaders;
    }
    return <String, String>{
      'User-Agent': imageHeaders['User-Agent']!,
      'Accept': imageHeaders['Accept']!,
    };
  }

  static bool isFragileImageHost(String url) {
    final lower = url.toLowerCase();
    return lower.contains('imageshack.') ||
        lower.contains('imagizer.imageshack') ||
        lower.contains('imaginer.imageshack');
  }

  static Future<List<int>> downloadBytes(String url, {String? referer}) async {
    final seen = <String>{};
    final candidates = <String>[
      url,
      ...cdnPageCandidates(url, referer: referer, pageIndex: 0).take(8),
    ];

    Object? lastError;
    for (final candidate in candidates) {
      if (!seen.add(candidate)) {
        continue;
      }
      try {
        return await _downloadOne(candidate);
      } catch (error) {
        lastError = error;
      }
    }

    if (isFragileImageHost(url)) {
      throw StateError(
        'Las imágenes de este capítulo ya no están en ManhwaWeb '
        '(el hosting ImageShack caducó). Prueba otro capítulo o manga.',
      );
    }
    throw lastError ?? StateError('ManhwaWeb: no se pudo descargar $url');
  }

  static Future<List<int>> _downloadOne(String url) async {
    final uri = Uri.parse(url.startsWith('http') ? url : '$siteUrl$url');
    final request = await _httpClient.getUrl(uri);
    _headersForImage(url).forEach(request.headers.set);
    final response = await request.close().timeout(const Duration(seconds: 45));
    final bytes = await response.fold<List<int>>(<int>[], (buffer, chunk) {
      buffer.addAll(chunk);
      return buffer;
    });
    if (response.statusCode >= 400) {
      throw HttpException(
        'ManhwaWeb download HTTP ${response.statusCode} for $uri',
      );
    }
    if (bytes.isEmpty) {
      throw StateError('ManhwaWeb: imagen vacía ($uri)');
    }
    return bytes;
  }

  static Future<CatalogPage> fetchCatalogPage({
    int page = 1,
    int postsPerPage = 12,
    String? search,
  }) async {
    final safePage = page < 1 ? 1 : page;
    final query = <String, String>{'page': '${safePage - 1}'};
    final cleaned = search?.trim() ?? '';
    if (cleaned.isNotEmpty) {
      query['buscar'] = cleaned;
    } else {
      query['order_item'] = 'creacion';
      query['order_dir'] = 'desc';
    }

    final data = await _getJson(
      Uri.parse('$apiUrl/manhwa/library').replace(queryParameters: query),
    );
    if (data is! Map) {
      return CatalogPage(
        items: const <OnlineMangaSummary>[],
        currentPage: safePage,
      );
    }

    final rawItems = data['data'];
    final items = rawItems is List
        ? rawItems
              .whereType<Map>()
              .map((item) => _summaryFromLibrary(item.cast<String, dynamic>()))
              .whereType<OnlineMangaSummary>()
              .toList()
        : <OnlineMangaSummary>[];

    final hasNext = data['next'] == true;
    return CatalogPage(
      items: items,
      currentPage: safePage,
      totalPages: hasNext ? safePage + 1 : safePage,
    );
  }

  static Future<List<OnlineMangaSummary>> fetchUpdated() async {
    final data = await _getJson(Uri.parse('$apiUrl/latest/new-manhwa'));
    if (data is! Map) {
      return <OnlineMangaSummary>[];
    }
    final block = data['manhwas'];
    if (block is! Map) {
      return <OnlineMangaSummary>[];
    }

    final seen = <String>{};
    final results = <OnlineMangaSummary>[];
    for (final key in const <String>['manhwas_esp', '_manhwas']) {
      final list = block[key];
      if (list is! List) {
        continue;
      }
      for (final item in list.whereType<Map>()) {
        final summary = _summaryFromLatest(item.cast<String, dynamic>());
        if (summary == null || !seen.add(summary.url)) {
          continue;
        }
        results.add(summary);
      }
    }
    return results;
  }

  static Future<List<OnlineMangaSummary>> search(String query) async {
    final cleaned = query.trim();
    if (cleaned.isEmpty) {
      return <OnlineMangaSummary>[];
    }
    return (await fetchCatalogPage(search: cleaned, postsPerPage: 30)).items;
  }

  static OnlineMangaSummary? _summaryFromLibrary(Map<String, dynamic> map) {
    final slug = (map['real_id'] ?? map['_id'])?.toString().trim() ?? '';
    if (slug.isEmpty) {
      return null;
    }
    final originalTitle = (map['name_esp'] ?? map['the_real_name'] ?? 'Manga')
        .toString();
    final title = TitleSanitizer.clean(originalTitle);
    final cover = map['_imagen']?.toString();
    return OnlineMangaSummary(
      title: title.isEmpty ? 'Manga' : title,
      originalTitle: originalTitle,
      url: seriesUrl(slug),
      coverUrl: (cover != null && cover.startsWith('http')) ? cover : null,
      chapterCount: int.tryParse('${map['_numero_cap']}'),
      type: _typeLabel(map['_tipo']?.toString()),
      status: _statusLabel(map['_status']?.toString()),
    );
  }

  static OnlineMangaSummary? _summaryFromLatest(Map<String, dynamic> map) {
    final slug = (map['id_rel'] ?? map['id_manhwa'])?.toString().trim() ?? '';
    if (slug.isEmpty) {
      return null;
    }
    final originalTitle = (map['name_manhwa'] ?? 'Manga').toString();
    final title = TitleSanitizer.clean(originalTitle);
    final cover = map['img']?.toString();
    return OnlineMangaSummary(
      title: title.isEmpty ? 'Manga' : title,
      originalTitle: originalTitle,
      url: seriesUrl(slug),
      coverUrl: (cover != null && cover.startsWith('http')) ? cover : null,
      type: _typeLabel(map['_tipo']?.toString()),
    );
  }

  static Future<OnlineMangaDetail> fetchMangaDetail(String urlOrSlug) async {
    final slug = extractSeriesSlug(urlOrSlug);
    if (slug == null || slug.isEmpty) {
      throw StateError('ID de serie ManhwaWeb inválido: $urlOrSlug');
    }

    final data = await _getJson(_apiSeeUri('/manhwa/see', slug));
    if (data is! Map) {
      throw StateError('ManhwaWeb: detalle inválido para $slug');
    }
    final map = data.cast<String, dynamic>();

    final realId = (map['real_id'] ?? map['_id'] ?? slug).toString();
    final internalId = (map['_id'] ?? realId).toString();
    final title = TitleSanitizer.clean(
      (map['name_esp'] ?? map['the_real_name'] ?? map['_name'] ?? 'Manga')
          .toString(),
    );
    final cover = map['_imagen']?.toString();
    final alt = map['_name']?.toString().trim();
    final altTitles =
        (alt != null &&
            alt.isNotEmpty &&
            alt.toLowerCase() != title.toLowerCase())
        ? <String>[alt]
        : const <String>[];
    final authors = _parseAuthors(map['_extras']);

    return OnlineMangaDetail(
      title: title.isEmpty ? 'Manga' : title,
      url: seriesUrl(realId),
      coverUrl: (cover != null && cover.startsWith('http')) ? cover : null,
      description: map['_sinopsis']?.toString().trim(),
      altTitles: altTitles,
      genres: _parseGenres(map['_categoris']),
      type: _typeLabel(map['_tipo']?.toString()),
      status: _statusLabel(map['_status']?.toString()),
      author: authors.isEmpty ? null : authors.join(', '),
      chapters: _parseChapters(
        map['chapters'],
        internalId: internalId,
        realId: realId,
      ),
    );
  }

  static List<Chapter> _parseChapters(
    dynamic raw, {
    required String internalId,
    required String realId,
  }) {
    if (raw is! List) {
      return <Chapter>[];
    }

    final chapters = <Chapter>[];
    final seen = <String>{};
    for (final item in raw.whereType<Map>()) {
      final map = item.cast<String, dynamic>();
      final esp = map['link']?.toString().trim();
      final rawLink = map['link_raw']?.toString().trim();
      var href = (esp != null && esp.isNotEmpty)
          ? esp
          : (rawLink != null && rawLink.isNotEmpty ? rawLink : '');
      if (href.isEmpty) {
        continue;
      }
      if (internalId.isNotEmpty && realId.isNotEmpty && internalId != realId) {
        href = href.replaceAll(internalId, realId);
      }
      if (!href.startsWith('http')) {
        href = href.startsWith('/') ? '$siteUrl$href' : '$siteUrl/$href';
      }
      href = href.replaceFirst('https://manhwaweb.com', siteUrl);

      if (!seen.add(href)) {
        continue;
      }

      final number = map['chapter'];
      final numberLabel = number is num
          ? number.toString().replaceFirst(RegExp(r'\.0$'), '')
          : number?.toString();
      final isRaw =
          (esp == null || esp.isEmpty) && rawLink != null && rawLink.isNotEmpty;
      final title = numberLabel == null || numberLabel.isEmpty
          ? (isRaw ? 'Capítulo (Raw)' : 'Capítulo')
          : (isRaw ? 'Capítulo $numberLabel (Raw)' : 'Capítulo $numberLabel');

      chapters.add(
        Chapter(
          title: title,
          path: href,
          pages: const <String>[],
          pageCount: 0,
        ),
      );
    }

    chapters.sort((a, b) => _chapterSortKey(a).compareTo(_chapterSortKey(b)));
    return chapters;
  }

  static double _chapterSortKey(Chapter chapter) {
    final match = RegExp(r'(\d+(?:\.\d+)?)').firstMatch(chapter.title);
    return double.tryParse(match?.group(1) ?? '') ?? 0;
  }

  static Future<List<String>> fetchChapterPages(String chapterPath) async {
    final slug = extractChapterSlug(chapterPath);
    if (slug == null || slug.isEmpty) {
      throw StateError('ManhwaWeb: chapter path inválido: $chapterPath');
    }

    final data = await _getJson(_apiSeeUri('/chapters/see', slug));
    if (data is! Map) {
      throw StateError('ManhwaWeb: respuesta de páginas inválida.');
    }
    final chapter = data['chapter'];
    final images = chapter is Map ? chapter['img'] : null;
    if (images is! List) {
      throw StateError('ManhwaWeb: el capítulo no tiene páginas.');
    }

    final pages = images
        .map((item) => item.toString().trim())
        .where((url) => url.startsWith('http'))
        .toList();
    if (pages.isEmpty) {
      throw StateError('ManhwaWeb: el capítulo no tiene páginas.');
    }

    if (pages.any(isFragileImageHost)) {
      final rewritten = await _rewriteFragilePages(chapterPath, pages.length);
      if (rewritten.isNotEmpty) {
        return rewritten;
      }
    }
    return pages;
  }

  /// Genera URLs del CDN propio a partir de un id de capítulo.
  static List<String> cdnPageCandidates(
    String url, {
    String? referer,
    required int pageIndex,
  }) {
    final source = referer ?? url;
    final parsed = parseChapterRef(source);
    if (parsed == null) {
      return const <String>[];
    }
    return _cdnUrlsForPage(
      series: parsed.series,
      chapter: parsed.chapter,
      ver: parsed.ver,
      pageIndex: pageIndex,
    );
  }

  static ManhwaWebChapterRef? parseChapterRef(String pathOrUrl) {
    final slug = extractChapterSlug(pathOrUrl);
    if (slug == null) {
      return null;
    }
    final series = _seriesSlugFromChapterSlug(slug);
    if (series == null || !slug.startsWith('$series-')) {
      return null;
    }
    final rest = slug.substring(series.length + 1);
    if (rest.isEmpty) {
      return null;
    }
    final parts = rest.split('_');
    final chapter = parts.first;
    final ver = parts.length > 1 ? parts.last : null;
    if (chapter.isEmpty) {
      return null;
    }
    return ManhwaWebChapterRef(series: series, chapter: chapter, ver: ver);
  }

  static List<String> _cdnUrlsForPage({
    required String series,
    required String chapter,
    required String? ver,
    required int pageIndex,
  }) {
    final page = pageIndex + 1;
    final pads = <String>{
      page.toString().padLeft(3, '0'),
      page.toString().padLeft(2, '0'),
      '$page',
    };
    final vers = <String>{
      if (ver != null && ver.isNotEmpty) ver,
      if (ver != null && ver.isNotEmpty) ver.padLeft(2, '0'),
      '01',
    };
    final urls = <String>[];
    for (final host in _cdnHosts) {
      for (final ext in const <String>['webp', 'jpg']) {
        for (final name in pads) {
          for (final v in vers) {
            urls.add(
              'https://$host/manhwas/$series/chapter_$chapter/ver_$v/$name.$ext',
            );
          }
          urls.add('https://$host/manhwas/$series/chapter_$chapter/$name.$ext');
        }
      }
    }
    return urls;
  }

  static Future<List<String>> _rewriteFragilePages(
    String chapterPath,
    int count,
  ) async {
    if (count <= 0) {
      return const <String>[];
    }
    final parsed = parseChapterRef(chapterPath);
    if (parsed == null) {
      return const <String>[];
    }

    final firstCandidates = _cdnUrlsForPage(
      series: parsed.series,
      chapter: parsed.chapter,
      ver: parsed.ver,
      pageIndex: 0,
    );
    String? template;
    for (final candidate in firstCandidates.take(24)) {
      if (await _isReachableImage(candidate)) {
        template = candidate;
        break;
      }
    }
    if (template == null) {
      return const <String>[];
    }

    final firstName = template.split('/').last;
    final match = RegExp(r'^0*1\.').firstMatch(firstName);
    if (match == null) {
      return <String>[template];
    }
    final pages = <String>[template];
    for (var i = 2; i <= count; i++) {
      final name = firstName.replaceFirst(
        RegExp(r'^0*1\.'),
        '${i.toString().padLeft(firstName.split('.').first.length, '0')}.',
      );
      pages.add(template.replaceFirst(firstName, name));
    }
    return pages;
  }

  static Future<bool> _isReachableImage(String url) async {
    try {
      final uri = Uri.parse(url);
      final request = await _httpClient.getUrl(uri);
      _headersForImage(url).forEach(request.headers.set);
      final response = await request.close().timeout(
        const Duration(seconds: 10),
      );
      final mime = response.headers.contentType?.mimeType ?? '';
      final ok = response.statusCode < 400 && mime.startsWith('image/');
      await response.drain<void>();
      return ok;
    } catch (_) {
      return false;
    }
  }

  static String? _statusLabel(String? raw) {
    switch (raw?.toLowerCase().trim()) {
      case 'publicandose':
        return 'Publicándose';
      case 'finalizado':
        return 'Finalizado';
      case 'hiatus':
        return 'Hiatus';
      default:
        return (raw == null || raw.trim().isEmpty) ? null : raw.trim();
    }
  }

  static String? _typeLabel(String? raw) {
    final value = raw?.trim();
    if (value == null || value.isEmpty) {
      return null;
    }
    return '${value[0].toUpperCase()}${value.substring(1).toLowerCase()}';
  }

  static List<String> _parseGenres(dynamic raw) {
    if (raw is! List) {
      return <String>[];
    }
    final names = <String>[];
    for (final item in raw) {
      if (item is Map) {
        for (final value in item.values) {
          final name = value.toString().trim();
          if (name.isNotEmpty && int.tryParse(name) == null) {
            names.add(name);
          }
        }
      } else if (item is String && item.trim().isNotEmpty) {
        names.add(item.trim());
      }
    }
    return names;
  }

  static List<String> _parseAuthors(dynamic extras) {
    if (extras is! Map) {
      return <String>[];
    }
    final raw = extras['autores'];
    if (raw is List) {
      return raw
          .map((item) => item.toString().trim())
          .where((item) => item.isNotEmpty)
          .toList();
    }
    if (raw is! String) {
      return <String>[];
    }
    final quoted = RegExp(r"'([^']+)'")
        .allMatches(raw)
        .map((match) => (match.group(1) ?? '').trim())
        .where((item) => item.isNotEmpty)
        .toList();
    if (quoted.isNotEmpty) {
      return quoted;
    }
    final trimmed = raw.trim();
    if (trimmed.isEmpty || trimmed == '[]') {
      return <String>[];
    }
    return <String>[trimmed];
  }
}

class ManhwaWebChapterRef {
  final String series;
  final String chapter;
  final String? ver;

  const ManhwaWebChapterRef({
    required this.series,
    required this.chapter,
    this.ver,
  });
}
