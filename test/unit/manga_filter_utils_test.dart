import 'package:flutter_test/flutter_test.dart';
import 'package:yomashi/models/chapter.dart';
import 'package:yomashi/models/manga.dart';
import 'package:yomashi/utils/manga_filter_utils.dart';

void main() {
  test('searchOffline matches title tokens', () {
    final mangas = <Manga>[
      Manga(
        title: 'One Piece',
        path: '/lib/One Piece',
        chapters: <Chapter>[
          Chapter(
            title: 'Cap 1',
            path: '/lib/One Piece/1',
            pages: const <String>[],
          ),
        ],
      ),
      Manga(title: 'Naruto', path: '/lib/Naruto', chapters: const <Chapter>[]),
    ];

    final result = MangaFilterUtils.searchOffline(mangas, 'one piece');
    expect(result, hasLength(1));
    expect(result.first.title, 'One Piece');
  });

  test('searchOffline matches path fragments', () {
    final mangas = <Manga>[
      Manga(
        title: 'Desconocido',
        path: '/storage/Manga/Berserk',
        chapters: const <Chapter>[],
      ),
    ];
    final result = MangaFilterUtils.searchOffline(mangas, 'berserk');
    expect(result, hasLength(1));
  });
}
