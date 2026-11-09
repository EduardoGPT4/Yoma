import '../data/library_store.dart';
import '../models/content_identity.dart';

class BookmarkService {
  static String key(String manga, String chapter, int page) =>
      ContentIdentity.id('$manga|$chapter|$page');
  static Future<List<Map<String, dynamic>>> list(String manga) async =>
      (await (await LibraryStore.ensureInitialized()).readRecords('bookmarks'))
          .where(
            (e) =>
                ContentIdentity.canonical(e['manga'] as String) ==
                ContentIdentity.canonical(manga),
          )
          .toList()
        ..sort(
          (a, b) => (b['updatedAt'] as int).compareTo(a['updatedAt'] as int),
        );
  static Future<bool> toggle({
    required String manga,
    required String title,
    required String chapter,
    required String chapterTitle,
    required int page,
  }) async {
    final store = await LibraryStore.ensureInitialized();
    final id = key(manga, chapter, page);
    return store.transaction(() async {
      if (await store.getRecord('bookmarks', id) != null) {
        await store.deleteRecord('bookmarks', id);
        return false;
      }
      await store.putRecord('bookmarks', id, {
        'id': id,
        'manga': manga,
        'title': title,
        'chapter': chapter,
        'chapterTitle': chapterTitle,
        'page': page,
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
      });
      return true;
    });
  }
}
