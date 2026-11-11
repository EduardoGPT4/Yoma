import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/library_store.dart';
import '../utils/preferences.dart';
import '../services/mal_reading_sync.dart';
import '../services/myanimelist_service.dart';
import '../services/diagnostics.dart';

/// Capítulos marcados como leídos (online y offline), por path/url del capítulo.
class ChapterReadProvider extends ChangeNotifier implements ReadChapters {
  /// Capítulos que el usuario desmarcó: MyAnimeList no los vuelve a marcar.
  static const unmarkedNamespace = 'mal_unread';

  Set<String> _readKeys = <String>{};
  Set<String> _unmarked = <String>{};
  bool _loaded = false;
  Future<void>? _loading;

  bool get isLoaded => _loaded;
  int get totalReadChapters => _readKeys.length;

  Future<void> load() =>
      _loading ??= _load().whenComplete(() => _loading = null);

  Future<void> _load() async {
    _readKeys = await PreferencesService.getReadChapterKeys();
    try {
      final store = await LibraryStore.ensureInitialized();
      _unmarked = {
        for (final row in await store.readRecords(unmarkedNamespace))
          '${row['id']}',
      };
    } catch (e) {
      await Diagnostics.record('myanimelist', e);
    }
    _loaded = true;
    notifyListeners();
  }

  @override
  bool isRead(String chapterPath) => _readKeys.contains(chapterPath);

  @override
  bool isUnmarked(String chapterPath) => _unmarked.contains(chapterPath);

  Future<void> _rememberUnmarked(String path, bool value) async {
    if (value ? !_unmarked.add(path) : !_unmarked.remove(path)) return;
    try {
      final store = await LibraryStore.ensureInitialized();
      if (value) {
        await store.putRecord(unmarkedNamespace, path, {
          'at': DateTime.now().millisecondsSinceEpoch,
        });
      } else {
        await store.deleteRecord(unmarkedNamespace, path);
      }
    } catch (e) {
      await Diagnostics.record('myanimelist', e);
    }
  }

  /// Marca como leídos capítulos que MyAnimeList ya tiene leídos. No los
  /// envía a MAL (ya los tiene) ni toca los que el usuario desmarcó. Se
  /// escriben uno a uno: nunca se sustituye la lista guardada entera.
  @override
  Future<void> markReadFromMal(Iterable<String> paths) async {
    if (!_loaded) await load();
    final added = [
      for (final path in paths.toSet())
        if (path.isNotEmpty &&
            !_readKeys.contains(path) &&
            !_unmarked.contains(path))
          path,
    ];
    if (added.isEmpty) return;
    for (final path in added) {
      await PreferencesService.setChapterRead(path, true);
    }
    _readKeys = Set<String>.from(_readKeys)..addAll(added);
    notifyListeners();
  }

  Future<void> _syncMal(Iterable<String> paths) async {
    try {
      for (final path in paths) {
        await MyAnimeListService.shared.queueRead(path);
      }
      await MyAnimeListService.shared.flush();
    } catch (e) {
      await Diagnostics.record('myanimelist', e);
    }
  }

  Future<void> markRead(String chapterPath) async {
    if (chapterPath.isEmpty || _readKeys.contains(chapterPath)) {
      return;
    }
    _readKeys = Set<String>.from(_readKeys)..add(chapterPath);
    await PreferencesService.setChapterRead(chapterPath, true);
    await _rememberUnmarked(chapterPath, false);
    unawaited(_syncMal([chapterPath]));
    notifyListeners();
  }

  Future<void> markUnread(String chapterPath) async {
    if (!_readKeys.contains(chapterPath)) {
      return;
    }
    _readKeys = Set<String>.from(_readKeys)..remove(chapterPath);
    await PreferencesService.setChapterRead(chapterPath, false);
    await _rememberUnmarked(chapterPath, true);
    notifyListeners();
  }

  Future<void> toggle(String chapterPath) async {
    if (isRead(chapterPath)) {
      await markUnread(chapterPath);
    } else {
      await markRead(chapterPath);
    }
  }

  Future<void> markManyRead(Iterable<String> paths) async {
    final added = paths
        .where((p) => p.isNotEmpty && !_readKeys.contains(p))
        .toList();
    final next = Set<String>.from(_readKeys)
      ..addAll(paths.where((p) => p.isNotEmpty));
    if (next.length == _readKeys.length) {
      return;
    }
    _readKeys = next;
    await PreferencesService.setReadChapterKeys(_readKeys);
    for (final path in added) {
      await _rememberUnmarked(path, false);
    }
    unawaited(_syncMal(added));
    notifyListeners();
  }

  Future<void> removeUnderPrefixes(Iterable<String> prefixes) async {
    final prefixList = prefixes
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty);
    if (prefixList.isEmpty) {
      return;
    }

    final next = _readKeys.where((key) {
      for (final prefix in prefixList) {
        if (key == prefix ||
            key.startsWith('$prefix/') ||
            key.startsWith('$prefix\\')) {
          return false;
        }
      }
      return true;
    }).toSet();

    if (next.length == _readKeys.length) {
      return;
    }
    _readKeys = next;
    await PreferencesService.setReadChapterKeys(_readKeys);
    notifyListeners();
  }

  int readCountForManga(Iterable<String> chapterPaths) {
    var count = 0;
    for (final path in chapterPaths) {
      if (_readKeys.contains(path)) {
        count++;
      }
    }
    return count;
  }
}
