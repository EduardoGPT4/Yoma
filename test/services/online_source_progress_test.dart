import 'package:flutter_test/flutter_test.dart';
import 'package:yomashi/services/online_catalog_service.dart';

void main() {
  group('OnlineCatalogService.sourceIdForRef', () {
    test('detects each of the four sources', () {
      expect(
        OnlineCatalogService.sourceIdForRef(
          'https://zonatmo.to/manga/shingeki-no-kyojin',
        ),
        'zonatmo_to',
      );
      expect(
        OnlineCatalogService.sourceIdForRef(
          'https://cdn.zonatmo.to/manga/jit/01.webp',
        ),
        'zonatmo_to',
      );
      expect(
        OnlineCatalogService.sourceIdForRef(
          'https://zonatmo.org/library/manga/9521/dandadan',
        ),
        'lectortmo',
      );
      expect(
        OnlineCatalogService.sourceIdForRef(
          'https://zonatmo.org/view_uploads/1033357',
        ),
        'lectortmo',
      );
      expect(
        OnlineCatalogService.sourceIdForRef(
          'https://www.manhwaweb.com/manhwa/soldadoesqueleto_1728569647299',
        ),
        'manhwaweb',
      );
      expect(
        OnlineCatalogService.sourceIdForRef(
          'https://mangadex.org/title/abc-123',
        ),
        'mangadex',
      );
      expect(
        OnlineCatalogService.sourceIdForRef(
          'https://inmanga.com/ver/manga/one-piece/aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee',
        ),
        'inmanga',
      );
    });

    test('does not leak one source into another', () {
      expect(
        OnlineCatalogService.belongsToSource(
          'https://zonatmo.to/manga/shingeki-no-kyojin',
          'lectortmo',
        ),
        isFalse,
      );
      expect(
        OnlineCatalogService.belongsToSource(
          'https://zonatmo.to/manga/shingeki-no-kyojin',
          'zonatmo_to',
        ),
        isTrue,
      );
      expect(
        OnlineCatalogService.belongsToSource(
          'https://www.manhwaweb.com/leer/foo_1234567890-1',
          'lectortmo',
        ),
        isFalse,
      );
      expect(
        OnlineCatalogService.belongsToSource(
          'https://zonatmo.org/library/manga/1/dandadan',
          'tmo',
        ),
        isTrue,
      );
    });

    test('searchable sources include every catalog', () {
      expect(
        OnlineCatalogService.searchableSourceIds,
        containsAll(<String>[
          'lectortmo',
          'zonatmo_to',
          'mangadex',
          'inmanga',
          'manhwaweb',
        ]),
      );
    });
  });
}
