import 'reading_status_filter.dart';

enum MangaSortOption {
  /// Orden original del catálogo/lista (imprescindible para scroll infinito).
  catalog,
  titleAsc,
  titleDesc,
  chaptersDesc,
  recentProgress,
}

class MangaListFilters {
  final bool favoritesOnly;
  final String? categoryId;
  final String? status;
  final String? type;
  final bool inProgressOnly;
  final ReadingStatusFilter readingStatus;
  final MangaSortOption sort;

  /// En Hitomi, muestra bajo el buscador las etiquetas con más galerías.
  final bool showPopularTags;

  const MangaListFilters({
    this.favoritesOnly = false,
    this.categoryId,
    this.status,
    this.type,
    this.inProgressOnly = false,
    this.readingStatus = ReadingStatusFilter.all,
    this.sort = MangaSortOption.catalog,
    this.showPopularTags = false,
  });

  static const MangaListFilters empty = MangaListFilters();

  bool get hasActiveFilters {
    return favoritesOnly ||
        categoryId != null ||
        (status != null && status!.isNotEmpty) ||
        (type != null && type!.isNotEmpty) ||
        inProgressOnly ||
        readingStatus != ReadingStatusFilter.all ||
        sort != MangaSortOption.catalog ||
        showPopularTags;
  }

  MangaListFilters copyWith({
    bool? favoritesOnly,
    String? categoryId,
    bool clearCategoryId = false,
    String? status,
    bool clearStatus = false,
    String? type,
    bool clearType = false,
    bool? inProgressOnly,
    ReadingStatusFilter? readingStatus,
    MangaSortOption? sort,
    bool? showPopularTags,
  }) {
    return MangaListFilters(
      favoritesOnly: favoritesOnly ?? this.favoritesOnly,
      categoryId: clearCategoryId ? null : (categoryId ?? this.categoryId),
      status: clearStatus ? null : (status ?? this.status),
      type: clearType ? null : (type ?? this.type),
      inProgressOnly: inProgressOnly ?? this.inProgressOnly,
      readingStatus: readingStatus ?? this.readingStatus,
      sort: sort ?? this.sort,
      showPopularTags: showPopularTags ?? this.showPopularTags,
    );
  }
}
