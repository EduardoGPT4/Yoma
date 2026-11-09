import 'chapter.dart';
import 'manga.dart';
import 'content_identity.dart';

class OnlineMangaSummary {
  final String title;

  /// Título de la fuente antes de limpiar metadatos para la presentación.
  final String? originalTitle;
  final String url;
  final String? coverUrl;
  final String? description;
  final int? chapterCount;
  final List<String> genres;
  final String? type;
  final String? status;

  /// Fuente del resultado (`lectortmo`, `mangadex`, `inmanga`, `manhwaweb`).
  final String? sourceId;

  const OnlineMangaSummary({
    required this.title,
    required this.url,
    this.originalTitle,
    this.coverUrl,
    this.description,
    this.chapterCount,
    this.genres = const <String>[],
    this.type,
    this.status,
    this.sourceId,
  });

  Map<String, dynamic> toMap() => {
    'title': title,
    'originalTitle': originalTitle,
    'url': url,
    'coverUrl': coverUrl,
    'description': description,
    'chapterCount': chapterCount,
    'genres': genres,
    'type': type,
    'status': status,
    'sourceId': sourceId,
  };
  factory OnlineMangaSummary.fromMap(Map<String, dynamic> map) =>
      OnlineMangaSummary(
        title: map['title'] as String? ?? 'Manga',
        originalTitle: map['originalTitle'] as String?,
        url: map['url'] as String? ?? '',
        coverUrl: map['coverUrl'] as String?,
        description: map['description'] as String?,
        chapterCount: map['chapterCount'] as int?,
        genres: (map['genres'] as List?)?.cast<String>() ?? [],
        type: map['type'] as String?,
        status: map['status'] as String?,
        sourceId: map['sourceId'] as String?,
      );

  OnlineMangaSummary copyWith({String? sourceId}) {
    return OnlineMangaSummary(
      title: title,
      originalTitle: originalTitle,
      url: url,
      coverUrl: coverUrl,
      description: description,
      chapterCount: chapterCount,
      genres: genres,
      type: type,
      status: status,
      sourceId: sourceId ?? this.sourceId,
    );
  }
}

class OnlineMangaDetail {
  final bool hasMoreChapters;
  final int nextChapterCursor;
  final String title;
  final String url;
  final String? coverUrl;
  final String? description;
  final List<String> altTitles;
  final List<String> genres;
  final String? type;
  final String? status;
  final String? author;
  final String? year;
  final List<Chapter> chapters;

  const OnlineMangaDetail({
    this.hasMoreChapters = false,
    this.nextChapterCursor = 0,
    required this.title,
    required this.url,
    required this.chapters,
    this.coverUrl,
    this.description,
    this.altTitles = const <String>[],
    this.genres = const <String>[],
    this.type,
    this.status,
    this.author,
    this.year,
  });

  String get id => ContentIdentity.id(url);

  Map<String, dynamic> toMap() {
    return {
      'hasMoreChapters': hasMoreChapters,
      'nextChapterCursor': nextChapterCursor,
      'title': title,
      'url': url,
      'coverUrl': coverUrl,
      'description': description,
      'altTitles': altTitles,
      'genres': genres,
      'type': type,
      'status': status,
      'author': author,
      'year': year,
      'chapters': chapters.map((chapter) => chapter.toMap()).toList(),
    };
  }

  factory OnlineMangaDetail.fromMap(Map<String, dynamic> map) {
    final chapterItems = (map['chapters'] as List<dynamic>?) ?? <dynamic>[];
    return OnlineMangaDetail(
      hasMoreChapters: map['hasMoreChapters'] as bool? ?? false,
      nextChapterCursor: map['nextChapterCursor'] as int? ?? 0,
      title: map['title'] as String? ?? '',
      url: map['url'] as String? ?? '',
      coverUrl: map['coverUrl'] as String?,
      description: map['description'] as String?,
      altTitles:
          (map['altTitles'] as List<dynamic>?)?.cast<String>() ?? <String>[],
      genres: (map['genres'] as List<dynamic>?)?.cast<String>() ?? <String>[],
      type: map['type'] as String?,
      status: map['status'] as String?,
      author: map['author'] as String?,
      year: map['year'] as String?,
      chapters: chapterItems
          .whereType<Map>()
          .map((entry) => Chapter.fromMap(Map<String, dynamic>.from(entry)))
          .toList(),
    );
  }

  Manga toOfflineManga() {
    return Manga(
      title: title,
      sourceUrl: url,
      hasMoreChapters: hasMoreChapters,
      nextChapterCursor: nextChapterCursor,
      path: url,
      coverPath: coverUrl,
      chapters: chapters,
    );
  }
}
