import 'source_http_client.dart';
import '../utils/app_failure.dart';
import 'dart:convert';
import 'dart:io';

import 'package:html/parser.dart' as html_parser;

import '../models/chapter.dart';
import '../models/online_manga.dart';
import '../utils/title_sanitizer.dart';
import '../models/catalog_page.dart';

/// Cliente de InManga (https://inmanga.com) vía scraping/AJAX.
///
/// Basado en el flujo de la extensión Keiyoushi/Tachiyomi:
/// - Catálogo: POST `/manga/getMangasConsultResult`
/// - Capítulos: GET `/chapter/getAll?mangaIdentification=`
/// - Páginas: GET `/chapter/chapterIndexControls?identification=`
/// - Imágenes: `cdn1.intomanga.com/i/m/{mangaId}/c/{chapterId}/o/{pageId}.jpg`
class InMangaService {
  static const String baseUrl = 'https://inmanga.com';
  static const String imageCdn = 'https://cdn1.intomanga.com';

  static const Map<String, String> _defaultHeaders = {
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    'Accept': '*/*',
    'Accept-Language': 'es-ES,es;q=0.9,en;q=0.8',
    'Referer': '$baseUrl/',
    'Origin': baseUrl,
  };

  static final SourceHttpClient _httpClient = SourceHttpClient()
    ..idleTimeout = const Duration(seconds: 25)
    ..connectionTimeout = const Duration(seconds: 20);

  static bool isInMangaRef(String? value) {
    if (value == null || value.trim().isEmpty) {
      return false;
    }
    final v = value.toLowerCase();
    return v.contains('inmanga.com') ||
        v.contains('intomanga.com') ||
        v.startsWith('inmanga:') ||
        v.startsWith('/ver/manga/') ||
        v.startsWith('/chapter/chapterindexcontrols');
  }

  static String? extractMangaId(String urlOrId) {
    final cleaned = urlOrId.trim();
    if (cleaned.isEmpty) {
      return null;
    }
    if (_isGuid(cleaned)) {
      return cleaned.toLowerCase();
    }
    final uri = Uri.tryParse(
      cleaned.startsWith('http') ? cleaned : '$baseUrl$cleaned',
    );
    if (uri == null) {
      return null;
    }
    final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    // /ver/manga/{slug}/{guid}
    if (segments.length >= 4 &&
        segments[0] == 'ver' &&
        segments[1] == 'manga') {
      final last = segments.last;
      if (_isGuid(last)) {
        return last.toLowerCase();
      }
    }
    // query mangaIdentification=
    final q = uri.queryParameters['mangaIdentification'];
    if (q != null && _isGuid(q)) {
      return q.toLowerCase();
    }
    return null;
  }

  static String? extractChapterId(String pathOrUrl) {
    final cleaned = pathOrUrl.trim();
    if (cleaned.isEmpty) {
      return null;
    }
    if (_isGuid(cleaned)) {
      return cleaned.toLowerCase();
    }
    final uri = Uri.tryParse(
      cleaned.startsWith('http') ? cleaned : '$baseUrl$cleaned',
    );
    if (uri == null) {
      return null;
    }
    final id = uri.queryParameters['identification'];
    if (id != null && _isGuid(id)) {
      return id.toLowerCase();
    }
    return null;
  }

  /// Miniatura que sí sirve el CDN. El `og:image` de la ficha apunta a
  /// `assets.intomanga.com/thumbnails/...` y responde 404.
  static String thumbnailUrl(String mangaId) =>
      '$imageCdn/i/m/$mangaId/t/o/$mangaId.jpg';

  /// Elige la primera portada usable. Ignora logos, placeholders y el
  /// thumbnail social roto.
  static String selectCoverUrl(
    String mangaId, {
    Iterable<String?> candidates = const <String?>[],
  }) {
    for (final raw in candidates) {
      final resolved = _absoluteCoverUrl(raw);
      if (resolved != null) {
        return resolved;
      }
    }
    return thumbnailUrl(mangaId);
  }

  static String? _absoluteCoverUrl(String? raw) {
    if (raw == null) {
      return null;
    }
    final value = raw.trim();
    if (value.isEmpty) {
      return null;
    }
    final lower = value.toLowerCase();
    if (lower.contains('loading-gear') ||
        lower.contains('onmangalogo') ||
        lower.contains('favicon') ||
        lower.contains('/thumbnails/manga/')) {
      return null;
    }
    if (value.startsWith('http://') || value.startsWith('https://')) {
      return value;
    }
    if (value.startsWith('//')) {
      return 'https:$value';
    }
    if (value.startsWith('/')) {
      return '$baseUrl$value';
    }
    return null;
  }

  static bool _isGuid(String value) {
    return RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
    ).hasMatch(value);
  }

  static Future<String> _getText(
    Uri uri, {
    Map<String, String>? headers,
  }) async {
    final request = await _httpClient.getUrl(uri);
    _defaultHeaders.forEach(request.headers.set);
    headers?.forEach(request.headers.set);
    final response = await request.close().timeout(const Duration(seconds: 35));
    final bytes = await response.fold<List<int>>(<int>[], (buffer, chunk) {
      buffer.addAll(chunk);
      return buffer;
    });
    if (response.statusCode >= 400) {
      throw HttpException('InManga HTTP ${response.statusCode} for $uri');
    }
    return utf8.decode(bytes);
  }

  static Future<String> _postForm(Uri uri, Map<String, String> fields) async {
    final body = fields.entries
        .map(
          (e) =>
              '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}',
        )
        .join('&');
    final request = await _httpClient.postUrl(uri);
    _defaultHeaders.forEach(request.headers.set);
    request.headers.set(
      'Content-Type',
      'application/x-www-form-urlencoded; charset=UTF-8',
    );
    request.headers.set('X-Requested-With', 'XMLHttpRequest');
    request.headers.set('Referer', '$baseUrl/manga/consult');
    request.add(utf8.encode(body));
    final response = await request.close().timeout(const Duration(seconds: 35));
    final bytes = await response.fold<List<int>>(<int>[], (buffer, chunk) {
      buffer.addAll(chunk);
      return buffer;
    });
    if (response.statusCode >= 400) {
      throw HttpException('InManga HTTP ${response.statusCode} for $uri');
    }
    return utf8.decode(bytes);
  }

  static Future<List<int>> downloadBytes(String url, {String? referer}) async {
    final uri = Uri.parse(url);
    final request = await _httpClient.getUrl(uri);
    _defaultHeaders.forEach(request.headers.set);
    request.headers.set('Accept', 'image/avif,image/webp,image/*,*/*;q=0.8');
    request.headers.set('Referer', referer ?? '$baseUrl/');
    final response = await request.close().timeout(const Duration(seconds: 45));
    if (response.statusCode >= 400) {
      throw HttpException(
        'InManga download HTTP ${response.statusCode} for $uri',
      );
    }
    return response.fold<List<int>>(<int>[], (buffer, chunk) {
      buffer.addAll(chunk);
      return buffer;
    });
  }

  /// sortby: 1 popular, 3 latest (según extensión Keiyoushi).
  static Future<CatalogPage> fetchCatalogPage({
    int page = 1,
    int postsPerPage = 12,
    String? search,
    bool latest = false,
  }) async {
    final take = postsPerPage.clamp(1, 30);
    final skip = ((page < 1 ? 1 : page) - 1) * take;
    final query = search?.trim() ?? '';
    final html = await _postForm(
      Uri.parse('$baseUrl/manga/getMangasConsultResult'),
      <String, String>{
        // Keiyoushi usa generes[]=-1; también acepta generes[0]=0.
        'filter[generes][]': '-1',
        'filter[queryString]': query,
        'filter[skip]': '$skip',
        'filter[take]': '$take',
        'filter[sortby]': latest ? '3' : '1',
        'filter[broadcastStatus]': '0',
        'filter[onlyFavorites]': 'false',
        'd': '',
      },
    );

    final items = _parseConsultHtml(html);
    // Si devolvió exactamente `take`, asumimos que hay más.
    final hasNext = items.length >= take;
    return CatalogPage(
      items: items,
      currentPage: page < 1 ? 1 : page,
      totalPages: hasNext ? page + 1 : page,
    );
  }

  static Future<List<OnlineMangaSummary>> fetchUpdated() async {
    final page = await fetchCatalogPage(
      page: 1,
      postsPerPage: 18,
      latest: true,
    );
    return page.items;
  }

  static Future<List<OnlineMangaSummary>> search(String query) async {
    final cleaned = query.trim();
    if (cleaned.isEmpty) {
      return <OnlineMangaSummary>[];
    }
    return (await fetchCatalogPage(search: cleaned, postsPerPage: 24)).items;
  }

  static List<OnlineMangaSummary> _parseConsultHtml(String html) {
    final document = html_parser.parse(html);
    final results = <OnlineMangaSummary>[];
    final seen = <String>{};

    for (final anchor in document.querySelectorAll('a.manga-result')) {
      final href = anchor.attributes['href'] ?? '';
      if (href.isEmpty) {
        continue;
      }
      final url = href.startsWith('http') ? href : '$baseUrl$href';
      final mangaId = extractMangaId(url);
      if (mangaId == null || !seen.add(mangaId)) {
        continue;
      }

      final titleEl =
          anchor.querySelector('h4.m0') ??
          anchor.querySelector('h4.ellipsed-text') ??
          anchor.querySelector('h4');
      final originalTitle =
          titleEl?.text.replaceAll(RegExp(r'\s+'), ' ').trim() ?? 'Manga';
      final title = TitleSanitizer.clean(originalTitle);

      final img = anchor.querySelector('img');
      final coverUrl = selectCoverUrl(
        mangaId,
        candidates: <String?>[
          img?.attributes['data-src'],
          img?.attributes['src'],
        ],
      );

      String? status;
      final statusLabel = anchor.querySelector('span.label');
      if (statusLabel != null) {
        final text = statusLabel.text.trim();
        if (text.isNotEmpty &&
            !text.toLowerCase().contains('favorito') &&
            !RegExp(r'^\d').hasMatch(text)) {
          status = text;
        }
      }

      results.add(
        OnlineMangaSummary(
          title: title.isEmpty ? 'Manga' : title,
          originalTitle: originalTitle,
          url: url,
          coverUrl: coverUrl,
          type: null,
          status: status,
        ),
      );
    }

    // Fallback: cualquier a[href*="/ver/manga/"]
    if (results.isEmpty) {
      for (final anchor in document.querySelectorAll(
        'a[href*="/ver/manga/"]',
      )) {
        final href = anchor.attributes['href'] ?? '';
        final url = href.startsWith('http') ? href : '$baseUrl$href';
        final mangaId = extractMangaId(url);
        if (mangaId == null || !seen.add(mangaId)) {
          continue;
        }
        final originalTitle =
            anchor.querySelector('h4')?.text.trim() ?? 'Manga';
        final title = TitleSanitizer.clean(originalTitle);
        results.add(
          OnlineMangaSummary(
            title: title,
            originalTitle: originalTitle,
            url: url,
            coverUrl: thumbnailUrl(mangaId),
            type: null,
          ),
        );
      }
    }

    return results;
  }

  static Future<OnlineMangaDetail> fetchMangaDetail(String urlOrId) async {
    final mangaId = extractMangaId(urlOrId);
    if (mangaId == null) {
      throw StateError('ID de manga InManga inválido: $urlOrId');
    }

    // Reconstruir URL de detalle si solo tenemos GUID.
    String detailUrl = urlOrId.trim();
    if (!detailUrl.contains('/ver/manga/')) {
      detailUrl = '$baseUrl/ver/manga/manga/$mangaId';
    } else if (!detailUrl.startsWith('http')) {
      detailUrl = '$baseUrl$detailUrl';
    }

    String title = 'Manga';
    String? description;
    var coverUrl = thumbnailUrl(mangaId);
    String? status;
    String? author;

    try {
      final html = await _getText(
        Uri.parse(detailUrl),
        headers: {'Accept': 'text/html'},
      );
      final document = html_parser.parse(html);
      title = TitleSanitizer.clean(
        document.querySelector('h1')?.text.trim() ??
            document
                .querySelector('meta[property="og:title"]')
                ?.attributes['content']
                ?.replaceAll(' Manga Online - InManga', '')
                .trim() ??
            title,
      );
      description =
          document.querySelector('div.col-md-9 div.panel-body')?.text.trim() ??
          document
              .querySelector('meta[property="og:description"]')
              ?.attributes['content']
              ?.trim();
      final panel =
          document.querySelector(
            'div.manga-index-detail-cover-photo-layout img',
          ) ??
          document.querySelector('div.col-md-3 div.panel.widget img') ??
          document.querySelector('div.col-md-3 img');
      coverUrl = selectCoverUrl(
        mangaId,
        candidates: <String?>[
          panel?.attributes['src'],
          panel?.attributes['data-src'],
          document
              .querySelector('img[src*="/cover/manga/"]')
              ?.attributes['src'],
          document
              .querySelector('meta[property="og:image"]')
              ?.attributes['content'],
        ],
      );
      // Estado
      for (final a in document.querySelectorAll('a.list-group-item')) {
        final text = a.text.toLowerCase();
        if (text.contains('estado')) {
          status = a.querySelector('span')?.text.trim() ?? status;
        }
        if (text.contains('autor') || text.contains('author')) {
          author = a.text
              .replaceAll(RegExp(r'Autor(es)?', caseSensitive: false), '')
              .trim();
        }
      }
    } catch (error) {
      throw AppFailure.from(error);
    }

    if (title.trim().isEmpty || title == 'Manga') {
      throw const AppFailure(
        FailureKind.parsing,
        'No se reconoció la ficha de InManga.',
      );
    }
    // Asegurar URL canónica con slug si el HTML trajo h1.
    final canonical = detailUrl.contains(mangaId)
        ? detailUrl
        : '$baseUrl/ver/manga/${_slugify(title)}/$mangaId';

    final chapters = await _fetchChapters(mangaId);

    return OnlineMangaDetail(
      title: title.isEmpty ? 'Manga' : title,
      url: canonical,
      coverUrl: coverUrl,
      description: description,
      status: status,
      author: author,
      chapters: chapters,
    );
  }

  static Future<List<Chapter>> _fetchChapters(String mangaId) async {
    final text = await _getText(
      Uri.parse('$baseUrl/chapter/getAll?mangaIdentification=$mangaId'),
      headers: {'X-Requested-With': 'XMLHttpRequest'},
    );

    dynamic decoded = jsonDecode(text);
    if (decoded is Map && decoded['data'] is String) {
      decoded = jsonDecode(decoded['data'] as String);
    }
    if (decoded is! Map) {
      throw const AppFailure(
        FailureKind.parsing,
        'InManga: respuesta de capítulos inválida.',
      );
    }
    final success = decoded['success'] == true;
    final result = decoded['result'];
    if (!success || result is! List) {
      throw const AppFailure(
        FailureKind.parsing,
        'InManga: respuesta de capítulos inválida.',
      );
    }

    final chapters = <Chapter>[];
    for (final item in result.whereType<Map>()) {
      final map = item.map((k, v) => MapEntry(k.toString(), v));
      final identification = (map['Identification'] ?? map['identification'])
          ?.toString();
      if (identification == null || identification.isEmpty) {
        continue;
      }
      final number = map['Number'];
      final friendly =
          map['FriendlyChapterNumber']?.toString() ??
          map['FriendlyChapterNumberUrl']?.toString() ??
          number?.toString() ??
          '';
      final pagesCount = int.tryParse('${map['PagesCount']}') ?? 0;
      final title = friendly.isEmpty ? 'Capítulo' : 'Capítulo $friendly';

      chapters.add(
        Chapter(
          title: title,
          path:
              '$baseUrl/chapter/chapterIndexControls?identification=${identification.toLowerCase()}',
          pages: const <String>[],
          pageCount: pagesCount,
        ),
      );
    }

    // Orden ascendente por número si es posible.
    chapters.sort((a, b) {
      final an =
          double.tryParse(a.title.replaceAll(RegExp(r'[^\d.]'), '')) ?? 0;
      final bn =
          double.tryParse(b.title.replaceAll(RegExp(r'[^\d.]'), '')) ?? 0;
      return an.compareTo(bn);
    });
    return chapters;
  }

  static Future<List<String>> fetchChapterPages(String chapterPath) async {
    final chapterId = extractChapterId(chapterPath);
    if (chapterId == null) {
      throw StateError('ID de capítulo InManga inválido: $chapterPath');
    }

    final html = await _getText(
      Uri.parse(
        '$baseUrl/chapter/chapterIndexControls?identification=$chapterId',
      ),
      headers: {'X-Requested-With': 'XMLHttpRequest'},
    );
    final document = html_parser.parse(html);

    String? mangaId;
    String? resolvedChapterId = chapterId;
    for (final input in document.querySelectorAll('input[type="hidden"]')) {
      final id = input.id;
      final value = input.attributes['value'] ?? '';
      if (id == 'MangaIdentification' && value.isNotEmpty) {
        mangaId = value.toLowerCase();
      }
      if (id == 'ChapterIdentification' && value.isNotEmpty) {
        resolvedChapterId = value.toLowerCase();
      }
    }

    if (mangaId == null || mangaId.isEmpty) {
      throw StateError(
        'No se pudo resolver mangaId para el capítulo $chapterId',
      );
    }

    final pages = <String>[];
    for (final img in document.querySelectorAll('img.ImageContainer')) {
      final pageId = img.id;
      if (!_isGuid(pageId)) {
        continue;
      }
      pages.add(
        '$imageCdn/i/m/$mangaId/c/$resolvedChapterId/o/${pageId.toLowerCase()}.jpg',
      );
    }

    if (pages.isEmpty) {
      throw const AppFailure(
        FailureKind.parsing,
        'InManga: no se encontraron páginas.',
      );
    }
    return pages;
  }

  static String _slugify(String title) {
    final cleaned = TitleSanitizer.clean(title)
        .replaceAll(RegExp(r'[^\w\s-]'), '')
        .trim()
        .replaceAll(RegExp(r'\s+'), '-');
    return cleaned.isEmpty ? 'manga' : cleaned;
  }
}
