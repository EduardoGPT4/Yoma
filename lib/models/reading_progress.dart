class ReadingProgress {
  final String mangaPath;
  final String mangaTitle;
  final String? coverPath;
  final String chapterPath;
  final String chapterTitle;
  final int pageIndex;
  final int updatedAt;

  /// Fuente online (`mangadex`, `inmanga`, `lectortmo`, `manhwaweb`). Null = local.
  final String? sourceId;

  const ReadingProgress({
    required this.mangaPath,
    required this.mangaTitle,
    this.coverPath,
    required this.chapterPath,
    required this.chapterTitle,
    required this.pageIndex,
    required this.updatedAt,
    this.sourceId,
  });

  DateTime get updatedAtDate => DateTime.fromMillisecondsSinceEpoch(updatedAt);

  Map<String, dynamic> toMap() {
    return {
      'mangaPath': mangaPath,
      'mangaTitle': mangaTitle,
      'coverPath': coverPath,
      'chapterPath': chapterPath,
      'chapterTitle': chapterTitle,
      'pageIndex': pageIndex,
      'updatedAt': updatedAt,
      'sourceId': sourceId,
    };
  }

  factory ReadingProgress.fromMap(Map<String, dynamic> map) {
    final storedSource = map['sourceId'] as String?;
    return ReadingProgress(
      mangaPath: map['mangaPath'] as String? ?? '',
      mangaTitle: map['mangaTitle'] as String? ?? '',
      coverPath: map['coverPath'] as String?,
      chapterPath: map['chapterPath'] as String? ?? '',
      chapterTitle: map['chapterTitle'] as String? ?? '',
      pageIndex: map['pageIndex'] as int? ?? 0,
      updatedAt: map['updatedAt'] as int? ?? 0,
      sourceId: (storedSource == null || storedSource.isEmpty)
          ? null
          : storedSource,
    );
  }
}
