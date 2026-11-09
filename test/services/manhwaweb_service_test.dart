import 'package:flutter_test/flutter_test.dart';
import 'package:yomashi/services/manhwaweb_service.dart';

void main() {
  group('ManhwaWebService slugs', () {
    test('extracts series slug from site URL', () {
      expect(
        ManhwaWebService.extractSeriesSlug(
          'https://www.manhwaweb.com/manhwa/soldadoesqueleto_1728569647299',
        ),
        'soldadoesqueleto_1728569647299',
      );
      expect(
        ManhwaWebService.extractSeriesSlug(
          '/manga/guia-de-supervivencia-del-extra-de-la-academia_1711593434710',
        ),
        'guia-de-supervivencia-del-extra-de-la-academia_1711593434710',
      );
    });

    test('extracts series slug from chapter URL', () {
      expect(
        ManhwaWebService.extractSeriesSlug(
          'https://www.manhwaweb.com/leer/soldadoesqueleto_1728569647299-384_01',
        ),
        'soldadoesqueleto_1728569647299',
      );
    });

    test('extracts chapter slug', () {
      expect(
        ManhwaWebService.extractChapterSlug(
          'https://manhwaweb.com/leer/soldadoesqueleto_1728569647299-384_01',
        ),
        'soldadoesqueleto_1728569647299-384_01',
      );
    });

    test('keeps full slug with trailing hyphen before timestamp', () {
      const slug = 'shingeki-no-kyojin-_1739724799664';
      expect(
        ManhwaWebService.extractSeriesSlug(
          'https://www.manhwaweb.com/manhwa/$slug',
        ),
        slug,
      );
      expect(
        ManhwaWebService.extractSeriesSlug(
          'https://www.manhwaweb.com/leer/$slug-139.5_01',
        ),
        slug,
      );
      expect(
        ManhwaWebService.extractChapterSlug(
          'https://www.manhwaweb.com/leer/$slug-139.5_01',
        ),
        '$slug-139.5_01',
      );
    });

    test('accepts short public ids and long titles', () {
      const slug = 'tensei-colosseum-saijaku-skill-de-saikyou-4185442';
      expect(
        ManhwaWebService.extractSeriesSlug(
          'https://www.manhwaweb.com/manhwa/$slug',
        ),
        slug,
      );
      expect(ManhwaWebService.extractSeriesSlug('manhwaweb:$slug'), slug);

      final longName = List.filled(240, 'a').join();
      final longSlug = '$longName-4185442';
      expect(
        ManhwaWebService.extractSeriesSlug(
          'https://www.manhwaweb.com/manhwa/$longSlug',
        ),
        longSlug,
      );
      expect(longSlug.length > slug.length, isTrue);
    });

    test('keeps suffix after the timestamp', () {
      const slug = 'Where_Is_My_Little_Stick_1679784882871-uncensored';
      expect(
        ManhwaWebService.extractSeriesSlug(
          'https://www.manhwaweb.com/manhwa/$slug',
        ),
        slug,
      );
      expect(
        ManhwaWebService.extractSeriesSlug(
          'https://www.manhwaweb.com/leer/$slug-1_01',
        ),
        slug,
      );
      expect(
        ManhwaWebService.extractChapterSlug(
          'https://www.manhwaweb.com/leer/$slug-1_01',
        ),
        '$slug-1_01',
      );
    });

    test('extracts series from short chapter urls', () {
      const series = 'tensei-colosseum-saijaku-skill-de-saikyou-4185442';
      const chapter = '$series-1_01';
      expect(
        ManhwaWebService.extractSeriesSlug(
          'https://www.manhwaweb.com/leer/$chapter',
        ),
        series,
      );
      expect(
        ManhwaWebService.extractChapterSlug(
          'https://manhwaweb.com/leer/$chapter',
        ),
        chapter,
      );
      final parsed = ManhwaWebService.parseChapterRef(
        'https://www.manhwaweb.com/leer/$chapter',
      );
      expect(parsed, isNotNull);
      expect(parsed!.series, series);
      expect(parsed.chapter, '1');
      expect(parsed.ver, '01');

      expect(
        ManhwaWebService.extractSeriesSlug(
          'https://www.manhwaweb.com/manhwa/blue_lock-702790353434',
        ),
        'blue_lock-702790353434',
      );
    });

    test('does not treat other catalogs as manhwaweb series', () {
      expect(
        ManhwaWebService.extractSeriesSlug(
          'https://zonatmo.org/library/manga/12/dandadan',
        ),
        isNull,
      );
      expect(
        ManhwaWebService.extractSeriesSlug(
          'https://zonatmo.to/manga/tensei-colosseum-saijaku-skill-de-saikyou-4185442',
        ),
        isNull,
      );
    });

    test('keeps full slug with double hyphen', () {
      const slug = 'shingeki-no-kyojin-chibi--koma_1743878973064';
      expect(
        ManhwaWebService.extractSeriesSlug(
          'https://www.manhwaweb.com/manhwa/$slug',
        ),
        slug,
      );
      expect(slug.contains('koma_'), isTrue);
      expect(
        ManhwaWebService.extractSeriesSlug(
          'https://www.manhwaweb.com/manhwa/$slug',
        ),
        isNot('koma_1743878973064'),
      );
    });

    test('parses chapter refs for CDN fallback', () {
      final parsed = ManhwaWebService.parseChapterRef(
        'https://www.manhwaweb.com/leer/sangeki_1775179216725-18_01',
      );
      expect(parsed, isNotNull);
      expect(parsed!.series, 'sangeki_1775179216725');
      expect(parsed.chapter, '18');
      expect(parsed.ver, '01');
      expect(
        ManhwaWebService.cdnPageCandidates(
          'https://imagizer.imageshack.com/img922/1200/V8CJut.jpg',
          referer: 'https://www.manhwaweb.com/leer/sangeki_1775179216725-18_01',
          pageIndex: 0,
        ),
        contains(
          'https://img2mw.xyz/manhwas/sangeki_1775179216725/chapter_18/ver_01/001.webp',
        ),
      );
    });

    test('flags ImageShack as fragile host', () {
      expect(
        ManhwaWebService.isFragileImageHost(
          'https://imagizer.imageshack.com/img922/1200/V8CJut.jpg',
        ),
        isTrue,
      );
      expect(
        ManhwaWebService.isFragileImageHost(
          'https://imaginer.imageshack.com/img922/1200/V8CJut.jpg',
        ),
        isTrue,
      );
      expect(
        ManhwaWebService.isFragileImageHost(
          'https://img2mw.xyz/manhwas/foo/chapter_1/ver_01/001.webp',
        ),
        isFalse,
      );
    });

    test('detects manhwaweb refs and hotlink hosts', () {
      expect(
        ManhwaWebService.isManhwaWebRef('https://www.manhwaweb.com/manhwa/x'),
        isTrue,
      );
      expect(
        ManhwaWebService.isManhwaWebRef('https://zonatmo.to/library'),
        isFalse,
      );
      expect(
        ManhwaWebService.needsHotlinkHeaders(
          'https://img2mw.xyz/manhwas/foo/cover.webp',
        ),
        isTrue,
      );
    });
  });
}
