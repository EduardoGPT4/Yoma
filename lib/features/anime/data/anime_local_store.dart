import 'dart:convert';
import '../../../data/library_store.dart';
import '../models/anime_models.dart';

/// Namespaces isolate anime state without changing the manga schema or records.
class AnimeLocalStore {
  final Future<LibraryStore> Function() database;
  AnimeLocalStore({Future<LibraryStore> Function()? database})
    : database = database ?? LibraryStore.ensureInitialized;
  Future<Map<String, dynamic>?> cache(String key) async {
    final value = await (await database()).getRecord('anime_cache', key);
    return value is Map ? Map<String, dynamic>.from(value) : null;
  }

  Future<void> putCache(String key, Map<String, dynamic> data) async {
    await _put('anime_cache', key, {
      'savedAt': DateTime.now().millisecondsSinceEpoch,
      'data': data,
    });
    // Cada búsqueda distinta guarda una página; se conservan las recientes.
    if (key.startsWith('catalog:')) {
      await (await database()).pruneRecords('anime_cache', 'catalog:', 40);
    }
  }

  Future<void> _put(String ns, String key, Map<String, dynamic> value) async =>
      (await database()).putRecord(ns, key, value);
  Future<List<Map<String, dynamic>>> library() async =>
      (await database()).readRecords('anime_library');
  Future<List<Map<String, dynamic>>> progress() async =>
      (await database()).readRecords('anime_progress');
  Future<Map<String, dynamic>> settings() async =>
      animeMap(await (await database()).getRecord('anime_settings', 'main'));
  Future<void> saveSettings(Map<String, dynamic> values) =>
      _put('anime_settings', 'main', values);
  Future<void> saveLibrary(
    AnimeTitle anime, {
    required bool saved,
    required bool favorite,
    String status = 'planned',
    int score = 0,
    String notes = '',
  }) => _put('anime_library', anime.slug, {
    'slug': anime.slug,
    'anime': anime.toJson(),
    'saved': saved,
    'favorite': favorite,
    'status': status,
    'score': score,
    'notes': notes,
    'updatedAt': DateTime.now().millisecondsSinceEpoch,
  });
  Future<void> saveProgress(
    AnimeTitle anime,
    AnimeEpisode episode, {
    required int positionMs,
    required int durationMs,
    bool? watched,
  }) async {
    final store = await database();
    await store.transaction(() async {
      final previous = animeMap(
        await store.getRecord('anime_progress', episode.key),
      );
      await store.putRecord('anime_progress', episode.key, {
        ...previous,
        'slug': anime.slug,
        'anime': anime.toJson(),
        'episode': episode.toJson(),
        'positionMs': positionMs.clamp(
          0,
          durationMs > 0 ? durationMs : positionMs,
        ),
        'durationMs': durationMs,
        'watched': watched ?? previous['watched'] == true,
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
      });
    });
  }

  Future<void> markWatched(
    AnimeTitle anime,
    AnimeEpisode episode,
    bool value,
  ) async {
    final old = animeMap(
      await (await database()).getRecord('anime_progress', episode.key),
    );
    await saveProgress(
      anime,
      episode,
      positionMs: animeInt(old['positionMs']),
      durationMs: animeInt(old['durationMs']),
      watched: value,
    );
  }

  Future<void> clearMetadataCache() async =>
      (await database()).replaceRecords('anime_cache', []);
  Future<void> saveNavigation(Map<String, dynamic> value) =>
      _put('anime_settings', 'navigation', value);
  Future<Map<String, dynamic>> navigation() async => animeMap(
    await (await database()).getRecord('anime_settings', 'navigation'),
  );
  String queryKey(Map<String, Object?> values) => jsonEncode(values);
}
