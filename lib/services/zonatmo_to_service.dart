import 'source_http_client.dart';
import '../models/chapter_batch.dart';
import '../utils/app_failure.dart';
import 'dart:convert';
import 'dart:io';
import 'package:html/parser.dart' as html_parser;

import '../models/chapter.dart';
import '../models/online_manga.dart';
import '../utils/title_sanitizer.dart';
import '../models/catalog_page.dart';

/// Cliente de zonatmo.to (WordPress + `/wp-api`).
///
/// No es zonatmo.org. Las URLs, el CDN y el catálogo son distintos:
/// - Catálogo: `/wp-api/api/listing/manga`
/// - Ficha: `/wp-api/api/single/manga/{slug}`
/// - Capítulo: `/wp-api/api/single/manga/{slug}/{chapterSlug}`
/// - Imágenes: `https://cdn.zonatmo.to/manga/{jit}/{archivo}`
class ZonatmoToService {
  static const String baseUrl = 'https://zonatmo.to';
  static const String apiBase = '$baseUrl/wp-api/api';
  static const String cdnBase = 'https://cdn.zonatmo.to';
  static const String uploadsBase = '$baseUrl/wp-content/uploads';
  static Future<Map<String, String>>? _genreLabels;

  static const Map<String, String> imageHeaders = <String, String>{
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    'Accept': 'image/avif,image/webp,image/apng,image/*,*/*;q=0.8',
    'Referer': '$baseUrl/',
  };

  static const Map<String, String> _headers = <String, String>{
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    'Accept': 'application/json,text/plain,*/*',
    'Accept-Language': 'es-ES,es;q=0.9',
    'Referer': '$baseUrl/',
  };

  static const Set<String> _hosts = <String>{
    'zonatmo.to',
    'www.zonatmo.to',
    'cdn.zonatmo.to',
  };

  static final SourceHttpClient _httpClient = SourceHttpClient()
    ..idleTimeout = const Duration(seconds: 20)
    ..connectionTimeout = const Duration(seconds: 25)
    ..autoUncompress = true;

  static bool isZonatmoToRef(String? value) {
    if (value == null || value.trim().isEmpty) {
      return false;
    }
    final lower = value.toLowerCase();
    if (lower.startsWith('zonatmo_to:') || lower.startsWith('zonatmoto:')) {
      return true;
    }
    final uri = Uri.tryParse(value);
    if (uri != null && uri.host.isNotEmpty) {
      final host = uri.host.toLowerCase();
      return _hosts.contains(host) || host.endsWith('.zonatmo.to');
    }
    return lower.contains('zonatmo.to');
  }

  static bool needsImageHeaders(String url) {
    final host = Uri.tryParse(url)?.host.toLowerCase() ?? '';
    return host == 'cdn.zonatmo.to' || host.endsWith('.zonatmo.to');
  }

  static Future<List<OnlineMangaSummary>> fetchUpdated() async {
    final page = await _getJson(
      '$apiBase/tops/views/month?postType=any&postsPerPage=24',
    );
    return _parseListing(page);
  }

  static Future<List<OnlineMangaSummary>> search(String query) async {
    return (await fetchCatalogPage(search: query)).items;
  }

  static Future<CatalogPage> fetchCatalogPage({
    int page = 1,
    int postsPerPage = 12,
    String orderBy = 'last_chapter_date',
    String order = 'desc',
    String? search,
  }) async {
    final safePage = page < 1 ? 1 : page;
    final params = <String, String>{
      'page': '$safePage',
      'postsPerPage': '${postsPerPage < 1 ? 12 : postsPerPage}',
    };
    final cleaned = search?.trim();
    if (cleaned != null && cleaned.isNotEmpty) {
      params['search'] = cleaned;
    }
    final uri = Uri.parse(
      '$apiBase/listing/manga',
    ).replace(queryParameters: params);
    final json = await _getJson(uri.toString());
    final items = _parseListing(json);
    final data = json['data'];
    final pagination = data is Map ? data['pagination'] : null;
    final hasNext = pagination is Map && _asBool(pagination['has_next']);
    final totalPages = pagination is Map
        ? int.tryParse('${pagination['total_pages']}')
        : null;
    return CatalogPage(
      items: items,
      currentPage: safePage,
      totalPages: hasNext ? null : (totalPages ?? safePage),
    );
  }

  static Future<OnlineMangaDetail> fetchMangaDetail(
    String urlOrSlug, {
    bool initialChaptersOnly = false,
  }) async {
    final slug = _mangaSlug(urlOrSlug);
    if (slug == null || slug.isEmpty) {
      throw HttpException('URL de zonatmo.to vacía.');
    }
    final json = await _getJson('$apiBase/single/manga/$slug');
    final data = json['data'];
    if (data is! Map) {
      throw HttpException('HTTP 404 for $baseUrl/manga/$slug');
    }
    final manga = Map<String, dynamic>.from(data);
    final title = _string(manga['title']) ?? slug;
    final batch = initialChaptersOnly
        ? await fetchChapterBatch(urlOrSlug, 1)
        : null;
    final chapters = batch?.chapters ?? await _fetchAllChapters(slug);
    return OnlineMangaDetail(
      title: TitleSanitizer.clean(title),
      url: '$baseUrl/manga/$slug',
      coverUrl: _coverUrl(_string(manga['cover'])),
      description: _plainText(manga['overview']),
      genres: await _genreNames(manga['genres']),
      type: _string(manga['type']),
      status: _statusLabel(manga['status']),
      author: _authorNames(manga['author']),
      chapters: chapters,
      hasMoreChapters: batch?.hasMore ?? false,
      nextChapterCursor: batch?.nextCursor ?? 0,
    );
  }

  static Future<List<String>> fetchChapterPages(String chapterUrl) async {
    final parts = _chapterSlugs(chapterUrl);
    if (parts == null) {
      throw const AppFailure(
        FailureKind.parsing,
        'ZonaTMO: respuesta de páginas inválida.',
      );
    }
    final json = await _getJson(
      '$apiBase/single/manga/${parts.$1}/${parts.$2}',
    );
    final data = json['data'];
    if (data is! Map) {
      throw const AppFailure(
        FailureKind.parsing,
        'ZonaTMO: respuesta de páginas inválida.',
      );
    }
    final chapter = data['chapter'];
    if (chapter is! Map) {
      throw const AppFailure(
        FailureKind.parsing,
        'ZonaTMO: respuesta de páginas inválida.',
      );
    }
    final jit = _string(chapter['jit']) ?? '';
    final images = chapter['images'];
    if (images is! List || jit.isEmpty) {
      throw const AppFailure(
        FailureKind.parsing,
        'ZonaTMO: respuesta de páginas inválida.',
      );
    }
    final pages = <({int number, String url})>[];
    for (final raw in images) {
      if (raw is! Map) {
        continue;
      }
      final name = _string(raw['image_url']);
      if (name == null || name.isEmpty) {
        continue;
      }
      final number = int.tryParse('${raw['page_number']}') ?? pages.length + 1;
      pages.add((number: number, url: _cdnImage(jit, name)));
    }
    pages.sort((a, b) => a.number.compareTo(b.number));
    if (pages.isEmpty) {
      throw const AppFailure(
        FailureKind.parsing,
        'ZonaTMO: capítulo sin páginas.',
      );
    }
    return pages.map((page) => page.url).toList();
  }

  static Future<List<int>> downloadBytes(String url, {String? referer}) async {
    final request = await _httpClient.getUrl(Uri.parse(url));
    request.followRedirects = true;
    imageHeaders.forEach(request.headers.set);
    request.headers.set('Referer', referer ?? '$baseUrl/');
    final response = await request.close();
    if (response.statusCode >= 400) {
      throw HttpException('HTTP ${response.statusCode} for $url');
    }
    return response.fold<List<int>>(<int>[], (buffer, chunk) {
      buffer.addAll(chunk);
      return buffer;
    });
  }

  static Future<ChapterBatch> fetchChapterBatch(String ref, int cursor) async {
    final slug = _mangaSlug(ref);
    if (slug == null) throw StateError('URL de zonatmo.to inválida.');
    var next = cursor, more = false;
    final chapters = await _fetchAllChapters(
      slug,
      onlyPage: cursor,
      onPage: (n, m) {
        next = n;
        more = m;
      },
    );
    return ChapterBatch(chapters: chapters, nextCursor: next, hasMore: more);
  }

  static Future<List<Chapter>> _fetchAllChapters(
    String slug, {
    int? onlyPage,
    void Function(int, bool)? onPage,
  }) async {
    final chapters = <Chapter>[];
    final seen = <String>{};
    var page = onlyPage ?? 1;
    var totalPages = page;
    while (page <= totalPages) {
      final json = await _getJson(
        '$apiBase/single/manga/$slug/chapters?page=$page&postsPerPage=50&order=asc',
      );
      final data = json['data'];
      if (data is! Map) {
        throw const AppFailure(
          FailureKind.parsing,
          'Lista de capítulos de zonatmo.to inválida.',
        );
      }
      final items = data['items'];
      if (items is! List) {
        throw const AppFailure(
          FailureKind.parsing,
          'Lista de capítulos de zonatmo.to inválida.',
        );
      }
      for (final raw in items) {
        if (raw is! Map) {
          continue;
        }
        final chapterSlug = _string(raw['slug']);
        if (chapterSlug == null || !seen.add(chapterSlug)) {
          continue;
        }
        final number = _string(raw['chapter_number']);
        final rawTitle = _string(raw['title']) ?? '';
        final title = number == null || number.isEmpty
            ? rawTitle
            : (rawTitle.isEmpty ? 'Capítulo $number' : 'Capítulo $number');
        chapters.add(
          Chapter(
            title: TitleSanitizer.clean(title),
            path: '$baseUrl/manga/$slug/$chapterSlug',
            pages: const <String>[],
            pageCount: 0,
            number: number,
          ),
        );
      }
      final pagination = data['pagination'];
      if (pagination is! Map) {
        throw const AppFailure(
          FailureKind.parsing,
          'No se pudo verificar la paginación de capítulos.',
        );
      }
      totalPages = int.tryParse(pagination['total_pages'].toString()) ?? page;
      final more = _asBool(pagination['has_next']) || page < totalPages;
      if (more && items.isEmpty) {
        throw const AppFailure(
          FailureKind.parsing,
          'El origen devolvió una lista de capítulos incompleta.',
        );
      }
      onPage?.call(page + 1, more);
      if (onlyPage != null || !more) break;
      if (totalPages < page + 1) totalPages = page + 1;
      page += 1;
    }
    chapters.sort((a, b) {
      final an = _chapterNumber(a.title);
      final bn = _chapterNumber(b.title);
      if (an == null && bn == null) {
        return a.title.compareTo(b.title);
      }
      if (an == null) {
        return 1;
      }
      if (bn == null) {
        return -1;
      }
      return an.compareTo(bn);
    });
    return chapters;
  }

  static List<OnlineMangaSummary> _parseListing(Map<String, dynamic> json) {
    final data = json['data'];
    if (data is! Map) {
      return <OnlineMangaSummary>[];
    }
    final items = data['items'];
    if (items is! List) {
      return <OnlineMangaSummary>[];
    }
    final results = <OnlineMangaSummary>[];
    for (final raw in items) {
      if (raw is! Map) {
        continue;
      }
      final slug = _string(raw['slug']);
      final title = _string(raw['title']);
      if (slug == null || title == null) {
        continue;
      }
      results.add(
        OnlineMangaSummary(
          title: TitleSanitizer.clean(title),
          originalTitle: title,
          url: '$baseUrl/manga/$slug',
          coverUrl: _coverUrl(_string(raw['cover'])),
          description: _plainText(raw['overview']),
          status: _statusLabel(raw['status']),
          sourceId: 'zonatmo_to',
        ),
      );
    }
    return results;
  }

  static String? _mangaSlug(String urlOrSlug) {
    final trimmed = urlOrSlug.trim();
    final uri = Uri.tryParse(trimmed);
    if (uri == null || !uri.hasScheme) {
      final parts = trimmed.split('/').where((part) => part.isNotEmpty);
      return parts.isEmpty ? null : parts.last;
    }
    final segments = uri.pathSegments
        .where((segment) => segment.isNotEmpty)
        .toList();
    if (segments.length >= 2 && segments.first == 'manga') {
      return segments[1];
    }
    return segments.isEmpty ? null : segments.last;
  }

  static (String, String)? _chapterSlugs(String url) {
    final uri = Uri.tryParse(url.trim());
    if (uri == null) {
      return null;
    }
    final segments = uri.pathSegments
        .where((segment) => segment.isNotEmpty)
        .toList();
    if (segments.length >= 3 && segments.first == 'manga') {
      return (segments[1], segments[2].split('#').first);
    }
    return null;
  }

  static String? _coverUrl(String? cover) {
    if (cover == null || cover.trim().isEmpty) {
      return null;
    }
    final value = cover.trim();
    if (value.startsWith('http')) {
      return value;
    }
    return '$uploadsBase/${value.replaceFirst(RegExp(r'^/+'), '')}';
  }

  static String _cdnImage(String jit, String imageName) {
    if (imageName.startsWith('http')) {
      return imageName;
    }
    final cleanJit = jit.replaceAll(RegExp(r'^/+|/+$'), '');
    final cleanName = imageName.replaceFirst(RegExp(r'^/+'), '');
    return '$cdnBase/manga/$cleanJit/$cleanName';
  }

  static String? _statusLabel(Object? raw) {
    final values = raw is List ? raw : [raw];
    final ids = values.map((item) => int.tryParse('$item')).whereType<int>();
    for (final id in ids) {
      switch (id) {
        case 12:
          return 'Publicándose';
        case 19:
          return 'Finalizado';
        case 174:
          return 'Pausado';
        case 198:
          return 'Cancelado';
      }
    }
    return raw is List ? null : _string(raw);
  }

  static Future<List<String>> _genreNames(Object? raw) async {
    if (raw is! List) {
      return const <String>[];
    }
    final needsLabels = raw.any((item) => int.tryParse('$item') != null);
    final labels = needsLabels
        ? await (_genreLabels ??= _loadGenreLabels())
        : const <String, String>{};
    return raw
        .map((item) {
          if (item is Map) return _plainText(item['name']);
          if (int.tryParse('$item') != null) return labels['$item'];
          return _plainText(item);
        })
        .whereType<String>()
        .toSet()
        .toList();
  }

  static Future<Map<String, String>> _loadGenreLabels() async {
    final token = CancellationToken();
    try {
      final html = await SourceHttpClient.withCancellation(
        token,
        () => _getText(baseUrl, accept: 'text/html'),
      ).timeout(const Duration(seconds: 8));
      final match = RegExp(r'\bgenres\s*:\s*\{').firstMatch(html);
      if (match == null) return const {};
      final start = match.end - 1;
      var depth = 0, quoted = false, escaped = false;
      for (var end = start; end < html.length; end++) {
        final char = html[end];
        if (quoted) {
          if (escaped) {
            escaped = false;
          } else if (char == '\\') {
            escaped = true;
          } else if (char == '"') {
            quoted = false;
          }
        } else if (char == '"') {
          quoted = true;
        } else if (char == '{') {
          depth++;
        } else if (char == '}' && --depth == 0) {
          final values = jsonDecode(html.substring(start, end + 1)) as Map;
          return {
            for (final entry in values.entries)
              if (entry.value is Map && _plainText(entry.value['name']) != null)
                '${entry.key}': _plainText(entry.value['name'])!,
          };
        }
      }
    } catch (_) {
      // Los metadatos opcionales no bloquean la ficha ni muestran IDs internos.
      _genreLabels = null;
    } finally {
      token.cancel();
    }
    return const {};
  }

  static String? _plainText(Object? value) {
    final text = _string(value);
    if (text == null) return null;
    return html_parser.parseFragment(text).text?.trim();
  }

  static String? _authorNames(Object? raw) {
    if (raw is! List) {
      return null;
    }
    final names = <String>[];
    for (final item in raw) {
      if (item is Map) {
        final name = _string(item['name']);
        if (name != null) {
          names.add(name);
        }
      }
    }
    return names.isEmpty ? null : names.join(', ');
  }

  static double? _chapterNumber(String title) {
    final match = RegExp(r'(\d+(?:\.\d+)?)').firstMatch(title);
    return double.tryParse(match?.group(1) ?? '');
  }

  static String? _string(Object? value) {
    if (value == null) {
      return null;
    }
    final text = value.toString().trim();
    return text.isEmpty ? null : text;
  }

  static bool _asBool(Object? value) {
    if (value is bool) {
      return value;
    }
    final text = '$value'.toLowerCase();
    return text == 'true' || text == '1';
  }

  static Future<String> _getText(String url, {String? accept}) async {
    final request = await _httpClient.getUrl(Uri.parse(url));
    request.followRedirects = true;
    _headers.forEach(request.headers.set);
    if (accept != null) request.headers.set('Accept', accept);
    final response = await request.close();
    final body = utf8.decode(
      await response.fold<List<int>>(<int>[], (buffer, chunk) {
        buffer.addAll(chunk);
        return buffer;
      }),
    );
    if (response.statusCode >= 400) {
      throw HttpException('HTTP ${response.statusCode} for $url');
    }
    return body;
  }

  static Future<Map<String, dynamic>> _getJson(String url) async {
    final body = await _getText(url);
    final decoded = jsonDecode(body);
    if (decoded is! Map) {
      throw HttpException('Respuesta inválida de zonatmo.to');
    }
    return Map<String, dynamic>.from(decoded);
  }
}
