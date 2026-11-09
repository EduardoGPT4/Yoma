import 'package:flutter/foundation.dart';

import '../models/favorite_entry.dart';
import '../utils/preferences.dart';

class FavoritesProvider extends ChangeNotifier {
  final Map<String, FavoriteEntry> _entries = <String, FavoriteEntry>{};

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
    var changed = false;
    for (final key in keys) {
      if (_entries.remove(key) != null) {
        changed = true;
      }
    }
    if (!changed) {
      return;
    }
    await PreferencesService.setFavoritesMap(_entries);
    notifyListeners();
  }
}
