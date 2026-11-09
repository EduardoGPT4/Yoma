import 'dart:convert';

/// ID estable derivado de la referencia canónica, independiente del título.
class ContentIdentity {
  static String canonical(String ref) {
    final uri = Uri.tryParse(ref);
    if (uri == null || !['http', 'https'].contains(uri.scheme)) return ref;
    var path = uri.path.replaceAll(RegExp(r'/+$'), '');
    final identitySegments = path
        .split('/')
        .where((part) => part.isNotEmpty)
        .toList();
    var host = uri.host.toLowerCase().replaceFirst(RegExp(r'^www\.'), '');
    if ([
      'lectortmo.com',
      'lectortmo.org',
      'zonatmo.com',
      'zonatmo.net',
    ].contains(host)) {
      host = 'zonatmo.org';
    }
    var keepQuery = true;
    if (host == 'inmanga.com' && path.startsWith('/ver/manga/')) {
      path = '/manga/${identitySegments.last}';
      keepQuery = false;
    }
    if (host == 'zonatmo.org' &&
        path.startsWith('/library/') &&
        uri.pathSegments.length >= 3) {
      path = '/${uri.pathSegments.take(3).join('/')}';
      keepQuery = false;
    }
    if (host == 'mangadex.org' &&
        identitySegments.isNotEmpty &&
        {'title', 'chapter'}.contains(identitySegments.first)) {
      final segments = identitySegments;
      if (segments.length >= 2) path = '/${segments[0]}/${segments[1]}';
    }
    return uri
        .replace(
          scheme: 'https',
          host: host,
          path: path,
          query: keepQuery ? uri.query : '',
          fragment: '',
        )
        .toString();
  }

  static String id(String ref) {
    var hash = BigInt.parse('cbf29ce484222325', radix: 16);
    final mask = BigInt.parse('ffffffffffffffff', radix: 16);
    for (final byte in utf8.encode(canonical(ref))) {
      hash = ((hash ^ BigInt.from(byte)) * BigInt.from(0x100000001b3)) & mask;
    }
    return hash.toRadixString(16).padLeft(16, '0');
  }

  static bool isRemote(String path) =>
      const ['http', 'https'].contains(Uri.tryParse(path)?.scheme);
}
