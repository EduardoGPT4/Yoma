import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import '../models/catalog_page.dart';
import '../models/chapter.dart';
import '../models/online_manga.dart';
import '../utils/app_failure.dart';
import 'content_exclusions.dart';
import 'source_http_client.dart';

/// Cliente de galerías de Hitomi.la.
///
/// Cada publicación es una galería con páginas. El sitio no expone una
/// jerarquía manga → capítulos, así que cada ficha se lee como una sola pieza.
class HitomiService {
  static const String site = 'https://hitomi.la';
  static const String origin = 'https://ltn.gold-usergeneratedcontent.net';
  static const String cdn = 'gold-usergeneratedcontent.net';
  static const String defaultLanguage = 'spanish';

  static const Map<String, String> languages = <String, String>{
    'spanish': 'Español',
    'english': 'English',
    'japanese': '日本語',
    'korean': '한국어',
    'chinese': '中文',
    'all': 'Todos',
  };

  static const Map<String, String> imageHeaders = <String, String>{
    'User-Agent': _userAgent,
    'Accept': 'image/avif,image/webp,image/apng,image/*,*/*;q=0.8',
    'Referer': '$site/',
    'Origin': site,
  };

  static const String _userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';

  static const Duration _listTtl = Duration(minutes: 10);
  static const Duration _ggTtl = Duration(minutes: 30);

  /// Alias de compatibilidad; las reglas se editan en content_exclusions.dart.
  static const Set<String> blockedTagNames = ContentExclusions.tags;

  /// Espacios de nombre que el buscador puede sugerir y combinar.
  static const Map<String, String> tagNamespaces = <String, String>{
    'artist': 'Artista',
    'group': 'Grupo',
    'series': 'Serie',
    'character': 'Personaje',
    'female': 'Género',
    'male': 'Género',
    'tag': 'Etiqueta',
    'type': 'Tipo',
    'language': 'Idioma',
  };

  /// Grupos del índice de etiquetas, de la más general a cada tipo.
  static const Map<String, String> popularTagGroups = <String, String>{
    'global': 'Todas',
    'artist': 'Artistas',
    'group': 'Grupos',
    'series': 'Series',
    'character': 'Personajes',
    'female': 'Género ♀',
    'male': 'Género ♂',
    'tag': 'Etiquetas',
    'type': 'Tipos',
    'language': 'Idiomas',
  };

  static String language = defaultLanguage;

  // Dart siempre anuncia gzip. Hay que descomprimir: si no, los .nozomi
  // se leen como IDs basura y el catálogo queda vacío.
  static final SourceHttpClient _http = SourceHttpClient()
    ..idleTimeout = const Duration(seconds: 20)
    ..connectionTimeout = const Duration(seconds: 25)
    ..autoUncompress = true;

  static final Map<String, ({DateTime time, List<int> ids})> _lists = {};
  static final Map<String, Future<List<int>>> _listRequests = {};
  static final _excludedIds = ExcludedContentIds(
    loadIndex: (token) => _nozomi('/n/tag/$token-all.nozomi'),
    ttl: _listTtl,
  );
  static final Map<String, ({DateTime time, List<HitomiTagSuggestion> items})>
  _suggestions = {};
  static ({DateTime time, HitomiGg gg})? _gg;
  static String? _indexVersion;
  static DateTime? _indexVersionAt;

  static void useLanguage(String code) {
    language = languages.containsKey(code) ? code : defaultLanguage;
  }

  static String languageLabel(String? code) =>
      languages[code] ?? languages[language] ?? 'Español';

  /// Olvida índices descargados para que un recargo vuelva a pedirlos.
  static void invalidateListings() {
    _lists.clear();
    _excludedIds.clear();
    _suggestions.clear();
  }

  static void resetForTest() {
    invalidateListings();
    _listRequests.clear();
    _gg = null;
    _indexVersion = null;
    _indexVersionAt = null;
    language = defaultLanguage;
  }

  static bool isReference(String? value) {
    if (value == null || value.trim().isEmpty) return false;
    final text = value.trim().toLowerCase();
    if (text.startsWith('hitomi:')) return true;
    final uri = Uri.tryParse(value.trim());
    if (uri == null || uri.host.isEmpty) return false;
    final host = uri.host.toLowerCase();
    return host == 'hitomi.la' || host.endsWith('.hitomi.la');
  }

  static bool needsImageHeaders(String url) {
    final host = Uri.tryParse(url)?.host.toLowerCase() ?? '';
    return host == cdn ||
        host.endsWith('.$cdn') ||
        host == 'hitomi.la' ||
        host.endsWith('.hitomi.la');
  }

  static int? galleryId(String ref) {
    final text = ref.trim();
    if (text.isEmpty) return null;
    final uri = Uri.tryParse(text);
    final last = uri == null || uri.pathSegments.isEmpty
        ? text
        : uri.pathSegments.last;
    final bare = last.replaceFirst(
      RegExp(r'\.(html|js)$', caseSensitive: false),
      '',
    );
    final match = RegExp(r'(\d+)$').firstMatch(bare);
    if (match == null) return null;
    return int.tryParse(match.group(1)!);
  }

  static String galleryUrl(int id) => '$site/galleries/$id.html';

  static List<int> decodeNozomi(List<int> bytes) {
    final data = ByteData.sublistView(Uint8List.fromList(bytes));
    final count = data.lengthInBytes ~/ 4;
    return [for (var i = 0; i < count; i++) data.getInt32(i * 4, Endian.big)];
  }

  static List<int> titleKey(String term) =>
      _sha256(utf8.encode(term)).sublist(0, 4);

  static HitomiGg parseGg(String source) {
    final fallbackMatch = RegExp(r'var\s+o\s*=\s*(\d+)').firstMatch(source);
    final fallback = fallbackMatch == null
        ? 0
        : int.parse(fallbackMatch.group(1)!);
    final baseMatch = RegExp("b:\\s*['\"]([^'\"]+)['\"]").firstMatch(source);
    final base = (baseMatch?.group(1) ?? '').replaceAll('/', '');
    final map = <int, int>{};
    final pending = <int>[];
    final token = RegExp(r'case\s+(\d+)\s*:|o\s*=\s*(\d+)');
    for (final match in token.allMatches(source)) {
      final caseId = match.group(1);
      if (caseId != null) {
        pending.add(int.parse(caseId));
        continue;
      }
      if (pending.isEmpty) continue;
      final value = int.parse(match.group(2)!);
      for (final id in pending) {
        map[id] = value;
      }
      pending.clear();
    }
    for (final match in RegExp(
      r'if\s*\(\s*g\s*===?\s*(\d+)\s*\)\s*\{?\s*o\s*=\s*(\d+)',
    ).allMatches(source)) {
      map[int.parse(match.group(1)!)] = int.parse(match.group(2)!);
    }
    return HitomiGg(exceptions: map, fallback: fallback, base: base);
  }

  static Map<String, dynamic> parseGalleryScript(String body) {
    final start = body.indexOf('{');
    final end = body.lastIndexOf('}');
    if (start < 0 || end <= start) {
      throw const AppFailure(
        FailureKind.parsing,
        'La ficha de la galería no tiene metadatos.',
      );
    }
    final decoded = jsonDecode(body.substring(start, end + 1));
    if (decoded is! Map) {
      throw const AppFailure(
        FailureKind.parsing,
        'La ficha de la galería no tiene metadatos.',
      );
    }
    return Map<String, dynamic>.from(decoded);
  }

  static bool tagIsBlocked(String raw) => ContentExclusions.matches(raw);

  /// Las sugerencias y las consultas usan las mismas exclusiones del catálogo.
  static bool suggestionAllowed(String namespace, String name) {
    final ns = namespace.trim().toLowerCase();
    if (!tagNamespaces.containsKey(ns)) return false;
    final trimmed = name.trim();
    return trimmed.isNotEmpty && !ContentExclusions.matches(trimmed);
  }

  static String tagToken(String namespace, String name) {
    final ns = namespace.trim().toLowerCase();
    final value = name.trim().toLowerCase().replaceAll(RegExp(r'\s+'), '_');
    return '$ns:$value';
  }

  /// `big breasts` → `/global/b/i/g/_/b/r/e/a/s/t/s.json` en tagindex.hitomi.la.
  /// Un espacio de nombre (`female:big`) limita el índice. Vacío pide las más usadas.
  static Uri suggestionUri(String raw) {
    var text = raw.trim().toLowerCase().replaceAll('_', ' ');
    if (text.startsWith('-')) text = text.substring(1).trimLeft();
    var field = 'global';
    var term = text;
    final colon = text.indexOf(':');
    if (colon > 0) {
      final namespace = text.substring(0, colon).trim();
      if (namespace == 'global' || tagNamespaces.containsKey(namespace)) {
        field = namespace;
        term = text.substring(colon + 1).trimLeft();
      }
    }
    if (term.length > 48) term = term.substring(0, 48);
    final encoded = <String>[
      for (final rune in term.runes) _encodeSuggestionChar(rune),
    ];
    final segments = encoded.isEmpty
        ? <String>['$field.json']
        : <String>[
            field,
            ...encoded.take(encoded.length - 1),
            '${encoded.last}.json',
          ];
    return Uri(
      scheme: 'https',
      host: 'tagindex.hitomi.la',
      pathSegments: segments,
    );
  }

  static List<HitomiTagSuggestion> parseTagSuggestions(String body) {
    final decoded = jsonDecode(body);
    if (decoded is! List) return const [];
    final items = <HitomiTagSuggestion>[];
    final seen = <String>{};
    for (final row in decoded) {
      if (row is! List || row.length < 3) continue;
      final name = '${row[0]}'.trim();
      final namespace = '${row[2]}'.trim().toLowerCase();
      if (!suggestionAllowed(namespace, name)) continue;
      final count = row[1] is num
          ? (row[1] as num).toInt()
          : int.tryParse('${row[1]}') ?? 0;
      final suggestion = HitomiTagSuggestion(
        namespace: namespace,
        name: name,
        count: count,
      );
      if (!seen.add(suggestion.token)) continue;
      items.add(suggestion);
    }
    return items;
  }

  static Future<List<HitomiTagSuggestion>> fetchTagSuggestions(
    String query, {
    int limit = 12,
  }) async {
    if (ContentExclusions.matches(query)) return const [];
    final key = suggestionUri(query).toString();
    final cached = _suggestions[key];
    if (cached != null && DateTime.now().difference(cached.time) < _listTtl) {
      return cached.items.take(limit).toList();
    }
    try {
      final body = utf8.decode(await _bytes(key), allowMalformed: true);
      final items = parseTagSuggestions(body);
      _suggestions[key] = (time: DateTime.now(), items: items);
      return items.take(limit).toList();
    } catch (error) {
      final failure = AppFailure.from(error);
      if (failure.kind == FailureKind.cancelled) throw failure;
      if (failure.statusCode == 404) return const [];
      throw failure;
    }
  }

  static String _encodeSuggestionChar(int rune) {
    final char = String.fromCharCodes(<int>[rune]);
    switch (char) {
      case ' ':
        return '_';
      case '/':
        return 'slash';
      case '.':
        return 'dot';
      default:
        return char;
    }
  }

  static bool galleryIsBlocked(Map<String, dynamic> info) {
    final tags = info['tags'];
    if (tags is! List) return false;
    for (final item in tags) {
      if (item is Map && tagIsBlocked('${item['tag'] ?? ''}')) return true;
    }
    return false;
  }

  static int hashNumber(String hash) {
    if (hash.length < 3) {
      throw const AppFailure(
        FailureKind.parsing,
        'La imagen no tiene un identificador válido.',
      );
    }
    final last = hash[hash.length - 1];
    final previous = hash.substring(hash.length - 3, hash.length - 1);
    return int.parse('$last$previous', radix: 16);
  }

  static String mediaUrl(
    HitomiGg gg,
    Map<String, dynamic> file, {
    bool thumbnail = false,
  }) {
    final hash = '${file['hash'] ?? ''}'.toLowerCase();
    final number = hashNumber(hash);
    final route = gg.route(number);
    if (thumbnail) {
      final subdomain = '${String.fromCharCode(97 + route)}tn';
      final tail = hash[hash.length - 1];
      final middle = hash.substring(hash.length - 3, hash.length - 1);
      return 'https://$subdomain.$cdn/webpsmalltn/$tail/$middle/$hash.webp';
    }
    final extension = _extensionOf(file);
    final prefix = extension == 'webp'
        ? 'w'
        : extension == 'avif'
        ? 'a'
        : '';
    final subdomain = '$prefix${route + 1}';
    final directory = extension == 'webp' || extension == 'avif'
        ? ''
        : '$extension/';
    return 'https://$subdomain.$cdn/$directory${gg.base}/$number/$hash.$extension';
  }

  static Future<CatalogPage> fetchCatalogPage({
    int page = 1,
    int postsPerPage = 12,
    String? search,
  }) async {
    final ids = await _idsFor(search);
    final size = postsPerPage < 1 ? 12 : postsPerPage;
    final safePage = page < 1 ? 1 : page;
    final totalPages = ids.isEmpty ? 1 : (ids.length / size).ceil();
    if (safePage > totalPages) {
      return CatalogPage(
        items: const [],
        currentPage: safePage,
        totalPages: totalPages,
      );
    }
    final start = (safePage - 1) * size;
    final items = await _summaries(ids.skip(start).take(size).toList());
    return CatalogPage(
      items: items,
      currentPage: safePage,
      totalPages: totalPages,
    );
  }

  static Future<List<OnlineMangaSummary>> fetchUpdated() async {
    final ids = await _idsFor(null, orderby: 'popular', orderbykey: 'week');
    return _summaries(ids.take(12).toList());
  }

  static Future<OnlineMangaDetail> fetchMangaDetail(String ref) async {
    final id = galleryId(ref);
    if (id == null) {
      throw const AppFailure(FailureKind.parsing, 'Galería no reconocida.');
    }
    final info = await _gallery(id);
    if (galleryIsBlocked(info)) {
      throw const AppFailure(
        FailureKind.parsing,
        'Esta galería no está disponible.',
      );
    }
    final gg = await _loadGg();
    return _detail(id, info, gg);
  }

  static Future<List<String>> fetchChapterPages(String ref) async {
    final id = galleryId(ref);
    if (id == null) {
      throw const AppFailure(FailureKind.parsing, 'Galería no reconocida.');
    }
    final info = await _gallery(id);
    if (galleryIsBlocked(info)) {
      throw const AppFailure(
        FailureKind.parsing,
        'Esta galería no está disponible.',
      );
    }
    final files = _files(info);
    if (files.isEmpty) {
      throw const AppFailure(
        FailureKind.parsing,
        'Esta publicación no tiene páginas para leer.',
      );
    }
    final gg = await _loadGg();
    return [for (final file in files) mediaUrl(gg, file)];
  }

  static Future<List<int>> downloadBytes(String url, {String? referer}) async {
    final request = await _http.getUrl(Uri.parse(url));
    request.followRedirects = true;
    request.maxRedirects = 5;
    imageHeaders.forEach(request.headers.set);
    if (referer != null && referer.isNotEmpty) {
      request.headers.set('Referer', referer);
    }
    final response = await request.close();
    return _read(response);
  }

  static Future<List<int>> _idsFor(
    String? search, {
    String orderby = 'date',
    String orderbykey = 'added',
  }) async {
    if (ContentExclusions.matches(search ?? '')) return const [];
    final parsed = _parseQuery(
      search,
      orderby: orderby,
      orderbykey: orderbykey,
    );
    final excludedIds = await _excludedIds.load();
    if (parsed.positive.isEmpty &&
        parsed.titles.isEmpty &&
        parsed.negative.isEmpty &&
        parsed.negativeTitles.isEmpty) {
      final ids = await _nozomi(
        _indexPath(parsed.orderby, parsed.orderbykey, parsed.language),
      );
      return _finish(ids, null, excludedIds, parsed);
    }

    List<int>? ordered;
    Set<int>? required;
    for (final term in parsed.positive) {
      final ids = await _nozomi(
        _tagPath(term, parsed.language, parsed.orderby, parsed.orderbykey),
      );
      if (ordered == null) {
        ordered = ids;
      } else {
        final allow = ids.toSet();
        ordered = ordered.where(allow.contains).toList();
      }
    }
    for (final title in parsed.titles) {
      final ids = (await _titleIds(title)).toSet();
      if (ordered != null) {
        ordered = ordered.where(ids.contains).toList();
      } else if (required == null) {
        required = ids;
      } else {
        required = required.intersection(ids);
      }
    }
    if (ordered == null && required == null) {
      ordered = await _nozomi(
        _indexPath(parsed.orderby, parsed.orderbykey, parsed.language),
      );
    } else if (ordered == null && parsed.language != 'all') {
      final languageIds = (await _nozomi(
        _indexPath('date', 'added', parsed.language),
      )).toSet();
      required = required == null
          ? languageIds
          : required.intersection(languageIds);
    }
    for (final term in parsed.negative) {
      final ban = (await _nozomi(
        _tagPath(term, parsed.language, 'date', 'added'),
      )).toSet();
      if (ordered != null) {
        ordered = ordered.where((id) => !ban.contains(id)).toList();
      } else if (required != null) {
        required = required.difference(ban);
      }
    }
    for (final title in parsed.negativeTitles) {
      final ban = (await _titleIds(title)).toSet();
      if (ordered != null) {
        ordered = ordered.where((id) => !ban.contains(id)).toList();
      } else if (required != null) {
        required = required.difference(ban);
      }
    }
    final base = ordered ?? required?.toList() ?? <int>[];
    if (ordered == null) {
      base.sort((a, b) => b.compareTo(a));
    }
    return _finish(base, required, excludedIds, parsed);
  }

  static List<int> _finish(
    List<int> ordered,
    Set<int>? required,
    Set<int> excludedIds,
    _HitomiQuery parsed,
  ) {
    var ids = ordered;
    if (required != null && !identical(ids, required.toList())) {
      ids = ids.where(required.contains).toList();
    }
    ids = ids.where((id) => !excludedIds.contains(id)).toList();
    if (parsed.ascending) {
      ids = ids.reversed.toList();
    }
    if (parsed.random) {
      ids = List<int>.of(ids)..shuffle(Random(parsed.seed));
    }
    return ids;
  }

  static Future<List<OnlineMangaSummary>> _summaries(List<int> ids) async {
    if (ids.isEmpty) return const [];
    final gg = await _loadGg();
    final rows = await Future.wait(
      ids.map((id) async {
        try {
          final info = await _gallery(id);
          if (galleryIsBlocked(info)) return null;
          return _summary(id, info, gg);
        } catch (_) {
          return null;
        }
      }),
    );
    return rows.whereType<OnlineMangaSummary>().toList();
  }

  static OnlineMangaSummary _summary(
    int id,
    Map<String, dynamic> info,
    HitomiGg gg,
  ) {
    final files = _files(info);
    final title = _text(info['title']);
    return OnlineMangaSummary(
      title: title.isEmpty ? 'Galería $id' : title,
      url: galleryUrl(id),
      coverUrl: files.isEmpty
          ? null
          : mediaUrl(gg, files.first, thumbnail: true),
      description: _joinNames(info['artists'], 'artist'),
      chapterCount: files.length,
      genres: _tagLabels(info).take(8).toList(),
      type: _text(info['type']),
      sourceId: 'hitomi',
    );
  }

  static OnlineMangaDetail _detail(
    int id,
    Map<String, dynamic> info,
    HitomiGg gg,
  ) {
    final files = _files(info);
    final title = _text(info['title']);
    final japanese = _text(info['japanese_title']);
    final url = galleryUrl(id);
    final languageName = _text(info['language_localname']).isEmpty
        ? _text(info['language'])
        : _text(info['language_localname']);
    final artists = _joinNames(info['artists'], 'artist');
    final lines = <String>[
      if (languageName.isNotEmpty) 'Idioma: $languageName',
      if (artists.isNotEmpty) 'Artistas: $artists',
      if (_joinNames(info['groups'], 'group').isNotEmpty)
        'Grupos: ${_joinNames(info['groups'], 'group')}',
      if (_joinNames(info['parodys'], 'parody').isNotEmpty)
        'Series: ${_joinNames(info['parodys'], 'parody')}',
      if (_joinNames(info['characters'], 'character').isNotEmpty)
        'Personajes: ${_joinNames(info['characters'], 'character')}',
      if (_editions(info, id).isNotEmpty)
        'Otras ediciones: ${_editions(info, id)}',
    ];
    final tags = _tagLabels(info);
    return OnlineMangaDetail(
      title: title.isEmpty ? 'Galería $id' : title,
      url: url,
      coverUrl: files.isEmpty
          ? null
          : mediaUrl(gg, files.first, thumbnail: true),
      description: lines.join('\n'),
      altTitles: japanese.isEmpty ? const [] : [japanese],
      genres: tags,
      type: _text(info['type']),
      author: artists.isEmpty ? null : artists,
      year: _year(info['date']),
      chapters: [
        Chapter(
          number: '1',
          title: files.isEmpty
              ? 'Galería'
              : 'Galería · ${files.length} páginas',
          language: _text(info['language']),
          sourceUrl: url,
          path: url,
          pageCount: files.length,
        ),
      ],
    );
  }

  static Future<Map<String, dynamic>> _gallery(int id) async {
    final body = utf8.decode(
      await _bytes('$origin/galleries/$id.js'),
      allowMalformed: true,
    );
    return parseGalleryScript(body);
  }

  static Future<HitomiGg> _loadGg() async {
    final cached = _gg;
    if (cached != null && DateTime.now().difference(cached.time) < _ggTtl) {
      return cached.gg;
    }
    final body = utf8.decode(
      await _bytes('$origin/gg.js'),
      allowMalformed: true,
    );
    final parsed = parseGg(body);
    _gg = (time: DateTime.now(), gg: parsed);
    return parsed;
  }

  static Future<List<int>> _nozomi(String path) {
    final cached = _lists[path];
    if (cached != null && DateTime.now().difference(cached.time) < _listTtl) {
      return Future<List<int>>.value(cached.ids);
    }
    final pending = _listRequests[path];
    if (pending != null) return pending;
    late final Future<List<int>> request;
    request =
        (() async {
          try {
            final ids = decodeNozomi(await _bytes('$origin$path'));
            _lists[path] = (time: DateTime.now(), ids: ids);
            return ids;
          } on AppFailure catch (error) {
            if (error.statusCode == 404) {
              _lists[path] = (time: DateTime.now(), ids: const []);
              return const <int>[];
            }
            rethrow;
          }
        })().whenComplete(() {
          if (identical(_listRequests[path], request)) {
            _listRequests.remove(path);
          }
        });
    _listRequests[path] = request;
    return request;
  }

  static Future<List<int>> _titleIds(String term) async {
    final version = await _galleriesVersion();
    final key = titleKey(term);
    final node = await _node(version, 0);
    final found = await _searchNode(version, key, node);
    if (found == null) return const [];
    return _idsFromData(version, found.$1, found.$2);
  }

  static Future<String> _galleriesVersion() async {
    final cached = _indexVersion;
    final at = _indexVersionAt;
    if (cached != null &&
        at != null &&
        DateTime.now().difference(at) < _ggTtl &&
        cached.isNotEmpty) {
      return cached;
    }
    final body = utf8
        .decode(
          await _bytes('$origin/galleriesindex/version'),
          allowMalformed: true,
        )
        .trim();
    if (body.isEmpty) {
      throw const AppFailure(
        FailureKind.parsing,
        'No se pudo leer el índice de títulos.',
      );
    }
    _indexVersion = body;
    _indexVersionAt = DateTime.now();
    return body;
  }

  static Future<_HitomiNode?> _node(String version, int address) async {
    final bytes = await _range(
      '$origin/galleriesindex/galleries.$version.index',
      address,
      address + 463,
    );
    return _decodeNode(bytes);
  }

  static Future<(int, int)?> _searchNode(
    String version,
    List<int> key,
    _HitomiNode? node,
  ) async {
    if (node == null || node.keys.isEmpty) return null;
    var compare = -1;
    var where = 0;
    for (; where < node.keys.length; where++) {
      compare = _compareBytes(key, node.keys[where]);
      if (compare <= 0) break;
    }
    if (compare == 0 && where < node.datas.length) return node.datas[where];
    if (node.subnodes.every((address) => address == 0)) return null;
    if (where >= node.subnodes.length || node.subnodes[where] == 0) return null;
    final next = await _node(version, node.subnodes[where]);
    return _searchNode(version, key, next);
  }

  static Future<List<int>> _idsFromData(
    String version,
    int offset,
    int length,
  ) async {
    if (length <= 0 || length > 100000000) return const [];
    final bytes = await _range(
      '$origin/galleriesindex/galleries.$version.data',
      offset,
      offset + length - 1,
    );
    if (bytes.length < 4) return const [];
    final view = ByteData.sublistView(Uint8List.fromList(bytes));
    final count = view.getInt32(0, Endian.big);
    if (count <= 0 || count > 10000000 || bytes.length != count * 4 + 4) {
      return const [];
    }
    return [
      for (var i = 0; i < count; i++) view.getInt32(4 + i * 4, Endian.big),
    ];
  }

  static _HitomiNode? _decodeNode(List<int> bytes) {
    final view = ByteData.sublistView(Uint8List.fromList(bytes));
    var pos = 0;
    int i32() {
      final value = view.getInt32(pos, Endian.big);
      pos += 4;
      return value;
    }

    int u64() {
      final value = view.getUint64(pos, Endian.big);
      pos += 8;
      return value;
    }

    try {
      final keyCount = i32();
      if (keyCount < 0 || keyCount > 16) return null;
      final keys = <List<int>>[];
      for (var i = 0; i < keyCount; i++) {
        final size = i32();
        if (size <= 0 || size > 32 || pos + size > bytes.length) return null;
        keys.add(bytes.sublist(pos, pos + size));
        pos += size;
      }
      final dataCount = i32();
      if (dataCount < 0 || dataCount > 16) return null;
      final datas = <(int, int)>[];
      for (var i = 0; i < dataCount; i++) {
        final offset = u64();
        final length = i32();
        datas.add((offset, length));
      }
      final subnodes = <int>[for (var i = 0; i < 17; i++) u64()];
      return _HitomiNode(keys: keys, datas: datas, subnodes: subnodes);
    } catch (_) {
      return null;
    }
  }

  static Future<List<int>> _bytes(String url) async {
    final request = await _http.getUrl(_uri(url));
    _decorate(request);
    final response = await request.close();
    return _read(response);
  }

  static Future<List<int>> _range(String url, int start, int end) async {
    final request = await _http.getUrl(_uri(url));
    _decorate(request);
    request.headers.set('Range', 'bytes=$start-$end');
    final response = await request.close();
    return _read(response);
  }

  static void _decorate(dynamic request) {
    request.followRedirects = true;
    request.maxRedirects = 4;
    request.headers.set('User-Agent', _userAgent);
    request.headers.set('Accept', '*/*');
    request.headers.set('Referer', '$site/');
    request.headers.set('Origin', site);
  }

  static Uri _uri(String url) {
    final parsed = Uri.parse(url);
    return Uri(
      scheme: parsed.scheme,
      host: parsed.host,
      port: parsed.hasPort ? parsed.port : null,
      pathSegments: parsed.pathSegments,
      query: parsed.hasQuery ? parsed.query : null,
    );
  }

  static Future<List<int>> _read(dynamic response) {
    return response.fold<List<int>>(<int>[], (
      List<int> buffer,
      List<int> chunk,
    ) {
      buffer.addAll(chunk);
      return buffer;
    });
  }

  static String _indexPath(String orderby, String orderbykey, String language) {
    if (orderby == 'date' && orderbykey != 'published') {
      return '/n/index-$language.nozomi';
    }
    if (orderby == 'date') return '/n/date/published-$language.nozomi';
    return '/n/$orderby/$orderbykey-$language.nozomi';
  }

  static String _tagPath(
    _HitomiTerm term,
    String language,
    String orderby,
    String orderbykey,
  ) {
    if (orderby != 'date' || orderbykey == 'published') {
      if (term.area == 'all') return _indexPath(orderby, orderbykey, language);
      return '/n/${term.area}/$orderby/$orderbykey/${term.tag}-$language.nozomi';
    }
    if (term.area == 'all') return '/n/${term.tag}-$language.nozomi';
    return '/n/${term.area}/${term.tag}-$language.nozomi';
  }

  static _HitomiQuery _parseQuery(
    String? raw, {
    required String orderby,
    required String orderbykey,
  }) {
    final query = _HitomiQuery(
      language: language,
      orderby: orderby,
      orderbykey: orderbykey,
    );
    final text = raw?.trim().toLowerCase() ?? '';
    if (text.isEmpty) return query;
    for (final piece in text.split(RegExp(r'\s+'))) {
      if (piece.isEmpty || piece == '-') continue;
      final negative = piece.startsWith('-');
      final term = (negative ? piece.substring(1) : piece).replaceAll('_', ' ');
      if (term.isEmpty) continue;
      final colon = term.indexOf(':');
      if (colon > 0) {
        final namespace = term.substring(0, colon).trim();
        final value = term
            .substring(colon + 1)
            .trim()
            .replaceAll(RegExp(r'[/#]'), '');
        if (value.isEmpty && namespace != 'language') continue;
        if (namespace == 'orderby' || namespace == 'sortby') {
          if (value == 'popular' || value == 'date') query.orderby = value;
          continue;
        }
        if (namespace == 'orderbykey' || namespace == 'sortbykey') {
          query.orderbykey = value;
          continue;
        }
        if (namespace == 'orderbydirection' || namespace == 'sortbydirection') {
          query.ascending = value == 'asc';
          query.random = value == 'random';
          continue;
        }
        if (namespace == 'language') {
          query.language = value.isEmpty ? query.language : value;
          continue;
        }
        final parsed = namespace == 'female' || namespace == 'male'
            ? _HitomiTerm('tag', '$namespace:$value')
            : _HitomiTerm(namespace, value);
        if (negative) {
          query.negative.add(parsed);
        } else {
          query.positive.add(parsed);
        }
        continue;
      }
      if (negative) {
        query.negativeTitles.add(term);
      } else {
        query.titles.add(term);
      }
    }
    query.seed = Object.hash(
      text,
      query.language,
      query.orderby,
      query.orderbykey,
    );
    return query;
  }

  static List<Map<String, dynamic>> _files(Map<String, dynamic> info) {
    final files = info['files'];
    if (files is! List) return const [];
    return [
      for (final file in files)
        if (file is Map && '${file['hash'] ?? ''}'.isNotEmpty)
          Map<String, dynamic>.from(file),
    ];
  }

  static String _extensionOf(Map<String, dynamic> file) {
    final hasWebp = file['haswebp'];
    if (hasWebp == 0 || hasWebp == '0' || hasWebp == false) {
      final name = _text(file['name']);
      final dot = name.lastIndexOf('.');
      if (dot >= 0 && dot < name.length - 1) {
        return name.substring(dot + 1).toLowerCase();
      }
      return 'jpg';
    }
    return 'webp';
  }

  static List<String> _tagLabels(Map<String, dynamic> info) {
    final tags = info['tags'];
    if (tags is! List) return const [];
    final labels = <String>[];
    for (final item in tags) {
      if (item is! Map) continue;
      final name = _text(item['tag']);
      if (name.isEmpty || tagIsBlocked(name)) continue;
      if (_flag(item['female'])) {
        labels.add('♀ $name');
      } else if (_flag(item['male'])) {
        labels.add('♂ $name');
      } else {
        labels.add(name);
      }
    }
    return labels;
  }

  static String _editions(Map<String, dynamic> info, int id) {
    final languages = info['languages'];
    if (languages is! List) return '';
    final names = <String>[];
    for (final item in languages) {
      if (item is! Map) continue;
      final gallery = item['galleryid'];
      final same = gallery == id || '$gallery' == '$id';
      if (same) continue;
      final name = _text(item['language_localname']).isEmpty
          ? _text(item['name'])
          : _text(item['language_localname']);
      if (name.isNotEmpty) names.add(name);
    }
    return names.join(', ');
  }

  static String _joinNames(Object? raw, String field) {
    if (raw is! List) return '';
    final names = <String>[
      for (final item in raw)
        if (item is Map && _text(item[field]).isNotEmpty) _text(item[field]),
    ];
    return names.join(', ');
  }

  static String _year(Object? raw) {
    final text = _text(raw);
    final match = RegExp(r'^(19|20)\d{2}').firstMatch(text);
    return match?.group(0) ?? '';
  }

  static String _text(Object? value) => value == null ? '' : '$value'.trim();

  static bool _flag(Object? value) =>
      value == 1 || value == '1' || value == true;

  static int _compareBytes(List<int> left, List<int> right) {
    final count = min(left.length, right.length);
    for (var i = 0; i < count; i++) {
      if (left[i] < right[i]) return -1;
      if (left[i] > right[i]) return 1;
    }
    return 0;
  }
}

class HitomiTagSuggestion {
  final String namespace;
  final String name;
  final int count;

  const HitomiTagSuggestion({
    required this.namespace,
    required this.name,
    required this.count,
  });

  String get token => HitomiService.tagToken(namespace, name);

  String get kindLabel => HitomiService.tagNamespaces[namespace] ?? 'Etiqueta';

  /// Texto visible al escribir, por ejemplo `Género: female:big_breasts`.
  String get caption => '$kindLabel: $token';

  String get countLabel {
    final digits = count.toString();
    final buffer = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      final remaining = digits.length - i;
      if (i > 0 && remaining % 3 == 0) buffer.write('.');
      buffer.write(digits[i]);
    }
    return '$buffer galerías';
  }
}

class HitomiGg {
  final Map<int, int> exceptions;
  final int fallback;
  final String base;
  const HitomiGg({
    required this.exceptions,
    required this.fallback,
    required this.base,
  });

  int route(int number) => exceptions[number] ?? fallback;
}

class _HitomiTerm {
  final String area;
  final String tag;
  const _HitomiTerm(this.area, this.tag);
}

class _HitomiQuery {
  String language;
  String orderby;
  String orderbykey;
  bool ascending = false;
  bool random = false;
  int seed = 1;
  final List<_HitomiTerm> positive = [];
  final List<_HitomiTerm> negative = [];
  final List<String> titles = [];
  final List<String> negativeTitles = [];
  _HitomiQuery({
    required this.language,
    required this.orderby,
    required this.orderbykey,
  });
}

class _HitomiNode {
  final List<List<int>> keys;
  final List<(int, int)> datas;
  final List<int> subnodes;
  const _HitomiNode({
    required this.keys,
    required this.datas,
    required this.subnodes,
  });
}

List<int> _sha256(List<int> message) {
  const k = <int>[
    0x428a2f98,
    0x71374491,
    0xb5c0fbcf,
    0xe9b5dba5,
    0x3956c25b,
    0x59f111f1,
    0x923f82a4,
    0xab1c5ed5,
    0xd807aa98,
    0x12835b01,
    0x243185be,
    0x550c7dc3,
    0x72be5d74,
    0x80deb1fe,
    0x9bdc06a7,
    0xc19bf174,
    0xe49b69c1,
    0xefbe4786,
    0x0fc19dc6,
    0x240ca1cc,
    0x2de92c6f,
    0x4a7484aa,
    0x5cb0a9dc,
    0x76f988da,
    0x983e5152,
    0xa831c66d,
    0xb00327c8,
    0xbf597fc7,
    0xc6e00bf3,
    0xd5a79147,
    0x06ca6351,
    0x14292967,
    0x27b70a85,
    0x2e1b2138,
    0x4d2c6dfc,
    0x53380d13,
    0x650a7354,
    0x766a0abb,
    0x81c2c92e,
    0x92722c85,
    0xa2bfe8a1,
    0xa81a664b,
    0xc24b8b70,
    0xc76c51a3,
    0xd192e819,
    0xd6990624,
    0xf40e3585,
    0x106aa070,
    0x19a4c116,
    0x1e376c08,
    0x2748774c,
    0x34b0bcb5,
    0x391c0cb3,
    0x4ed8aa4a,
    0x5b9cca4f,
    0x682e6ff3,
    0x748f82ee,
    0x78a5636f,
    0x84c87814,
    0x8cc70208,
    0x90befffa,
    0xa4506ceb,
    0xbef9a3f7,
    0xc67178f2,
  ];
  int mask(int value) => value & 0xffffffff;
  int rotr(int value, int bits) =>
      mask((value >>> bits) | (value << (32 - bits)));
  var h0 = 0x6a09e667;
  var h1 = 0xbb67ae85;
  var h2 = 0x3c6ef372;
  var h3 = 0xa54ff53a;
  var h4 = 0x510e527f;
  var h5 = 0x9b05688c;
  var h6 = 0x1f83d9ab;
  var h7 = 0x5be0cd19;
  final bytes = List<int>.of(message)..add(0x80);
  while (bytes.length % 64 != 56) {
    bytes.add(0);
  }
  final bitLength = message.length * 8;
  for (var shift = 56; shift >= 0; shift -= 8) {
    bytes.add((bitLength >> shift) & 0xff);
  }
  final words = List<int>.filled(64, 0);
  for (var offset = 0; offset < bytes.length; offset += 64) {
    for (var i = 0; i < 16; i++) {
      final at = offset + i * 4;
      words[i] = mask(
        (bytes[at] << 24) |
            (bytes[at + 1] << 16) |
            (bytes[at + 2] << 8) |
            bytes[at + 3],
      );
    }
    for (var i = 16; i < 64; i++) {
      final w15 = words[i - 15];
      final w2 = words[i - 2];
      final s0 = rotr(w15, 7) ^ rotr(w15, 18) ^ (w15 >>> 3);
      final s1 = rotr(w2, 17) ^ rotr(w2, 19) ^ (w2 >>> 10);
      words[i] = mask(words[i - 16] + s0 + words[i - 7] + s1);
    }
    var a = h0, b = h1, c = h2, d = h3, e = h4, f = h5, g = h6, h = h7;
    for (var i = 0; i < 64; i++) {
      final s1 = rotr(e, 6) ^ rotr(e, 11) ^ rotr(e, 25);
      final ch = (e & f) ^ (mask(~e) & g);
      final temp1 = mask(h + s1 + ch + k[i] + words[i]);
      final s0 = rotr(a, 2) ^ rotr(a, 13) ^ rotr(a, 22);
      final maj = (a & b) ^ (a & c) ^ (b & c);
      final temp2 = mask(s0 + maj);
      h = g;
      g = f;
      f = e;
      e = mask(d + temp1);
      d = c;
      c = b;
      b = a;
      a = mask(temp1 + temp2);
    }
    h0 = mask(h0 + a);
    h1 = mask(h1 + b);
    h2 = mask(h2 + c);
    h3 = mask(h3 + d);
    h4 = mask(h4 + e);
    h5 = mask(h5 + f);
    h6 = mask(h6 + g);
    h7 = mask(h7 + h);
  }
  final out = Uint8List(32);
  final view = ByteData.sublistView(out);
  final values = [h0, h1, h2, h3, h4, h5, h6, h7];
  for (var i = 0; i < values.length; i++) {
    view.setUint32(i * 4, values[i]);
  }
  return out;
}
