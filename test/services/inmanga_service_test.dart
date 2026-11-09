import 'package:flutter_test/flutter_test.dart';
import 'package:yomashi/services/inmanga_service.dart';

void main() {
  const id = 'dfc7ecb5-e9b3-4aa5-a61b-a498993cd935';

  test('detail cover ignores the broken og:image thumbnail', () {
    final cover = InMangaService.selectCoverUrl(
      id,
      candidates: <String?>[
        'https://cdn1.intomanga.com/i/m/$id/t/o/$id.jpg',
        'https://assets.intomanga.com/thumbnails/manga/One-Piece/$id',
      ],
    );
    expect(cover, 'https://cdn1.intomanga.com/i/m/$id/t/o/$id.jpg');
  });

  test('falls back to the CDN thumbnail when only og:image is present', () {
    expect(
      InMangaService.selectCoverUrl(
        id,
        candidates: <String?>[
          'https://assets.intomanga.com/thumbnails/manga/One-Piece/$id',
          '../content/img/loading-gear.gif',
          'https://assets.intomanga.com/Content/img/OnMangaLogo.png',
        ],
      ),
      InMangaService.thumbnailUrl(id),
    );
  });

  test('resolves the relative detail cover', () {
    expect(
      InMangaService.selectCoverUrl(
        id,
        candidates: <String?>['/cover/manga/One-Piece/$id'],
      ),
      'https://inmanga.com/cover/manga/One-Piece/$id',
    );
  });
}
