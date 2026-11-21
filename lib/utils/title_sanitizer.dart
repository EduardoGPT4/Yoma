import 'package:html/parser.dart' show parseFragment;

class TitleSanitizer {
  static final List<RegExp> _metadataPatterns = <RegExp>[
    RegExp(r'\[?\s*traduccion\s*:\s*[^\]\|]+', caseSensitive: false),
    RegExp(r'\[?\s*traducción\s*:\s*[^\]\|]+', caseSensitive: false),
    RegExp(r'\[?\s*edicion\s*:\s*[^\]\|]+', caseSensitive: false),
    RegExp(r'\[?\s*edición\s*:\s*[^\]\|]+', caseSensitive: false),
    RegExp(r'\[?\s*scan\s*:\s*[^\]\|]+', caseSensitive: false),
    RegExp(r'\[?\s*upscaled\s+by\s*[^\]\|]+', caseSensitive: false),
    RegExp(r'\[?\s*raw\s*:\s*[^\]\|]+', caseSensitive: false),
    RegExp(r'\[?\s*group\s*:\s*[^\]\|]+', caseSensitive: false),
    RegExp(r'\[?\s*version\s*:\s*[^\]\|]+', caseSensitive: false),
    RegExp(
      r'\([^)]*(?:traduccion|edicion|upscaled|scan)[^)]*\)',
      caseSensitive: false,
    ),
    RegExp(
      r'\[[^\]]*(?:traduccion|edicion|upscaled|scan)[^\]]*\]',
      caseSensitive: false,
    ),
  ];

  /// La biblioteca ordena y filtra por el título limpio en cada reconstrucción;
  /// sin caché, ordenar 300 títulos costaba cientos de milisegundos.
  static final Map<String, String> _cache = <String, String>{};
  static const int _cacheLimit = 4096;

  static String clean(String title) {
    final cached = _cache[title];
    if (cached != null) return cached;
    final result = _clean(title);
    if (_cache.length >= _cacheLimit) _cache.remove(_cache.keys.first);
    _cache[title] = result;
    return result;
  }

  static String _clean(String title) {
    var result = title.trim();
    // Decode source entities without treating angle brackets in a title as tags.
    for (var pass = 0; pass < 2 && result.contains('&'); pass++) {
      final decoded = parseFragment(
        result.replaceAll('<', '&lt;').replaceAll('>', '&gt;'),
      ).text;
      if (decoded == null || decoded == result) break;
      result = decoded;
    }
    if (result.isEmpty) {
      return title;
    }

    if (result.contains('|')) {
      result = result.split('|').first.trim();
    }

    for (final pattern in _metadataPatterns) {
      result = result.replaceAll(pattern, ' ');
    }

    result = _stripSeo(result.replaceAll(RegExp(r'\s+'), ' ').trim());
    result = _trimStrayBrackets(result)
        .replaceAll(RegExp(r'\s*[-–—]\s*\d+\s*$'), '')
        .replaceAll(RegExp(r'^\d+\s*[-–—]\s*'), '')
        .trim();

    return result.isEmpty ? title.trim() : result;
  }

  /// Envoltorios de buscador que algunas fuentes ponen en el título de la
  /// página: «Ver X Online Gratis», «Leer X Manga Online», «X - Leer Online».
  /// «Online» suelto se respeta: forma parte de títulos como «Sword Art Online».
  static final RegExp _seoWrapped = RegExp(
    r'^(?:ver|leer)\s+(.+?)\s+(?:(?:manga|manhwa|manhua)\s+)?(?:online|en\s+l[ií]nea)'
    r'(?:\s+gratis)?(?:\s+en\s+español)?$',
    caseSensitive: false,
  );
  static final List<RegExp> _seoSuffixes = <RegExp>[
    RegExp(
      r'\s*[-–—:]\s*(?:ver|leer)\s+(?:(?:manga|manhwa|manhua)\s+)?'
      r'(?:online|gratis|en\s+español).*$',
      caseSensitive: false,
    ),
    RegExp(r'\s+online\s+gratis(?:\s+en\s+español)?$', caseSensitive: false),
    RegExp(
      r'\s+(?:manga|manhwa|manhua)\s+online(?:\s+gratis)?(?:\s+en\s+español)?$',
      caseSensitive: false,
    ),
    RegExp(r'\s+gratis\s+en\s+español$', caseSensitive: false),
  ];

  static String _stripSeo(String value) {
    final wrapped = _seoWrapped.firstMatch(value);
    var result = wrapped == null ? value : wrapped.group(1)!.trim();
    for (final pattern in _seoSuffixes) {
      result = result.replaceFirst(pattern, '').trim();
    }
    return result.isEmpty ? value : result;
  }

  /// Quita corchetes o paréntesis sueltos que dejan los metadatos, pero no
  /// los que cierran parte del título, como «Choujin X (Reedición)».
  static String _trimStrayBrackets(String value) {
    const pairs = {'(': ')', '[': ']', '{': '}'};
    int count(String text, String char) => char.allMatches(text).length;
    var result = value;
    var changed = true;
    while (changed && result.isNotEmpty) {
      changed = false;
      final first = result[0];
      final closer = pairs[first];
      if (closer != null && count(result, first) > count(result, closer)) {
        result = result.substring(1).trim();
        changed = true;
        continue;
      }
      final last = result[result.length - 1];
      for (final pair in pairs.entries) {
        if (last == pair.value &&
            count(result, pair.value) > count(result, pair.key)) {
          result = result.substring(0, result.length - 1).trim();
          changed = true;
          break;
        }
      }
    }
    return result;
  }

  static String chapterLabel(String raw) {
    final cleaned = clean(raw);
    final match = RegExp(
      r'cap[íi]tulo\s*(\d+(?:\.\d+)?)',
      caseSensitive: false,
    ).firstMatch(cleaned);
    if (match != null) {
      return 'Cap. ${match.group(1)}';
    }
    if (RegExp(r'^\d').hasMatch(cleaned)) {
      return 'Cap. $cleaned';
    }
    return cleaned.isEmpty ? 'Capítulo' : cleaned;
  }
}
