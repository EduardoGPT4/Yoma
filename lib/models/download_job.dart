import 'chapter.dart';
import 'online_manga.dart';

enum DownloadJobStatus {
  queued,
  downloading,
  paused,
  completed,
  stopped,
  failed,
}

class DownloadJob {
  final bool automatic;
  final int? maxBytes;
  String? destinationRoot;
  final Set<int> completedChapterIndexes;
  final Map<int, int> chapterPageCounts;
  int receivedBytes;
  double bytesPerSecond = 0;
  int retryCount;
  bool automaticRetry;
  DateTime? retryAt;
  String? folderPath;
  final String id;
  final OnlineMangaDetail manga;

  /// Si no es null, solo se descargan estos índices de capítulo.
  final Set<int>? chapterIndexes;
  DownloadJobStatus status;
  bool paused;
  bool stopped;
  int completedChapters;
  int completedPages;
  int totalPages;
  int currentChapterIndex;
  int currentPageIndex;
  final Set<int> countedChapterIndexes;
  bool pausedByLifecycle;
  String? currentChapter;
  String? error;
  DateTime? startedAt;
  DateTime? lastProgressAt;

  DownloadJob({
    this.automatic = false,
    this.maxBytes,
    this.destinationRoot,
    Set<int>? completedChapterIndexes,
    Map<int, int>? chapterPageCounts,
    this.receivedBytes = 0,
    this.retryCount = 0,
    this.automaticRetry = false,
    this.retryAt,
    this.folderPath,
    required this.id,
    required this.manga,
    this.chapterIndexes,
    this.status = DownloadJobStatus.queued,
    this.paused = false,
    this.stopped = false,
    this.completedChapters = 0,
    this.completedPages = 0,
    this.totalPages = 0,
    this.currentChapterIndex = 0,
    this.currentPageIndex = 0,
    Set<int>? countedChapterIndexes,
    this.pausedByLifecycle = false,
    this.currentChapter,
    this.error,
    this.startedAt,
    this.lastProgressAt,
  }) : countedChapterIndexes = countedChapterIndexes ?? <int>{},
       completedChapterIndexes = completedChapterIndexes ?? <int>{},
       chapterPageCounts = chapterPageCounts ?? <int, int>{};

  /// Total de capítulos a descargar en este job (puede ser un subconjunto).
  int get totalChapters => chapterIndexesToDownload.length;

  int get pendingChapters =>
      (totalChapters - completedChapters).clamp(0, totalChapters);

  /// Progreso por capítulos completados (no por páginas del capítulo actual).
  double get progress {
    final total = totalChapters;
    if (total <= 0) {
      return 0.0;
    }
    return (completedChapters.clamp(0, total)) / total;
  }

  List<int> get chapterIndexesToDownload {
    if (chapterIndexes == null) {
      return List<int>.generate(manga.chapters.length, (i) => i);
    }
    final sorted =
        chapterIndexes!
            .where((i) => i >= 0 && i < manga.chapters.length)
            .toList()
          ..sort();
    return sorted;
  }

  String? get etaLabel {
    if (status != DownloadJobStatus.downloading ||
        startedAt == null ||
        completedChapters <= 0 ||
        totalChapters <= completedChapters) {
      return null;
    }
    final elapsed = DateTime.now().difference(startedAt!).inMilliseconds;
    if (elapsed < 500) {
      return null;
    }
    final perChapter = elapsed / completedChapters;
    final remaining = ((totalChapters - completedChapters) * perChapter)
        .round();
    final seconds = (remaining / 1000).ceil();
    if (seconds < 60) {
      return '~${seconds}s';
    }
    final minutes = (seconds / 60).ceil();
    return '~${minutes}m';
  }

  Map<String, dynamic> toMap({bool includeManga = true}) {
    return {
      'automatic': automatic,
      'maxBytes': maxBytes,
      'destinationRoot': destinationRoot,
      'folderPath': folderPath,
      'completedChapterIndexes': completedChapterIndexes.toList(),
      'chapterPageCounts': chapterPageCounts.map(
        (key, value) => MapEntry('$key', value),
      ),
      'receivedBytes': receivedBytes,
      'bytesPerSecond': bytesPerSecond,
      'retryCount': retryCount,
      'automaticRetry': automaticRetry,
      'retryAt': retryAt?.millisecondsSinceEpoch,
      'id': id,
      if (includeManga) 'manga': manga.toMap(),
      'chapterIndexes': chapterIndexes?.toList(),
      'status': status.name,
      'paused': paused,
      'stopped': stopped,
      'completedChapters': completedChapters,
      'completedPages': completedPages,
      'totalPages': totalPages,
      'currentChapterIndex': currentChapterIndex,
      'currentPageIndex': currentPageIndex,
      'countedChapterIndexes': countedChapterIndexes.toList(),
      'pausedByLifecycle': pausedByLifecycle,
      'currentChapter': currentChapter,
      'error': error,
      'startedAt': startedAt?.millisecondsSinceEpoch,
      'lastProgressAt': lastProgressAt?.millisecondsSinceEpoch,
    };
  }

  factory DownloadJob.fromMap(Map<String, dynamic> map) {
    final mangaMap = map['manga'];
    final chapterIndexesRaw = map['chapterIndexes'] as List<dynamic>?;
    final job = DownloadJob(
      automatic: map['automatic'] == true,
      maxBytes: map['maxBytes'] as int?,
      destinationRoot: map['destinationRoot'] as String?,
      folderPath: map['folderPath'] as String?,
      completedChapterIndexes: (map['completedChapterIndexes'] as List?)
          ?.cast<int>()
          .toSet(),
      chapterPageCounts: (map['chapterPageCounts'] as Map?)?.map(
        (k, v) => MapEntry(int.parse('$k'), v as int),
      ),
      receivedBytes: map['receivedBytes'] as int? ?? 0,
      retryCount: map['retryCount'] as int? ?? 0,
      automaticRetry: map['automaticRetry'] as bool? ?? false,
      retryAt: map['retryAt'] is int
          ? DateTime.fromMillisecondsSinceEpoch(map['retryAt'] as int)
          : null,
      id: map['id'] as String? ?? '',
      manga: mangaMap is Map
          ? OnlineMangaDetail.fromMap(Map<String, dynamic>.from(mangaMap))
          : const OnlineMangaDetail(title: '', url: '', chapters: <Chapter>[]),
      chapterIndexes: chapterIndexesRaw
          ?.map((e) => int.tryParse('$e'))
          .whereType<int>()
          .toSet(),
      status: DownloadJobStatus.values.firstWhere(
        (value) => value.name == map['status'],
        orElse: () => DownloadJobStatus.queued,
      ),
      paused: map['paused'] as bool? ?? false,
      stopped: map['stopped'] as bool? ?? false,
      completedChapters: map['completedChapters'] as int? ?? 0,
      completedPages: map['completedPages'] as int? ?? 0,
      totalPages: map['totalPages'] as int? ?? 0,
      currentChapterIndex: map['currentChapterIndex'] as int? ?? 0,
      currentPageIndex: map['currentPageIndex'] as int? ?? 0,
      countedChapterIndexes:
          (map['countedChapterIndexes'] as List<dynamic>?)
              ?.whereType<int>()
              .toSet() ??
          <int>{},
      pausedByLifecycle: map['pausedByLifecycle'] as bool? ?? false,
      currentChapter: map['currentChapter'] as String?,
      error: map['error'] as String?,
      startedAt: map['startedAt'] is int
          ? DateTime.fromMillisecondsSinceEpoch(map['startedAt'] as int)
          : null,
      lastProgressAt: map['lastProgressAt'] is int
          ? DateTime.fromMillisecondsSinceEpoch(map['lastProgressAt'] as int)
          : null,
    );
    job.bytesPerSecond = (map['bytesPerSecond'] as num?)?.toDouble() ?? 0;
    return job;
  }
}

class DownloadArchiveEntry {
  final List<String> completedTitles;
  final String id;
  final String title;
  final String? coverUrl;
  final String reason;
  final String chapterFrom;
  final String chapterTo;
  final int completedChapters;
  final int completedPages;
  final int totalPages;
  final int updatedAt;

  const DownloadArchiveEntry({
    this.completedTitles = const [],
    required this.id,
    required this.title,
    required this.reason,
    required this.chapterFrom,
    required this.chapterTo,
    required this.completedChapters,
    required this.completedPages,
    required this.totalPages,
    required this.updatedAt,
    this.coverUrl,
  });

  /// Resumen; la lista completa se consulta en el detalle del historial.
  String get rangeLabel {
    if (completedTitles.isEmpty) return 'Sin detalle de capítulos';
    if (completedTitles.length == 1) return completedTitles.first;
    return '${completedTitles.first} … ${completedTitles.last}';
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'coverUrl': coverUrl,
      'reason': reason,
      'completedTitles': completedTitles,
      'chapterFrom': chapterFrom,
      'chapterTo': chapterTo,
      'completedChapters': completedChapters,
      'completedPages': completedPages,
      'totalPages': totalPages,
      'updatedAt': updatedAt,
    };
  }

  factory DownloadArchiveEntry.fromMap(Map<String, dynamic> map) {
    return DownloadArchiveEntry(
      id: map['id'] as String? ?? '',
      title: map['title'] as String? ?? '',
      coverUrl: map['coverUrl'] as String?,
      reason: map['reason'] as String? ?? 'descargado',
      completedTitles: (map['completedTitles'] as List?)?.cast<String>() ?? [],
      chapterFrom: map['chapterFrom'] as String? ?? 'capitulo 1',
      chapterTo: map['chapterTo'] as String? ?? 'capitulo 1',
      completedChapters: map['completedChapters'] as int? ?? 0,
      completedPages: map['completedPages'] as int? ?? 0,
      totalPages: map['totalPages'] as int? ?? 0,
      updatedAt: map['updatedAt'] as int? ?? 0,
    );
  }
}
