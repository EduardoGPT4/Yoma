import 'dart:convert';

import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;

import '../models/catalog_page.dart';
import '../models/chapter.dart';
import '../models/online_manga.dart';
import '../utils/app_failure.dart';
import '../utils/title_sanitizer.dart';
import 'source_http_client.dart';

/// Cliente de LeerCapitulo (https://www.leercapitulo.co) vía scraping.
///
/// - Catálogo / búsqueda: `GET /manga/?q=&page=`
/// - Tendencias: portada del sitio
/// - Ficha + capítulos: `GET /manga/{id}/{slug}/`
/// - Páginas: `GET /leer/{id}/{slug}/{número}/` (`img[data-src]`)
///
/// Las imágenes viven en un CDN de nombre variable que no exige Referer.
class LeerCapituloService {
  static const String baseUrl = 'https://www.leercapitulo.co';

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

  static final RegExp _mangaPath = RegExp(r'^/manga/([a-z0-9]+)/([^/]+)/?$');
  static final RegExp _chapterPath = RegExp(
    r'^/leer/([a-z0-9]+)/([^/]+)/([^/]+)/?$',
  );
  static final RegExp _numberPattern = RegExp(r'(\d+(?:\.\d+)?)');

  static Uri? _siteUri(String ref) {
    final cleaned = ref.trim();
    if (cleaned.isEmpty) return null;
    final uri = Uri.tryParse(
      cleaned.startsWith('http')
          ? cleaned
          : '$baseUrl${cleaned.startsWith('/') ? cleaned : '/$cleaned'}',
    );
    if (uri == null) return null;
    final host = uri.host.toLowerCase();
    return host == 'leercapitulo.co' || host.endsWith('.leercapitulo.co')
        ? uri
        : null;
  }

  /// URL canónica de la ficha, o `null` si la referencia no es de este sitio.
  static String? mangaUrl(String ref) {
    final match = _mangaPath.firstMatch(_siteUri(ref)?.path ?? '');
    if (match != null) {
      return '$baseUrl/manga/${match.group(1)}/${match.group(2)}/';
    }
    final chapter = _chapterPath.firstMatch(_siteUri(ref)?.path ?? '');
    return chapter == null
        ? null
        : '$baseUrl/manga/${chapter.group(1)}/${chapter.group(2)}/';
  }

  static String? chapterUrl(String ref) {
    final match = _chapterPath.firstMatch(_siteUri(ref)?.path ?? '');
    return match == null
        ? null
        : '$baseUrl/leer/${match.group(1)}/${match.group(2)}/${match.group(3)}/';
  }

  static String? _absolute(String? raw) {
    final value = raw?.trim() ?? '';
    if (value.isEmpty || value.startsWith('data:')) return null;
    if (value.startsWith('http://') || value.startsWith('https://')) {
      return value;
    }
    if (value.startsWith('//')) return 'https:$value';
    return value.startsWith('/') ? '$baseUrl$value' : null;
  }

  static String _text(Element? element) =>
      element?.text.replaceAll(RegExp(r'\s+'), ' ').trim() ?? '';

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
      throw const AppFailure(
        FailureKind.parsing,
        'LeerCapitulo: imagen vacía.',
      );
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
    final document = await _getDocument(
      Uri.parse('$baseUrl/manga/').replace(
        queryParameters: <String, String>{
          if (query.isNotEmpty) 'q': query,
          if (safePage > 1) 'page': '$safePage',
        },
      ),
    );

    final items = <OnlineMangaSummary>[];
    final seen = <String>{};
    for (final card in document.querySelectorAll('article.lc-card')) {
      final link =
          card.querySelector('a.lc-card-name') ??
          card.querySelector('a[href*="/manga/"]');
      final summary = _summary(
        href: link?.attributes['href'],
        rawTitle: _text(link),
        cover: card.querySelector('img'),
        type: _text(card.querySelector('.lc-card-badge')),
      );
      if (summary != null && seen.add(summary.url)) items.add(summary);
    }

    final hasNext =
        document.querySelector('a.page-link[rel="next"]') != null &&
        items.isNotEmpty;
    return CatalogPage(
      items: items,
      currentPage: safePage,
      totalPages: hasNext ? safePage + 1 : safePage,
    );
  }

  /// Tendencias, populares y últimos mangas de la portada.
  static Future<List<OnlineMangaSummary>> fetchUpdated() async {
    final document = await _getDocument(Uri.parse('$baseUrl/'));
    final items = <OnlineMangaSummary>[];
    final seen = <String>{};
    for (final block in document.querySelectorAll(
      '.lc-slide, a.lc-side-item',
    )) {
      final link = block.localName == 'a'
          ? block
          : (block.querySelector('a.lc-slide-name') ??
                block.querySelector('a[href*="/manga/"]'));
      final name =
          block.querySelector('.lc-side-name') ??
          block.querySelector('.lc-slide-name');
      final summary = _summary(
        href: link?.attributes['href'],
        rawTitle: _text(name),
        cover: block.querySelector('img'),
      );
      if (summary != null && seen.add(summary.url)) items.add(summary);
    }
    return items;
  }

  static OnlineMangaSummary? _summary({
    required String? href,
    required String rawTitle,
    Element? cover,
    String? type,
  }) {
    final url = mangaUrl(href ?? '');
    if (url == null || rawTitle.isEmpty) return null;
    final title = TitleSanitizer.clean(rawTitle);
    return OnlineMangaSummary(
      title: title.isEmpty ? rawTitle : title,
      originalTitle: rawTitle,
      url: url,
      coverUrl: _absolute(
        cover?.attributes['data-src'] ?? cover?.attributes['src'],
      ),
      type: (type == null || type.isEmpty) ? null : type,
    );
  }

  static Future<OnlineMangaDetail> fetchMangaDetail(String ref) async {
    final url = mangaUrl(ref);
    if (url == null) {
      throw AppFailure(
        FailureKind.parsing,
        'Referencia de LeerCapitulo inválida: $ref',
      );
    }
    final document = await _getDocument(Uri.parse(url));
    final heading = document.querySelector('h1');
    final rawTitle = _text(heading);
    if (rawTitle.isEmpty) {
      throw const AppFailure(
        FailureKind.parsing,
        'No se reconoció la ficha de LeerCapitulo.',
      );
    }
    final title = TitleSanitizer.clean(rawTitle);

    final altTitles = <String>[];
    final sibling = heading?.nextElementSibling;
    if (sibling != null && sibling.localName == 'p') {
      final titleKey = rawTitle.toLowerCase();
      for (final name in sibling.text.split('·')) {
        final value = name.replaceAll(RegExp(r'\s+'), ' ').trim();
        if (value.isNotEmpty &&
            value.toLowerCase() != titleKey &&
            !altTitles.contains(value)) {
          altTitles.add(value);
        }
      }
    }

    final genres = <String>[];
    for (final badge
        in heading?.parent?.querySelectorAll('a.badge') ?? const <Element>[]) {
      final name = _text(badge);
      if (name.isNotEmpty && !genres.contains(name)) genres.add(name);
    }

    final facts = <String, String>{};
    for (final item in document.querySelectorAll('ul.lc-facts li')) {
      final key = _text(item.querySelector('.k')).toLowerCase();
      final value = _text(
        item,
      ).substring(_text(item.querySelector('.k')).length);
      if (key.isNotEmpty) facts[key] = value.trim();
    }

    final chapters = <Chapter>[];
    final seen = <String>{};
    for (final row in document.querySelectorAll(
      '#chapterList a[href*="/leer/"]',
    )) {
      final path = chapterUrl(row.attributes['href'] ?? '');
      if (path == null || !seen.add(path)) continue;
      final label = _text(row.querySelector('.n'));
      final number = _numberPattern
          .firstMatch(
            label.isEmpty ? path.split('/').reversed.elementAt(1) : label,
          )
          ?.group(1);
      chapters.add(
        Chapter(
          number: number,
          title: number == null
              ? (label.isEmpty ? 'Capítulo' : label)
              : 'Capítulo $number',
          path: path,
          pages: const <String>[],
          pageCount: 0,
        ),
      );
    }
    chapters.sort(
      (a, b) => (double.tryParse(a.number ?? '') ?? 0).compareTo(
        double.tryParse(b.number ?? '') ?? 0,
      ),
    );

    final description = _text(
      document.querySelector('#sinopsis p') ??
          document.querySelector('#sinopsis div'),
    );
    final author = facts['autor'];
    return OnlineMangaDetail(
      title: title.isEmpty ? rawTitle : title,
      url: url,
      coverUrl: _absolute(
        document.querySelector('.lc-cover-lg img')?.attributes['src'],
      ),
      description: description.isEmpty ? null : description,
      altTitles: altTitles,
      genres: genres,
      type: (facts['tipo'] ?? '').isEmpty ? null : facts['tipo'],
      status: _statusLabel(facts['estado']),
      author: (author == null || author.isEmpty) ? null : author,
      chapters: chapters,
    );
  }

  static Future<List<String>> fetchChapterPages(String chapterPath) async {
    final url = chapterUrl(chapterPath);
    if (url == null) {
      throw AppFailure(
        FailureKind.parsing,
        'Capítulo de LeerCapitulo inválido: $chapterPath',
      );
    }
    final document = await _getDocument(Uri.parse(url));
    final pages = <String>[];
    for (final image in document.querySelectorAll(
      '#lcPages img, main.lc-pages img',
    )) {
      final page = _absolute(
        image.attributes['data-src'] ?? image.attributes['src'],
      );
      if (page != null && !pages.contains(page)) pages.add(page);
    }
    if (pages.isEmpty) {
      throw const AppFailure(
        FailureKind.parsing,
        'LeerCapitulo: no se encontraron páginas.',
      );
    }
    return pages;
  }

  static String? _statusLabel(String? raw) {
    final value = raw?.trim() ?? '';
    return switch (value.toLowerCase()) {
      '' => null,
      'ongoing' => 'Publicándose',
      'completed' => 'Finalizado',
      'paused' => 'Hiatus',
      'cancelled' => 'Cancelado',
      _ => value,
    };
  }
}
