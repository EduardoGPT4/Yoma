class ReadingStats {
  final int mangaOpens;
  final int chaptersOpened;
  final int pagesRead;
  final List<String> openedMangaPaths;

  const ReadingStats({
    this.mangaOpens = 0,
    this.chaptersOpened = 0,
    this.pagesRead = 0,
    this.openedMangaPaths = const <String>[],
  });

  int get uniqueMangasOpened => openedMangaPaths.length;

  ReadingStats recordMangaOpen(String mangaPath) {
    final paths = List<String>.from(openedMangaPaths);
    if (!paths.contains(mangaPath)) {
      paths.add(mangaPath);
    }

    return ReadingStats(
      mangaOpens: mangaOpens + 1,
      chaptersOpened: chaptersOpened,
      pagesRead: pagesRead,
      openedMangaPaths: paths,
    );
  }

  ReadingStats recordChapterOpen() {
    return ReadingStats(
      mangaOpens: mangaOpens,
      chaptersOpened: chaptersOpened + 1,
      pagesRead: pagesRead,
      openedMangaPaths: openedMangaPaths,
    );
  }

  ReadingStats recordPageRead() {
    return ReadingStats(
      mangaOpens: mangaOpens,
      chaptersOpened: chaptersOpened,
      pagesRead: pagesRead + 1,
      openedMangaPaths: openedMangaPaths,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'mangaOpens': mangaOpens,
      'chaptersOpened': chaptersOpened,
      'pagesRead': pagesRead,
      'openedMangaPaths': openedMangaPaths,
    };
  }

  factory ReadingStats.fromMap(Map<String, dynamic> map) {
    return ReadingStats(
      mangaOpens: map['mangaOpens'] as int? ?? 0,
      chaptersOpened: map['chaptersOpened'] as int? ?? 0,
      pagesRead: map['pagesRead'] as int? ?? 0,
      openedMangaPaths:
          (map['openedMangaPaths'] as List<dynamic>?)?.cast<String>() ??
          <String>[],
    );
  }
}
