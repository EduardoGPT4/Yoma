import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import '../models/download_job.dart';
import '../models/online_manga.dart';
import '../services/download_engine.dart';
import '../services/download_events.dart';
import '../services/maintenance_service.dart';
export '../models/download_job.dart';

/// En Android, el servicio posee el único motor. La UI observa instantáneas.
class DownloadQueueProvider extends ChangeNotifier {
  static const _channel = MethodChannel('app.yomashi.reader/downloads');
  late final DownloadEngine? _local;
  Map<String, dynamic> _state = {};
  List<DownloadJob> _jobs = [];
  List<DownloadArchiveEntry> _archive = [];
  bool _disposed = false;
  String? _error;
  DownloadQueueProvider({
    DownloadPersistence? persistence,
    Future<List<String>> Function(String)? fetchPages,
    Future<bool> Function(bool)? canDownload,
    bool? useNative,
  }) {
    _local =
        (useNative ?? Platform.isAndroid) &&
            persistence == null &&
            fetchPages == null &&
            canDownload == null
        ? null
        : DownloadEngine(
            persistence: persistence,
            fetchPages: fetchPages,
            canDownload: canDownload,
          );
    _local?.addListener(_localChanged);
  }
  void _localChanged() {
    if (!_disposed) notifyListeners();
  }

  List<DownloadJob> get jobs => _local?.jobs ?? List.unmodifiable(_jobs);
  List<DownloadArchiveEntry> get archive =>
      _local?.archive ?? List.unmodifiable(_archive);
  String? get downloadRoot => _local?.downloadRoot ?? _state['root'] as String?;
  String? get downloadFolderPath =>
      downloadRoot == null ? null : Directory('${downloadRoot!}/Manga').path;
  String? get activeJobId => _local?.activeJobId ?? _state['active'] as String?;
  bool get wifiOnlyDownloads =>
      _local?.wifiOnlyDownloads ?? (_state['wifi'] as bool? ?? false);
  int get downloadThreads =>
      _local?.downloadThreads ?? (_state['threads'] as int? ?? 4);
  int get speedLimitKbps =>
      _local?.speedLimitKbps ?? (_state['limit'] as int? ?? 0);
  String? get persistenceError =>
      _local?.persistenceError ?? _error ?? _state['error'] as String?;
  void _apply(Map<dynamic, dynamic> state) {
    if (_disposed) return;
    _state = Map<String, dynamic>.from(state);
    _jobs = (_state['jobs'] as List? ?? [])
        .whereType<Map>()
        .map((e) => DownloadJob.fromMap(Map<String, dynamic>.from(e)))
        .toList();
    _archive = (_state['archive'] as List? ?? [])
        .whereType<Map>()
        .map((e) => DownloadArchiveEntry.fromMap(Map<String, dynamic>.from(e)))
        .toList();
    _error = null;
    notifyListeners();
  }

  Future<void> _command(
    String method, [
    Map<String, dynamic> args = const {},
  ]) async {
    try {
      final state = await _channel
          .invokeMapMethod<dynamic, dynamic>(method, args)
          .timeout(
            method == 'migrate'
                ? const Duration(minutes: 30)
                : const Duration(seconds: 45),
          );
      if (state != null) _apply(state);
    } catch (error) {
      _error = 'No se pudo actualizar la cola: $error';
      if (!_disposed) notifyListeners();
      rethrow;
    }
  }

  void _send(String method, [Map<String, dynamic> args = const {}]) {
    unawaited(_command(method, args).catchError((_) {}));
  }

  Future<void> load() async {
    if (_local != null) {
      try {
        await _local.load();
      } catch (error) {
        _error = error.toString();
        notifyListeners();
      }
      return;
    }
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'state' && call.arguments is Map) {
        _apply(call.arguments as Map);
      }
      if (call.method == 'progress' && call.arguments is Map) {
        final delta = Map<String, dynamic>.from(call.arguments as Map);
        final old = {
          for (final raw in _state['jobs'] as List? ?? [])
            (raw as Map)['id']: raw,
        };
        final jobs = [
          for (final raw in delta['jobs'] as List? ?? [])
            if (old[(raw as Map)['id']] != null)
              {...old[raw['id']] as Map, ...raw},
        ];
        _apply({..._state, ...delta, 'jobs': jobs});
      }
      if (call.method == 'completed' && call.arguments is String) {
        DownloadEvents.completed(call.arguments as String);
      }
    });
    try {
      await _command('snapshot');
    } catch (_) {}
  }

  Future<void> chooseJobDestination(String id) async {
    final root = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Copiar descarga (se conserva el origen)',
    );
    if (root == null) return;
    if (_local != null) {
      await _local.migrateJobDestination(id, root);
      return;
    }
    await _command('migrate', {'id': id, 'root': root});
  }

  Future<bool> chooseDownloadRoot() async {
    if (_local != null) return _local.chooseDownloadRoot();
    final root = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Carpeta de descargas',
    );
    if (root == null) return false;
    await _command('root', {'root': root});
    return true;
  }

  Future<void> applyDefaultDownloadRoot(String root) async {
    if (_local != null) {
      await _local.applyDefaultDownloadRoot(root);
      return;
    }
    if (downloadRoot == null) await _command('root', {'root': root});
  }

  Future<void> enqueueManga(
    OnlineMangaDetail manga, {
    Set<int>? chapterIndexes,
  }) async {
    if (_local != null) {
      await _local.enqueueManga(manga, chapterIndexes: chapterIndexes);
      return;
    }
    await _command('enqueue', {
      'manga': manga.toMap(),
      'chapters': chapterIndexes?.toList(),
    });
  }

  void pauseJob(String id) {
    if (_local != null) {
      _local.pauseJob(id);
    } else {
      _send('pause', {'id': id});
    }
  }

  void resumeJob(String id) {
    if (_local != null) {
      _local.resumeJob(id);
    } else {
      _send('resume', {'id': id});
    }
  }

  void stopJob(String id) {
    if (_local != null) {
      _local.stopJob(id);
    } else {
      _send('stop', {'id': id});
    }
  }

  void moveJobUp(String id) {
    if (_local != null) {
      _local.moveJobUp(id);
    } else {
      _send('up', {'id': id});
    }
  }

  void moveJobDown(String id) {
    if (_local != null) {
      _local.moveJobDown(id);
    } else {
      _send('down', {'id': id});
    }
  }

  void prioritizeJob(String id) {
    if (_local != null) {
      _local.prioritizeJob(id);
    } else {
      _send('prioritize', {'id': id});
    }
  }

  bool canMoveUp(String id) => jobs.indexWhere((e) => e.id == id) > 0;
  bool canMoveDown(String id) {
    final i = jobs.indexWhere((e) => e.id == id);
    return i >= 0 && i < jobs.length - 1;
  }

  void clearArchive() {
    if (_local != null) {
      _local.clearArchive();
    } else {
      _send('clearArchive');
    }
  }

  void removeArchiveEntry(String id) {
    if (_local != null) {
      _local.removeArchiveEntry(id);
    } else {
      _send('removeArchive', {'id': id});
    }
  }

  Future<void> setWifiOnlyDownloads(bool value) =>
      _local?.setWifiOnlyDownloads(value) ?? _command('wifi', {'value': value});
  Future<void> setDownloadThreads(int value) =>
      _local?.setDownloadThreads(value) ??
      _command('threads', {'value': value});
  Future<void> setSpeedLimitKbps(int value) =>
      _local?.setSpeedLimitKbps(value) ?? _command('limit', {'value': value});
  Future<void> pauseForManga(String ref) =>
      _local?.pauseForManga(ref) ?? _command('pauseManga', {'ref': ref});
  Future<void> checkForRetryableJobs() =>
      _local?.checkForRetryableJobs() ?? _command('retry');
  Future<void> repair(String folder) =>
      _local?.repair(folder) ?? _command('repair', {'folder': folder});
  Future<void> runMaintenance({bool manual = false}) => _local != null
      ? MaintenanceService(_local).run(manual: manual)
      : _command('maintenance', {'manual': manual});
  Future<void> prepareAhead(String manga, String chapter) => _local != null
      ? MaintenanceService(_local).ahead(manga, chapter)
      : _command('ahead', {'manga': manga, 'chapter': chapter});
  void setReaderActive(bool active) {
    if (_local != null) {
      _local.setReaderActive(active);
    } else {
      _send('reader', {'active': active});
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _local?.removeListener(_localChanged);
    _local?.dispose();
    if (_local == null) _channel.setMethodCallHandler(null);
    super.dispose();
  }
}
