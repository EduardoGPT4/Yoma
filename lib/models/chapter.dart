class Chapter {
  final String? number;
  final String? volume;
  final String? language;
  final String? sourceUrl;
  final bool complete;
  final String title;
  final String path;
  final List<String> pages;
  final int pageCount;
  final String? coverPath;

  const Chapter({
    this.number,
    this.volume,
    this.language,
    this.sourceUrl,
    this.complete = true,
    required this.title,
    required this.path,
    this.pages = const <String>[],
    int? pageCount,
    this.coverPath,
  }) : pageCount = pageCount ?? pages.length;

  bool get hasLoadedPages => pages.isNotEmpty;

  Map<String, dynamic> toMap() {
    return {
      'number': number,
      'volume': volume,
      'language': language,
      'sourceUrl': sourceUrl,
      'complete': complete,
      'title': title,
      'path': path,
      'pages': pages,
      'pageCount': pageCount,
      'coverPath': coverPath,
    };
  }

  factory Chapter.fromMap(Map<String, dynamic> map) {
    final pages =
        (map['pages'] as List<dynamic>?)?.cast<String>() ?? <String>[];
    return Chapter(
      number: map['number'] as String?,
      volume: map['volume'] as String?,
      language: map['language'] as String?,
      sourceUrl: map['sourceUrl'] as String?,
      complete: map['complete'] as bool? ?? true,
      title: map['title'] as String? ?? '',
      path: map['path'] as String? ?? '',
      pages: pages,
      pageCount: map['pageCount'] as int? ?? pages.length,
      coverPath: map['coverPath'] as String?,
    );
  }
}
