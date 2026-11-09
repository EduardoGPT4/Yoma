import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:yomashi/services/inmanga_service.dart';
import 'package:yomashi/services/mangadex_service.dart';
import 'package:yomashi/services/tmo_service.dart';
import 'package:yomashi/services/zonatmo_to_service.dart';
import 'package:yomashi/utils/app_failure.dart';
import 'package:yomashi/services/online_catalog_service.dart';

const mangaId = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee';
const chapterId = '11111111-2222-3333-4444-555555555555';

class FixtureHttp extends HttpClientFake {
  FixtureHttp(this.raw, this.origin);
  final HttpClient raw;
  final Uri origin;
  @override
  Future<HttpClientRequest> getUrl(Uri url) =>
      raw.getUrl(origin.replace(path: url.path, query: url.query));
}

class HttpClientFake implements HttpClient {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class FixtureOverrides extends HttpOverrides {
  FixtureOverrides(this.client);
  final HttpClient client;
  @override
  HttpClient createHttpClient(SecurityContext? context) => client;
}

class RealHttp extends HttpOverrides {}

void main() {
  late HttpServer server;
  late HttpClient raw;
  var largeFeed = false;
  var multilingualFeed = false;
  String? catalogTitle;
  final requestedUris = <Uri>[];
  setUpAll(() async {
    raw = HttpOverrides.runWithHttpOverrides(() => HttpClient(), RealHttp());
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    HttpOverrides.global = FixtureOverrides(
      FixtureHttp(raw, Uri.parse('http://127.0.0.1:${server.port}')),
    );
    server.listen((request) async {
      requestedUris.add(request.uri);
      final path = request.uri.path;
      Object? body;
      if (path == '/manga/$mangaId') {
        body = {
          'data': {
            'attributes': {
              'title': {'es': 'Fixture'},
            },
            'relationships': [],
          },
        };
      } else if (path == '/manga/$mangaId/feed' && largeFeed) {
        final offset = int.parse(request.uri.queryParameters['offset']!);
        body = {
          'total': 2100,
          'data': [
            for (var i = offset; i < offset + 100 && i < 2100; i++)
              {
                'id': 'chapter-$i',
                'attributes': {
                  'pages': 2,
                  'volume': '1',
                  'chapter': i.toString(),
                  'translatedLanguage': 'es',
                },
              },
          ],
        };
      } else if (path == '/manga/$mangaId/feed' && multilingualFeed) {
        body = {
          'total': 3,
          'data': [
            for (final (id, language, chapter) in [
              ('portuguese-1', 'pt-br', '1'),
              ('english-1', 'en', '1'),
              ('portuguese-2', 'pt-br', '2'),
            ])
              {
                'id': id,
                'attributes': {
                  'pages': 2,
                  'volume': '1',
                  'chapter': chapter,
                  'translatedLanguage': language,
                },
              },
          ],
        };
      } else if (path == '/manga/$mangaId/feed') {
        body = {
          'total': 2,
          'data': [
            {
              'id': 'chapter-a',
              'attributes': {
                'pages': 2,
                'volume': '1',
                'chapter': '1',
                'title': 'Amanecer',
                'translatedLanguage': 'es',
              },
            },
            {
              'id': 'chapter-b',
              'attributes': {
                'pages': 2,
                'volume': '1',
                'chapter': '1',
                'title': 'Dawn',
                'translatedLanguage': 'es-la',
              },
            },
          ],
        };
      } else if (path == '/manga') {
        body = {
          'data': [
            if (catalogTitle != null)
              {
                'id': mangaId,
                'attributes': {
                  'title': {'es': catalogTitle},
                },
                'relationships': [],
              },
          ],
          'total': 24,
        };
      } else if (path.startsWith('/ver/manga/')) {
        request.response.statusCode = 503;
        body = 'Temporary failure';
      } else if (path == '/chapter/getAll') {
        body = {
          'success': true,
          'result': [
            {'Identification': chapterId, 'Number': 1, 'PagesCount': 2},
          ],
        };
      } else if (path == '/wp-api/api/single/manga/fixture') {
        body = {
          'data': {
            'title': 'Fixture',
            'overview': 'Conocido como &lt;Twilight&gt; &amp; familia',
            'genres': [2, 4, 9999],
          },
        };
      } else if (path == '/') {
        body =
            '<script>var app = { datas: { genres: {"2":{"name":"Acción"},"4":{"name":"Comedia"}} } };</script>';
      } else if (path == '/wp-api/api/single/manga/fixture/chapters') {
        final page = int.parse(request.uri.queryParameters['page']!);
        body = {
          'data': {
            'items': [
              {'slug': 'chapter-$page', 'chapter_number': page.toString()},
            ],
            'pagination': {'total_pages': 41, 'has_next': page < 41},
          },
        };
      } else if (path == '/wp-api/api/single/manga/fixture/ordered') {
        body = {
          'data': {
            'chapter': {
              'jit': 'cdn-hash',
              'images': [
                {'image_url': '2.jpg', 'page_number': 2},
                {'image_url': '1.jpg', 'page_number': 1},
              ],
            },
          },
        };
      } else if (path == '/wp-api/api/single/manga/fixture/empty') {
        body = {
          'data': {
            'chapter': {'jit': 'cdn-hash', 'images': []},
          },
        };
      } else if (path == '/biblioteca') {
        body =
            '<div class="element"><a href="/library/manga/77/probe"><h4>Probe</h4></a></div>';
      } else if (path == '/library/manga/77/probe') {
        body =
            '<h1 class="element-title">Probe</h1><li class="upload-link" data-chapter-number="10"><span class="chapter-number">Capítulo 10</span><a href="/view_uploads/10">Leer</a></li>';
      } else if (path == '/view_uploads/10') {
        body =
            '<img class="reader-image" src="https://storage2.zonatmo.org/chapters/10/1.webp">';
      } else {
        request.response.statusCode = 404;
        body = 'Unknown fixture $path';
      }
      request.response.write(body is String ? body : jsonEncode(body));
      await request.response.close();
    });
  });
  tearDownAll(() async {
    await server.close(force: true);
    raw.close(force: true);
  });

  setUp(() {
    requestedUris.clear();
    catalogTitle = null;
    multilingualFeed = false;
    MangaDexService.setPreferredLanguages(MangaDexLanguage.defaultCodes);
  });

  tearDown(() {
    multilingualFeed = false;
    MangaDexService.setPreferredLanguages(MangaDexLanguage.defaultCodes);
  });

  test(
    'MangaDex sends all selected languages in search and pagination',
    () async {
      MangaDexService.setPreferredLanguages(['en', 'pt-br', 'zh-hk']);
      await MangaDexService.search('A & B');
      await MangaDexService.fetchCatalogPage(page: 2, postsPerPage: 12);

      final requests = requestedUris
          .where((uri) => uri.path == '/manga')
          .toList();
      expect(requests, hasLength(2));
      for (final request in requests) {
        expect(request.queryParametersAll['availableTranslatedLanguage[]'], [
          'en',
          'pt-br',
          'zh-hk',
        ]);
      }
      expect(requests.first.queryParameters['title'], 'A & B');
      expect(requests.last.queryParameters['offset'], '12');
    },
  );

  test(
    'MangaDex filters chapters and deduplicates using selected language order',
    () async {
      multilingualFeed = true;
      MangaDexService.setPreferredLanguages(['en', 'pt-br']);
      final detail = await MangaDexService.fetchMangaDetail(mangaId);

      final feed = requestedUris.singleWhere(
        (uri) => uri.path.endsWith('/feed'),
      );
      expect(feed.queryParametersAll['translatedLanguage[]'], ['en', 'pt-br']);
      expect(detail.chapters, hasLength(2));
      expect(detail.chapters.first.language, 'en');
      expect(detail.chapters.last.language, 'pt-br');
    },
  );

  test(
    'MangaDex deduplicates translated titles by volume and chapter',
    () async {
      final detail = await MangaDexService.fetchMangaDetail(mangaId);
      expect(detail.chapters.length, 1);
      expect(detail.chapters.single.language, 'es');
    },
  );
  test(
    'catalog keeps the original title for exact matching despite display cleanup',
    () async {
      catalogTitle = 'Probe - 2';
      final page = await MangaDexService.fetchCatalogPage(postsPerPage: 12);
      expect(page.items.single.title, 'Probe');
      expect(page.items.single.originalTitle, 'Probe - 2');
      expect(
        page.items.single.copyWith(sourceId: 'mangadex').originalTitle,
        'Probe - 2',
      );
    },
  );

  test('MangaDex exact page count', () async {
    final page = await MangaDexService.fetchCatalogPage(postsPerPage: 12);
    expect(page.totalPages, 2);
  });
  test('InManga preserves an HTTP failure as an error', () async {
    await expectLater(
      InMangaService.fetchMangaDetail(
        'https://inmanga.com/ver/manga/probe/$mangaId',
      ),
      throwsA(isA<AppFailure>().having((e) => e.statusCode, 'status', 503)),
    );
  });
  test('TMO legacy chapter 1 cannot resolve chapter 10', () async {
    await expectLater(
      TmoService.fetchChapterPages(
        'https://zonatmo.org/manga/probe/capitulo-1',
      ),
      throwsA(isA<Exception>()),
    );
  });
  test('zonatmo.to reads beyond forty chapter pages', () async {
    final detail = await ZonatmoToService.fetchMangaDetail(
      'https://zonatmo.to/manga/fixture',
    );
    expect(detail.chapters.length, 41);
    expect(detail.chapters.last.number, '41');
    expect(detail.description, 'Conocido como <Twilight> & familia');
    expect(detail.genres, ['Acción', 'Comedia']);
  });
  test('zonatmo.to sorts page_number and rejects empty pages', () async {
    final pages = await ZonatmoToService.fetchChapterPages(
      'https://zonatmo.to/manga/fixture/ordered',
    );
    expect(pages.first, endsWith('1.jpg'));
    expect(pages.last, endsWith('2.jpg'));
    await expectLater(
      ZonatmoToService.fetchChapterPages(
        'https://zonatmo.to/manga/fixture/empty',
      ),
      throwsA(isA<AppFailure>()),
    );
  });
  test(
    'interactive zonatmo.to detail exposes a partial list and an advancing cursor',
    () async {
      var detail = await ZonatmoToService.fetchMangaDetail(
        'https://zonatmo.to/manga/fixture',
        initialChaptersOnly: true,
      );
      expect(detail.chapters.length, 1);
      expect(detail.hasMoreChapters, isTrue);
      expect(detail.nextChapterCursor, 2);
      detail = await OnlineCatalogService.loadMoreChapters(detail);
      expect(detail.chapters.length, 2);
      expect(detail.nextChapterCursor, 3);
      final resolved = await OnlineCatalogService.resolveChapter(
        detail,
        'https://zonatmo.to/manga/fixture/chapter-4',
      );
      expect(resolved.chapters.length, 4);
      expect(resolved.hasMoreChapters, isTrue);
    },
  );

  test(
    'MangaDex chapter feed is not truncated at two thousand records',
    () async {
      largeFeed = true;
      try {
        final partial = await MangaDexService.fetchMangaDetail(
          mangaId,
          initialChaptersOnly: true,
        );
        expect(partial.chapters.length, 100);
        expect(partial.hasMoreChapters, isTrue);
        final full = await MangaDexService.fetchMangaDetail(mangaId);
        expect(full.chapters.length, 2100);
        expect(full.hasMoreChapters, isFalse);
      } finally {
        largeFeed = false;
      }
    },
  );
}
