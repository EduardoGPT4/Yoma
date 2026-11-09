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

  static String clean(String title) {
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

    result = result
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll(RegExp(r'^[\[\(\{]+|[\]\)\}]+$'), '')
        .replaceAll(RegExp(r'\s*[-–—]\s*\d+\s*$'), '')
        .replaceAll(RegExp(r'^\d+\s*[-–—]\s*'), '')
        .trim();

    return result.isEmpty ? title.trim() : result;
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
