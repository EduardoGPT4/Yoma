import 'content_identity.dart';
import 'favorite_entry.dart';
import 'manga.dart';
import 'reading_progress.dart';

enum LibraryView { all, downloaded, favorites, reading }

extension LibraryViewLabel on LibraryView {
  String get label => switch (this) {
    LibraryView.all => 'Todos',
    LibraryView.downloaded => 'Descargados',
    LibraryView.favorites => 'Favoritos',
    LibraryView.reading => 'Leyendo',
  };
}

/// Joins only stable references; equal titles from different sources stay separate.
class LibraryEntry {
  final String key, title;
  final String? cover;
  final Manga? local;
  final FavoriteEntry? favorite;
  final ReadingProgress? progress;
  final Set<String> favoriteKeys;
  const LibraryEntry({
    required this.key,
    required this.title,
    this.cover,
    this.local,
    this.favorite,
    this.progress,
    this.favoriteKeys = const {},
  });

  Set<String> get references => {
    key,
    ?local?.path,
    ?local?.sourceUrl,
    ?favorite?.key,
    ...favoriteKeys,
    ?progress?.mangaPath,
  };

  bool get downloaded =>
      local?.chapters.any((c) => c.complete && c.pageCount > 0) == true;
  bool matches(LibraryView view, {String? readingStatus}) => switch (view) {
    LibraryView.all => true,
    LibraryView.downloaded => downloaded,
    LibraryView.favorites => favorite != null,
    LibraryView.reading =>
      readingStatus == 'reading' || (readingStatus == null && progress != null),
  };

  static List<LibraryEntry> combine({
    required Iterable<Manga> local,
    required Iterable<FavoriteEntry> favorites,
    required Iterable<ReadingProgress> progress,
    Map<String, String> sourceLinks = const {},
  }) {
    final locals = <String, Manga>{};
    final aliases = <String, String>{};
    for (final manga in local) {
      final key = ContentIdentity.canonical(
        manga.sourceUrl ?? sourceLinks[manga.path] ?? manga.path,
      );
      locals.putIfAbsent(key, () => manga);
      aliases[ContentIdentity.canonical(manga.path)] = key;
    }
    String keyFor(String ref) {
      final key = ContentIdentity.canonical(ref);
      return aliases[key] ?? key;
    }

    final saved = <String, FavoriteEntry>{};
    final savedKeys = <String, Set<String>>{};
    for (final f in favorites) {
      saved[keyFor(f.key)] = f;
      savedKeys.putIfAbsent(keyFor(f.key), () => <String>{}).add(f.key);
    }
    final recent = <String, ReadingProgress>{};
    for (final p in progress) {
      final key = keyFor(p.mangaPath);
      if ((recent[key]?.updatedAt ?? -1) < p.updatedAt) recent[key] = p;
    }
    final keys = {...locals.keys, ...saved.keys, ...recent.keys};
    final entries = <LibraryEntry>[];
    for (final key in keys) {
      if (key.isEmpty) continue;
      final m = locals[key], f = saved[key], p = recent[key];
      // Missing local folders remain in History, not as unusable library cards.
      if (m == null && !ContentIdentity.isRemote(key)) continue;
      entries.add(
        LibraryEntry(
          key: key,
          title: m?.title ?? f?.title ?? p!.mangaTitle,
          cover: m?.coverPath ?? f?.coverPath ?? p?.coverPath,
          local: m,
          favorite: f,
          favoriteKeys: savedKeys[key] ?? const {},
          progress: p,
        ),
      );
    }
    entries.sort(
      (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
    );
    return entries;
  }
}
