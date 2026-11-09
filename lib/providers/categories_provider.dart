import 'package:flutter/foundation.dart';

import '../models/manga_category.dart';
import '../utils/preferences.dart';

class CategoriesProvider extends ChangeNotifier {
  final List<MangaCategory> _categories = <MangaCategory>[];

  List<MangaCategory> get categories =>
      List<MangaCategory>.unmodifiable(_categories);

  Future<void> load() async {
    final stored = await PreferencesService.getCategories();
    _categories
      ..clear()
      ..addAll(stored.map(MangaCategory.fromMap));

    notifyListeners();
  }

  MangaCategory? categoryById(String? id) {
    if (id == null) {
      return null;
    }
    for (final category in _categories) {
      if (category.id == id) {
        return category;
      }
    }
    return null;
  }

  bool isMangaInCategory(String categoryId, String mangaKey) {
    final category = categoryById(categoryId);
    return category?.mangaKeys.contains(mangaKey) ?? false;
  }

  List<MangaCategory> categoriesForManga(String mangaKey) {
    return _categories
        .where((category) => category.mangaKeys.contains(mangaKey))
        .toList();
  }

  Future<void> createCategory(String name) async {
    final cleaned = name.trim();
    if (cleaned.isEmpty) {
      return;
    }

    final exists = _categories.any(
      (category) => category.name.toLowerCase() == cleaned.toLowerCase(),
    );
    if (exists) {
      return;
    }

    final id =
        '${DateTime.now().microsecondsSinceEpoch}_${cleaned.toLowerCase()}';
    _categories.add(MangaCategory(id: id, name: cleaned));
    await _persist();
    notifyListeners();
  }

  Future<void> deleteCategory(String id) async {
    _categories.removeWhere((category) => category.id == id);
    await _persist();
    notifyListeners();
  }

  Future<void> removeMangaKeys(Iterable<String> keys) async {
    final keySet = keys.where((key) => key.trim().isNotEmpty).toSet();
    if (keySet.isEmpty) {
      return;
    }

    var changed = false;
    for (var i = 0; i < _categories.length; i++) {
      final category = _categories[i];
      final nextKeys = category.mangaKeys
          .where((key) => !keySet.contains(key))
          .toList();
      if (nextKeys.length == category.mangaKeys.length) {
        continue;
      }
      _categories[i] = category.copyWith(mangaKeys: nextKeys);
      changed = true;
    }

    if (!changed) {
      return;
    }
    await _persist();
    notifyListeners();
  }

  Future<void> toggleMangaInCategory(String categoryId, String mangaKey) async {
    final index = _categories.indexWhere(
      (category) => category.id == categoryId,
    );
    if (index < 0) {
      return;
    }

    final category = _categories[index];
    final keys = List<String>.from(category.mangaKeys);
    if (keys.contains(mangaKey)) {
      keys.remove(mangaKey);
    } else {
      keys.add(mangaKey);
    }

    _categories[index] = category.copyWith(mangaKeys: keys);
    await _persist();
    notifyListeners();
  }

  Future<void> _persist() async {
    await PreferencesService.setCategories(
      _categories.map((category) => category.toMap()).toList(),
    );
  }
}
