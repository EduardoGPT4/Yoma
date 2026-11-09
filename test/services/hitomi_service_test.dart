import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:yomashi/services/hitomi_service.dart';
import 'package:yomashi/services/online_catalog_service.dart';
import 'package:yomashi/utils/app_failure.dart';

const _hash =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaabc';

void main() {
  late HttpServer server;
  late HttpClient raw;
  late HttpOverrides? previous;
  final requestedPaths = <String>[];
  String? failedExclusionIndex;

  setUpAll(() async {
    previous = HttpOverrides.current;
    raw = HttpOverrides.runWithHttpOverrides(HttpClient.new, _DirectHttp());
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    HttpOverrides.global = _Redirect(
      raw,
      Uri.parse('http://127.0.0.1:${server.port}'),
    );
    server.listen((request) async {
      final path = Uri.decodeComponent(request.uri.path);
      requestedPaths.add(path);
      final response = request.response;
      List<int> body;
      var status = 200;
      if (path == failedExclusionIndex) {
        status = 503;
        body = utf8.encode('synthetic exclusion index failure');
      } else if (path == '/gg.js') {
        body = utf8.encode('''
gg = { m: function(g) {
var o = 1;
switch (g) {
case 3243:
o = 0; break;
}
return o;
},
b: '123/'
};
''');
      } else if (path == '/galleries/42.js') {
        body = utf8.encode(_gallery(42, 'Hola'));
      } else if (path == '/galleries/99.js') {
        body = utf8.encode(_gallery(99, 'Otra'));
      } else if (path == '/galleries/7.js') {
        body = utf8.encode(_gallery(7, 'No'));
      } else if (RegExp(r'^/galleries/(8|9|10)\.js$').hasMatch(path)) {
        final id = int.parse(path.split('/').last.split('.').first);
        body = utf8.encode(_gallery(id, 'Excluida'));
      } else if (path == '/n/index-spanish.nozomi') {
        body = _nozomi(const [7, 8, 9, 10, 42, 99]);
      } else if (path == '/n/popular/week-spanish.nozomi') {
        body = _nozomi(const [99, 42]);
      } else if (path == '/n/artist/autor-spanish.nozomi') {
        body = _nozomi(const [42]);
      } else if (path == '/n/type/manga-spanish.nozomi') {
        body = _nozomi(const [42, 99]);
      } else if (path == '/n/tag/female:esternocleidomastoideo-all.nozomi') {
        body = _nozomi(const [7]);
      } else if (path == '/n/tag/guro-all.nozomi') {
        body = _nozomi(const [8]);
      } else if (path == '/n/tag/male:ryona-all.nozomi') {
        body = _nozomi(const [9]);
      } else if (path == '/n/tag/female:snuff-all.nozomi') {
        body = _nozomi(const [10]);
      } else if (path == '/galleriesindex/version') {
        body = utf8.encode('v1');
      } else if (path == '/galleriesindex/galleries.v1.index') {
        body = _titleNode(HitomiService.titleKey('hola'));
      } else if (path == '/galleriesindex/galleries.v1.data') {
        body = _idsData(const [42]);
      } else {
        status = 404;
        body = utf8.encode('missing');
      }
      final bytes = body;
      final range = request.headers.value(HttpHeaders.rangeHeader);
      var slice = bytes;
      if (range != null && status == 200) {
        final match = RegExp(r'bytes=(\d+)-(\d+)').firstMatch(range);
        if (match != null) {
          final start = int.parse(match.group(1)!);
          final end = int.parse(match.group(2)!);
          final last = bytes.isEmpty ? 0 : bytes.length - 1;
          final from = start.clamp(0, bytes.length);
          final to = end.clamp(from, last);
          slice = bytes.isEmpty ? bytes : bytes.sublist(from, to + 1);
          status = 206;
          response.headers.set(
            HttpHeaders.contentRangeHeader,
            'bytes $from-$to/${bytes.length}',
          );
        }
      }
      response.statusCode = status;
      response.add(slice);
      await response.close();
    });
  });

  tearDownAll(() async {
    HttpOverrides.global = previous;
    raw.close(force: true);
    await server.close(force: true);
  });

  setUp(() {
    HitomiService.resetForTest();
    requestedPaths.clear();
    failedExclusionIndex = null;
  });

  test('la clave de título usa los 4 primeros bytes de SHA-256', () {
    expect(HitomiService.titleKey('abc'), [0xba, 0x78, 0x16, 0xbf]);
  });

  test('construye la miniatura y la página con gg.js', () {
    final gg = HitomiService.parseGg('''
var o = 1;
case 3243:
o = 0;
b: '123/'
''');
    final file = {'hash': _hash, 'name': '001.jpg', 'haswebp': 1};
    expect(HitomiService.hashNumber(_hash), 0xcab);
    expect(
      HitomiService.mediaUrl(gg, file),
      'https://w1.gold-usergeneratedcontent.net/123/3243/$_hash.webp',
    );
    expect(
      HitomiService.mediaUrl(gg, file, thumbnail: true),
      'https://atn.gold-usergeneratedcontent.net/webpsmalltn/c/ab/$_hash.webp',
    );
  });

  test('el catálogo omite galerías bloqueadas y conserva el orden', () async {
    HitomiService.useLanguage('spanish');
    final page = await HitomiService.fetchCatalogPage(
      page: 1,
      postsPerPage: 12,
    );
    expect(page.items.map((item) => item.title), ['Hola', 'Otra']);
    expect(page.items.first.url, 'https://hitomi.la/galleries/42.html');
    expect(page.items.first.coverUrl, contains('/webpsmalltn/'));
    expect(page.items.first.sourceId, 'hitomi');
    for (final id in [7, 8, 9, 10]) {
      expect(requestedPaths, isNot(contains('/galleries/$id.js')));
    }
  });

  test('additional exclusions reject direct details and pages', () async {
    for (final id in [8, 9, 10]) {
      await expectLater(
        HitomiService.fetchMangaDetail('$id'),
        throwsA(isA<Exception>()),
      );
      await expectLater(
        HitomiService.fetchChapterPages('$id'),
        throwsA(isA<Exception>()),
      );
    }
  });

  test('failed exclusion indexes report an error and can be retried', () async {
    failedExclusionIndex = '/n/tag/guro-all.nozomi';
    await expectLater(
      HitomiService.fetchCatalogPage(),
      throwsA(
        isA<AppFailure>().having(
          (failure) => failure.statusCode,
          'status',
          503,
        ),
      ),
    );
    failedExclusionIndex = null;
    final page = await HitomiService.fetchCatalogPage();
    expect(page.items.map((item) => item.title), ['Hola', 'Otra']);
  });

  test(
    'restricted searches and suggestions stop before requesting indexes',
    () async {
      for (final query in ['tag:GURO', 'male:ryona', 'snuff']) {
        final page = await HitomiService.fetchCatalogPage(search: query);
        expect(page.items, isEmpty);
        expect(await HitomiService.fetchTagSuggestions(query), isEmpty);
      }
      expect(requestedPaths, isEmpty);
    },
  );

  test('la ficha es una sola galería y sus páginas salen del hash', () async {
    final detail = await HitomiService.fetchMangaDetail(
      'https://hitomi.la/manga/hola-42.html',
    );
    expect(detail.title, 'Hola');
    expect(detail.chapters, hasLength(1));
    expect(detail.chapters.single.pageCount, 1);
    expect(detail.author, 'autor');
    expect(detail.genres, contains('♀ romance'));
    final pages = await HitomiService.fetchChapterPages(detail.url);
    expect(pages, [
      'https://w1.gold-usergeneratedcontent.net/123/3243/$_hash.webp',
    ]);
    expect(
      () =>
          HitomiService.fetchMangaDetail('https://hitomi.la/galleries/7.html'),
      throwsA(isA<Exception>()),
    );
  });

  test('la búsqueda combina etiquetas, exclusiones y título', () async {
    HitomiService.useLanguage('spanish');
    final artist = await HitomiService.fetchCatalogPage(search: 'artist:autor');
    expect(artist.items.single.title, 'Hola');
    final excluded = await HitomiService.fetchCatalogPage(
      search: 'type:manga -artist:autor',
    );
    expect(excluded.items.single.title, 'Otra');
    final title = await HitomiService.fetchCatalogPage(search: 'hola');
    expect(title.items.single.url, contains('42'));
    final popular = await HitomiService.fetchUpdated();
    expect(popular.map((item) => item.title), ['Otra', 'Hola']);
  });

  test('los enlaces de Hitomi no se confunden con otra fuente', () {
    expect(
      OnlineCatalogService.sourceIdForRef(
        'https://hitomi.la/galleries/42.html',
      ),
      'hitomi',
    );
    expect(
      OnlineCatalogService.sourceIdForRef('hitomi://galleries/42'),
      'hitomi',
    );
    expect(
      OnlineCatalogService.searchableSourceIds.contains('hitomi'),
      isFalse,
    );
    expect(
      OnlineCatalogService.imageRequestHeaders(
        'https://w1.gold-usergeneratedcontent.net/123/1/abc.webp',
      ),
      containsPair('Referer', 'https://hitomi.la/'),
    );
  });
}

String _gallery(int id, String title) {
  return 'var galleryinfo = ${jsonEncode({
    'id': '$id',
    'title': title,
    'japanese_title': '別題',
    'language': 'spanish',
    'language_localname': 'Español',
    'type': 'manga',
    'date': '2024-05-01 00:00:00-05',
    'artists': [
      {'artist': 'autor'},
    ],
    'groups': [
      {'group': 'circulo'},
    ],
    'parodys': [
      {'parody': 'serie'},
    ],
    'characters': [
      {'character': 'ana'},
    ],
    'tags': [
      {
        'tag': const {7: 'esternocleidomastoideo', 8: 'guro', 9: 'ryona', 10: 'snuff'}[id] ?? 'romance',
        'female': '1',
      },
    ],
    'languages': [
      {'name': 'spanish', 'galleryid': id, 'language_localname': 'Español'},
      {'name': 'english', 'galleryid': id + 1, 'language_localname': 'English'},
    ],
    'files': [
      {'name': '001.jpg', 'hash': _hash, 'haswebp': 1, 'width': 800, 'height': 1200},
    ],
  })};';
}

List<int> _nozomi(List<int> ids) {
  final data = ByteData(ids.length * 4);
  for (var i = 0; i < ids.length; i++) {
    data.setInt32(i * 4, ids[i], Endian.big);
  }
  return data.buffer.asUint8List();
}

List<int> _idsData(List<int> ids) {
  final data = ByteData(4 + ids.length * 4);
  data.setInt32(0, ids.length, Endian.big);
  for (var i = 0; i < ids.length; i++) {
    data.setInt32(4 + i * 4, ids[i], Endian.big);
  }
  return data.buffer.asUint8List();
}

List<int> _titleNode(List<int> key) {
  final builder = BytesBuilder();
  void i32(int value) {
    final data = ByteData(4)..setInt32(0, value, Endian.big);
    builder.add(data.buffer.asUint8List());
  }

  void u64(int value) {
    final data = ByteData(8)..setUint64(0, value, Endian.big);
    builder.add(data.buffer.asUint8List());
  }

  i32(1);
  i32(key.length);
  builder.add(key);
  i32(1);
  u64(0);
  i32(8);
  for (var i = 0; i < 17; i++) {
    u64(0);
  }
  return builder.toBytes();
}

class _DirectHttp extends HttpOverrides {}

class _Redirect extends HttpOverrides {
  _Redirect(this.raw, this.origin);
  final HttpClient raw;
  final Uri origin;
  @override
  HttpClient createHttpClient(SecurityContext? context) => _Client(raw, origin);
}

class _Client implements HttpClient {
  _Client(this.raw, this.origin);
  final HttpClient raw;
  final Uri origin;
  @override
  Future<HttpClientRequest> getUrl(Uri url) {
    return raw.getUrl(origin.replace(path: url.path, query: url.query));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
