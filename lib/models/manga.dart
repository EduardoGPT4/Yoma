import 'chapter.dart';

class Manga {
  final bool hasMoreChapters;
  final int nextChapterCursor;
  final String? sourceUrl;
  final String title;
  final String path;
  final String? _coverPath;
  final List<Chapter> chapters;

  const Manga({
    this.hasMoreChapters = false,
    this.nextChapterCursor = 0,
    this.sourceUrl,
    required this.title,
    required this.path,
    String? coverPath,
    required this.chapters,
  }) : _coverPath = coverPath;

  Chapter? get firstChapter => chapters.isNotEmpty ? chapters.first : null;

  int get chapterCount => chapters.length;

  int get pageCount =>
      chapters.fold<int>(0, (total, chapter) => total + chapter.pageCount);

  String? get coverPath {
    if (_coverPath != null && _coverPath.isNotEmpty) {
      return _coverPath;
    }
    if (chapters.isEmpty) {
      return null;
    }
    for (final chapter in chapters) {
      if (chapter.coverPath != null && chapter.coverPath!.isNotEmpty) {
        return chapter.coverPath;
      }
      if (chapter.pages.isNotEmpty) {
        return chapter.pages.first;
      }
    }
    return null;
  }

  Map<String, dynamic> toMap() {
    return {
      'sourceUrl': sourceUrl,
      'hasMoreChapters': hasMoreChapters,
      'nextChapterCursor': nextChapterCursor,
      'title': title,
      'path': path,
      'coverPath': _coverPath,
      'chapters': chapters.map((chapter) => chapter.toMap()).toList(),
    };
  }

  factory Manga.fromMap(Map<String, dynamic> map) {
    final chapters =
        (map['chapters'] as List<dynamic>?)
            ?.whereType<Map>()
            .map((chapter) => Chapter.fromMap(chapter.cast<String, dynamic>()))
            .toList() ??
        <Chapter>[];

    return Manga(
      sourceUrl: map['sourceUrl'] as String?,
      hasMoreChapters: map['hasMoreChapters'] as bool? ?? false,
      nextChapterCursor: map['nextChapterCursor'] as int? ?? 0,
      title: map['title'] as String? ?? '',
      path: map['path'] as String? ?? '',
      coverPath: map['coverPath'] as String?,
      chapters: chapters,
    );
  }
}
