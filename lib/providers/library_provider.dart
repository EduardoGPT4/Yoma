import '../services/download_events.dart';
import '../models/content_identity.dart';
import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../models/manga.dart';
import '../models/reading_progress.dart';
import '../models/reading_stats.dart';
import '../utils/fs_scanner.dart';
import '../utils/library_cache.dart';
import '../utils/manga_storage.dart';
import '../utils/preferences.dart';
import '../utils/sorting.dart';
import '../utils/title_sanitizer.dart';

class MangaDeleteResult {
  final List<String> deletedPaths;
  final List<String> failedTitles;

  const MangaDeleteResult({
    required this.deletedPaths,
    required this.failedTitles,
  });

  int get deletedCount => deletedPaths.length;
}

class LibraryProvider extends ChangeNotifier {
  final StreamController<List<Manga>> _mangaStreamController =
      StreamController<List<Manga>>.broadcast();
  final List<StreamSubscription<FileSystemEvent>> _watchSubscriptions =
      <StreamSubscription<FileSystemEvent>>[];

  List<String> _libraryPaths = <String>[];
  List<Manga> _mangas = <Manga>[];
  Map<String, ReadingProgress> _progress = <String, ReadingProgress>{};
  ReadingStats _readingStats = const ReadingStats();
  bool _loading = false;
  bool _disposed = false;
  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  bool _watchEnabled = false;
  bool _watchRescanQueued = false;
  final Set<String> _dirtyFolders = {};
  String? _error;
  StreamSubscription<String>? _downloadSubscription;
  Timer? _statsTimer;
  Completer<void>? _scanCompleter;
  Timer? _watchDebounceTimer;
  ReceivePort? _scanPort;
  StreamSubscription<dynamic>? _scanSubscription;
  Isolate? _scanIsolate;
  int _scanGeneration = 0;

  List<String> get libraryPaths => _libraryPaths;
  List<Manga> get mangas => _mangas;
  Stream<List<Manga>> get mangasStream => _mangaStreamController.stream;
  Map<String, ReadingProgress> get progressMap => _progress;
  ReadingStats get readingStats => _readingStats;
  bool get isLoading => _loading;
  bool get autoRescanEnabled => _watchEnabled;
  String? get error => _error;

  @override
  void dispose() {
    _disposed = true;
    _statsTimer?.cancel();
    unawaited(flushStats());
    unawaited(_downloadSubscription?.cancel());
    _watchDebounceTimer?.cancel();
    _watchDebounceTimer = null;
    unawaited(_cancelWatchers());
    unawaited(_stopActiveScan());
    _mangaStreamController.close();
    super.dispose();
  }

  Future<void> load() async {
    await _downloadSubscription?.cancel();
    _downloadSubscription = DownloadEvents.completedFolders.listen((folder) {
      unawaited(refreshMangaFolder(folder));
    });
    _loading = true;
    notifyListeners();

    _libraryPaths = await PreferencesService.getLibraryPaths();
    _progress = await PreferencesService.getProgressMap();
    _readingStats = await PreferencesService.getReadingStats();
    _watchEnabled = await PreferencesService.getAutoRescanEnabled();

    final downloadRoot = await PreferencesService.getDownloadRoot();
    if (downloadRoot != null && downloadRoot.trim().isNotEmpty) {
      final downloadFolder = MangaStoragePaths.downloadFolder(downloadRoot);
      final legacyFolder = MangaStoragePaths.legacyDownloadFolder(downloadRoot);
      var paths = List<String>.from(_libraryPaths);
      var changed = false;

      if (!paths.contains(downloadFolder)) {
        paths.add(downloadFolder);
        changed = true;
      }

      // Ocultar páginas de mangas de la galería del sistema (.nomedia).
      await MangaStoragePaths.ensureNoMedia(Directory(downloadFolder));

      final legacyDir = Directory(legacyFolder);
      if (await legacyDir.exists()) {
        await MangaStoragePaths.ensureNoMedia(legacyDir);
        if (!paths.contains(legacyFolder)) {
          paths.add(legacyFolder);
          changed = true;
        }
      } else if (paths.remove(legacyFolder)) {
        changed = true;
      }

      if (changed) {
        _libraryPaths = paths;
        await PreferencesService.setLibraryPaths(_libraryPaths);
      }
    }

    final cache = await LibraryCacheService.load();
    if (cache != null) {
      _mangas = cache.mangas;
      _emitMangas();
    }

    notifyListeners();
    await _refreshWatchers();

    unawaited(rescan());
  }

  /// Borra la carpeta contenedora de cada manga y lo quita de la biblioteca.
  Future<MangaDeleteResult> deleteMangas(Iterable<Manga> mangas) async {
    _watchDebounceTimer?.cancel();
    await _stopActiveScan();

    final failedTitles = <String>[];
    final deletedPaths = <String>{};
    final deletedTitles = <String>{};

    for (final manga in mangas) {
      if (!_canDeleteMangaFolder(manga.path)) {
        failedTitles.add(manga.title.isEmpty ? manga.path : manga.title);
        continue;
      }

      try {
        final directory = Directory(manga.path);
        if (await directory.exists()) {
          await directory.delete(recursive: true);
        }
        deletedPaths.add(manga.path);
        if (manga.title.trim().isNotEmpty) {
          deletedTitles.add(manga.title.trim());
        }
      } catch (_) {
        failedTitles.add(manga.title.isEmpty ? manga.path : manga.title);
      }
    }

    if (deletedPaths.isNotEmpty) {
      _mangas = _mangas
          .where((manga) => !deletedPaths.contains(manga.path))
          .toList();
      _progress = Map<String, ReadingProgress>.from(_progress)
        ..removeWhere((key, _) => deletedPaths.contains(key));
      await PreferencesService.setProgressMap(_progress);
      await _removeSourceLinks(deletedPaths, deletedTitles);
      _emitMangas();
      notifyListeners();
      unawaited(
        LibraryCacheService.save(libraryPaths: _libraryPaths, mangas: _mangas),
      );
    }

    return MangaDeleteResult(
      deletedPaths: deletedPaths.toList(),
      failedTitles: failedTitles,
    );
  }

  bool _canDeleteMangaFolder(String mangaPath) {
    final trimmed = mangaPath.trim();
    if (trimmed.isEmpty) {
      return false;
    }

    final normalized = p.normalize(trimmed);
    final parent = p.dirname(normalized);
    if (parent.isEmpty || parent == normalized || parent == p.separator) {
      return false;
    }

    for (final root in _libraryPaths) {
      final normalizedRoot = p.normalize(root.trim());
      if (normalizedRoot.isEmpty) {
        continue;
      }
      if (p.equals(normalized, normalizedRoot)) {
        return false;
      }
      if (p.isWithin(normalizedRoot, normalized)) {
        return true;
      }
    }
    return false;
  }

  Future<void> _removeSourceLinks(Set<String> paths, Set<String> titles) async {
    final links = await PreferencesService.getMangaSourceLinks();
    if (links.isEmpty) {
      return;
    }
    final next = Map<String, String>.from(links)
      ..removeWhere((key, _) => paths.contains(key) || titles.contains(key));
    if (next.length != links.length) {
      await PreferencesService.setMangaSourceLinks(next);
    }
  }

  Future<void> addLibraryPath(String path) async {
    final normalizedPath = path.trim();
    if (normalizedPath.isEmpty) {
      return;
    }

    if (!_libraryPaths.contains(normalizedPath)) {
      _libraryPaths = List<String>.from(_libraryPaths)..add(normalizedPath);
      await PreferencesService.setLibraryPaths(_libraryPaths);
      await _refreshWatchers();
      notifyListeners();
    }

    unawaited(rescan());
  }

  Future<void> setAutoRescanEnabled(bool value) async {
    if (_watchEnabled == value) {
      return;
    }

    _watchEnabled = value;
    await PreferencesService.setAutoRescanEnabled(value);
    await _refreshWatchers();
    notifyListeners();
  }

  Future<void> rescan() async {
    final generation = ++_scanGeneration;
    await _stopActiveScan();
    if (_disposed) return;
    _loading = true;
    _error = null;
    notifyListeners();

    final receivePort = ReceivePort();
    _scanPort = receivePort;
    final completer = Completer<void>();
    _scanCompleter = completer;
    var received = 0;
    final mangasByPath = <String, Manga>{
      for (final manga in _mangas) manga.path: manga,
    };

    _scanSubscription = receivePort.listen(
      (message) {
        if (generation != _scanGeneration) {
          return;
        }

        if (message is! Map<String, dynamic>) {
          return;
        }

        final type = message['type'] as String? ?? '';
        if (type == 'item') {
          final mangaMap = message['manga'];
          if (mangaMap is Map) {
            final manga = Manga.fromMap(mangaMap.cast<String, dynamic>());
            mangasByPath[manga.path] = manga;
            if (++received % 20 == 0) {
              _mangas = _sortedMangas(mangasByPath.values.toList());
              _emitMangas();
            }
          }
          return;
        }

        if (type == 'done') {
          final mangaMaps = message['mangas'];
          if (mangaMaps is List) {
            _mangas = _sortedMangas(
              mangaMaps
                  .whereType<Map>()
                  .map((entry) => Manga.fromMap(entry.cast<String, dynamic>()))
                  .toList(),
            );
            _emitMangas();
          }

          _error = null;
          _loading = false;
          notifyListeners();
          unawaited(
            LibraryCacheService.save(
              libraryPaths: _libraryPaths,
              mangas: _mangas,
            ),
          );
          unawaited(_stopActiveScan());
          if (!completer.isCompleted) {
            completer.complete();
          }
          if (_watchRescanQueued) {
            _watchRescanQueued = false;
            unawaited(rescan());
          }
          return;
        }

        if (type == 'error') {
          _error =
              message['message'] as String? ??
              'No se pudo escanear la biblioteca.';
          _loading = false;
          notifyListeners();
          unawaited(_stopActiveScan());
          if (!completer.isCompleted) {
            completer.complete();
          }
        }
      },
      onError: (Object error) {
        _error = 'No se pudo escanear la biblioteca.';
        _loading = false;
        notifyListeners();
        unawaited(_stopActiveScan());
        if (!completer.isCompleted) {
          completer.complete();
        }
      },
      onDone: () {
        if (!completer.isCompleted) {
          completer.complete();
        }
      },
    );

    try {
      _scanIsolate = await Isolate.spawn(
        FsScanner.scanLibraryIncremental,
        <String, dynamic>{
          'roots': _libraryPaths,
          'sendPort': receivePort.sendPort,
        },
      );
    } catch (_) {
      _error = 'No se pudo escanear la biblioteca.';
      _loading = false;
      notifyListeners();
      await _stopActiveScan();
      if (!completer.isCompleted) {
        completer.complete();
      }
      return;
    }

    await completer.future;
  }

  ReadingProgress? getProgress(String mangaPath) {
    final direct = _progress[mangaPath];
    if (direct != null) return direct;
    final canonical = ContentIdentity.canonical(mangaPath);
    final matches =
        _progress.values
            .where(
              (entry) =>
                  ContentIdentity.canonical(entry.mangaPath) == canonical,
            )
            .toList()
          ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return matches.isEmpty ? null : matches.first;
  }

  List<ReadingProgress> getRecentProgress() {
    final items = _progress.values.toList();
    items.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return items;
  }

  /// Progreso local (o el online del mismo título) para un manga de la biblioteca.
  ReadingProgress? progressForManga(Manga manga) {
    final direct = getProgress(manga.sourceUrl ?? manga.path);
    if (direct != null) {
      return direct;
    }

    final wantPath = _normalizeFsPath(manga.path);
    final wantTitle = TitleSanitizer.clean(manga.title).toLowerCase();
    ReadingProgress? byTitle;

    for (final progress in getRecentProgress()) {
      if (_normalizeFsPath(progress.mangaPath) == wantPath) {
        return progress;
      }
      if (wantTitle.isEmpty) {
        continue;
      }
      final progressTitle = TitleSanitizer.clean(
        progress.mangaTitle,
      ).toLowerCase();
      if (progressTitle == wantTitle &&
          manga.sourceUrl == null &&
          _mangas
                  .where(
                    (m) =>
                        TitleSanitizer.clean(m.title).toLowerCase() ==
                        wantTitle,
                  )
                  .length ==
              1) {
        byTitle ??= progress;
      }
    }
    return getRecentProgress()
                .where(
                  (p) =>
                      TitleSanitizer.clean(p.mangaTitle).toLowerCase() ==
                      wantTitle,
                )
                .length ==
            1
        ? byTitle
        : null;
  }

  /// Capítulo y página donde retomar un manga local. Si no hay progreso, (0, 0).
  ({int chapterIndex, int pageIndex}) resumePosition(Manga manga) {
    if (manga.chapters.isEmpty) {
      return (chapterIndex: 0, pageIndex: 0);
    }

    final progress = progressForManga(manga);
    if (progress == null) {
      return (chapterIndex: 0, pageIndex: 0);
    }

    var chapterIndex = manga.chapters.indexWhere(
      (chapter) =>
          _normalizeFsPath(chapter.sourceUrl ?? chapter.path) ==
          _normalizeFsPath(progress.chapterPath),
    );
    if (chapterIndex < 0) {
      final wanted = TitleSanitizer.chapterLabel(progress.chapterTitle);
      chapterIndex = manga.chapters.indexWhere(
        (chapter) => TitleSanitizer.chapterLabel(chapter.title) == wanted,
      );
    }
    if (chapterIndex < 0) {
      final number = RegExp(r'(\d+(?:\.\d+)?)')
          .firstMatch(TitleSanitizer.chapterLabel(progress.chapterTitle))
          ?.group(1);
      if (number != null) {
        chapterIndex = manga.chapters.indexWhere((chapter) {
          return RegExp(r'(\d+(?:\.\d+)?)')
                  .firstMatch(TitleSanitizer.chapterLabel(chapter.title))
                  ?.group(1) ==
              number;
        });
      }
    }
    if (chapterIndex < 0) {
      return (chapterIndex: 0, pageIndex: 0);
    }

    final chapter = manga.chapters[chapterIndex];
    final pageIndex = chapter.pageCount > 0
        ? progress.pageIndex.clamp(0, chapter.pageCount - 1)
        : progress.pageIndex;
    return (chapterIndex: chapterIndex, pageIndex: pageIndex);
  }

  /// Manga local que corresponde a un progreso (ruta exacta o mismo título).
  Manga? localMangaForProgress(ReadingProgress progress, List<Manga> mangas) {
    final wantPath = _normalizeFsPath(progress.mangaPath);
    for (final manga in mangas) {
      if (_normalizeFsPath(manga.sourceUrl ?? manga.path) == wantPath) {
        return manga;
      }
    }

    final wantTitle = TitleSanitizer.clean(progress.mangaTitle).toLowerCase();
    if (wantTitle.isEmpty) {
      return null;
    }
    final matches = mangas
        .where(
          (m) =>
              m.sourceUrl == null &&
              TitleSanitizer.clean(m.title).toLowerCase() == wantTitle,
        )
        .toList();
    return matches.length == 1 ? matches.single : null;
  }

  static String _normalizeFsPath(String path) {
    var value = path.trim().replaceAll('\\', '/');
    while (value.length > 1 && value.endsWith('/')) {
      value = value.substring(0, value.length - 1);
    }
    return value.toLowerCase();
  }

  Future<void> updateProgress(ReadingProgress progress) async {
    _progress = Map<String, ReadingProgress>.from(_progress)
      ..[progress.mangaPath] = progress;
    await PreferencesService.saveProgress(progress);
    notifyListeners();
  }

  Future<void> recordMangaOpen(String mangaPath) async {
    if (mangaPath.trim().isEmpty) {
      return;
    }

    _readingStats = _readingStats.recordMangaOpen(mangaPath);
    _scheduleStats();
    notifyListeners();
  }

  Future<void> recordChapterOpen() async {
    _readingStats = _readingStats.recordChapterOpen();
    _scheduleStats();
    notifyListeners();
  }

  Future<void> recordPageRead() async {
    _readingStats = _readingStats.recordPageRead();
    _scheduleStats();
    notifyListeners();
  }

  void _scheduleStats() {
    _statsTimer?.cancel();
    _statsTimer = Timer(
      const Duration(seconds: 1),
      () => unawaited(flushStats()),
    );
  }

  Future<void> flushStats() async {
    _statsTimer?.cancel();
    _statsTimer = null;
    await PreferencesService.setReadingStats(_readingStats);
  }

  Future<void> refreshMangaFolder(String folder) async {
    if (_disposed) return;
    _libraryPaths = await PreferencesService.getLibraryPaths();
    final result = await compute<String, Map<String, dynamic>?>(
      FsScanner.scanMangaFolder,
      folder,
    );
    if (_disposed) return;
    final manga = result == null ? null : Manga.fromMap(result);
    _mangas = _sortedMangas([
      ..._mangas.where((m) => m.path != folder),
      ?manga,
    ]);
    _emitMangas();
    notifyListeners();
  }

  void _emitMangas() {
    if (!_mangaStreamController.isClosed) {
      _mangaStreamController.add(List<Manga>.unmodifiable(_mangas));
    }
  }

  List<Manga> _sortedMangas(List<Manga> mangas) {
    mangas.sort((a, b) => naturalCompare(a.title, b.title));
    return mangas;
  }

  Future<void> _refreshWatchers() async {
    await _cancelWatchers();

    if (_disposed || !_watchEnabled) {
      return;
    }

    for (final path in _libraryPaths) {
      if (_disposed) return;
      final directory = Directory(path);
      if (!await directory.exists()) {
        continue;
      }

      try {
        final subscription = directory
            .watch(recursive: true)
            .listen(
              (event) => _scheduleWatchRescan(path, event),
              onError: (_) {},
            );
        _watchSubscriptions.add(subscription);
      } catch (_) {
        // Watchers are optional. Ignore unsupported roots.
      }
    }
  }

  void _scheduleWatchRescan(String root, FileSystemEvent event) {
    void dirty(String path) {
      final relative = p.relative(path, from: root);
      if (relative == '.' || relative.startsWith('..')) {
        _watchRescanQueued = true;
        return;
      }
      _dirtyFolders.add(p.join(root, p.split(relative).first));
    }

    if (!event.path.endsWith('.part') && !event.path.endsWith('.tmp')) {
      dirty(event.path);
    }
    if (event is FileSystemMoveEvent && event.destination != null) {
      dirty(event.destination!);
    }
    if (_disposed || !_watchEnabled) {
      return;
    }

    _watchDebounceTimer?.cancel();
    _watchDebounceTimer = Timer(const Duration(seconds: 2), () {
      if (_loading) {
        _watchRescanQueued = true;
        return;
      }
      if (_watchRescanQueued) {
        _watchRescanQueued = false;
        unawaited(rescan());
        return;
      }
      final folders = _dirtyFolders.toList();
      _dirtyFolders.clear();
      unawaited(Future.wait(folders.map(refreshMangaFolder)));
    });
  }

  Future<void> _cancelWatchers() async {
    for (final subscription in _watchSubscriptions) {
      await subscription.cancel();
    }
    _watchSubscriptions.clear();
  }

  Future<void> _stopActiveScan() async {
    final complete = _scanCompleter;
    _scanCompleter = null;
    final subscription = _scanSubscription;
    _scanSubscription = null;
    final port = _scanPort;
    _scanPort = null;
    final isolate = _scanIsolate;
    _scanIsolate = null;
    if (complete?.isCompleted == false) complete!.complete();
    _watchDebounceTimer?.cancel();
    _watchDebounceTimer = null;
    await subscription?.cancel();
    port?.close();
    isolate?.kill(priority: Isolate.immediate);
  }
}
