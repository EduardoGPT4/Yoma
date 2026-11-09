import 'dart:async';

import 'package:flutter/foundation.dart';

import '../utils/preferences.dart';
import '../services/myanimelist_service.dart';
import '../services/diagnostics.dart';

/// Capítulos marcados como leídos (online y offline), por path/url del capítulo.
class ChapterReadProvider extends ChangeNotifier {
  Set<String> _readKeys = <String>{};
  bool _loaded = false;

  bool get isLoaded => _loaded;
  int get totalReadChapters => _readKeys.length;

  Future<void> load() async {
    _readKeys = await PreferencesService.getReadChapterKeys();
    _loaded = true;
    notifyListeners();
  }

  bool isRead(String chapterPath) => _readKeys.contains(chapterPath);
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
    unawaited(_syncMal([chapterPath]));
    notifyListeners();
  }

  Future<void> markUnread(String chapterPath) async {
    if (!_readKeys.contains(chapterPath)) {
      return;
    }
    _readKeys = Set<String>.from(_readKeys)..remove(chapterPath);
    await PreferencesService.setChapterRead(chapterPath, false);
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
