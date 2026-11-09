import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yomashi/services/hitomi_service.dart';

void main() {
  final enabled = Platform.environment['HITOMI_LIVE'] == '1';

  test(
    'el catálogo real de Hitomi responde y sirve una página',
    () async {
      HitomiService.resetForTest();
      HitomiService.useLanguage('spanish');
      final page = await HitomiService.fetchCatalogPage(
        page: 1,
        postsPerPage: 8,
      );
      expect(page.items, isNotEmpty);
      for (final item in page.items) {
        expect(item.url, startsWith('https://hitomi.la/galleries/'));
        expect(item.coverUrl, contains('gold-usergeneratedcontent.net'));
        for (final genre in item.genres) {
          final name = genre.replaceFirst(RegExp(r'^[♀♂]\s*'), '');
          expect(HitomiService.tagIsBlocked(name), isFalse);
        }
      }
      final detail = await HitomiService.fetchMangaDetail(page.items.first.url);
      expect(detail.chapters, hasLength(1));
      expect(detail.chapters.single.pageCount, greaterThan(0));
      final pages = await HitomiService.fetchChapterPages(detail.url);
      expect(pages, isNotEmpty);
      final client = HttpClient();
      try {
        final request = await client.getUrl(Uri.parse(pages.first));
        HitomiService.imageHeaders.forEach(request.headers.set);
        request.headers.set(HttpHeaders.rangeHeader, 'bytes=0-31');
        final response = await request.close();
        expect(response.statusCode, isIn(<int>[200, 206]));
        final bytes = await response.fold<List<int>>(<int>[], (buffer, chunk) {
          buffer.addAll(chunk);
          return buffer;
        });
        expect(bytes, isNotEmpty);
        expect(bytes.first, isNot(0x3c));
      } finally {
        client.close(force: true);
      }
    },
    skip: enabled ? false : 'Define HITOMI_LIVE=1 para consultar hitomi.la',
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
