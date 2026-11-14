import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/favorite_entry.dart';
import '../data/library_store.dart';
import '../services/manga_sync.dart';
import '../utils/preferences.dart';

class FavoritesProvider extends ChangeNotifier {
  final Map<String, FavoriteEntry> _entries = <String, FavoriteEntry>{};

  /// Lo cambiado en otro dispositivo de la cuenta llega por [MangaSync].
  FavoritesProvider() {
    MangaSync.changes.addListener(_reload);
  }

  void _reload() => unawaited(load());

  @override
  void dispose() {
    MangaSync.changes.removeListener(_reload);
    super.dispose();
  }

  List<FavoriteEntry> get entries {
    final items = _entries.values.toList();
    items.sort((a, b) => a.title.compareTo(b.title));
    return items;
  }

  bool isFavorite(String key) => _entries.containsKey(key);

  FavoriteEntry? getEntry(String key) => _entries[key];

  Future<void> load() async {
    _entries
      ..clear()
      ..addAll(await PreferencesService.getFavoritesMap());
    notifyListeners();
  }

  Future<void> toggle({
    required String key,
    required String title,
    String? coverPath,
  }) async {
    if (_entries.containsKey(key)) {
      _entries.remove(key);
    } else {
      _entries[key] = FavoriteEntry(
        key: key,
        title: title,
        coverPath: coverPath,
      );
    }
    final entry = _entries[key];
    if (entry == null) {
      await PreferencesService.removeFavorite(key);
    } else {
      await PreferencesService.saveFavorite(entry);
    }
    notifyListeners();
  }

  Future<void> remove(String key) async {
    if (!_entries.containsKey(key)) {
      return;
    }
    _entries.remove(key);
    await PreferencesService.removeFavorite(key);
    notifyListeners();
  }

  Future<void> removeMany(Iterable<String> keys) async {
    final removed = [
      for (final key in keys)
        if (_entries.remove(key) != null) key,
    ];
    if (removed.isEmpty) {
      return;
    }
    await PreferencesService.setFavoritesMap(_entries);
    final store = await LibraryStore.ensureInitialized();
    for (final key in removed) {
      await store.noteMangaChange('manga', key, deleted: true);
    }
    notifyListeners();
  }
}
