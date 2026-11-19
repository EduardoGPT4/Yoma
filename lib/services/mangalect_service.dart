import 'dart:convert';

import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;

import '../models/catalog_page.dart';
import '../models/chapter.dart';
import '../models/online_manga.dart';
import '../utils/app_failure.dart';
import '../utils/title_sanitizer.dart';
import 'content_exclusions.dart';
import 'source_http_client.dart';

/// Cliente de MangaLect (https://mangalect.org).
///
/// - Catálogo y búsqueda: `GET /api/buscar_mangas/?query=&page=&page_size=` (JSON)
/// - Novedades: `GET /api/latest_chapters_with_dates/` (JSON)
/// - Ficha: `GET /info/{slug}/`. Muestra 96 capítulos, del más nuevo al más
///   viejo; el resto llega con `?before={número}` (enlace `#more-link`).
/// - Páginas: `GET /lectura/{slug}/{número}/`; la variable `paginasRutas`
///   trae las rutas relativas al CDN `images.mangalect.org`.
class MangaLectService {
  static const String baseUrl = 'https://mangalect.org';
  static const String assetBase =
      'https://images.mangalect.org/file/leermangaesp';

  /// Fijo para que la numeración de páginas no cambie entre peticiones.
  static const int _pageSize = 24;

  /// Tope de páginas de capítulos (96 cada una) por si el enlace se repite.
  static const int _maxChapterPages = 60;

  static const Map<String, String> _defaultHeaders = <String, String>{
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    'Accept': 'text/html,application/xhtml+xml,application/json,*/*;q=0.8',
    'Accept-Language': 'es-ES,es;q=0.9,en;q=0.8',
    'Referer': '$baseUrl/',
  };

  static final SourceHttpClient _httpClient = SourceHttpClient()
    ..idleTimeout = const Duration(seconds: 25)
    ..connectionTimeout = const Duration(seconds: 20);

  static final RegExp _slugPattern = RegExp(r'^[A-Za-z0-9][A-Za-z0-9_-]*$');
  static final RegExp _numberPattern = RegExp(r'^\d+(?:\.\d+)?$');
  static final RegExp _routesPattern = RegExp(
    r'paginasRutas\s*:\s*(\[[^\]]*\])',
  );
  static final RegExp _assetPattern = RegExp(
    r'''B2_URL\s*:\s*['"](https?://[^'"]+)['"]''',
  );

  static List<String> _siteSegments(String ref) {
    final cleaned = ref.trim();
    if (cleaned.isEmpty) return const <String>[];
    final uri = Uri.tryParse(
      cleaned.startsWith('http')
          ? cleaned
          : '$baseUrl${cleaned.startsWith('/') ? cleaned : '/$cleaned'}',
    );
    final host = uri?.host.toLowerCase() ?? '';
    if (host != 'mangalect.org' && !host.endsWith('.mangalect.org')) {
      return const <String>[];
    }
    return uri!.pathSegments.where((part) => part.isNotEmpty).toList();
  }

  /// URL canónica de la ficha. Acepta también la de un capítulo.
  static String? mangaUrl(String ref) {
    final segments = _siteSegments(ref);
    if (segments.length < 2) return null;
    final kind = segments[0];
    final valid =
        (kind == 'info' && segments.length == 2) ||
        (kind == 'lectura' && segments.length == 3);
    if (!valid || !_slugPattern.hasMatch(segments[1])) return null;
    return '$baseUrl/info/${segments[1]}/';
  }

  static String? chapterUrl(String ref) {
    final segments = _siteSegments(ref);
    if (segments.length != 3 || segments[0] != 'lectura') return null;
    final number = chapterNumber(segments[2]);
    if (!_slugPattern.hasMatch(segments[1]) || number == null) return null;
    return '$baseUrl/lectura/${segments[1]}/$number/';
  }

  /// `62.00` → `62`, `90.50` → `90.5`: la forma que el sitio no redirige.
  static String? chapterNumber(String raw) {
    final value = raw.trim();
    if (!_numberPattern.hasMatch(value)) return null;
    final trimmed = value.contains('.')
        ? value
              .replaceFirst(RegExp(r'0+$'), '')
              .replaceFirst(RegExp(r'\.$'), '')
        : value;
    return trimmed.replaceFirst(RegExp(r'^0+(?=\d)'), '');
  }

  static String? _asset(Object? raw) {
    final value = raw?.toString().trim() ?? '';
    if (value.isEmpty) return null;
    if (value.startsWith('https://') || value.startsWith('http://')) {
      return value;
    }
    return '$assetBase/${value.startsWith('/') ? value.substring(1) : value}';
  }

  static String _text(Element? element) =>
      element?.text.replaceAll(RegExp(r'\s+'), ' ').trim() ?? '';

  static String? _typeLabel(Object? raw) {
    final value = raw?.toString().trim() ?? '';
    if (value.isEmpty) return null;
    return '${value[0].toUpperCase()}${value.substring(1).toLowerCase()}';
  }

  /// El sitio repite géneros con y sin tilde o en inglés y en español.
  static List<String> _genres(Iterable<String> raw) {
    String key(String value) => value
        .toLowerCase()
        .replaceAll('á', 'a')
        .replaceAll('é', 'e')
        .replaceAll('í', 'i')
        .replaceAll(RegExp('[óō]'), 'o')
        .replaceAll(RegExp('[úū]'), 'u')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    final seen = <String>{};
    return <String>[
      for (final genre in raw)
        if (genre.trim().isNotEmpty && seen.add(key(genre))) genre.trim(),
    ];
  }

  static bool _excluded(Iterable<String> genres) =>
      genres.any(ContentExclusions.matches);

  static Future<List<int>> _getBytes(Uri uri) async {
    final request = await _httpClient.getUrl(uri);
    _defaultHeaders.forEach(request.headers.set);
    final response = await request.close();
    return response.fold<List<int>>(<int>[], (buffer, chunk) {
      buffer.addAll(chunk);
      return buffer;
    });
  }

  static Future<Document> _getDocument(Uri uri) async => html_parser.parse(
    utf8.decode(await _getBytes(uri), allowMalformed: true),
  );

  static Future<Object?> _getJson(Uri uri) async {
    final text = utf8.decode(await _getBytes(uri), allowMalformed: true);
    try {
      return jsonDecode(text);
    } on FormatException {
      throw const AppFailure(
        FailureKind.parsing,
        'MangaLect devolvió una respuesta no válida.',
      );
    }
  }

  static Future<List<int>> downloadBytes(String url, {String? referer}) async {
    final request = await _httpClient.getUrl(Uri.parse(url));
    request.headers.set('User-Agent', _defaultHeaders['User-Agent']!);
    request.headers.set('Accept', 'image/avif,image/webp,image/*,*/*;q=0.8');
    request.headers.set('Referer', '$baseUrl/');
    final response = await request.close();
    final bytes = await response.fold<List<int>>(<int>[], (buffer, chunk) {
      buffer.addAll(chunk);
      return buffer;
    });
    if (bytes.isEmpty) {
      throw const AppFailure(FailureKind.parsing, 'MangaLect: imagen vacía.');
    }
    return bytes;
  }

  static Future<CatalogPage> fetchCatalogPage({
    int page = 1,
    int postsPerPage = 12,
    String? search,
  }) async {
    final safePage = page < 1 ? 1 : page;
    final query = search?.trim() ?? '';
    final json = await _getJson(
      Uri.parse('$baseUrl/api/buscar_mangas/').replace(
        queryParameters: <String, String>{
          if (query.isNotEmpty) 'query': query,
          'page': '$safePage',
          'page_size': '$_pageSize',
        },
      ),
    );
    if (json is! Map || json['resultados'] is! List) {
      throw const AppFailure(
        FailureKind.parsing,
        'MangaLect: catálogo no válido.',
      );
    }
    final total = int.tryParse('${json['total_pages']}');
    return CatalogPage(
      items: _summaries(json['resultados'] as List),
      currentPage: safePage,
      totalPages: total == null ? safePage : (total < 1 ? 1 : total),
    );
  }

  /// Obras con capítulos recientes, de la más nueva a la más vieja.
  static Future<List<OnlineMangaSummary>> fetchUpdated() async {
    final json = await _getJson(
      Uri.parse('$baseUrl/api/latest_chapters_with_dates/'),
    );
    if (json is! List) {
      throw const AppFailure(
        FailureKind.parsing,
        'MangaLect: novedades no válidas.',
      );
    }
    return _summaries(json);
  }

  static List<OnlineMangaSummary> _summaries(List raw) {
    final items = <OnlineMangaSummary>[];
    final seen = <String>{};
    for (final entry in raw) {
      if (entry is! Map) continue;
      final slug = '${entry['slug'] ?? ''}'.trim();
      final rawTitle = '${entry['titulo'] ?? ''}'.trim();
      if (!_slugPattern.hasMatch(slug) || rawTitle.isEmpty) continue;
      if (!seen.add(slug)) continue;
      final genres = _genres(<String>[
        if (entry['generos'] is List)
          for (final genre in entry['generos'] as List) '$genre',
        if (entry['genero'] is String) entry['genero'] as String,
      ]);
      if (_excluded(genres)) continue;
      final title = TitleSanitizer.clean(rawTitle);
      items.add(
        OnlineMangaSummary(
          title: title.isEmpty ? rawTitle : title,
          originalTitle: rawTitle,
          url: '$baseUrl/info/$slug/',
          coverUrl: _asset(entry['portada']),
          genres: genres
              .where((genre) => genre.toLowerCase() != '${entry['tipo']}')
              .toList(),
          type: _typeLabel(entry['tipo']),
        ),
      );
    }
    return items;
  }

  static Future<OnlineMangaDetail> fetchMangaDetail(String ref) async {
    final url = mangaUrl(ref);
    if (url == null) {
      throw AppFailure(
        FailureKind.parsing,
        'Referencia de MangaLect inválida: $ref',
      );
    }
    final document = await _getDocument(Uri.parse(url));
    final rawTitle = _text(document.querySelector('h1.manga-title'));
    if (rawTitle.isEmpty) {
      throw const AppFailure(
        FailureKind.parsing,
        'No se reconoció la ficha de MangaLect.',
      );
    }
    final title = TitleSanitizer.clean(rawTitle);
    final root = document.querySelector('[data-manga-tipo]');

    final genres = _genres(
      document.querySelectorAll('#info-generos a.genero-item').map(_text),
    );
    if (_excluded(genres)) {
      throw const AppFailure(
        FailureKind.parsing,
        'Esta obra no está disponible en Yoma.',
      );
    }

    final altTitles = <String>[];
    for (final item in document.querySelectorAll('.alternate-titles li')) {
      final text = _text(item);
      // Algunas fichas juntan muchos nombres en una sola línea.
      final names = ','.allMatches(text).length > 2
          ? text.split(',')
          : <String>[text];
      for (final name in names.map((name) => name.trim())) {
        if (name.isNotEmpty &&
            name.toLowerCase() != rawTitle.toLowerCase() &&
            !altTitles.contains(name)) {
          altTitles.add(name);
        }
      }
    }

    final description = _text(document.querySelector('#synopsis-text'));
    final chapters = await _allChapters(url, document);

    return OnlineMangaDetail(
      title: title.isEmpty ? rawTitle : title,
      url: url,
      coverUrl: _asset(root?.attributes['data-portada-rel']),
      description: description.isEmpty ? null : description,
      altTitles: altTitles,
      genres: genres,
      type: _typeLabel(root?.attributes['data-manga-tipo']),
      status: _statusLabel(
        _text(document.querySelector('#info-block .status-text')),
      ),
      chapters: chapters,
    );
  }

  /// Recorre los enlaces «Ver más» y devuelve los capítulos en orden ascendente.
  static Future<List<Chapter>> _allChapters(String url, Document first) async {
    final byPath = <String, Chapter>{};
    var document = first;
    final visited = <String>{};
    for (var page = 0; page < _maxChapterPages; page++) {
      for (final link in document.querySelectorAll(
        '#chapter-list a.chapter-link[data-chapter]',
      )) {
        final path = chapterUrl(link.attributes['href'] ?? '');
        final number = chapterNumber(link.attributes['data-chapter'] ?? '');
        if (path == null || number == null || byPath.containsKey(path)) {
          continue;
        }
        byPath[path] = Chapter(
          number: number,
          title: 'Capítulo $number',
          path: path,
          pages: const <String>[],
          pageCount: 0,
        );
      }
      final before = Uri.tryParse(
        document.querySelector('#more-link')?.attributes['href'] ?? '',
      )?.queryParameters['before'];
      if (before == null || before.isEmpty || !visited.add(before)) break;
      document = await _getDocument(
        Uri.parse(
          url,
        ).replace(queryParameters: <String, String>{'before': before}),
      );
    }
    return byPath.values.toList()..sort(
      (a, b) => double.parse(a.number!).compareTo(double.parse(b.number!)),
    );
  }

  static Future<List<String>> fetchChapterPages(String chapterPath) async {
    final url = chapterUrl(chapterPath);
    if (url == null) {
      throw AppFailure(
        FailureKind.parsing,
        'Capítulo de MangaLect inválido: $chapterPath',
      );
    }
    final bytes = await _getBytes(Uri.parse(url));
    final pages = decodePages(utf8.decode(bytes, allowMalformed: true));
    if (pages.isEmpty) {
      throw const AppFailure(
        FailureKind.parsing,
        'MangaLect: no se encontraron páginas.',
      );
    }
    return pages;
  }

  /// Lee `paginasRutas`; si falta, las imágenes del modo cascada.
  static List<String> decodePages(String html) {
    final routes = _routesPattern.firstMatch(html)?.group(1);
    if (routes != null) {
      try {
        final list = jsonDecode(routes);
        if (list is List) {
          final base = _assetPattern.firstMatch(html)?.group(1) ?? assetBase;
          final pages = <String>[
            for (final route in list)
              if ('$route'.trim().isNotEmpty)
                '$route'.startsWith('http')
                    ? '$route'
                    : '${base.endsWith('/') ? base.substring(0, base.length - 1) : base}/'
                          '${'$route'.startsWith('/') ? '$route'.substring(1) : route}',
          ];
          if (pages.isNotEmpty) return pages;
        }
      } on FormatException {
        // Sigue con el HTML.
      }
    }
    final document = html_parser.parse(html);
    final pages = <String>[];
    for (final image in document.querySelectorAll(
      '#cascade-view img.manga-image',
    )) {
      final src = (image.attributes['src'] ?? '').trim();
      if (src.startsWith('http') && !pages.contains(src)) pages.add(src);
    }
    return pages;
  }

  static String? _statusLabel(String raw) {
    final value = raw.trim();
    return switch (value.toLowerCase()) {
      '' => null,
      'en curso' || 'en emisión' || 'publicándose' => 'Publicándose',
      'finalizado' || 'completado' || 'terminado' => 'Finalizado',
      _ => value,
    };
  }
}
