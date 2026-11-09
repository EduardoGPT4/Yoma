import '../models/chapter.dart';
import '../models/online_manga.dart';
import 'online_catalog_service.dart';

class AlternativeChapter {
  final OnlineMangaDetail manga;
  final int index;
  final String sourceId;
  const AlternativeChapter(this.manga, this.index, this.sourceId);
  Chapter get chapter => manga.chapters[index];
}

class AlternativeChapterService {
  static String normalized(String value) =>
      value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9áéíóúñ]'), '');
  static String? number(Chapter chapter) {
    final raw =
        chapter.number ??
        RegExp(
          r'(?:cap[íi]tulo|chapter|cap\.)\s*(\d+(?:\.\d+)?)',
          caseSensitive: false,
        ).firstMatch(chapter.title)?.group(1) ??
        (RegExp(r'^\d+(?:\.\d+)?$').hasMatch(chapter.title.trim())
            ? chapter.title.trim()
            : null);
    return raw == null ? null : double.tryParse(raw)?.toString();
  }

  static bool sameChapter(Chapter wanted, Chapter candidate) {
    final n = number(wanted), other = number(candidate);
    if (wanted.language != null &&
        candidate.language != null &&
        wanted.language != candidate.language) {
      return false;
    }
    if (wanted.volume != null &&
        candidate.volume != null &&
        wanted.volume != candidate.volume) {
      return false;
    }
    return n != null
        ? n == other
        : normalized(wanted.title) == normalized(candidate.title);
  }

  static Future<List<AlternativeChapter>> find(
    String title,
    String origin,
    Chapter wanted,
  ) async {
    final results = await OnlineCatalogService.searchAll(
      title,
      postsPerPage: 8,
    );
    final found = <AlternativeChapter>[];
    final current = OnlineCatalogService.sourceIdForRef(origin);
    for (final source in results.where((s) => s.sourceId != current)) {
      final candidates = source.items
          .where((m) => normalized(m.title) == normalized(title))
          .take(2);
      for (final item in candidates) {
        try {
          var detail = await OnlineCatalogService.fetchMangaDetail(
            item.url,
            sourceId: source.sourceId,
          );
          while (true) {
            for (var i = 0; i < detail.chapters.length; i++) {
              if (sameChapter(wanted, detail.chapters[i])) {
                found.add(AlternativeChapter(detail, i, source.sourceId));
                break;
              }
            }
            if (found.any((e) => e.manga.url == detail.url) ||
                !detail.hasMoreChapters) {
              break;
            }
            detail = await OnlineCatalogService.loadMoreChapters(detail);
          }
        } catch (_) {
          /* Otras fuentes aún pueden ofrecer una alternativa. */
        }
      }
    }
    return found;
  }
}
