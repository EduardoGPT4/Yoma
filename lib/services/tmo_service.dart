import 'source_http_client.dart';
import '../utils/app_failure.dart';
import '../models/catalog_page.dart';
export '../models/catalog_page.dart' show CatalogPage, TmoCatalogPage;
import 'dart:convert';
import 'dart:io';

import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;

import '../models/chapter.dart';
import '../models/online_manga.dart';
import '../utils/title_sanitizer.dart';

/// Cliente de TuMangaOnline / Lectortmo en [https://zonatmo.org].
///
/// zonatmo.to es otra fuente (`ZonatmoToService`) y no se reescribe aquí.
/// Este cliente habla solo con el visor clásico:
/// - Catálogo: `/biblioteca?page=N`
/// - Ficha: `/library/{tipo}/{id}/{slug}`
/// - Capítulo: `/view_uploads/{id}`
/// - Páginas: `https://storage2.zonatmo.org/chapters/{id}/{n}.webp`
class TmoService {
  static const String baseUrl = 'https://zonatmo.org';

  static const Map<String, String> imageHeaders = <String, String>{
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    'Accept': 'image/avif,image/webp,image/apng,image/*,*/*;q=0.8',
    'Referer': '$baseUrl/',
  };

  static const Map<String, String> _defaultHeaders = <String, String>{
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    'Accept':
        'text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8',
    'Accept-Language': 'es-ES,es;q=0.9,en;q=0.8',
    'Connection': 'keep-alive',
    'Referer': '$baseUrl/',
  };

  static const Set<String> _tmoHosts = <String>{
    'zonatmo.org',
    'www.zonatmo.org',
    'storage.zonatmo.org',
    'storage2.zonatmo.org',
    'zonatmo.com',
    'www.zonatmo.com',
    'zonatmo.net',
    'www.zonatmo.net',
  };

  static const Set<String> _libraryTypes = <String>{
    'manga',
    'manhwa',
    'manhua',
    'doujinshi',
    'one_shot',
    'one-shot',
    'comic',
    'novel',
  };

  static final SourceHttpClient _httpClient = SourceHttpClient()
    ..idleTimeout = const Duration(seconds: 20)
    ..connectionTimeout = const Duration(seconds: 25)
    ..autoUncompress = true;

  static bool isTmoRef(String? value) {
    if (value == null || value.trim().isEmpty) {
      return false;
    }
    final v = value.toLowerCase();
    if (v.startsWith('tmo:') || v.startsWith('lectortmo:')) {
      return true;
    }
    if (v.contains('lectortmo.') ||
        v.contains('visortmo.') ||
        v.contains('tmofans.') ||
        v.contains('tumangaonline.')) {
      return true;
    }
    final uri = Uri.tryParse(value);
    if (uri != null && uri.host.isNotEmpty) {
      final host = uri.host.toLowerCase();
      if (host.endsWith('.zonatmo.to') || host == 'zonatmo.to') {
        return false;
      }
      if (_tmoHosts.contains(host) || host.endsWith('.zonatmo.org')) {
        return true;
      }
    }
    if (v.contains('zonatmo.to')) {
      return false;
    }
    return v.contains('zonatmo.org') ||
        v.contains('zonatmo.com') ||
        v.contains('/view_uploads/');
  }

  static bool needsImageHeaders(String url) {
    final host = Uri.tryParse(url)?.host.toLowerCase() ?? '';
    if (host.isEmpty) {
      return false;
    }
    if (host == 'zonatmo.to' || host.endsWith('.zonatmo.to')) {
      return false;
    }
    return host.endsWith('.zonatmo.org') ||
        host.contains('lectortmo.') ||
        host.contains('visortmo.');
  }

  /// Reescribe hosts clásicos caídos (`zonatmo.com`) a zonatmo.org.
  /// zonatmo.to no se toca: es otra fuente.
  static String rewriteLegacyUrl(String urlOrPath) {
    var value = urlOrPath.trim();
    if (value.isEmpty) {
      return value;
    }
    value = value
        .replaceAll('://www.zonatmo.com', '://zonatmo.org')
        .replaceAll('://zonatmo.com', '://zonatmo.org')
        .replaceAll('://www.zonatmo.net', '://zonatmo.org')
        .replaceAll('://zonatmo.net', '://zonatmo.org');
    return value;
  }

  static String? extractViewUploadId(String urlOrPath) {
    final match = RegExp(
      r'/view_uploads/(\d+)',
      caseSensitive: false,
    ).firstMatch(rewriteLegacyUrl(urlOrPath));
    return match?.group(1);
  }

  static bool isLibraryMangaUrl(String urlOrPath) {
    final uri = _uri(urlOrPath);
    final segments = uri.pathSegments
        .where((segment) => segment.isNotEmpty)
        .toList();
    return segments.length >= 3 &&
        segments.first == 'library' &&
        _libraryTypes.contains(segments[1].toLowerCase()) &&
        RegExp(r'^\d+$').hasMatch(segments[2]);
  }

  static Uri _uri(String pathOrUrl) {
    final rewritten = rewriteLegacyUrl(pathOrUrl);
    final uri = Uri.tryParse(rewritten);
    if (uri != null && uri.hasScheme) {
      return uri;
    }
    return Uri.parse(
      '$baseUrl${rewritten.startsWith('/') ? '' : '/'}$rewritten',
    );
  }

  static Future<String> _getHtml(String pathOrUrl, {String? referer}) async {
    final uri = _uri(pathOrUrl);
    final request = await _httpClient.getUrl(uri);
    request.followRedirects = true;
    request.maxRedirects = 8;
    _defaultHeaders.forEach(request.headers.set);
    request.headers.set('Referer', referer ?? '$baseUrl/');
    final response = await request.close();
    if (response.statusCode >= 400) {
      throw HttpException('HTTP ${response.statusCode} for $uri');
    }
    final body = utf8.decode(
      await response.fold<List<int>>(<int>[], (buffer, chunk) {
        buffer.addAll(chunk);
        return buffer;
      }),
    );
    if (_looksLikeChallenge(body)) {
      throw HttpException('HTTP 403 for $uri');
    }
    return body;
  }

  static bool _looksLikeChallenge(String html) {
    final lower = html.toLowerCase();
    return lower.contains('just a moment') ||
        lower.contains('cf-challenge') ||
        lower.contains('checking your browser');
  }

  static Future<List<int>> downloadBytes(String url, {String? referer}) async {
    final uri = _uri(url);
    final request = await _httpClient.getUrl(uri);
    request.followRedirects = true;
    request.maxRedirects = 8;
    imageHeaders.forEach(request.headers.set);
    request.headers.set('Referer', referer ?? '$baseUrl/');
    final response = await request.close();
    if (response.statusCode >= 400) {
      throw HttpException('HTTP ${response.statusCode} for $uri');
    }
    return response.fold<List<int>>(<int>[], (buffer, chunk) {
      buffer.addAll(chunk);
      return buffer;
    });
  }

  static Future<List<OnlineMangaSummary>> fetchHomeFeed() async {
    return (await fetchCatalogPage()).items;
  }

  static Future<List<OnlineMangaSummary>> fetchNewest() async {
    return (await fetchCatalogPage(orderBy: 'creation', order: 'desc')).items;
  }

  static Future<List<OnlineMangaSummary>> fetchUpdated() async {
    return (await fetchCatalogPage(orderBy: 'creation', order: 'desc')).items;
  }

  static Future<List<OnlineMangaSummary>> fetchCatalogManga({
    int page = 1,
    int postsPerPage = 12,
    String orderBy = 'likes_count',
    String order = 'desc',
    String? search,
  }) async {
    return (await fetchCatalogPage(
      page: page,
      postsPerPage: postsPerPage,
      orderBy: orderBy,
      order: order,
      search: search,
    )).items;
  }

  static Future<CatalogPage> fetchCatalogPage({
    int page = 1,
    int postsPerPage = 12,
    String orderBy = 'likes_count',
    String order = 'desc',
    String? search,
  }) async {
    final safePage = page < 1 ? 1 : page;
    final mappedOrder = _mapOrderBy(orderBy);
    final query = <String, String>{
      'page': '$safePage',
      '_pg': '$safePage',
      'order_item': mappedOrder,
      'order_dir': order.toLowerCase() == 'asc' ? 'asc' : 'desc',
      'filter_by': 'title',
    };
    final cleanedSearch = search?.trim();
    if (cleanedSearch != null && cleanedSearch.isNotEmpty) {
      query['title'] = cleanedSearch;
    }

    final uri = Uri.parse(
      '$baseUrl/biblioteca',
    ).replace(queryParameters: query);
    final html = await _getHtml(uri.toString());
    final items = _parseLibraryCards(html);
    return CatalogPage(
      items: items,
      currentPage: safePage,
      totalPages: items.length >= 24 ? null : safePage,
    );
  }

  static String _mapOrderBy(String orderBy) {
    switch (orderBy) {
      case 'creation':
      case 'created_at':
        return 'creation';
      case 'score':
        return 'score';
      case 'alphabetically':
      case 'title':
        return 'alphabetically';
      case 'release_date':
      case 'year':
        return 'release_date';
      case 'num_chapters':
        return 'num_chapters';
      case 'likes_count':
      case 'last_chapter_date':
      default:
        return 'likes_count';
    }
  }

  static Future<List<OnlineMangaSummary>> search(String query) async {
    final cleaned = query.trim();
    if (cleaned.isEmpty) {
      return <OnlineMangaSummary>[];
    }
    return (await fetchCatalogPage(search: cleaned)).items;
  }

  static Future<OnlineMangaDetail> fetchMangaDetail(String urlOrSlug) async {
    final url = await _resolveMangaPageUrl(urlOrSlug);
    if (!isLibraryMangaUrl(url)) {
      throw HttpException('HTTP 404 for $url');
    }
    final html = await _getHtml(url, referer: '$baseUrl/biblioteca');
    final document = html_parser.parse(html);

    final title =
        _firstNonEmpty([
          document
              .querySelector('h1.element-title')
              ?.nodes
              .whereType<Text>()
              .map((node) => node.text.trim())
              .where((text) => text.isNotEmpty)
              .join(' '),
          document.querySelector('h1.element-title')?.text,
          document
              .querySelector('meta[property="og:title"]')
              ?.attributes['content'],
          document.querySelector('h1')?.text,
        ]) ??
        'Manga';

    final year = _firstNonEmpty([
      document
          .querySelector('h1.element-title small')
          ?.text
          .replaceAll(RegExp(r'[()]'), ''),
      _metaBarValue(document, 'fa-calendar'),
    ]);

    final description = _firstNonEmpty([
      _extractCleanText(document.querySelector('#manga-synopsis')),
      _extractCleanText(document.querySelector('p.element-description')),
      document
          .querySelector('meta[property="og:description"]')
          ?.attributes['content'],
    ]);

    final coverUrl = _firstNonEmpty([
      document
          .querySelector('meta[property="og:image"]')
          ?.attributes['content'],
      document.querySelector('.book-thumbnail img')?.attributes['src'],
      document.querySelector('img.cover-bg-img')?.attributes['src'],
    ]);

    final altTitles = _compactTexts(
      document.querySelectorAll('.element-subtitle').map((el) => el.text),
    );

    final genres = _compactTexts(
      document
          .querySelectorAll('a[href*="genders"]')
          .map((el) => el.text.trim()),
    );

    final type = _firstNonEmpty([
      _extractCleanText(document.querySelector('.book-type')),
      _libraryTypeFromUrl(url)?.toUpperCase(),
    ]);

    final status = _firstNonEmpty([
      _extractCleanText(document.querySelector('.book-meta-status')),
      _extractStatusFromDocument(document),
    ]);

    final author = _firstNonEmpty([_authorFromDocument(document)]);

    final chapters = _parseChapters(document);

    return OnlineMangaDetail(
      title: TitleSanitizer.clean(title),
      url: url,
      coverUrl: _absoluteUrl(coverUrl),
      description: description,
      altTitles: altTitles,
      genres: genres,
      type: type,
      status: status,
      author: author,
      year: year,
      chapters: chapters,
    );
  }

  static Future<String> _resolveMangaPageUrl(String urlOrSlug) async {
    final rewritten = rewriteLegacyUrl(urlOrSlug.trim());
    if (rewritten.isEmpty) {
      throw const HttpException('URL de manga TMO vacía.');
    }

    if (isLibraryMangaUrl(rewritten)) {
      return _uri(rewritten).toString();
    }

    final uploadId = extractViewUploadId(rewritten);
    if (uploadId != null) {
      final html = await _getHtml(
        '/view_uploads/$uploadId',
        referer: '$baseUrl/',
      );
      final fromChapter = _libraryUrlFromHtml(html);
      if (fromChapter != null) {
        return fromChapter;
      }
    }

    final slug = _legacyMangaSlug(rewritten);
    if (slug != null && slug.isNotEmpty) {
      final results = await search(slug.replaceAll('-', ' '));
      for (final item in results) {
        if (item.url.toLowerCase().endsWith('/$slug')) {
          return item.url;
        }
      }
      throw const AppFailure(
        FailureKind.parsing,
        'No se pudo identificar la obra del enlace antiguo.',
      );
    }

    return _uri(rewritten).toString();
  }

  static String? _legacyMangaSlug(String urlOrPath) {
    final uri = _uri(urlOrPath);
    final segments = uri.pathSegments
        .where((segment) => segment.isNotEmpty)
        .toList();
    if (segments.length >= 2 && segments.first == 'manga') {
      return segments[1];
    }
    if (segments.length == 1 &&
        !segments.first.contains('.') &&
        segments.first != 'biblioteca') {
      return segments.first;
    }
    return null;
  }

  static String? _libraryUrlFromHtml(String html) {
    final match = RegExp(
      r'https://zonatmo\.org/library/(?:manga|manhwa|manhua|doujinshi|one_shot|one-shot|comic|novel)/\d+/[^\s"<>]+',
      caseSensitive: false,
    ).firstMatch(html);
    return match?.group(0);
  }

  static String? _libraryTypeFromUrl(String url) {
    final uri = _uri(url);
    final segments = uri.pathSegments
        .where((segment) => segment.isNotEmpty)
        .toList();
    if (segments.length >= 2 && segments.first == 'library') {
      return segments[1];
    }
    return null;
  }

  static String? _authorFromDocument(Document document) {
    for (final anchor in document.querySelectorAll(
      'a[href*="filter_by=author"]',
    )) {
      final text = anchor.text.trim();
      if (text.isNotEmpty) {
        return text;
      }
    }
    return null;
  }

  static String? _extractStatusFromDocument(Document document) {
    final text = document.body?.text ?? '';
    for (final label in <String>[
      'En emisión',
      'En emision',
      'Publicándose',
      'Publicandose',
      'Finalizado',
      'Pausado',
      'Cancelado',
    ]) {
      if (text.contains(label)) {
        return label;
      }
    }
    return null;
  }

  static String? _metaBarValue(Document document, String iconHint) {
    for (final span in document.querySelectorAll('.manga-meta-bar span')) {
      final html = span.innerHtml;
      if (html.contains(iconHint)) {
        return span.text.trim();
      }
    }
    return null;
  }

  static Future<List<String>> fetchChapterPages(String chapterUrl) async {
    final rewritten = rewriteLegacyUrl(chapterUrl);
    var target = rewritten;
    var uploadId = extractViewUploadId(rewritten);

    if (uploadId == null) {
      target = await _resolveLegacyChapterUrl(rewritten);
      uploadId = extractViewUploadId(target);
    }
    if (uploadId == null) {
      throw const AppFailure(
        FailureKind.parsing,
        'TMO: enlace de capítulo inválido.',
      );
    }

    final html = await _getHtml(
      '/view_uploads/$uploadId',
      referer: '$baseUrl/',
    );
    return _parseChapterImages(html, uploadId: uploadId);
  }

  static Future<String> _resolveLegacyChapterUrl(String url) async {
    final uri = _uri(url);
    final segments = uri.pathSegments
        .where((segment) => segment.isNotEmpty)
        .toList();
    if (segments.length < 3 || segments.first != 'manga') {
      return url;
    }
    final mangaUrl = await _resolveMangaPageUrl(
      '$baseUrl/manga/${segments[1]}',
    );
    final detail = await fetchMangaDetail(mangaUrl);
    final needle = segments.sublist(2).join('-').toLowerCase();
    final number = RegExp(r'(\d+(?:\.\d+)?)').firstMatch(needle)?.group(1);

    final matches = detail.chapters.where((chapter) {
      if (number != null) {
        return RegExp(
              r'cap[íi]tulo\s*(\d+(?:\.\d+)?)',
              caseSensitive: false,
            ).firstMatch(chapter.title)?.group(1) ==
            number;
      }
      return chapter.title.toLowerCase().replaceAll(RegExp(r'\s+'), '-') ==
          needle;
    }).toList();
    if (matches.length == 1) return matches.single.path;
    throw const AppFailure(
      FailureKind.parsing,
      'No se pudo identificar el capítulo del enlace antiguo.',
    );
  }

  static List<String> _parseChapterImages(
    String html, {
    required String uploadId,
  }) {
    final document = html_parser.parse(html);
    final pages = <String>[];
    final seen = <String>{};

    void addUrl(String? raw) {
      final resolved = _absoluteUrl(raw);
      if (resolved == null || resolved.isEmpty) {
        return;
      }
      if (!seen.add(resolved)) {
        return;
      }
      pages.add(resolved);
    }

    for (final image in document.querySelectorAll('img.reader-image')) {
      addUrl(image.attributes['src'] ?? image.attributes['data-src']);
    }

    if (pages.isEmpty) {
      final matches = RegExp(
        r'https://storage\d?\.zonatmo\.org/chapters/\d+/\d+\.[a-zA-Z0-9]+',
      ).allMatches(html);
      for (final match in matches) {
        addUrl(match.group(0));
      }
    }

    final totalMatch = RegExp(
      r'var\s+TOTAL_PAGES\s*=\s*(\d+)',
    ).firstMatch(html);
    final total = int.tryParse(totalMatch?.group(1) ?? '');
    if (total != null && total > 0 && pages.length < total) {
      if (pages.isEmpty) {
        throw const AppFailure(
          FailureKind.parsing,
          'TMO no proporcionó una muestra verificable de páginas.',
        );
      }
      final sample = Uri.parse(pages.first);
      final match = RegExp(
        r'^(.*?/)(\d+)\.([a-zA-Z0-9]+)$',
      ).firstMatch(sample.path);
      if (match == null || int.parse(match.group(2)!) != 1 || total > 10000) {
        throw const AppFailure(
          FailureKind.parsing,
          'TMO cambió el formato de las páginas.',
        );
      }
      final width = match.group(2)!.startsWith('0')
          ? match.group(2)!.length
          : 1;
      final inferred = List<String>.generate(
        total,
        (index) => sample
            .replace(
              path:
                  '${match.group(1)!}${(index + 1).toString().padLeft(width, '0')}.${match.group(3)!}',
            )
            .toString(),
      );
      if (pages.any((url) => !inferred.contains(url))) {
        throw const AppFailure(
          FailureKind.parsing,
          'La lista de páginas de TMO es inconsistente.',
        );
      }
      return inferred;
    }

    if (pages.isEmpty) {
      throw const AppFailure(
        FailureKind.parsing,
        'TMO: no se encontraron páginas.',
      );
    }
    return pages;
  }

  static List<Chapter> _parseChapters(Document document) {
    final chapters = <Chapter>[];
    final seenUploads = <String>{};
    final seenNumbers = <String>{};

    for (final item in document.querySelectorAll('li.upload-link')) {
      final number = item.attributes['data-chapter-number']?.trim();
      final title =
          _firstNonEmpty([
            item.querySelector('.chapter-number')?.text,
            number == null || number.isEmpty ? null : 'Capítulo $number',
          ]) ??
          'Capítulo';
      final upload = item.querySelector('a[href*="/view_uploads/"]');
      final href = upload?.attributes['href'];
      if (href == null || href.isEmpty) {
        continue;
      }
      final path = _uri(href).toString();
      final uploadId = extractViewUploadId(path);
      if (uploadId != null && !seenUploads.add(uploadId)) {
        continue;
      }
      if (number != null && number.isNotEmpty && !seenNumbers.add(number)) {
        continue;
      }
      chapters.add(
        Chapter(
          title: TitleSanitizer.clean(title),
          path: path,
          pages: const <String>[],
          pageCount: 0,
        ),
      );
    }

    if (chapters.isEmpty) {
      for (final anchor in document.querySelectorAll(
        'a[href*="/view_uploads/"]',
      )) {
        final href = anchor.attributes['href'];
        if (href == null || href.isEmpty) {
          continue;
        }
        final path = _uri(href).toString();
        final uploadId = extractViewUploadId(path);
        if (uploadId == null || !seenUploads.add(uploadId)) {
          continue;
        }
        chapters.add(
          Chapter(
            title: TitleSanitizer.clean(anchor.text),
            path: path,
            pages: const <String>[],
            pageCount: 0,
          ),
        );
      }
    }

    return chapters.reversed.toList();
  }

  static List<OnlineMangaSummary> _parseLibraryCards(String html) {
    final document = html_parser.parse(html);
    final results = <OnlineMangaSummary>[];
    final seen = <String>{};

    for (final card in document.querySelectorAll('div.element')) {
      final anchor = card.querySelector('a[href*="/library/"]');
      final href = anchor?.attributes['href'];
      if (href == null || href.isEmpty) {
        continue;
      }
      final url = _uri(href).toString();
      if (!isLibraryMangaUrl(url) || !seen.add(url)) {
        continue;
      }

      final img =
          card.querySelector('img.cover-bg-img') ?? card.querySelector('img');
      final title =
          _firstNonEmpty([
            card.querySelector('h4')?.attributes['title'],
            card.querySelector('h4')?.text,
            img?.attributes['alt'],
          ]) ??
          'Manga';
      final cover = _firstNonEmpty([
        img?.attributes['src'],
        img?.attributes['data-src'],
        card.querySelector('.thumbnail')?.attributes['data-bg'],
        _backgroundImageUrl(
          card.querySelector('.thumbnail')?.attributes['style'],
        ),
      ]);
      final type = _extractCleanText(card.querySelector('.book-type'));
      final status = _extractCleanText(card.querySelector('.book-meta-status'));
      final chapterCount = _parseChapterCount(card);

      results.add(
        OnlineMangaSummary(
          title: TitleSanitizer.clean(title),
          originalTitle: title,
          url: url,
          coverUrl: _absoluteUrl(cover),
          chapterCount: chapterCount,
          type: type,
          status: status,
        ),
      );
    }

    return results;
  }

  static int? _parseChapterCount(Element card) {
    final titled = card
        .querySelectorAll('[title]')
        .map((el) => el.attributes['title'] ?? '')
        .join(' ');
    final match = RegExp(
      r'(\d+)\s*cap[íi]tulo',
      caseSensitive: false,
    ).firstMatch('$titled ${card.text}');
    if (match == null) {
      return null;
    }
    return int.tryParse(match.group(1) ?? '');
  }

  static String? _backgroundImageUrl(String? css) {
    if (css == null || css.isEmpty) {
      return null;
    }
    final match = RegExp(r'''url\(['"]?([^'")]+)['"]?\)''').firstMatch(css);
    return match?.group(1);
  }

  static String? _absoluteUrl(String? urlOrPath) {
    if (urlOrPath == null || urlOrPath.trim().isEmpty) {
      return null;
    }
    final trimmed = rewriteLegacyUrl(urlOrPath.trim());
    if (trimmed.startsWith('//')) {
      return 'https:$trimmed';
    }
    final uri = Uri.tryParse(trimmed);
    if (uri != null && uri.hasScheme) {
      return uri.toString();
    }
    return _uri(trimmed).toString();
  }

  static String? _firstNonEmpty(List<String?> values) {
    for (final value in values) {
      if (value != null && value.trim().isNotEmpty) {
        return value.trim();
      }
    }
    return null;
  }

  static String? _extractCleanText(dynamic container) {
    if (container == null) {
      return null;
    }
    final text = container.text.replaceAll(RegExp(r'\s+'), ' ').trim();
    return text.isEmpty ? null : text;
  }

  static List<String> _compactTexts(Iterable<String> values) {
    return values
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toSet()
        .toList();
  }
}
