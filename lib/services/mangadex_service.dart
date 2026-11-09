import 'source_http_client.dart';
import '../models/chapter_batch.dart';
import '../utils/app_failure.dart';
import 'dart:convert';
import 'dart:io';

import '../models/chapter.dart';
import '../models/online_manga.dart';
import '../utils/title_sanitizer.dart';
import '../models/catalog_page.dart';

/// Cliente de la API pública de MangaDex (https://api.mangadex.org).
///
/// Devuelve los mismos modelos que el resto del catálogo online
/// ([OnlineMangaSummary], [OnlineMangaDetail], [CatalogPage]) para reutilizar UI y cola.
/// Idioma de traducción de capítulos en MangaDex.
class MangaDexLanguage {
  final String code;
  final String label;

  const MangaDexLanguage({required this.code, required this.label});

  static const castilian = MangaDexLanguage(
    code: 'es',
    label: 'Español (España)',
  );
  static const latin = MangaDexLanguage(
    code: 'es-la',
    label: 'Español (Latino)',
  );

  /// Idiomas de capítulos; las variantes regionales usan los códigos de MangaDex.
  /// https://api.mangadex.org/docs/3-enumerations/#language-codes--localization
  static const selectable = <MangaDexLanguage>[
    castilian,
    latin,
    MangaDexLanguage(code: 'de', label: 'Alemán'),
    MangaDexLanguage(code: 'ar', label: 'Árabe'),
    MangaDexLanguage(code: 'bn', label: 'Bengalí'),
    MangaDexLanguage(code: 'bg', label: 'Búlgaro'),
    MangaDexLanguage(code: 'ca', label: 'Catalán'),
    MangaDexLanguage(code: 'cs', label: 'Checo'),
    MangaDexLanguage(code: 'zh', label: 'Chino (simplificado)'),
    MangaDexLanguage(code: 'zh-hk', label: 'Chino (tradicional)'),
    MangaDexLanguage(code: 'ko', label: 'Coreano'),
    MangaDexLanguage(code: 'hr', label: 'Croata'),
    MangaDexLanguage(code: 'da', label: 'Danés'),
    MangaDexLanguage(code: 'sk', label: 'Eslovaco'),
    MangaDexLanguage(code: 'sl', label: 'Esloveno'),
    MangaDexLanguage(code: 'fi', label: 'Finés'),
    MangaDexLanguage(code: 'fr', label: 'Francés'),
    MangaDexLanguage(code: 'el', label: 'Griego'),
    MangaDexLanguage(code: 'he', label: 'Hebreo'),
    MangaDexLanguage(code: 'hi', label: 'Hindi'),
    MangaDexLanguage(code: 'hu', label: 'Húngaro'),
    MangaDexLanguage(code: 'id', label: 'Indonesio'),
    MangaDexLanguage(code: 'en', label: 'Inglés'),
    MangaDexLanguage(code: 'it', label: 'Italiano'),
    MangaDexLanguage(code: 'ja', label: 'Japonés'),
    MangaDexLanguage(code: 'lt', label: 'Lituano'),
    MangaDexLanguage(code: 'ms', label: 'Malayo'),
    MangaDexLanguage(code: 'nl', label: 'Neerlandés'),
    MangaDexLanguage(code: 'no', label: 'Noruego'),
    MangaDexLanguage(code: 'fa', label: 'Persa'),
    MangaDexLanguage(code: 'pl', label: 'Polaco'),
    MangaDexLanguage(code: 'pt', label: 'Portugués (Portugal)'),
    MangaDexLanguage(code: 'pt-br', label: 'Portugués (Brasil)'),
    MangaDexLanguage(code: 'ro', label: 'Rumano'),
    MangaDexLanguage(code: 'ru', label: 'Ruso'),
    MangaDexLanguage(code: 'sr', label: 'Serbio'),
    MangaDexLanguage(code: 'sv', label: 'Sueco'),
    MangaDexLanguage(code: 'tl', label: 'Tagalo'),
    MangaDexLanguage(code: 'th', label: 'Tailandés'),
    MangaDexLanguage(code: 'tr', label: 'Turco'),
    MangaDexLanguage(code: 'uk', label: 'Ucraniano'),
    MangaDexLanguage(code: 'vi', label: 'Vietnamita'),
  ];

  /// Conserva la selección inicial de España + Latino.
  static const defaultCodes = <String>['es', 'es-la'];

  static final _supportedCodes = selectable
      .map((language) => language.code)
      .toSet();

  static bool supports(String code) => _supportedCodes.contains(code);

  /// Mismo saneado para la interfaz y el servicio de descargas en segundo plano.
  static List<String> normalizeCodes(Iterable<String> codes) {
    final cleaned = codes
        .map((code) => code.trim().toLowerCase())
        .where(supports)
        .toSet()
        .toList();
    return cleaned.isEmpty ? List<String>.from(defaultCodes) : cleaned;
  }
}

class MangaDexService {
  static bool dataSaver = false;
  static const String apiBase = 'https://api.mangadex.org';
  static const String siteBase = 'https://mangadex.org';
  static const String uploadsBase = 'https://uploads.mangadex.org';

  static const Map<String, String> _defaultHeaders = {
    'User-Agent': 'YomaShi/2.1.0 (Flutter; manga reader)',
    'Accept': 'application/json',
  };

  static final SourceHttpClient _httpClient = SourceHttpClient()
    ..idleTimeout = const Duration(seconds: 25)
    ..connectionTimeout = const Duration(seconds: 20);

  /// Códigos activos para catálogo y feed (`es`, `es-la`, …).
  static List<String> _preferredLanguages = List<String>.from(
    MangaDexLanguage.defaultCodes,
  );

  static List<String> get preferredLanguages =>
      List<String>.unmodifiable(_preferredLanguages);

  /// Actualiza idiomas preferidos conservando su orden de prioridad.
  static void setPreferredLanguages(List<String> codes) {
    _preferredLanguages = MangaDexLanguage.normalizeCodes(codes);
  }

  static List<String> _languageQueryParams(
    String key, [
    List<String>? languages,
  ]) {
    return (languages ?? preferredLanguages)
        .map((code) => '$key=${Uri.encodeQueryComponent(code)}')
        .toList();
  }

  /// True si la URL/id pertenece a MangaDex.
  static bool isMangaDexRef(String? value) {
    if (value == null || value.trim().isEmpty) {
      return false;
    }
    final v = value.toLowerCase();
    return v.contains('mangadex.org') ||
        v.startsWith('md:') ||
        v.startsWith('mangadex:');
  }

  static String mangaSiteUrl(String mangaId) => '$siteBase/title/$mangaId';

  static String? extractMangaId(String urlOrId) {
    final cleaned = urlOrId.trim();
    if (cleaned.isEmpty) {
      return null;
    }
    if (RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
      caseSensitive: false,
    ).hasMatch(cleaned)) {
      return cleaned;
    }
    final uri = Uri.tryParse(cleaned);
    if (uri == null) {
      return null;
    }
    final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    // /title/{id} or /title/{id}/slug
    final titleIndex = segments.indexOf('title');
    if (titleIndex >= 0 && titleIndex + 1 < segments.length) {
      return segments[titleIndex + 1];
    }
    // /manga/{id} legacy
    final mangaIndex = segments.indexOf('manga');
    if (mangaIndex >= 0 && mangaIndex + 1 < segments.length) {
      return segments[mangaIndex + 1];
    }
    return null;
  }

  static String? extractChapterId(String pathOrUrl) {
    final cleaned = pathOrUrl.trim();
    if (cleaned.isEmpty) {
      return null;
    }
    if (RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
      caseSensitive: false,
    ).hasMatch(cleaned)) {
      return cleaned;
    }
    final uri = Uri.tryParse(cleaned);
    if (uri == null) {
      return null;
    }
    final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    final chapterIndex = segments.indexOf('chapter');
    if (chapterIndex >= 0 && chapterIndex + 1 < segments.length) {
      return segments[chapterIndex + 1];
    }
    // mangadex://chapter/{id}
    if (uri.scheme == 'mangadex' || uri.scheme == 'md') {
      if (segments.isNotEmpty) {
        return segments.last;
      }
    }
    return null;
  }

  static Future<dynamic> _getJson(Uri uri) async {
    final request = await _httpClient.getUrl(uri);
    _defaultHeaders.forEach(request.headers.set);
    final response = await request.close().timeout(const Duration(seconds: 30));
    final body = await response.fold<List<int>>(<int>[], (buffer, chunk) {
      buffer.addAll(chunk);
      return buffer;
    });
    final text = utf8.decode(body);
    if (response.statusCode >= 400) {
      throw HttpException('MangaDex HTTP ${response.statusCode}: $text');
    }
    return jsonDecode(text);
  }

  static Future<List<int>> downloadBytes(String url) async {
    final uri = Uri.parse(url);
    final request = await _httpClient.getUrl(uri);
    _defaultHeaders.forEach(request.headers.set);
    // At-home CDN a veces es más permisivo con Accept image/*
    request.headers.set('Accept', 'image/*,*/*;q=0.8');
    final response = await request.close().timeout(const Duration(seconds: 45));
    if (response.statusCode >= 400) {
      throw HttpException(
        'MangaDex download HTTP ${response.statusCode} for $uri',
      );
    }
    return response.fold<List<int>>(<int>[], (buffer, chunk) {
      buffer.addAll(chunk);
      return buffer;
    });
  }

  static Future<CatalogPage> fetchCatalogPage({
    int page = 1,
    int postsPerPage = 12,
    String? search,
    String order = 'latest',
  }) async {
    final limit = postsPerPage.clamp(1, 32);
    final offset = ((page < 1 ? 1 : page) - 1) * limit;

    // Uri.replace no soporta bien keys repetidas; construimos query a mano.
    final query = <String>[
      'limit=$limit',
      'offset=$offset',
      'includes[]=cover_art',
      'contentRating[]=safe',
      'contentRating[]=suggestive',
      'contentRating[]=erotica',
      ..._languageQueryParams('availableTranslatedLanguage[]'),
    ];

    final cleaned = search?.trim();
    if (cleaned != null && cleaned.isNotEmpty) {
      query.add('title=${Uri.encodeQueryComponent(cleaned)}');
      query.add('order[relevance]=desc');
    } else if (order == 'followed') {
      query.add('order[followedCount]=desc');
    } else {
      query.add('order[latestUploadedChapter]=desc');
    }

    final uri = Uri.parse('$apiBase/manga?${query.join('&')}');
    final response = await _getJson(uri);
    if (response is! Map<String, dynamic>) {
      return const CatalogPage(items: <OnlineMangaSummary>[]);
    }

    final data = response['data'];
    final total = int.tryParse('${response['total']}') ?? 0;
    final items = data is List
        ? data
              .whereType<Map<String, dynamic>>()
              .map(_summaryFromMangaEntity)
              .whereType<OnlineMangaSummary>()
              .toList()
        : <OnlineMangaSummary>[];

    final totalPages = total > 0 ? (total / limit).ceil() : 1;

    return CatalogPage(
      items: items,
      currentPage: page < 1 ? 1 : page,
      totalPages: totalPages,
    );
  }

  static Future<List<OnlineMangaSummary>> fetchUpdated() async {
    final page = await fetchCatalogPage(
      page: 1,
      postsPerPage: 18,
      order: 'latest',
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

  static Future<OnlineMangaDetail> fetchMangaDetail(
    String urlOrId, {
    bool initialChaptersOnly = false,
  }) async {
    final mangaId = extractMangaId(urlOrId);
    if (mangaId == null) {
      throw StateError('ID de manga MangaDex inválido: $urlOrId');
    }

    final uri = Uri.parse(
      '$apiBase/manga/$mangaId?includes[]=cover_art&includes[]=author&includes[]=artist',
    );
    final response = await _getJson(uri);
    if (response is! Map<String, dynamic>) {
      throw StateError('Respuesta MangaDex inválida para $mangaId');
    }
    final data = response['data'];
    if (data is! Map<String, dynamic>) {
      throw StateError('Manga no encontrado en MangaDex: $mangaId');
    }

    final attributes = data['attributes'] as Map<String, dynamic>? ?? {};
    final relationships = data['relationships'] as List<dynamic>? ?? [];
    final title = TitleSanitizer.clean(
      _localizedString(attributes['title']) ?? 'Manga',
    );
    final description = _localizedString(attributes['description']);
    final altTitles = _altTitles(attributes['altTitles']);
    final status = attributes['status']?.toString();
    final year = attributes['year']?.toString();
    final tags = _tagNames(attributes['tags']);
    final author = _authorNames(relationships);
    final coverFile = _coverFileName(relationships);
    final coverUrl = coverFile == null
        ? null
        : '$uploadsBase/covers/$mangaId/$coverFile';

    final batch = initialChaptersOnly
        ? await fetchChapterBatch(mangaId, 0)
        : null;
    final chapters = batch?.chapters ?? await _fetchAllChapters(mangaId);

    return OnlineMangaDetail(
      title: title,
      url: mangaSiteUrl(mangaId),
      coverUrl: coverUrl,
      description: description,
      altTitles: altTitles,
      genres: tags,
      type: _mangaType(attributes),
      status: status,
      author: author,
      year: year,
      chapters: chapters,
      hasMoreChapters: batch?.hasMore ?? false,
      nextChapterCursor: batch?.nextCursor ?? 0,
    );
  }

  static Future<List<String>> fetchChapterPages(
    String chapterPath, {
    bool? useDataSaver,
  }) async {
    final saver = useDataSaver ?? MangaDexService.dataSaver;
    final chapterId = extractChapterId(chapterPath);
    if (chapterId == null) {
      throw StateError('ID de capítulo MangaDex inválido: $chapterPath');
    }

    final uri = Uri.parse('$apiBase/at-home/server/$chapterId');
    final response = await _getJson(uri);
    if (response is! Map<String, dynamic>) {
      throw const AppFailure(
        FailureKind.parsing,
        'MangaDex: respuesta de páginas inválida.',
      );
    }

    final baseUrl = response['baseUrl']?.toString();
    final chapter = response['chapter'];
    if (baseUrl == null || chapter is! Map<String, dynamic>) {
      throw const AppFailure(
        FailureKind.parsing,
        'MangaDex: respuesta de páginas inválida.',
      );
    }

    final hash = chapter['hash']?.toString();
    // Prefer full quality; fallback data-saver.
    final data = chapter['data'];
    final dataSaver = chapter['dataSaver'];
    final List<dynamic> files;
    final String quality;
    if (!saver && data is List && data.isNotEmpty) {
      files = data;
      quality = 'data';
    } else if (dataSaver is List && dataSaver.isNotEmpty) {
      files = dataSaver;
      quality = 'data-saver';
    } else if (data is List && data.isNotEmpty) {
      files = data;
      quality = 'data';
    } else {
      throw const AppFailure(
        FailureKind.parsing,
        'MangaDex: respuesta de páginas inválida.',
      );
    }

    if (hash == null || hash.isEmpty) {
      throw const AppFailure(
        FailureKind.parsing,
        'MangaDex: respuesta de páginas inválida.',
      );
    }

    return files
        .map((file) => file?.toString() ?? '')
        .where((file) => file.isNotEmpty)
        .map((file) => '$baseUrl/$quality/$hash/$file')
        .toList();
  }

  static Future<ChapterBatch> fetchChapterBatch(String ref, int cursor) async {
    final id = extractMangaId(ref);
    if (id == null) throw StateError('ID de MangaDex inválido.');
    var next = cursor, more = false;
    final chapters = await _fetchAllChapters(
      id,
      onlyOffset: cursor,
      onPage: (n, m) {
        next = n;
        more = m;
      },
    );
    return ChapterBatch(chapters: chapters, nextCursor: next, hasMore: more);
  }

  static Future<List<Chapter>> _fetchAllChapters(
    String mangaId, {
    int? onlyOffset,
    void Function(int, bool)? onPage,
  }) async {
    final languages = preferredLanguages;
    final chapters = <Chapter>[];
    const limit = 100;
    var offset = onlyOffset ?? 0;
    var total = offset + 1;

    while (offset < total) {
      // No filtrar contentRating en el feed: muchos capítulos quedan fuera
      // y el manga parece vacío (p. ej. Solo Leveling).
      final query = <String>[
        'limit=$limit',
        'offset=$offset',
        ..._languageQueryParams('translatedLanguage[]', languages),
        'order[chapter]=asc',
        'order[volume]=asc',
        'includeEmptyPages=0',
        'includeFuturePublishAt=0',
        'includeExternalUrl=0',
      ];
      final uri = Uri.parse('$apiBase/manga/$mangaId/feed?${query.join('&')}');
      final response = await _getJson(uri);
      if (response is! Map<String, dynamic>) {
        throw const AppFailure(
          FailureKind.parsing,
          'Lista de capítulos de MangaDex inválida.',
        );
      }
      total = int.tryParse('${response['total']}') ?? 0;
      final data = response['data'];
      if (data is! List || data.isEmpty) {
        if (offset < total) {
          throw const AppFailure(
            FailureKind.parsing,
            'La lista de capítulos de MangaDex está incompleta.',
          );
        }
        break;
      }

      onPage?.call(offset + data.length, offset + data.length < total);
      for (final item in data.whereType<Map<String, dynamic>>()) {
        final id = item['id']?.toString();
        final attributes =
            item['attributes'] as Map<String, dynamic>? ?? <String, dynamic>{};
        if (id == null || id.isEmpty) {
          continue;
        }
        // Saltar capítulos externos (solo enlace).
        final external = attributes['externalUrl']?.toString();
        if (external != null && external.isNotEmpty) {
          continue;
        }
        final pages = int.tryParse('${attributes['pages']}') ?? 0;
        if (pages <= 0) {
          continue;
        }

        final chapterNum = attributes['chapter']?.toString();
        final volume = attributes['volume']?.toString();
        final titleAttr = attributes['title']?.toString().trim();
        final lang = attributes['translatedLanguage']?.toString() ?? '';

        final title = _chapterTitle(
          chapterNum: chapterNum,
          volume: volume,
          title: titleAttr,
          lang: lang,
        );

        chapters.add(
          Chapter(
            title: title,
            path: '$siteBase/chapter/$id',
            pages: const <String>[],
            pageCount: pages,
            number: chapterNum,
            volume: volume,
            language: lang,
          ),
        );
      }

      offset += data.length;
      if (onlyOffset != null) break;
    }

    // Deduplicar por número de capítulo preferiendo español.
    return _preferSpanishChapters(chapters, languages);
  }

  static List<Chapter> _preferSpanishChapters(
    List<Chapter> chapters,
    List<String> languages,
  ) {
    // Si hay el mismo capítulo en varios idiomas, preferimos el orden de preferredLanguages.
    final priority = <String, int>{
      for (var i = 0; i < languages.length; i++) languages[i]: i,
    };
    final byKey = <String, Chapter>{};
    final byKeyLang = <String, String>{};

    for (final chapter in chapters) {
      final lang = chapter.language ?? '';
      final key = chapter.number == null || chapter.number!.isEmpty
          ? chapter.path
          : '${chapter.volume ?? ''}|${chapter.number}';
      final existing = byKey[key];
      if (existing == null) {
        byKey[key] = chapter;
        byKeyLang[key] = lang;
        continue;
      }
      final existingLang = byKeyLang[key] ?? '';
      final newRank = priority[lang] ?? 999;
      final oldRank = priority[existingLang] ?? 999;
      if (newRank < oldRank) {
        byKey[key] = chapter;
        byKeyLang[key] = lang;
      }
    }
    return byKey.values.toList();
  }

  static String _chapterTitle({
    required String? chapterNum,
    required String? volume,
    required String? title,
    required String lang,
  }) {
    final parts = <String>[];
    if (volume != null && volume.isNotEmpty && volume != 'null') {
      parts.add('Vol. $volume');
    }
    if (chapterNum != null && chapterNum.isNotEmpty && chapterNum != 'null') {
      parts.add('Capítulo $chapterNum');
    } else {
      parts.add('Capítulo');
    }
    if (title != null && title.isNotEmpty) {
      parts.add(title);
    }
    final base = parts.join(' · ');
    if (lang.isEmpty) {
      return base;
    }
    return '$base ($lang)';
  }

  static OnlineMangaSummary? _summaryFromMangaEntity(
    Map<String, dynamic> entity,
  ) {
    final id = entity['id']?.toString();
    if (id == null || id.isEmpty) {
      return null;
    }
    final attributes = entity['attributes'] as Map<String, dynamic>? ?? {};
    final relationships = entity['relationships'] as List<dynamic>? ?? [];
    final originalTitle = _localizedString(attributes['title']) ?? 'Manga';
    final title = TitleSanitizer.clean(originalTitle);
    final description = _localizedString(attributes['description']);
    final status = attributes['status']?.toString();
    final coverFile = _coverFileName(relationships);
    final coverUrl = coverFile == null
        ? null
        : '$uploadsBase/covers/$id/$coverFile.256.jpg';
    final tags = _tagNames(attributes['tags']);

    return OnlineMangaSummary(
      title: title,
      originalTitle: originalTitle,
      url: mangaSiteUrl(id),
      coverUrl: coverUrl,
      description: description,
      genres: tags,
      type: _mangaType(attributes),
      status: status,
    );
  }

  static String? _mangaType(Map<String, dynamic> attributes) {
    return switch (attributes['originalLanguage']) {
      'ko' => 'MANHWA',
      'zh' || 'zh-hk' => 'MANHUA',
      'ja' => 'MANGA',
      _ => null,
    };
  }

  static String? _localizedString(dynamic value) {
    if (value is String && value.trim().isNotEmpty) {
      return value.trim();
    }
    if (value is! Map) {
      return null;
    }
    final map = value.map(
      (k, v) => MapEntry(k.toString(), v?.toString() ?? ''),
    );
    for (final lang in [
      ...preferredLanguages,
      'es',
      'es-la',
      'en',
      'ja-ro',
      'ja',
    ]) {
      final text = map[lang]?.trim();
      if (text != null && text.isNotEmpty) {
        return text;
      }
    }
    for (final text in map.values) {
      if (text.trim().isNotEmpty) {
        return text.trim();
      }
    }
    return null;
  }

  static List<String> _altTitles(dynamic raw) {
    if (raw is! List) {
      return <String>[];
    }
    final result = <String>[];
    for (final item in raw) {
      final text = _localizedString(item);
      if (text != null && text.isNotEmpty) {
        result.add(text);
      }
    }
    return result;
  }

  static List<String> _tagNames(dynamic raw) {
    if (raw is! List) {
      return <String>[];
    }
    final names = <String>[];
    for (final tag in raw) {
      if (tag is! Map) {
        continue;
      }
      final attributes = tag['attributes'];
      if (attributes is Map) {
        final name = _localizedString(attributes['name']);
        if (name != null && name.isNotEmpty) {
          names.add(name);
        }
      }
    }
    return names;
  }

  static String? _coverFileName(List<dynamic> relationships) {
    for (final rel in relationships) {
      if (rel is! Map) {
        continue;
      }
      if (rel['type']?.toString() != 'cover_art') {
        continue;
      }
      final attributes = rel['attributes'];
      if (attributes is Map) {
        final fileName = attributes['fileName']?.toString();
        if (fileName != null && fileName.isNotEmpty) {
          return fileName;
        }
      }
    }
    return null;
  }

  static String? _authorNames(List<dynamic> relationships) {
    final names = <String>[];
    for (final rel in relationships) {
      if (rel is! Map) {
        continue;
      }
      final type = rel['type']?.toString();
      if (type != 'author' && type != 'artist') {
        continue;
      }
      final attributes = rel['attributes'];
      if (attributes is Map) {
        final name = attributes['name']?.toString().trim();
        if (name != null && name.isNotEmpty && !names.contains(name)) {
          names.add(name);
        }
      }
    }
    if (names.isEmpty) {
      return null;
    }
    return names.join(', ');
  }
}
