import 'package:flutter_test/flutter_test.dart';
import 'package:yomashi/services/tmo_service.dart';

void main() {
  group('TmoService refs', () {
    test('detects the current zonatmo.org URLs', () {
      expect(
        TmoService.isTmoRef('https://zonatmo.org/library/manga/9521/dandadan'),
        isTrue,
      );
      expect(
        TmoService.isTmoRef('https://zonatmo.org/view_uploads/1033357'),
        isTrue,
      );
      expect(
        TmoService.isTmoRef(
          'https://storage2.zonatmo.org/chapters/1033357/1.webp',
        ),
        isTrue,
      );
      expect(
        TmoService.isLibraryMangaUrl(
          'https://zonatmo.org/library/manhwa/178/jinx',
        ),
        isTrue,
      );
    });

    test('does not claim zonatmo.to, that is another source', () {
      expect(
        TmoService.isTmoRef('https://zonatmo.to/manga/shingeki-no-kyojin'),
        isFalse,
      );
      expect(
        TmoService.isTmoRef('https://cdn.zonatmo.to/manga/abc/01.jpg'),
        isFalse,
      );
    });

    test('does not claim other sources', () {
      expect(
        TmoService.isTmoRef('https://www.manhwaweb.com/manhwa/foo'),
        isFalse,
      );
      expect(TmoService.isTmoRef('https://mangadex.org/title/abc'), isFalse);
    });
  });

  group('TmoService URL helpers', () {
    test('does not rewrite zonatmo.to into zonatmo.org', () {
      expect(
        TmoService.rewriteLegacyUrl('https://zonatmo.to/manga/dandadan'),
        'https://zonatmo.to/manga/dandadan',
      );
      expect(
        TmoService.rewriteLegacyUrl('https://zonatmo.com/library/manga/1/x'),
        'https://zonatmo.org/library/manga/1/x',
      );
    });

    test('extracts view_uploads ids', () {
      expect(
        TmoService.extractViewUploadId(
          'https://zonatmo.org/view_uploads/1033357',
        ),
        '1033357',
      );
      expect(
        TmoService.extractViewUploadId('https://zonatmo.org/view_uploads/99'),
        '99',
      );
      expect(
        TmoService.extractViewUploadId(
          'https://zonatmo.org/library/manga/9521/dandadan',
        ),
        isNull,
      );
    });

    test('flags storage hosts for image headers', () {
      expect(
        TmoService.needsImageHeaders(
          'https://storage2.zonatmo.org/chapters/1/1.webp',
        ),
        isTrue,
      );
      expect(
        TmoService.needsImageHeaders('https://img2mw.xyz/foo.webp'),
        isFalse,
      );
    });
  });
}
