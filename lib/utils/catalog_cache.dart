import '../data/library_store.dart';
import '../models/online_manga.dart';
import '../services/content_exclusions.dart';
import '../services/mangadex_service.dart';

class CatalogCache {
  static String _key(String? source, String section, String? languageKey) {
    final language =
        languageKey ??
        (source == 'mangadex'
            ? MangaDexService.preferredLanguages.join(',')
            : '');
    final exclusions = source == 'hitomi'
        ? ':exclusions=${ContentExclusions.cacheKey}'
        : '';
    return '${source ?? 'default'}:$language:$section$exclusions';
  }

  static Future<void> saveHome(
    List<OnlineMangaSummary> items, {
    String? sourceId,
    String? languageKey,
  }) => _save(_key(sourceId, 'home', languageKey), items);
  static Future<void> saveUpdated(
    List<OnlineMangaSummary> items, {
    String? sourceId,
    String? languageKey,
  }) => _save(_key(sourceId, 'feed', languageKey), items);
  static Future<List<OnlineMangaSummary>> loadHome({
    String? sourceId,
    String? languageKey,
  }) => _load(_key(sourceId, 'home', languageKey));
  static Future<List<OnlineMangaSummary>> loadUpdated({
    String? sourceId,
    String? languageKey,
  }) => _load(_key(sourceId, 'feed', languageKey));
  static Future<DateTime?> savedAt({
    String? sourceId,
    String? languageKey,
  }) async {
    final raw = await (await LibraryStore.ensureInitialized()).getRecord(
      'catalog',
      _key(sourceId, 'home', languageKey),
    );
    final time = raw is Map ? raw['savedAt'] : null;
    return time is int ? DateTime.fromMillisecondsSinceEpoch(time) : null;
  }

  static Future<bool> isFresh({String? sourceId, String? languageKey}) async {
    final time = await savedAt(sourceId: sourceId, languageKey: languageKey);
    return time != null &&
        DateTime.now().difference(time) < const Duration(minutes: 10);
  }

  static Future<void> _save(String key, List<OnlineMangaSummary> items) async =>
      (await LibraryStore.ensureInitialized()).putRecord('catalog', key, {
        'savedAt': DateTime.now().millisecondsSinceEpoch,
        'items': items.map((e) => e.toMap()).toList(),
      });
  static Future<List<OnlineMangaSummary>> _load(String key) async {
    try {
      final raw = await (await LibraryStore.ensureInitialized()).getRecord(
        'catalog',
        key,
      );
      return raw is Map
          ? (raw['items'] as List)
                .whereType<Map>()
                .map(
                  (e) =>
                      OnlineMangaSummary.fromMap(Map<String, dynamic>.from(e)),
                )
                .toList()
          : [];
    } catch (_) {
      return [];
    }
  }
}
