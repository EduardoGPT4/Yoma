import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yomashi/models/content_identity.dart';
import 'package:yomashi/models/manga_source.dart';
import 'package:yomashi/services/leercapitulo_service.dart';
import 'package:yomashi/services/mal_source_matcher.dart';
import 'package:yomashi/services/mangalect_service.dart';
import 'package:yomashi/services/mangaoni_service.dart';
import 'package:yomashi/services/manhwaweb_service.dart';
import 'package:yomashi/services/myanimelist_client.dart';
import 'package:yomashi/services/myanimelist_service.dart';
import 'package:yomashi/services/online_catalog_service.dart';
import 'package:yomashi/utils/app_failure.dart';

/// Redirige cualquier host al servidor local, conservando ruta y consulta.
class _FixtureHttp implements HttpClient {
  _FixtureHttp(this.raw, this.origin, this.hosts);
  final HttpClient raw;
  final Uri origin;
  final List<String> hosts;
  @override
  Future<HttpClientRequest> getUrl(Uri url) {
    hosts.add(url.host);
    return raw.getUrl(origin.replace(path: url.path, query: url.query));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FixtureOverrides extends HttpOverrides {
  _FixtureOverrides(this.client);
  final HttpClient client;
  @override
  HttpClient createHttpClient(SecurityContext? context) => client;
}

class _RealHttp extends HttpOverrides {}

const _leerCatalog = '''
<div class="row g-3">
  <div class="col-4"><article class="lc-card">
    <a class="lc-card-cover" href="/manga/mzstjz4n73/sakamoto-days/" tabindex="-1">
      <img src="/covers/62/de8f.jpg?v1" alt="" loading="lazy">
      <span class="lc-card-badge">Manga</span>
    </a>
    <div class="lc-card-body">
      <a class="lc-card-name d-block" href="/manga/mzstjz4n73/sakamoto-days/">Sakamoto Days</a>
    </div>
  </article></div>
  <div class="col-4"><article class="lc-card">
    <a class="lc-card-cover" href="/manga/o9rry7nrso/el-jugador/"><img src="/covers/89/a0aa.jpg" alt=""><span class="lc-card-badge">Manhwa</span></a>
    <div class="lc-card-body"><a class="lc-card-name d-block" href="/manga/o9rry7nrso/el-jugador/">El jugador &amp; cía</a></div>
  </article></div>
</div>
<a class="page-link" href="/manga/?page=2" rel="next">&rsaquo;</a>
''';

const _leerHome = '''
<div class="lc-slide">
  <a class="lc-slide-cover" href="/manga/mzstjz4n73/sakamoto-days/"><img src="/covers/62/de8f.jpg" alt=""></a>
  <a class="lc-slide-name" href="/manga/mzstjz4n73/sakamoto-days/">Sakamoto Days</a>
  <a class="lc-slide-chapter d-block" href="/leer/mzstjz4n73/sakamoto-days/283/">Capitulo 283</a>
</div>
<a class="lc-side-item" href="/manga/mzstjz4n73/sakamoto-days/">
  <img src="/covers/62/de8f.jpg" alt="Portada de Sakamoto Days">
  <span class="lc-sr-body"><span class="lc-side-name">Sakamoto Days</span><span class="lc-side-chapter">Capitulo 283</span></span>
</a>
<a class="lc-side-item" href="/manga/5wug0t6pnz/pei-bao/">
  <img src="/covers/e6/b25f.jpg" alt="Portada de Pei Bao">
  <span class="lc-sr-body"><span class="lc-side-name">Pei Bao</span><span class="lc-side-chapter">Capitulo 2</span></span>
</a>
''';

const _leerDetail = '''
<aside><a class="badge" href="/manga/?genre=hentai">No es de esta obra</a></aside>
<article class="lc-panel"><div class="row">
  <div class="col-5"><div class="lc-cover-lg"><img src="/covers/62/de8f.jpg?v1" alt="Portada de Sakamoto Days"></div></div>
  <div class="col-7">
    <h1 class="h3 mb-1">Sakamoto Days</h1>
    <p class="small lc-muted mb-2">サカモト デイズ · Sakamoto Days · SAKAMOTO DAYS 坂本日常</p>
    <div class="d-flex">
      <a class="badge text-bg-secondary" href="/manga/?genre=action">Action</a>
      <a class="badge text-bg-light" href="/manga/?theme=delinquents">Delinquents</a>
    </div>
    <ul class="lc-facts mb-3">
      <li><span class="k">Estado</span><a href="/manga/?status=ongoing">Ongoing</a></li>
      <li><span class="k">Tipo</span><a href="/manga/?type=manga">Manga</a></li>
      <li><span class="k">Autor</span><span>Suzuki Yuuto</span></li>
    </ul>
  </div>
</div></article>
<section class="lc-panel" id="sinopsis"><h2>Sinopsis</h2><div><p class="mb-0">Taro Sakamoto era el asesino definitivo.</p></div></section>
<div id="chapterList">
  <a class="lc-chapter-row" href="/leer/mzstjz4n73/sakamoto-days/10/"><span class="n">Capitulo 10</span><span class="d">2026-11-15</span></a>
  <a class="lc-chapter-row" href="/leer/mzstjz4n73/sakamoto-days/9.5/"><span class="n">Capitulo 9.5</span><span class="d">2026-11-08</span></a>
  <a class="lc-chapter-row" href="/leer/mzstjz4n73/sakamoto-days/2/"><span class="n">Capitulo 2</span><span class="d">2026-11-04</span></a>
</div>
''';

const _leerChapter = '''
<main class="lc-pages" id="lcPages" data-mode="vertical">
  <img data-src="https://es1s11-95168.t34798ndc.com/a/1.jpg" alt="Capitulo 10 pagina 1" data-index="0" class="is-pending">
  <img data-src="https://es1s11-95168.t34798ndc.com/a/2.jpg" alt="Capitulo 10 pagina 2" data-index="1" class="is-pending">
</main>
<img src="/covers/otro.jpg" alt="recomendado">
''';

String _oniCard(String kind, String slug, String title, {bool lazy = true}) =>
    '<div class="_135yj"><a href="https://manga-oni.com/$kind/$slug/" itemprop="url" class="_1A2Dc">'
    '<div class="_1-8M9"><img src="https://oni.ntr-files.online/public/archivos/default.gif" '
    '${lazy ? 'data-src="https://oni.ntr-files.online/public/archivos/mangas/$slug/cover.jpg?1"' : ''} '
    'alt="$title" itemprop="image"><b id="in" class="c0">$kind</b></div>'
    '<div class="_2NNxg"><span class="_1A2Dc">$title</span></div></a></div>';

final _oniDirectory =
    '<div id="article-div">'
    '${_oniCard('manga', 'berserk', 'Berserk')}'
    '${_oniCard('novela', 'una-novela', 'Una novela')}'
    '${_oniCard('manhwa', 'la-vida', 'La vida después')}'
    '</div><a class="page-link" href="https://manga-oni.com/directorio?p=2" rel="next">&rsaquo;</a>';

final _oniChapter =
    "<script> var unicap = '${base64.encode(utf8.encode('https://oni.ntr-files.online/public/archivos/mangas/dandadan/828300/||["001.webp?up=1","002.webp?up=1"]||'))}'; </script>";

const _oniDetail = '''
<meta content="https://oni.ntr-files.online/public/archivos/mangas/dandadan/cover.jpg?175" property="og:image" />
<article class="manga post hentry"><header class="entry-header">
  <h1 class="post-title"> <a data-id="4497" class="ajp" href="https://manga-oni.com/manga/dandadan/">Dandadan</a> </h1>
  <div id="categ"><a href="#">Comedia</a><a href="#">Acción</a></div></header>
  <div id="info-i"> <strong>Alterno:</strong> ダ ン ダ ダ ン<br><strong>Ranking:</strong> <span id="ranking" class="estado">#36</span><br>
   <strong>Autor:</strong> Tatsu Yukinobu <br><strong>Fecha:</strong> 2021<br><strong>Estado:</strong> <span id="desarrollo" class="estado">En desarrollo</span> <br></div>
  <div id="sinopsis"> <h3>Sinopsis</h3> Takakura es un entusiasta del ocultismo. </div>
</article>
<div id="c_list">
  <a href="https://manga-oni.com/lector/dandadan/828300/" class=""><div class="entry-title"><span class="timeago" data-user="x" data-num="253" datetime="2026-11-16 15:51:40"></span><h3 class="entry-title-h2">Capítulo 253 </h3></div></a>
  <a href="https://manga-oni.com/lector/dandadan/824289/" class=""><div class="entry-title"><span class="timeago" data-user="x" data-num="252" datetime="2026-11-09 15:07:58"></span><h3 class="entry-title-h2">Capítulo 252 </h3></div></a>
</div>
''';

const _manhwaDetail = <String, dynamic>{
  '_id': 'solo-leveling-ragnarok_1783909089054',
  'real_id': 'solo-leveling-ragnarok_1783909089054',
  'name_esp': 'Solo Leveling: Ragnarok',
  '_imagen': 'https://img2mw.xyz/manhwas/solo/cover.webp',
  '_status': 'publicandose',
  '_tipo': 'manhwa',
  '_sinopsis': 'La Tierra se ve amenazada.',
  '_categoris': [
    {'1': 'Drama'},
  ],
  '_extras': {'autores': <String>[]},
  'autor': [
    {'_id': 'a1', 'name': 'DAUL'},
  ],
  'chapters': [
    {
      'chapter': 1,
      'link':
          'https://manhwaweb.com/leer/solo-leveling-ragnarok_1783909089054-1_01',
    },
    // Los capítulos recientes solo traen `versions`.
    {
      'chapter': 72,
      'img': <String>[],
      'versions': [
        {
          'link':
              'https://manhwaweb.com/leer/solo-leveling-ragnarok_1783909089054-72_01',
        },
      ],
    },
  ],
};

const _lectCatalog = <String, Object>{
  'resultados': [
    {
      'id': 1605,
      'slug': 'kijin-gentoushou',
      'titulo': 'Kijin Gentoushou',
      'portada': 'portadas/Kijin_Gentoushou.webp',
      'tipo': 'manga',
      'generos': ['Acción', 'Accion', 'acción', 'Samurai', 'Manga'],
      'ultimo_capitulo': 62.0,
      'demografia': 'seinen',
    },
    {
      'id': 9,
      'slug': 'oculta',
      'titulo': 'Oculta',
      'portada': 'portadas/oculta.webp',
      'tipo': 'manga',
      'generos': ['Comedia', 'Loli'],
    },
    {
      'id': 7544,
      'slug': 'the-war-of-corpses',
      'titulo': 'The War Of Corpses',
      'portada':
          'https://images.mangalect.org/file/leermangaesp/portadas/war.webp',
      'tipo': 'manhwa',
      'generos': ['Acción'],
    },
    {'slug': 'kijin-gentoushou', 'titulo': 'Repetida', 'tipo': 'manga'},
  ],
  'page': 2,
  'page_size': 24,
  'total_pages': 3,
  'total_results': 60,
};

const _lectLatest = [
  {
    'slug': 'sanda',
    'titulo': 'SANDA',
    'portada': 'portadas/SANDA.webp',
    'tipo': 'manga',
    'genero': 'manga',
    'ultimo_capitulo': 88.0,
  },
  {'slug': 'sanda', 'titulo': 'SANDA', 'tipo': 'manga'},
];

String _lectChapterCard(String number) =>
    '''
<div class="chapter-card">
  <a href="/lectura/kijin-gentoushou/$number/" class="chapter-link" data-chapter="$number" data-manga-slug="kijin-gentoushou">
    <div class="chapter-title">Capítulo $number</div>
    <div class="chapter-date">November 19, 2026</div>
  </a>
</div>''';

String _lectDetail({required List<String> chapters, String? before}) =>
    '''
<div class="manga-page" data-manga-id="1605" data-portada-rel="portadas/Kijin_Gentoushou.webp" data-manga-tipo="manga" data-manga-demografia="seinen">
  <div class="manga-info" id="manga-info">
    <h1 class="manga-title">Kijin Gentoushou</h1>
    <ul class="info-value alternate-titles">
      <li>Sword of the Demon Hunter: Kijin Gentōshō</li>
      <li>鬼人幻燈抄, Kijin Gentosho, Demon Person, Kijin Gentoushou</li>
    </ul>
  </div>
  <div class="info-generos" id="info-generos">
    <a href="/biblioteca/?generos=Acci%C3%B3n" class="genero-item"> Acción </a>
    <a href="/biblioteca/?generos=Accion" class="genero-item"> Accion </a>
    <a href="/biblioteca/?generos=Samurai" class="genero-item"> Samurai </a>
  </div>
  <div class="info-block status-badge-row" id="info-block">
    <span class="info-value status-text">
      En curso
    </span>
  </div>
  <p id="synopsis-text"> En el período Edo, Jinta protege a la doncella. </p>
  <div class="chapter-scroll" id="chapter-list">
    <div id="continue-reading" class="chapter-card continue-card" hidden>
      <a id="continue-link" class="chapter-link" href="#">Continuar</a>
    </div>
    ${chapters.map(_lectChapterCard).join()}
    ${before == null ? '' : '<div class="chapter-card chapter-card-full"><a id="more-link" class="btn-ver-mas" href="?before=$before">Ver más</a></div>'}
  </div>
</div>
''';

const _lectChapter = '''
<link rel="preload" as="image" href="https://images.mangalect.org/file/leermangaesp/mangas/66237/capitulo_62.00/pagina_001.webp">
<script>
document.addEventListener("DOMContentLoaded", function () {
  const Config = {
    B2_URL: "https://images.mangalect.org/file/leermangaesp",
    capituloId: "353083",
    paginasRutas: ["mangas/66237/capitulo_62.00/pagina_001.webp", "mangas/66237/capitulo_62.00/pagina_002.webp"],
  };
});
</script>
''';

const _lectCascade = '''
<div id="cascade-view" class="chapter-container">
  <div class="manga-image-container" data-page-index="0">
    <img src="https://images.mangalect.org/file/leermangaesp/mangas/66237/capitulo_1.00/pagina_001.webp" class="manga-image">
  </div>
  <div class="manga-image-container" data-page-index="1">
    <img src="https://images.mangalect.org/file/leermangaesp/mangas/66237/capitulo_1.00/pagina_002.webp" class="manga-image">
  </div>
</div>
''';

void main() {
  late HttpServer server;
  late HttpClient raw;
  final hosts = <String>[];
  final requested = <Uri>[];

  setUpAll(() async {
    raw = HttpOverrides.runWithHttpOverrides(() => HttpClient(), _RealHttp());
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    HttpOverrides.global = _FixtureOverrides(
      _FixtureHttp(raw, Uri.parse('http://127.0.0.1:${server.port}'), hosts),
    );
    server.listen((request) async {
      requested.add(request.uri);
      final path = request.uri.path;
      final query = request.uri.queryParameters;
      Object? body;
      if (path == '/manga/' && query['q'] == 'nada') {
        body = '<div class="row g-3"></div>';
      } else if (path == '/manga/') {
        body = _leerCatalog;
      } else if (path == '/') {
        body = _leerHome;
      } else if (path == '/manga/mzstjz4n73/sakamoto-days/') {
        body = _leerDetail;
      } else if (path == '/leer/mzstjz4n73/sakamoto-days/10/') {
        body = _leerChapter;
      } else if (path == '/leer/mzstjz4n73/sakamoto-days/2/') {
        body = '<main class="lc-pages" id="lcPages"></main>';
      } else if (path == '/directorio') {
        body = _oniDirectory;
      } else if (path == '/buscar') {
        body = _oniCard('manga', 'one-piece', 'One Piece', lazy: false);
      } else if (path == '/manga/dandadan/') {
        body = _oniDetail;
      } else if (path == '/lector/dandadan/828300/') {
        body = _oniChapter;
      } else if (path == '/lector/dandadan/824289/') {
        body = '<script>var otra = 1;</script>';
      } else if (path == '/api/buscar_mangas/' && query['query'] == 'nada') {
        body = <String, Object>{'resultados': <Object>[], 'total_pages': 0};
      } else if (path == '/api/buscar_mangas/') {
        body = _lectCatalog;
      } else if (path == '/api/latest_chapters_with_dates/') {
        body = _lectLatest;
      } else if (path == '/info/kijin-gentoushou/' &&
          query['before'] == '61.50') {
        // Repite el enlace: el cliente no debe volver a pedirlo.
        body = _lectDetail(
          chapters: ['61.50', '1.00', '10.00'],
          before: '61.50',
        );
      } else if (path == '/info/kijin-gentoushou/') {
        body = _lectDetail(chapters: ['62.00', '61.50'], before: '61.50');
      } else if (path == '/info/oculta/') {
        body = _lectDetail(chapters: ['1.00']).replaceAll('Samurai', 'Shota');
      } else if (path == '/lectura/kijin-gentoushou/62/') {
        body = _lectChapter;
      } else if (path == '/lectura/kijin-gentoushou/1/') {
        body = _lectCascade;
      } else if (path == '/lectura/kijin-gentoushou/2/') {
        body = '<div id="cascade-view"></div>';
      } else if (path == '/manhwa/see/solo-leveling-ragnarok_1783909089054') {
        body = _manhwaDetail;
      } else {
        request.response.statusCode = 404;
        body = 'Unknown fixture $path';
      }
      request.response.headers.contentType = ContentType(
        'text',
        body is String ? 'html' : 'json',
        charset: 'utf-8',
      );
      request.response.write(body is String ? body : jsonEncode(body));
      await request.response.close();
    });
  });

  tearDownAll(() async {
    await server.close(force: true);
    raw.close(force: true);
  });

  setUp(() {
    hosts.clear();
    requested.clear();
  });

  group('ManhwaWeb', () {
    test('usa el backend actual y lee capítulos que solo traen versions', () async {
      final detail = await OnlineCatalogService.adapter('manhwaweb').detail(
        'https://www.manhwaweb.com/manhwa/solo-leveling-ragnarok_1783909089054',
      );

      expect(hosts.single, 'api.manhwaweb.com');
      expect(detail.title, 'Solo Leveling: Ragnarok');
      expect(detail.author, 'DAUL');
      expect(detail.genres, ['Drama']);
      expect(detail.chapters.map((c) => c.title), [
        'Capítulo 1',
        'Capítulo 72',
      ]);
      expect(
        detail.chapters.last.path,
        'https://www.manhwaweb.com/leer/solo-leveling-ragnarok_1783909089054-72_01',
      );
      expect(MyAnimeListService.chapterNumber(detail.chapters.last), 72);
      expect(ManhwaWebService.apiUrl, isNot(contains('railway')));
    });
  });

  group('LeerCapitulo', () {
    test('catálogo, búsqueda y paginación', () async {
      final page = await OnlineCatalogService.fetchCatalogPageForSource(
        'leercapitulo',
        search: 'sakamoto days',
        page: 2,
      );
      expect(requested.single.queryParameters, {
        'q': 'sakamoto days',
        'page': '2',
      });
      expect(hosts.single, 'www.leercapitulo.co');
      expect(page.items, hasLength(2));
      expect(page.hasNext, isTrue);
      final first = page.items.first;
      expect(first.title, 'Sakamoto Days');
      expect(
        first.url,
        'https://www.leercapitulo.co/manga/mzstjz4n73/sakamoto-days/',
      );
      expect(
        first.coverUrl,
        'https://www.leercapitulo.co/covers/62/de8f.jpg?v1',
      );
      expect(first.type, 'Manga');
      expect(page.items.last.originalTitle, 'El jugador & cía');

      final empty = await LeerCapituloService.fetchCatalogPage(search: 'nada');
      expect(empty.items, isEmpty);
      expect(empty.hasNext, isFalse);
    });

    test('la portada no repite obras', () async {
      final feed = await OnlineCatalogService.adapter('leercapitulo').feed();
      expect(feed.map((item) => item.title), ['Sakamoto Days', 'Pei Bao']);
      expect(feed.last.coverUrl, endsWith('/covers/e6/b25f.jpg'));
    });

    test('ficha técnica con capítulos en orden ascendente', () async {
      final detail = await OnlineCatalogService.fetchMangaDetail(
        'https://www.leercapitulo.co/manga/mzstjz4n73/sakamoto-days/',
      );
      expect(detail.title, 'Sakamoto Days');
      expect(detail.altTitles, ['サカモト デイズ', 'SAKAMOTO DAYS 坂本日常']);
      expect(detail.genres, ['Action', 'Delinquents']);
      expect(detail.status, 'Publicándose');
      expect(detail.type, 'Manga');
      expect(detail.author, 'Suzuki Yuuto');
      expect(detail.description, 'Taro Sakamoto era el asesino definitivo.');
      expect(detail.coverUrl, endsWith('/covers/62/de8f.jpg?v1'));
      expect(detail.chapters.map((c) => c.number), ['2', '9.5', '10']);
      expect(detail.chapters.last.title, 'Capítulo 10');
      expect(
        detail.chapters.last.path,
        'https://www.leercapitulo.co/leer/mzstjz4n73/sakamoto-days/10/',
      );
      // MAL solo cuenta capítulos enteros.
      expect(MyAnimeListService.chapterNumber(detail.chapters.last), 10);
      expect(MyAnimeListService.chapterNumber(detail.chapters[1]), isNull);
    });

    test('páginas del lector y capítulo vacío', () async {
      final pages = await OnlineCatalogService.fetchChapterPages(
        'https://www.leercapitulo.co/leer/mzstjz4n73/sakamoto-days/10/',
      );
      expect(pages, [
        'https://es1s11-95168.t34798ndc.com/a/1.jpg',
        'https://es1s11-95168.t34798ndc.com/a/2.jpg',
      ]);
      await expectLater(
        LeerCapituloService.fetchChapterPages(
          'https://www.leercapitulo.co/leer/mzstjz4n73/sakamoto-days/2/',
        ),
        throwsA(isA<AppFailure>()),
      );
    });

    test('un 404 de la fuente se conserva como error HTTP', () async {
      await expectLater(
        LeerCapituloService.fetchMangaDetail(
          'https://www.leercapitulo.co/manga/zzz/no-existe/',
        ),
        throwsA(isA<AppFailure>().having((e) => e.statusCode, 'status', 404)),
      );
    });

    test('rechaza referencias de otros sitios', () {
      expect(
        LeerCapituloService.mangaUrl('https://manga-oni.com/manga/dandadan/'),
        isNull,
      );
      expect(
        LeerCapituloService.mangaUrl(
          'https://www.leercapitulo.co/leer/mzstjz4n73/sakamoto-days/10/',
        ),
        'https://www.leercapitulo.co/manga/mzstjz4n73/sakamoto-days/',
      );
    });
  });

  group('MangaOni', () {
    test('el directorio omite novelas y pagina', () async {
      final page = await OnlineCatalogService.fetchCatalogPageForSource(
        'mangaoni',
        page: 3,
      );
      expect(requested.single.path, '/directorio');
      expect(requested.single.queryParameters['p'], '3');
      expect(requested.single.queryParameters['filtro'], 'visitas');
      expect(page.items.map((item) => item.title), [
        'Berserk',
        'La vida después',
      ]);
      expect(page.items.last.type, 'Manhwa');
      expect(page.items.last.url, 'https://manga-oni.com/manhwa/la-vida/');
      expect(
        page.items.first.coverUrl,
        'https://oni.ntr-files.online/public/archivos/mangas/berserk/cover.jpg?1',
      );
      expect(page.hasNext, isTrue);
    });

    test('la búsqueda es de una sola página', () async {
      final page = await MangaOniService.fetchCatalogPage(search: 'one piece');
      expect(requested.single.path, '/buscar');
      expect(requested.single.queryParameters['q'], 'one piece');
      expect(page.items.single.title, 'One Piece');
      expect(page.items.single.type, 'Manga');
      expect(page.items.single.coverUrl, isNull);
      expect(page.hasNext, isFalse);

      requested.clear();
      final second = await MangaOniService.fetchCatalogPage(
        search: 'one piece',
        page: 2,
      );
      expect(second.items, isEmpty);
      expect(requested, isEmpty);
    });

    test('ficha técnica', () async {
      final detail = await OnlineCatalogService.fetchMangaDetail(
        'https://manga-oni.com/manga/dandadan/',
      );
      expect(detail.title, 'Dandadan');
      expect(detail.altTitles, ['ダ ン ダ ダ ン']);
      expect(detail.author, 'Tatsu Yukinobu');
      expect(detail.year, '2021');
      expect(detail.status, 'Publicándose');
      expect(detail.type, 'Manga');
      expect(detail.genres, ['Comedia', 'Acción']);
      expect(detail.description, 'Takakura es un entusiasta del ocultismo.');
      expect(detail.coverUrl, contains('/dandadan/cover.jpg'));
      expect(detail.chapters.map((c) => c.number), ['252', '253']);
      expect(detail.chapters.last.title, 'Capítulo 253');
      expect(MyAnimeListService.chapterNumber(detail.chapters.last), 253);
    });

    test('decodifica las páginas del lector', () async {
      final pages = await OnlineCatalogService.fetchChapterPages(
        'https://manga-oni.com/lector/dandadan/828300/cascada/',
      );
      expect(requested.single.path, '/lector/dandadan/828300/');
      expect(pages, [
        'https://oni.ntr-files.online/public/archivos/mangas/dandadan/828300/001.webp?up=1',
        'https://oni.ntr-files.online/public/archivos/mangas/dandadan/828300/002.webp?up=1',
      ]);
      await expectLater(
        MangaOniService.fetchChapterPages(
          'https://manga-oni.com/lector/dandadan/824289/',
        ),
        throwsA(isA<AppFailure>()),
      );
      expect(MangaOniService.decodePages("var unicap = '%%%';"), isEmpty);
    });

    test('solo acepta fichas de obras', () {
      expect(
        MangaOniService.mangaUrl('https://manga-oni.com/novela/x/'),
        isNull,
      );
      expect(
        MangaOniService.mangaUrl('https://manga-oni.com/grupo/3/'),
        isNull,
      );
      expect(
        MangaOniService.mangaUrl('https://zonatmo.to/manga/dandadan'),
        isNull,
      );
    });
  });

  group('MangaLect', () {
    test('catálogo paginado sin repetidos ni obras excluidas', () async {
      final page = await OnlineCatalogService.fetchCatalogPageForSource(
        'mangalect',
        page: 2,
      );
      expect(requested.single.path, '/api/buscar_mangas/');
      expect(requested.single.queryParameters['page'], '2');
      expect(requested.single.queryParameters['page_size'], '24');
      expect(requested.single.queryParameters.containsKey('query'), isFalse);
      expect(page.items.map((item) => item.title), [
        'Kijin Gentoushou',
        'The War Of Corpses',
      ]);
      final first = page.items.first;
      expect(first.url, 'https://mangalect.org/info/kijin-gentoushou/');
      expect(
        first.coverUrl,
        'https://images.mangalect.org/file/leermangaesp/portadas/Kijin_Gentoushou.webp',
      );
      expect(first.type, 'Manga');
      expect(first.genres, ['Acción', 'Samurai']);
      expect(page.items.last.type, 'Manhwa');
      expect(page.items.last.coverUrl, endsWith('/portadas/war.webp'));
      expect(page.hasNext, isTrue);
    });

    test('búsqueda y novedades', () async {
      final empty = await MangaLectService.fetchCatalogPage(search: ' nada ');
      expect(requested.single.queryParameters['query'], 'nada');
      expect(empty.items, isEmpty);
      expect(empty.hasNext, isFalse);

      final feed = await MangaLectService.fetchUpdated();
      expect(feed.single.title, 'SANDA');
      expect(feed.single.url, 'https://mangalect.org/info/sanda/');
      expect(feed.single.genres, isEmpty);
    });

    test('ficha con todos los capítulos en orden ascendente', () async {
      final detail = await OnlineCatalogService.fetchMangaDetail(
        'https://mangalect.org/lectura/kijin-gentoushou/62/',
      );
      expect(requested.map((uri) => uri.queryParameters['before']).toList(), [
        null,
        '61.50',
      ]);
      expect(detail.url, 'https://mangalect.org/info/kijin-gentoushou/');
      expect(detail.title, 'Kijin Gentoushou');
      expect(detail.type, 'Manga');
      expect(detail.status, 'Publicándose');
      expect(detail.genres, ['Acción', 'Samurai']);
      expect(
        detail.description,
        'En el período Edo, Jinta protege a la doncella.',
      );
      expect(detail.altTitles, [
        'Sword of the Demon Hunter: Kijin Gentōshō',
        '鬼人幻燈抄',
        'Kijin Gentosho',
        'Demon Person',
      ]);
      expect(detail.coverUrl, endsWith('/portadas/Kijin_Gentoushou.webp'));
      expect(detail.chapters.map((c) => c.number), ['1', '10', '61.5', '62']);
      expect(
        detail.chapters.last.path,
        'https://mangalect.org/lectura/kijin-gentoushou/62/',
      );
      expect(detail.chapters[2].title, 'Capítulo 61.5');
      expect(detail.hasMoreChapters, isFalse);
      expect(MyAnimeListService.chapterNumber(detail.chapters.last), 62);
    });

    test('una ficha excluida no se abre', () async {
      await expectLater(
        MangaLectService.fetchMangaDetail('https://mangalect.org/info/oculta/'),
        throwsA(isA<AppFailure>()),
      );
    });

    test('páginas del lector', () async {
      final pages = await OnlineCatalogService.fetchChapterPages(
        'https://mangalect.org/lectura/kijin-gentoushou/62.00/',
      );
      expect(requested.single.path, '/lectura/kijin-gentoushou/62/');
      expect(pages, [
        'https://images.mangalect.org/file/leermangaesp/mangas/66237/capitulo_62.00/pagina_001.webp',
        'https://images.mangalect.org/file/leermangaesp/mangas/66237/capitulo_62.00/pagina_002.webp',
      ]);
      final cascade = await MangaLectService.fetchChapterPages(
        'https://mangalect.org/lectura/kijin-gentoushou/1/',
      );
      expect(cascade, hasLength(2));
      expect(cascade.last, endsWith('/capitulo_1.00/pagina_002.webp'));
      await expectLater(
        MangaLectService.fetchChapterPages(
          'https://mangalect.org/lectura/kijin-gentoushou/2/',
        ),
        throwsA(isA<AppFailure>()),
      );
    });

    test('referencias y números de capítulo', () {
      expect(MangaLectService.chapterNumber('62.00'), '62');
      expect(MangaLectService.chapterNumber('90.50'), '90.5');
      expect(MangaLectService.chapterNumber('6.2'), '6.2');
      expect(MangaLectService.chapterNumber('007'), '7');
      expect(MangaLectService.chapterNumber('0.50'), '0.5');
      expect(MangaLectService.chapterNumber('extra'), isNull);
      expect(
        MangaLectService.mangaUrl('https://www.mangalect.org/info/sanda'),
        'https://mangalect.org/info/sanda/',
      );
      expect(MangaLectService.mangaUrl('https://mangalect.org/dmca/'), isNull);
      expect(
        MangaLectService.mangaUrl('https://manga-oni.com/info/x/'),
        isNull,
      );
      expect(
        MangaLectService.chapterUrl('/lectura/sanda/88.00/'),
        'https://mangalect.org/lectura/sanda/88/',
      );
    });
  });

  group('Integración con el resto de la app', () {
    test('las referencias se atribuyen a su fuente', () {
      const refs = {
        'https://www.leercapitulo.co/manga/mzstjz4n73/sakamoto-days/':
            'leercapitulo',
        'https://www.leercapitulo.co/leer/mzstjz4n73/sakamoto-days/10/':
            'leercapitulo',
        'https://manga-oni.com/manhwa/la-vida/': 'mangaoni',
        'https://manga-oni.com/lector/dandadan/828300/': 'mangaoni',
        'https://oni.ntr-files.online/public/archivos/mangas/a/1/001.webp':
            'mangaoni',
        'https://www.manhwaweb.com/manhwa/x_1783909089054': 'manhwaweb',
        'https://mangalect.org/info/sanda/': 'mangalect',
        'https://images.mangalect.org/file/leermangaesp/mangas/1/a.webp':
            'mangalect',
      };
      refs.forEach(
        (ref, id) => expect(OnlineCatalogService.sourceIdForRef(ref), id),
      );
      expect(
        OnlineCatalogService.belongsToSource(
          'https://manga-oni.com/manga/dandadan/',
          'leercapitulo',
        ),
        isFalse,
      );
    });

    test('aparecen en Fuentes, en la búsqueda global y en Mangas MAL', () {
      for (final id in ['leercapitulo', 'mangaoni', 'mangalect']) {
        expect(MangaSources.all.map((source) => source.id), contains(id));
        expect(MangaSources.byId(id).id, id);
        expect(MangaSources.shortLabel(id), MangaSources.byId(id).name);
        expect(OnlineCatalogService.searchableSourceIds, contains(id));
      }
      // Toda fuente visible tiene conector, y al revés.
      expect(
        MangaSources.all.map((source) => source.id).toSet(),
        OnlineCatalogService.searchableSourceIds.toSet(),
      );
    });

    test('la identidad no depende de www ni de la barra final', () {
      expect(
        ContentIdentity.id(
          'https://www.leercapitulo.co/manga/mzstjz4n73/sakamoto-days/',
        ),
        ContentIdentity.id(
          'https://leercapitulo.co/manga/mzstjz4n73/sakamoto-days',
        ),
      );
    });

    test('Mangas MAL encuentra la obra por título exacto', () async {
      const entry = MalManga(
        id: 1,
        title: 'SAKAMOTO DAYS',
        alternativeTitles: ['Dandadan'],
        chaptersRead: 0,
        totalChapters: 0,
        status: 'reading',
        publishingStatus: '',
      );
      final matcher = MalSourceMatcher();
      final leer = await matcher.findInSource(entry, 'leercapitulo');
      expect(leer.error, isNull);
      expect(leer.items.single.url, contains('/manga/mzstjz4n73/'));
      expect(leer.items.single.sourceId, 'leercapitulo');

      const other = MalManga(
        id: 2,
        title: 'one piece',
        chaptersRead: 0,
        totalChapters: 0,
        status: 'reading',
        publishingStatus: '',
      );
      final oni = await matcher.findInSource(other, 'mangaoni');
      expect(oni.error, isNull);
      expect(oni.items.single.url, 'https://manga-oni.com/manga/one-piece/');
      expect(oni.items.single.sourceId, 'mangaoni');
    });
  });
}
