import '../models/manga.dart';
import '../models/manga_list_filters.dart';
import '../models/reading_progress.dart';
import '../models/reading_status_filter.dart';
import '../models/online_manga.dart';
import '../providers/categories_provider.dart';
import '../providers/chapter_read_provider.dart';
import '../providers/favorites_provider.dart';

class MangaFilterUtils {
  static String normalizedStatus(String? value) {
    final text = (value ?? '').toLowerCase();
    if ([
      'ongoing',
      'publicándose',
      'publicandose',
      'en emisión',
      'en emision',
      'en curso',
    ].contains(text)) {
      return 'ongoing';
    }
    if ([
      'completed',
      'finalizado',
      'finalizada',
      'terminado',
      'finished',
    ].contains(text)) {
      return 'completed';
    }
    return text;
  }

  static List<Manga> filterOfflineMangas({
    required List<Manga> mangas,
    required MangaListFilters filters,
    required FavoritesProvider favorites,
    required CategoriesProvider categories,
    required Map<String, ReadingProgress> progressMap,
    ChapterReadProvider? chapterRead,
  }) {
    var result = List<Manga>.from(mangas);

    if (filters.favoritesOnly) {
      result = result
          .where((manga) => favorites.isFavorite(manga.path))
          .toList();
    }

    if (filters.categoryId != null) {
      final category = categories.categoryById(filters.categoryId);
      if (category != null) {
        final keys = category.mangaKeys.toSet();
        result = result.where((manga) => keys.contains(manga.path)).toList();
      }
    }

    if (filters.inProgressOnly) {
      result = result
          .where((manga) => progressMap.containsKey(manga.path))
          .toList();
    }

    switch (filters.readingStatus) {
      case ReadingStatusFilter.all:
        break;
      case ReadingStatusFilter.inProgress:
        result = result.where((manga) {
          final progress = progressMap[manga.path];
          if (progress == null) {
            return false;
          }
          if (chapterRead == null || manga.chapters.isEmpty) {
            return true;
          }
          final readCount = chapterRead.readCountForManga(
            manga.chapters.map((c) => c.path),
          );
          return readCount < manga.chapters.length;
        }).toList();
      case ReadingStatusFilter.notStarted:
        result = result
            .where((manga) => !progressMap.containsKey(manga.path))
            .toList();
      case ReadingStatusFilter.completed:
        result = result.where((manga) {
          if (manga.chapters.isEmpty) {
            return false;
          }
          if (chapterRead == null) {
            return progressMap.containsKey(manga.path);
          }
          final readCount = chapterRead.readCountForManga(
            manga.chapters.map((c) => c.path),
          );
          return readCount >= manga.chapters.length;
        }).toList();
    }

    switch (filters.sort) {
      case MangaSortOption.catalog:
        // Conservar el orden de la biblioteca (ya natural-sorted al escanear).
        break;
      case MangaSortOption.titleAsc:
        result.sort(
          (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
        );
      case MangaSortOption.titleDesc:
        result.sort(
          (a, b) => b.title.toLowerCase().compareTo(a.title.toLowerCase()),
        );
      case MangaSortOption.chaptersDesc:
        result.sort((a, b) => b.chapterCount.compareTo(a.chapterCount));
      case MangaSortOption.recentProgress:
        result.sort((a, b) {
          final aTime = progressMap[a.path]?.updatedAt ?? 0;
          final bTime = progressMap[b.path]?.updatedAt ?? 0;
          return bTime.compareTo(aTime);
        });
    }

    return result;
  }

  /// Búsqueda offline ampliada: título, path y nombre de carpeta.
  static List<Manga> searchOffline(List<Manga> mangas, String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) {
      return mangas;
    }
    final tokens = q.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
    return mangas.where((manga) {
      final haystack = [
        manga.title,
        manga.path,
        ...manga.chapters.map((c) => c.title),
      ].join(' ').toLowerCase();
      return tokens.every(haystack.contains);
    }).toList();
  }

  static List<OnlineMangaSummary> filterOnlineMangas({
    required List<OnlineMangaSummary> items,
    required MangaListFilters filters,
    required FavoritesProvider favorites,
  }) {
    var result = List<OnlineMangaSummary>.from(items);

    if (filters.favoritesOnly) {
      result = result.where((item) => favorites.isFavorite(item.url)).toList();
    }

    if (filters.status != null && filters.status!.isNotEmpty) {
      final status = normalizedStatus(filters.status);
      result = result
          .where((item) => normalizedStatus(item.status) == status)
          .toList();
    }

    if (filters.type != null && filters.type!.isNotEmpty) {
      final type = filters.type!.toLowerCase();
      result = result
          .where((item) => (item.type ?? '').toLowerCase() == type)
          .toList();
    }

    switch (filters.sort) {
      case MangaSortOption.catalog:
        // NO reordenar: el scroll infinito appendea páginas 1→2→3 abajo.
        break;
      case MangaSortOption.titleAsc:
        result.sort(
          (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
        );
      case MangaSortOption.titleDesc:
        result.sort(
          (a, b) => b.title.toLowerCase().compareTo(a.title.toLowerCase()),
        );
      case MangaSortOption.chaptersDesc:
        result.sort((a, b) {
          final aCount = a.chapterCount ?? 0;
          final bCount = b.chapterCount ?? 0;
          return bCount.compareTo(aCount);
        });
      case MangaSortOption.recentProgress:
        // En online el catálogo ya viene por “latest”; no reordenar.
        break;
    }

    return result;
  }
}
