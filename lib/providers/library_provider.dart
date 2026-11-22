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
import '../services/manga_sync.dart';
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
  Timer? _progressNotifyTimer;
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

  /// El progreso de otro dispositivo de la cuenta llega por [MangaSync].
  LibraryProvider() {
    MangaSync.changes.addListener(_reloadProgress);
  }

  Future<void> _reloadProgress() async {
    final progress = await PreferencesService.getProgressMap();
    if (_disposed) return;
    _progress = progress;
    notifyListeners();
  }

  @override
  void dispose() {
    MangaSync.changes.removeListener(_reloadProgress);
    _disposed = true;
    _statsTimer?.cancel();
    _progressNotifyTimer?.cancel();
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

  /// Clave con la que se reconoce el mismo manga en fuentes distintas:
  /// título limpio, sin acentos, mayúsculas ni signos («Boku Girl» y
  /// «Bokugirl!» coinciden).
  static String titleKey(String title) =>
      _titleKeys[title] ??= _buildTitleKey(title);
  static final Map<String, String> _titleKeys = {};
  static const Map<String, String> _accents = {
    'á': 'a', 'à': 'a', 'ä': 'a', 'â': 'a', //
    'é': 'e', 'è': 'e', 'ë': 'e', 'ê': 'e', //
    'í': 'i', 'ì': 'i', 'ï': 'i', 'î': 'i', //
    'ó': 'o', 'ò': 'o', 'ö': 'o', 'ô': 'o', //
    'ú': 'u', 'ù': 'u', 'ü': 'u', 'û': 'u', 'ñ': 'n',
  };
  // Letras latinas, cifras, kana, kanji y hangul; el resto (espacios,
  // signos) no cuenta.
  static final RegExp _keyChar = RegExp(r'[a-z0-9぀-ヿ一-鿿가-힯]');
  static String _buildTitleKey(String title) {
    final lower = TitleSanitizer.clean(title).toLowerCase();
    final buffer = StringBuffer();
    for (final rune in lower.runes) {
      final char = String.fromCharCode(rune);
      final plain = _accents[char] ?? char;
      if (_keyChar.hasMatch(plain)) buffer.write(plain);
    }
    return buffer.toString();
  }

  /// Progreso compartido de un manga: el suyo o el de ese mismo título en
  /// otra fuente o en una descarga. Gana el más reciente, así que leer en
  /// cualquiera de ellos sirve para seguir en los demás.
  ReadingProgress? progressFor(String ref, String title) {
    ReadingProgress? best = getProgress(ref);
    final key = titleKey(title);
    if (key.length >= 3) {
      for (final entry in _progress.values) {
        if ((best == null || entry.updatedAt > best.updatedAt) &&
            titleKey(entry.mangaTitle) == key) {
          best = entry;
        }
      }
    }
    return best;
  }

  /// Progreso de un manga de la biblioteca: el de su fuente, el de su
  /// carpeta o el del mismo título en cualquier otra fuente.
  ReadingProgress? progressForManga(Manga manga) {
    var best = progressFor(manga.sourceUrl ?? manga.path, manga.title);
    final wantPath = _normalizeFsPath(manga.path);
    for (final progress in _progress.values) {
      if ((best == null || progress.updatedAt > best.updatedAt) &&
          _normalizeFsPath(progress.mangaPath) == wantPath) {
        best = progress;
      }
    }
    return best;
  }

  static final RegExp _chapterNumber = RegExp(r'(\d+(?:\.\d+)?)');

  /// Número de capítulo de un título («Capítulo 012.5» → 12.5).
  static double? chapterNumberOf(String title) {
    final raw = _chapterNumber
        .firstMatch(TitleSanitizer.chapterLabel(title))
        ?.group(1);
    return raw == null ? null : double.tryParse(raw);
  }

  /// Capítulo de [chapters] donde retomar [progress]: el mismo enlace, el
  /// mismo título o, si viene de otra fuente, el mismo número. -1 si no está.
  static int chapterIndexFor(
    ReadingProgress progress,
    List<({String ref, String title})> chapters,
  ) {
    final wantRef = _normalizeFsPath(progress.chapterPath);
    var index = chapters.indexWhere(
      (chapter) => _normalizeFsPath(chapter.ref) == wantRef,
    );
    if (index >= 0) return index;
    final wantLabel = TitleSanitizer.chapterLabel(progress.chapterTitle);
    index = chapters.indexWhere(
      (chapter) => TitleSanitizer.chapterLabel(chapter.title) == wantLabel,
    );
    if (index >= 0) return index;
    final number = chapterNumberOf(progress.chapterTitle);
    if (number == null) return -1;
    return chapters.indexWhere(
      (chapter) => chapterNumberOf(chapter.title) == number,
    );
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

    final chapterIndex = chapterIndexFor(progress, [
      for (final chapter in manga.chapters)
        (ref: chapter.sourceUrl ?? chapter.path, title: chapter.title),
    ]);
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

  /// El lector guarda el progreso en cada página. Avisar a cada cambio de
  /// página reconstruía la biblioteca, el inicio y la ficha que quedan debajo
  /// del lector; dentro del mismo capítulo basta un aviso al detenerse.
  Future<void> updateProgress(ReadingProgress progress) async {
    final previous = _progress[progress.mangaPath];
    _progress = Map<String, ReadingProgress>.from(_progress)
      ..[progress.mangaPath] = progress;
    await PreferencesService.saveProgress(progress);
    if (_disposed) return;
    _progressNotifyTimer?.cancel();
    if (previous?.chapterPath == progress.chapterPath) {
      _progressNotifyTimer = Timer(const Duration(milliseconds: 1500), () {
        _progressNotifyTimer = null;
        if (!_disposed) notifyListeners();
      });
    } else {
      _progressNotifyTimer = null;
      notifyListeners();
    }
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

  /// Sin aviso propio: el progreso de la misma página ya avisa, y un segundo
  /// aviso por página volvía a reconstruir todo lo que escucha la biblioteca.
  Future<void> recordPageRead() async {
    _readingStats = _readingStats.recordPageRead();
    _scheduleStats();
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
