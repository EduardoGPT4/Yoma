import 'dart:convert';

import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;

import '../models/catalog_page.dart';
import '../models/chapter.dart';
import '../models/online_manga.dart';
import '../utils/app_failure.dart';
import '../utils/title_sanitizer.dart';
import 'source_http_client.dart';

/// Cliente de MangaOni (https://manga-oni.com) vía scraping.
///
/// - Catálogo: `GET /directorio?...&p=` (18 obras por página)
/// - Búsqueda: `GET /buscar?q=` (una sola página de resultados)
/// - Ficha + capítulos: `GET /{manga|manhwa|manhua|one-shot}/{slug}/`
/// - Páginas: `GET /lector/{slug}/{id}/`; la variable `unicap` trae en
///   base64 `directorio||["001.webp", ...]`.
class MangaOniService {
  static const String baseUrl = 'https://manga-oni.com';

  /// El directorio mezcla novelas, que la app no puede leer.
  static const Set<String> _seriesKinds = <String>{
    'manga',
    'manhwa',
    'manhua',
    'one-shot',
    'oneshot',
  };

  static const Map<String, String> _defaultHeaders = <String, String>{
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    'Accept': 'text/html,application/xhtml+xml,*/*;q=0.8',
    'Accept-Language': 'es-ES,es;q=0.9,en;q=0.8',
    'Referer': '$baseUrl/',
  };

  static final SourceHttpClient _httpClient = SourceHttpClient()
    ..idleTimeout = const Duration(seconds: 25)
    ..connectionTimeout = const Duration(seconds: 20);

  static final RegExp _unicapPattern = RegExp(
    r'''unicap\s*=\s*['"]([A-Za-z0-9+/=]+)['"]''',
  );
  static final RegExp _numberPattern = RegExp(r'(\d+(?:\.\d+)?)');

  static List<String> _siteSegments(String ref) {
    final cleaned = ref.trim();
    if (cleaned.isEmpty) return const <String>[];
    final uri = Uri.tryParse(
      cleaned.startsWith('http')
          ? cleaned
          : '$baseUrl${cleaned.startsWith('/') ? cleaned : '/$cleaned'}',
    );
    final host = uri?.host.toLowerCase() ?? '';
    if (host != 'manga-oni.com' && !host.endsWith('.manga-oni.com')) {
      return const <String>[];
    }
    return uri!.pathSegments.where((part) => part.isNotEmpty).toList();
  }

  /// URL canónica de la ficha, o `null` si la referencia no es una obra.
  static String? mangaUrl(String ref) {
    final segments = _siteSegments(ref);
    if (segments.length != 2 || !_seriesKinds.contains(segments[0])) {
      return null;
    }
    return '$baseUrl/${segments[0]}/${segments[1]}/';
  }

  static String? chapterUrl(String ref) {
    final segments = _siteSegments(ref);
    if (segments.length < 3 || segments[0] != 'lector') return null;
    return '$baseUrl/lector/${segments[1]}/${segments[2]}/';
  }

  static String _text(Element? element) =>
      element?.text.replaceAll(RegExp(r'\s+'), ' ').trim() ?? '';

  static String? _typeLabel(String? raw) {
    final value = raw?.trim() ?? '';
    if (value.isEmpty) return null;
    return '${value[0].toUpperCase()}${value.substring(1).toLowerCase()}';
  }

  static Future<Document> _getDocument(Uri uri) async {
    final request = await _httpClient.getUrl(uri);
    _defaultHeaders.forEach(request.headers.set);
    final response = await request.close();
    final bytes = await response.fold<List<int>>(<int>[], (buffer, chunk) {
      buffer.addAll(chunk);
      return buffer;
    });
    return html_parser.parse(utf8.decode(bytes, allowMalformed: true));
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
      throw const AppFailure(FailureKind.parsing, 'MangaOni: imagen vacía.');
    }
    return bytes;
  }

  static Uri _directoryUri(int page, {required String order}) =>
      Uri.parse('$baseUrl/directorio').replace(
        queryParameters: <String, String>{
          'genero': 'false',
          'estado': 'false',
          'filtro': order,
          'tipo': 'false',
          // El +18 tiene su propio apartado en la app; al buscar sí aparece.
          'adulto': '0',
          'orden': 'desc',
          'p': '$page',
        },
      );

  static Future<CatalogPage> fetchCatalogPage({
    int page = 1,
    int postsPerPage = 12,
    String? search,
  }) async {
    final safePage = page < 1 ? 1 : page;
    final query = search?.trim() ?? '';
    if (query.isNotEmpty) {
      // La búsqueda del sitio no pagina.
      if (safePage > 1) {
        return CatalogPage(
          items: const <OnlineMangaSummary>[],
          currentPage: safePage,
          totalPages: 1,
        );
      }
      final document = await _getDocument(
        Uri.parse(
          '$baseUrl/buscar',
        ).replace(queryParameters: <String, String>{'q': query}),
      );
      return CatalogPage(
        items: _parseCards(document),
        currentPage: 1,
        totalPages: 1,
      );
    }

    final document = await _getDocument(
      _directoryUri(safePage, order: 'visitas'),
    );
    final items = _parseCards(document);
    final hasNext =
        items.isNotEmpty &&
        document.querySelector('a.page-link[rel="next"]') != null;
    return CatalogPage(
      items: items,
      currentPage: safePage,
      totalPages: hasNext ? safePage + 1 : safePage,
    );
  }

  /// Obras añadidas recientemente al directorio.
  static Future<List<OnlineMangaSummary>> fetchUpdated() async =>
      _parseCards(await _getDocument(_directoryUri(1, order: 'id')));

  static List<OnlineMangaSummary> _parseCards(Document document) {
    final items = <OnlineMangaSummary>[];
    final seen = <String>{};
    for (final link in document.querySelectorAll('a[itemprop="url"]')) {
      final url = mangaUrl(link.attributes['href'] ?? '');
      if (url == null || !seen.add(url)) continue;
      final image = link.querySelector('img');
      var rawTitle = (image?.attributes['alt'] ?? '').trim();
      if (rawTitle.isEmpty) rawTitle = _text(link.querySelector('span'));
      if (rawTitle.isEmpty) continue;
      final title = TitleSanitizer.clean(rawTitle);
      final cover =
          (image?.attributes['data-src'] ?? image?.attributes['src'] ?? '')
              .trim();
      final kind = _text(link.querySelector('b'));
      items.add(
        OnlineMangaSummary(
          title: title.isEmpty ? rawTitle : title,
          originalTitle: rawTitle,
          url: url,
          coverUrl: cover.startsWith('http') && !cover.endsWith('default.gif')
              ? cover
              : null,
          type: _typeLabel(
            kind.isEmpty ? Uri.parse(url).pathSegments.first : kind,
          ),
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
        'Referencia de MangaOni inválida: $ref',
      );
    }
    final document = await _getDocument(Uri.parse(url));
    final rawTitle = _text(
      document.querySelector('h1.post-title') ?? document.querySelector('h1'),
    );
    if (rawTitle.isEmpty) {
      throw const AppFailure(
        FailureKind.parsing,
        'No se reconoció la ficha de MangaOni.',
      );
    }
    final title = TitleSanitizer.clean(rawTitle);

    final genres = <String>[];
    for (final item in document.querySelectorAll('#categ a')) {
      final name = _text(item);
      if (name.isNotEmpty && !genres.contains(name)) genres.add(name);
    }

    final info = _infoFields(document.querySelector('#info-i'));
    final altTitles = <String>[
      for (final name in (info['alterno'] ?? '').split(RegExp(r'\s*[;|]\s*')))
        if (name.trim().isNotEmpty &&
            name.trim().toLowerCase() != rawTitle.toLowerCase())
          name.trim(),
    ];

    final synopsis = document.querySelector('#sinopsis');
    var description = _text(synopsis);
    final synopsisHeading = _text(synopsis?.querySelector('h3'));
    if (synopsisHeading.isNotEmpty && description.startsWith(synopsisHeading)) {
      description = description.substring(synopsisHeading.length).trim();
    }

    final cover =
        document
            .querySelector('meta[property="og:image"]')
            ?.attributes['content']
            ?.trim() ??
        '';

    final chapters = <Chapter>[];
    final seen = <String>{};
    for (final row in document.querySelectorAll('#c_list a[href]')) {
      final path = chapterUrl(row.attributes['href'] ?? '');
      if (path == null || !seen.add(path)) continue;
      final label = _text(row.querySelector('h3'));
      final dataNumber =
          row.querySelector('[data-num]')?.attributes['data-num']?.trim() ?? '';
      final number = _numberPattern
          .firstMatch(dataNumber.isEmpty ? label : dataNumber)
          ?.group(1);
      chapters.add(
        Chapter(
          number: number,
          title: label.isEmpty
              ? (number == null ? 'Capítulo' : 'Capítulo $number')
              : label,
          path: path,
          pages: const <String>[],
          pageCount: 0,
        ),
      );
    }
    // El sitio lista del más nuevo al más viejo.
    final ordered = chapters.reversed.toList();
    if (ordered.every((chapter) => chapter.number != null)) {
      ordered.sort(
        (a, b) => double.parse(a.number!).compareTo(double.parse(b.number!)),
      );
    }

    return OnlineMangaDetail(
      title: title.isEmpty ? rawTitle : title,
      url: url,
      coverUrl: cover.startsWith('http') ? cover : null,
      description: description.isEmpty ? null : description,
      altTitles: altTitles,
      genres: genres,
      type: _typeLabel(Uri.parse(url).pathSegments.first),
      status: _statusLabel(info['estado']),
      author: (info['autor'] ?? '').isEmpty ? null : info['autor'],
      year: RegExp(r'\d{4}').firstMatch(info['fecha'] ?? '')?.group(0),
      chapters: ordered,
    );
  }

  /// `<strong>Autor:</strong> Nombre <br>` → `{autor: Nombre}`.
  static Map<String, String> _infoFields(Element? info) {
    final fields = <String, String>{};
    if (info == null) return fields;
    String? key;
    final value = StringBuffer();
    void flush() {
      final text = value.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
      final name = key;
      if (name != null && text.isNotEmpty) fields[name] = text;
      value.clear();
    }

    for (final node in info.nodes) {
      if (node is Element && node.localName == 'strong') {
        flush();
        key = node.text.replaceAll(':', '').trim().toLowerCase();
      } else if (node is Element && node.localName == 'br') {
        flush();
        key = null;
      } else {
        value.write(node.text ?? '');
      }
    }
    flush();
    return fields;
  }

  static Future<List<String>> fetchChapterPages(String chapterPath) async {
    final url = chapterUrl(chapterPath);
    if (url == null) {
      throw AppFailure(
        FailureKind.parsing,
        'Capítulo de MangaOni inválido: $chapterPath',
      );
    }
    final document = await _getDocument(Uri.parse(url));
    final pages = decodePages(document.outerHtml);
    if (pages.isEmpty) {
      throw const AppFailure(
        FailureKind.parsing,
        'MangaOni: no se encontraron páginas.',
      );
    }
    return pages;
  }

  /// Decodifica `unicap`: base64 de `directorio||["001.webp", ...]`.
  static List<String> decodePages(String html) {
    final encoded = _unicapPattern.firstMatch(html)?.group(1);
    if (encoded == null) return const <String>[];
    try {
      final parts = utf8
          .decode(base64.decode(base64.normalize(encoded)))
          .split('||');
      if (parts.length < 2 || !parts[0].startsWith('http')) {
        return const <String>[];
      }
      final names = jsonDecode(parts[1]);
      if (names is! List) return const <String>[];
      return <String>[
        for (final name in names)
          if (name.toString().trim().isNotEmpty) '${parts[0]}$name',
      ];
    } on FormatException {
      return const <String>[];
    }
  }

  static String? _statusLabel(String? raw) {
    final value = raw?.trim() ?? '';
    return switch (value.toLowerCase()) {
      '' => null,
      'en desarrollo' => 'Publicándose',
      'completo' => 'Finalizado',
      _ => value,
    };
  }
}
