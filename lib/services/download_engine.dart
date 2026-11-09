import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:file_picker/file_picker.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../data/download_storage.dart';
import '../models/content_identity.dart';
import '../models/download_job.dart';
import '../models/online_manga.dart';
import '../utils/app_failure.dart';
import '../utils/connectivity_helper.dart';
import '../utils/download_rate_limiter.dart';
import '../utils/manga_storage.dart';
import '../utils/preferences.dart';
import 'download_events.dart';
import 'diagnostics.dart';
import 'download_notification_service.dart';
import 'image_repository.dart';
import 'storage_transfer.dart';
import 'online_catalog_service.dart';
import 'source_http_client.dart';
import 'maintenance_service.dart';
import 'repair_service.dart';
import '../models/automation_settings.dart';

abstract class DownloadPersistence {
  Future<List<Map<String, dynamic>>> readJobs();
  Future<void> writeJobs(List<Map<String, dynamic>> jobs);
  Future<List<Map<String, dynamic>>> readArchive();
  Future<void> writeArchive(List<Map<String, dynamic>> entries);
}

class PreferencesDownloadPersistence implements DownloadPersistence {
  @override
  Future<List<Map<String, dynamic>>> readJobs() =>
      PreferencesService.getDownloadQueue();
  @override
  Future<void> writeJobs(List<Map<String, dynamic>> jobs) =>
      PreferencesService.setDownloadQueue(jobs);
  @override
  Future<List<Map<String, dynamic>>> readArchive() =>
      PreferencesService.getDownloadArchive();
  @override
  Future<void> writeArchive(List<Map<String, dynamic>> entries) =>
      PreferencesService.setDownloadArchive(entries);
}

/// Posee la cola y sus efectos; Provider solo conecta comandos y presentación.
class DownloadEngine extends ChangeNotifier {
  final DownloadPersistence persistence;
  final ImageRepository images;
  final DownloadStorage storage;
  final Future<List<String>> Function(String) fetchPages;
  final Future<bool> Function(bool wifiOnly) canDownload;
  final List<DownloadJob> _jobs = [];
  final List<DownloadArchiveEntry> _archive = [];
  final DownloadRateLimiter _limiter = DownloadRateLimiter();
  final Map<String, CancellationToken> _tokens = {};
  Future<void> _persisting = Future.value();
  StreamSubscription<List<ConnectivityResult>>? _networkSubscription;
  Timer? _retryTimer;
  Timer? _notifyTimer;
  Timer? _persistTimer;
  int revision = 0;
  bool _running = false;
  bool _disposed = false;
  String? _activeJobId;
  String? _downloadRoot;
  bool _wifiOnly = false;
  int _threads = 4;
  int _limit = 0;
  String? persistenceError;
  DateTime? _readerUntil;
  int _pageWorkers = 0;
  bool get readerActive =>
      _readerUntil != null && DateTime.now().isBefore(_readerUntil!);
  void setReaderActive(bool value) {
    _readerUntil = value
        ? DateTime.now().add(const Duration(seconds: 35))
        : null;
  }

  Future<void> repair(String folder) async {
    final report = await RepairService.inspect(folder);
    if (report.damaged.isEmpty) return;
    await pauseForManga(report.detail.url);
    for (final job in List<DownloadJob>.of(_jobs).where(
      (j) =>
          ContentIdentity.canonical(j.manga.url) ==
          ContentIdentity.canonical(report.detail.url),
    )) {
      stopJob(job.id);
    }
    await enqueueManga(
      report.detail,
      chapterIndexes: report.damaged,
      destinationRoot: report.root,
    );
  }

  DownloadEngine({
    DownloadPersistence? persistence,
    ImageRepository? images,
    DownloadStorage? storage,
    Future<List<String>> Function(String)? fetchPages,
    Future<bool> Function(bool)? canDownload,
  }) : persistence = persistence ?? PreferencesDownloadPersistence(),
       images = images ?? ImageRepository.shared,
       storage = storage ?? DownloadStorage(),
       fetchPages = fetchPages ?? OnlineCatalogService.fetchChapterPages,
       canDownload =
           canDownload ??
           ((wifi) => wifi
               ? ConnectivityHelper.isOnWifi()
               : ConnectivityHelper.hasConnection());

  List<DownloadJob> get jobs => List.unmodifiable(_jobs);
  List<DownloadArchiveEntry> get archive => List.unmodifiable(_archive);
  String? get downloadRoot => _downloadRoot;
  String? get downloadFolderPath => _downloadRoot == null
      ? null
      : MangaStoragePaths.downloadFolder(_downloadRoot!);
  String? get activeJobId => _activeJobId;
  bool get wifiOnlyDownloads => _wifiOnly;
  int get downloadThreads => _threads;
  int get speedLimitKbps => _limit;
  bool get hasRunnableWork => _jobs.any(
    (job) =>
        job.status == DownloadJobStatus.queued ||
        job.status == DownloadJobStatus.downloading ||
        job.automaticRetry,
  );

  Future<void> load() async {
    _downloadRoot = await PreferencesService.getDownloadRoot();
    _wifiOnly = await PreferencesService.getWifiOnlyDownloads();
    _threads = await PreferencesService.getDownloadThreads();
    _limit = await PreferencesService.getDownloadSpeedLimitKbps();
    _limiter.updateLimit(_limit * 1024);
    _jobs.clear();
    for (final data in await persistence.readJobs()) {
      try {
        final job = DownloadJob.fromMap(data);
        job.destinationRoot ??= _downloadRoot;
        if (job.status == DownloadJobStatus.downloading) {
          job.status = DownloadJobStatus.queued;
          job.paused = false;
        }
        _jobs.add(job);
      } catch (error, stack) {
        debugPrint('Cola: entrada inválida: $error\n$stack');
      }
    }
    _archive
      ..clear()
      ..addAll(
        (await persistence.readArchive()).map(DownloadArchiveEntry.fromMap),
      );
    try {
      _networkSubscription = Connectivity().onConnectivityChanged.listen(
        (_) {
          unawaited(checkForRetryableJobs());
        },
        onError: (Object error) {
          debugPrint('Conectividad: $error');
        },
      );
    } catch (error) {
      debugPrint('Conectividad opcional: $error');
    }
    _changed();
    unawaited(_process());
  }

  Future<bool> chooseDownloadRoot() async {
    final selected = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Carpeta de descargas',
    );
    if (selected == null || selected.trim().isEmpty) return false;
    await setDownloadRoot(selected);
    return true;
  }

  Future<void> setDownloadRoot(String root) async {
    await Directory(root).create(recursive: true);
    final folder = Directory(MangaStoragePaths.downloadFolder(root));
    await folder.create(recursive: true);
    await MangaStoragePaths.ensureNoMedia(folder);
    _downloadRoot = root;
    await PreferencesService.setDownloadRoot(root);
    final paths = await PreferencesService.getLibraryPaths();
    if (!paths.contains(folder.path)) {
      await PreferencesService.setLibraryPaths([...paths, folder.path]);
    }
    _changed();
  }

  Future<void> applyDefaultDownloadRoot(String root) async {
    if (_downloadRoot == null) await setDownloadRoot(root);
  }

  Future<void> enqueueManga(
    OnlineMangaDetail manga, {
    Set<int>? chapterIndexes,
    bool automatic = false,
    int? maxBytes,
    String? destinationRoot,
  }) async {
    if (chapterIndexes == null && manga.hasMoreChapters) {
      manga = await OnlineCatalogService.completeDetail(manga);
    }
    manga = OnlineMangaDetail.fromMap(manga.toMap());
    if (_downloadRoot == null && destinationRoot == null) {
      throw const AppFailure(
        FailureKind.storage,
        'Elige una carpeta de descargas.',
      );
    }
    final selection =
        chapterIndexes ?? {for (var i = 0; i < manga.chapters.length; i++) i};
    if (selection.isEmpty ||
        selection.any((i) => i < 0 || i >= manga.chapters.length)) {
      throw const AppFailure(
        FailureKind.parsing,
        'Selecciona al menos un capítulo válido.',
      );
    }
    final pending = <int>{...selection};
    for (final job in _jobs.where(
      (job) =>
          [
            DownloadJobStatus.queued,
            DownloadJobStatus.downloading,
            DownloadJobStatus.paused,
          ].contains(job.status) &&
          ContentIdentity.canonical(job.manga.url) ==
              ContentIdentity.canonical(manga.url),
    )) {
      final chapterKeys = job.chapterIndexesToDownload
          .map((i) => job.manga.chapters[i].path)
          .toSet();
      pending.removeWhere((i) => chapterKeys.contains(manga.chapters[i].path));
    }
    if (pending.isEmpty) return;
    _jobs.add(
      DownloadJob(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        manga: manga,
        chapterIndexes: pending,
        automatic: automatic,
        maxBytes: maxBytes,
        destinationRoot: destinationRoot ?? _downloadRoot,
      ),
    );
    await _persist();
    _changed();
    unawaited(_process());
  }

  DownloadJob? _find(String id) {
    for (final job in _jobs) {
      if (job.id == id) return job;
    }
    return null;
  }

  void _interrupt(DownloadJob job, DownloadJobStatus status) {
    job.status = status;
    job.paused = status == DownloadJobStatus.paused;
    job.stopped = status == DownloadJobStatus.stopped;
    job.automaticRetry = false;
    _tokens[job.id]?.cancel();
    unawaited(DownloadNotificationService.cancel(job.id));
    _changed();
    unawaited(_process());
  }

  void pauseJob(String id) {
    final job = _find(id);
    if (job != null) _interrupt(job, DownloadJobStatus.paused);
  }

  void resumeJob(String id) {
    final job = _find(id);
    if (job == null || job.stopped) return;
    job.error = null;
    job.retryCount = 0;
    job.retryAt = null;
    _interrupt(job, DownloadJobStatus.queued);
  }

  void stopJob(String id) {
    final job = _find(id);
    if (job == null) return;
    _interrupt(job, DownloadJobStatus.stopped);
    if (_activeJobId != id) _archiveJob(job, 'Detenida manualmente');
  }

  bool canMoveUp(String id) => _jobs.indexWhere((j) => j.id == id) > 0;
  bool canMoveDown(String id) {
    final i = _jobs.indexWhere((j) => j.id == id);
    return i >= 0 && i < _jobs.length - 1;
  }

  void moveJobUp(String id) {
    final i = _jobs.indexWhere((j) => j.id == id);
    if (i <= 0) return;
    final job = _jobs.removeAt(i);
    _jobs.insert(i - 1, job);
    _yieldActiveIfNeeded();
    _changed();
  }

  void moveJobDown(String id) {
    final i = _jobs.indexWhere((j) => j.id == id);
    if (i < 0 || i >= _jobs.length - 1) return;
    final job = _jobs.removeAt(i);
    _jobs.insert(i + 1, job);
    _yieldActiveIfNeeded();
    _changed();
  }

  void prioritizeJob(String id) {
    final i = _jobs.indexWhere((j) => j.id == id);
    if (i < 0) return;
    final job = _jobs.removeAt(i);
    _jobs.insert(0, job);
    if (job.id != _activeJobId) {
      job.status = DownloadJobStatus.queued;
      job.paused = false;
      job.automaticRetry = false;
      job.retryAt = null;
      job.error = null;
    }
    _yieldActiveIfNeeded();
    _changed();
    unawaited(_process());
  }

  void _yieldActiveIfNeeded() {
    if (_activeJobId == null) return;
    for (final job in _jobs) {
      if (job.id == _activeJobId) return;
      if (job.status == DownloadJobStatus.queued) {
        final active = _find(_activeJobId!);
        if (active != null && active.status == DownloadJobStatus.downloading) {
          _interrupt(active, DownloadJobStatus.queued);
        }
        return;
      }
    }
  }

  Future<void> setWifiOnlyDownloads(bool value) async {
    _wifiOnly = value;
    await PreferencesService.setWifiOnlyDownloads(value);
    if (_activeJobId != null) {
      final job = _find(_activeJobId!);
      if (job != null && !await canDownload(value)) {
        _interrupt(job, DownloadJobStatus.paused);
        job.automaticRetry = true;
      }
    }
    _changed();
    await checkForRetryableJobs();
  }

  Future<void> pauseForManga(String ref) async {
    final matches = _jobs
        .where(
          (job) =>
              ContentIdentity.canonical(job.manga.url) ==
                  ContentIdentity.canonical(ref) ||
              job.folderPath == ref ||
              (job.destinationRoot != null &&
                  storage.mangaFolder(job.destinationRoot!, job.manga).path ==
                      ref),
        )
        .toList();
    for (final job in matches) {
      pauseJob(job.id);
    }
    while (matches.any((job) => _tokens.containsKey(job.id))) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    await flush();
  }

  Future<void> migrateJobDestination(String id, String root) async {
    final job = _find(id);
    if (job == null) return;
    await pauseForManga(job.manga.url);
    final oldRoot = job.destinationRoot;
    if (oldRoot == null) {
      throw const AppFailure(
        FailureKind.storage,
        'La descarga no tiene un origen.',
      );
    }
    final target = storage.mangaFolder(root, job.manga);
    await StorageTransfer.copyVerified(
      storage.mangaFolder(oldRoot, job.manga),
      target,
    );
    job.destinationRoot = root;
    job.folderPath = target.path;
    final paths = await PreferencesService.getLibraryPaths();
    if (!paths.contains(target.parent.path)) {
      await PreferencesService.setLibraryPaths([...paths, target.parent.path]);
    }
    _changed();
    await flush();
    DownloadEvents.completed(target.path);
  }

  Future<void> setDownloadThreads(int value) async {
    _threads = value.clamp(1, 8);
    await PreferencesService.setDownloadThreads(_threads);
    _changed();
  }

  Future<void> setSpeedLimitKbps(int value) async {
    _limit = value < 0 ? 0 : value;
    _limiter.updateLimit(_limit * 1024);
    await PreferencesService.setDownloadSpeedLimitKbps(_limit);
    _changed();
  }

  Future<void> _process() async {
    if (_running || _disposed) return;
    _running = true;
    try {
      while (!_disposed) {
        final candidates = _jobs
            .where((j) => j.status == DownloadJobStatus.queued)
            .toList();
        if (candidates.isEmpty) break;
        await _run(candidates.first);
      }
    } finally {
      _running = false;
      _activeJobId = null;
      _changed();
      _scheduleRetry();
    }
  }

  Future<void> _run(DownloadJob job) async {
    final token = CancellationToken();
    _tokens[job.id] = token;
    _activeJobId = job.id;
    final clock = Stopwatch()..start();
    final initialBytes = job.receivedBytes;
    job.bytesPerSecond = 0;
    job.status = DownloadJobStatus.downloading;
    job.paused = false;
    job.error = null;
    job.startedAt ??= DateTime.now();
    _changed();
    try {
      if (!await canDownload(_wifiOnly) ||
          (job.automatic &&
              !MaintenancePlatform.allowed(
                await AutomationSettings.load(),
                await MaintenancePlatform.conditions(),
              ))) {
        job.status = DownloadJobStatus.paused;
        job.paused = true;
        job.automaticRetry = true;
        job.error = _wifiOnly
            ? 'Esperando conexión WiFi.'
            : 'Esperando conexión a internet.';
        return;
      }
      final root = job.destinationRoot;
      if (root == null) {
        throw const AppFailure(
          FailureKind.storage,
          'No hay carpeta de destino.',
        );
      }
      final folder = storage.mangaFolder(root, job.manga);
      job.folderPath = folder.path;
      await storage.saveManga(folder, job.manga);
      await MangaStoragePaths.ensureNoMedia(folder.parent);
      await PreferencesService.setMangaSourceLink(folder.path, job.manga.url);
      token.check();
      await _cover(folder, job, token);
      job.completedChapterIndexes.clear();
      job.completedChapters = 0;
      job.completedPages = 0;
      for (final index in job.chapterIndexesToDownload) {
        token.check();
        if (!await canDownload(_wifiOnly)) {
          job.status = DownloadJobStatus.paused;
          job.paused = true;
          job.automaticRetry = true;
          job.error = 'Esperando conexión de red permitida.';
          return;
        }
        final chapter = job.manga.chapters[index];
        job.currentChapterIndex = index;
        job.currentChapter = chapter.title;
        final chapterFolder = storage.chapterFolder(folder, chapter);
        // También contabilizar páginas parciales de trabajos interrumpidos.
        if (job.automatic) {
          await MaintenanceService.rememberAutomatic(
            chapterFolder.path,
            chapter.path,
          );
        }
        final cached = await DownloadStorage.readJson(
          File('${chapterFolder.path}/${DownloadStorage.chapterManifest}'),
        );
        final cachedPages = (cached?['pages'] as List?)?.cast<String>();
        var pages = chapter.pages;
        if (pages.isEmpty &&
            cached?['complete'] == true &&
            cachedPages != null &&
            cachedPages.isNotEmpty) {
          final cachedVerified = await storage.verifiedPages(
            chapterFolder,
            cachedPages,
          );
          if (cachedVerified.length == cachedPages.length) pages = cachedPages;
        }
        if (pages.isEmpty) {
          pages = await SourceHttpClient.withCancellation(
            token,
            () => fetchPages(chapter.path),
          );
        }
        token.check();
        if (pages.isEmpty) {
          throw const AppFailure(
            FailureKind.parsing,
            'El capítulo no tiene páginas disponibles.',
          );
        }
        var verified = await storage.verifiedPages(chapterFolder, pages);
        job.chapterPageCounts[index] = pages.length;
        job.totalPages = job.chapterPageCounts.values.fold(0, (a, b) => a + b);
        job.completedPages += verified.length;
        await storage.saveChapter(
          chapterFolder,
          chapter,
          index,
          pages,
          complete: false,
        );
        final pending = [
          for (var i = 0; i < pages.length; i++)
            if (!verified.contains(i)) i,
        ];
        var next = 0;
        Object? failure;
        Future<void> worker() async {
          while (next < pending.length &&
              failure == null &&
              !token.isCancelled) {
            while (readerActive &&
                _pageWorkers >= 2 &&
                !token.isCancelled &&
                failure == null) {
              await Future<void>.delayed(const Duration(milliseconds: 50));
            }
            if (token.isCancelled ||
                failure != null ||
                next >= pending.length) {
              break;
            }
            final page = pending[next++];
            _pageWorkers++;
            try {
              if (job.automatic &&
                  !MaintenancePlatform.allowed(
                    await AutomationSettings.load(),
                    await MaintenancePlatform.conditions(),
                  )) {
                job.status = DownloadJobStatus.paused;
                job.paused = true;
                job.automaticRetry = true;
                token.cancel();
                return;
              }
              final file = storage.pageFile(chapterFolder, page);
              await images.download(
                pages[page],
                file,
                headers: {
                  ...?OnlineCatalogService.imageRequestHeaders(pages[page]),
                  'Referer': chapter.path,
                },
                cancellation: token,
                limiter: _limiter,
                onBytes: (bytes) {
                  if (job.maxBytes != null &&
                      job.receivedBytes + bytes > job.maxBytes!) {
                    throw const AppFailure(
                      FailureKind.storage,
                      'Se alcanzó el límite de espacio para descargas automáticas.',
                    );
                  }
                  job.receivedBytes += bytes;
                  if (clock.elapsedMilliseconds > 250) {
                    job.bytesPerSecond =
                        (job.receivedBytes - initialBytes) *
                        1000 /
                        clock.elapsedMilliseconds;
                  }
                  _progressChanged();
                },
              );
              token.check();
              verified.add(page);
              job.completedPages++;
              images.registerOffline(pages[page], file.path);
              job.currentPageIndex = 0;
              while (verified.contains(job.currentPageIndex)) {
                job.currentPageIndex++;
              }
              job.lastProgressAt = DateTime.now();
              _progressChanged();
            } catch (error) {
              failure ??= error;
            } finally {
              _pageWorkers--;
            }
          }
        }

        final workers = <Future<void>>[];
        for (var i = 0; i < _threads.clamp(1, 8) && i < pending.length; i++) {
          workers.add(worker());
        }
        await Future.wait(workers);
        token.check();
        if (failure != null) throw failure!;
        verified = await storage.verifiedPages(chapterFolder, pages);
        if (verified.length != pages.length) {
          throw const AppFailure(
            FailureKind.parsing,
            'Faltan páginas por verificar.',
          );
        }
        await storage.saveChapter(
          chapterFolder,
          chapter,
          index,
          pages,
          complete: true,
        );
        job.completedChapterIndexes.add(index);
        job.completedChapters = job.completedChapterIndexes.length;
        job.currentPageIndex = 0;
        job.automaticRetry = false;
        DownloadEvents.completed(folder.path);
        _changed();
        unawaited(_notifyProgress(job));
      }
      token.check();
      job.status = DownloadJobStatus.completed;
      _archiveJob(job, 'Descargada');
      unawaited(
        DownloadNotificationService.showCompleted(
          jobId: job.id,
          title: job.manga.title,
          coverUrl: job.manga.coverUrl,
        ),
      );
    } catch (error, stack) {
      if (!token.isCancelled) {
        final failure = AppFailure.from(error);
        unawaited(Diagnostics.record('download', failure));
        job.status = DownloadJobStatus.failed;
        job.paused = false;
        job.error = failure.message;
        job.retryCount++;
        job.automaticRetry = failure.retryable && job.retryCount <= 5;
        final delay =
            failure.retryAfter ??
            Duration(
              seconds:
                  (5 * (1 << job.retryCount.clamp(0, 7))) +
                  job.id.hashCode.abs() % 5,
            );
        job.retryAt = DateTime.now().add(
          delay < Duration.zero ? Duration.zero : delay,
        );
        debugPrint('Descarga ${job.id}: $error\n$stack');
        unawaited(
          DownloadNotificationService.showFailed(
            jobId: job.id,
            title: job.manga.title,
            error: job.error,
          ),
        );
      }
    } finally {
      _tokens.remove(job.id);
      _activeJobId = null;
      if (job.status != DownloadJobStatus.completed && job.folderPath != null) {
        DownloadEvents.completed(job.folderPath!);
      }
      if (job.status == DownloadJobStatus.stopped) {
        _archiveJob(job, 'Detenida manualmente');
      }
      _changed();
      await _persist();
    }
  }

  Future<void> _cover(
    Directory folder,
    DownloadJob job,
    CancellationToken token,
  ) async {
    final url = job.manga.coverUrl;
    if (url == null) return;
    final file = File('${folder.path}/cover.image');
    if (await ImageRepository.valid(file)) return;
    try {
      await images.download(
        url,
        file,
        headers: {
          ...?OnlineCatalogService.imageRequestHeaders(url),
          'Referer': job.manga.url,
        },
        cancellation: token,
        limiter: _limiter,
      );
    } catch (error) {
      token.check();
      debugPrint('Portada opcional: $error');
    }
  }

  Future<void> _notifyProgress(DownloadJob job) =>
      DownloadNotificationService.showProgress(
        jobId: job.id,
        title: job.manga.title,
        completedChapters: job.completedChapters,
        totalChapters: job.totalChapters,
        chapter: job.currentChapter,
        coverUrl: job.manga.coverUrl,
      );
  void _archiveJob(DownloadJob job, String reason) {
    if (!_jobs.contains(job)) return;
    final indexes = job.chapterIndexesToDownload;
    final confirmed = indexes
        .where(job.completedChapterIndexes.contains)
        .toList();
    final from = indexes.isEmpty ? null : indexes.first;
    final to = confirmed.isNotEmpty ? confirmed.last : from;
    _archive.removeWhere((e) => e.id == job.id);
    _archive.insert(
      0,
      DownloadArchiveEntry(
        id: job.id,
        title: job.manga.title,
        coverUrl: job.manga.coverUrl,
        reason: reason,
        completedTitles: confirmed
            .map((i) => job.manga.chapters[i].title)
            .toList(),
        chapterFrom: from == null ? '—' : job.manga.chapters[from].title,
        chapterTo: to == null ? '—' : job.manga.chapters[to].title,
        completedChapters: job.completedChapterIndexes.length,
        completedPages: job.completedPages,
        totalPages: job.totalPages,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      ),
    );
    _jobs.remove(job);
    _changed();
    _saveArchiveSnapshot();
  }

  void clearArchive() {
    _archive.clear();
    _saveArchive();
  }

  void removeArchiveEntry(String id) {
    _archive.removeWhere((e) => e.id == id);
    _saveArchive();
  }

  void _saveArchive() {
    _changed();
    _saveArchiveSnapshot();
  }

  void _saveArchiveSnapshot() {
    final snapshot = _archive.map((e) => e.toMap()).toList();
    _persisting = _persisting
        .then((_) => persistence.writeArchive(snapshot))
        .catchError((Object error) {
          persistenceError = 'No se pudo guardar el historial: $error';
          if (!_disposed) notifyListeners();
        });
  }

  Future<void> checkForRetryableJobs() async {
    if (_disposed || !await canDownload(_wifiOnly)) return;
    final now = DateTime.now();
    for (final job in _jobs) {
      if (job.automaticRetry &&
          (job.retryAt == null || !now.isBefore(job.retryAt!))) {
        if (job.automatic &&
            !MaintenancePlatform.allowed(
              await AutomationSettings.load(),
              await MaintenancePlatform.conditions(),
            )) {
          continue;
        }
        job.status = DownloadJobStatus.queued;
        job.paused = false;
        job.automaticRetry = false;
        job.error = null;
      }
    }
    _changed();
    unawaited(_process());
    _scheduleRetry();
  }

  void _scheduleRetry() {
    _retryTimer?.cancel();
    _retryTimer = null;
    if (_disposed) return;
    final retry = _jobs.where((j) => j.automaticRetry).toList();
    if (retry.isEmpty) return;
    var delay = const Duration(minutes: 1);
    for (final job in retry) {
      final until =
          job.retryAt?.difference(DateTime.now()) ??
          const Duration(seconds: 30);
      if (until < delay) delay = until;
    }
    if (delay < const Duration(seconds: 2)) delay = const Duration(seconds: 2);
    _retryTimer = Timer(delay, () => unawaited(checkForRetryableJobs()));
  }

  void _progressChanged() {
    if (_disposed) return;
    _notifyTimer ??= Timer(const Duration(milliseconds: 200), () {
      _notifyTimer = null;
      if (!_disposed) notifyListeners();
    });
    _persistTimer ??= Timer(const Duration(seconds: 1), () {
      _persistTimer = null;
      unawaited(_persist());
    });
  }

  void _changed() {
    if (_disposed) return;
    revision++;
    notifyListeners();
    unawaited(_persist());
  }

  Future<void> _persist() {
    final snapshot = _jobs.map((j) => j.toMap()).toList();
    final next = _persisting.then((_) => persistence.writeJobs(snapshot));
    _persisting = next.catchError((Object error, StackTrace stack) {
      persistenceError = 'No se pudo guardar la cola: $error';
      debugPrint('$persistenceError\n$stack');
      if (!_disposed) notifyListeners();
    });
    return _persisting;
  }

  Future<void> flush() {
    _persistTimer?.cancel();
    _persistTimer = null;
    return _persist();
  }

  Future<void> waitForIdle() async {
    while (_running) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    await _persisting;
  }

  @override
  void dispose() {
    _disposed = true;
    _retryTimer?.cancel();
    _notifyTimer?.cancel();
    _persistTimer?.cancel();
    for (final token in _tokens.values) {
      token.cancel();
    }
    unawaited(_networkSubscription?.cancel());
    super.dispose();
  }
}
