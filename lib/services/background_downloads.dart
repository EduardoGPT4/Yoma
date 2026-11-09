import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../data/library_store.dart';
import '../models/online_manga.dart';
import '../utils/preferences.dart';
import 'download_engine.dart';
import 'download_events.dart';
import 'mangadex_service.dart';
import 'maintenance_service.dart';
import 'diagnostics.dart';

/// Ejecutado en el FlutterEngine del servicio, independiente de la Activity.
Future<void> runDownloadHost() async {
  try {
    await _runDownloadHost();
  } catch (error, stack) {
    const channel = MethodChannel('app.yomashi.reader/download_host');
    channel.setMethodCallHandler(
      (_) async => throw PlatformException(
        code: 'DOWNLOAD_INIT',
        message: error.toString(),
      ),
    );
    await channel.invokeMethod<void>('ready', {
      'jobs': [],
      'archive': [],
      'runnable': false,
      'error': error.toString(),
    });
    debugPrint('Servicio de descargas: $error\n$stack');
  }
}

Future<void> _runDownloadHost() async {
  WidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('app.yomashi.reader/download_host');
  await LibraryStore.initialize();
  final prefs = await SharedPreferences.getInstance();
  MangaDexService.setPreferredLanguages(
    await PreferencesService.getMangaDexLanguages(),
  );
  MangaDexService.dataSaver = prefs.getBool('mangadex_data_saver') ?? false;
  final engine = DownloadEngine();
  var maintenanceRunning = false;
  Map<String, dynamic> snapshot() => {
    'jobs': engine.jobs.map((e) => e.toMap()).toList(),
    'archive': engine.archive.map((e) => e.toMap()).toList(),
    'root': engine.downloadRoot,
    'wifi': engine.wifiOnlyDownloads,
    'threads': engine.downloadThreads,
    'limit': engine.speedLimitKbps,
    'active': engine.activeJobId,
    'error': engine.persistenceError,
    'runnable': engine.hasRunnableWork || maintenanceRunning,
    'maintenance': maintenanceRunning,
  };
  var revision = -1;
  engine.addListener(() {
    final full = revision != engine.revision;
    revision = engine.revision;
    final value = full
        ? snapshot()
        : {
            'jobs': engine.jobs
                .map((e) => e.toMap(includeManga: false))
                .toList(),
            'active': engine.activeJobId,
            'runnable': engine.hasRunnableWork || maintenanceRunning,
          };
    unawaited(
      channel
          .invokeMethod<void>(full ? 'state' : 'progress', value)
          .catchError((_) {}),
    );
  });
  DownloadEvents.completedFolders.listen((folder) {
    unawaited(
      channel.invokeMethod<void>('completed', folder).catchError((_) {}),
    );
  });
  Future<void> commands = Future.value();
  channel.setMethodCallHandler((call) async {
    final result = Completer<Map<String, dynamic>>();
    commands = commands.then((_) async {
      try {
        final args = Map<String, dynamic>.from(call.arguments as Map? ?? {});
        final id = args['id'] as String? ?? '';
        switch (call.method) {
          case 'repair':
            await engine.repair(args['folder'] as String);
          case 'reader':
            engine.setReaderActive(args['active'] == true);
          case 'maintenance':
          case 'ahead':
            if (!maintenanceRunning) {
              maintenanceRunning = true;
              final work = call.method == 'ahead'
                  ? MaintenanceService(
                      engine,
                    ).ahead(args['manga'] as String, args['chapter'] as String)
                  : MaintenanceService(
                      engine,
                    ).run(manual: args['manual'] == true);
              unawaited(
                work
                    .catchError((Object e) async {
                      await Diagnostics.record('maintenance', e);
                    })
                    .whenComplete(() async {
                      maintenanceRunning = false;
                      await channel
                          .invokeMethod<void>('state', snapshot())
                          .catchError((_) {});
                    }),
              );
            }
          case 'snapshot':
            break;
          case 'migrate':
            await engine.migrateJobDestination(id, args['root'] as String);
          case 'enqueue':
            await prefs.reload();
            MangaDexService.setPreferredLanguages(
              await PreferencesService.getMangaDexLanguages(),
            );
            MangaDexService.dataSaver =
                prefs.getBool('mangadex_data_saver') ?? false;
            await engine.enqueueManga(
              OnlineMangaDetail.fromMap(
                Map<String, dynamic>.from(args['manga'] as Map),
              ),
              chapterIndexes: (args['chapters'] as List?)?.cast<int>().toSet(),
            );
          case 'pauseManga':
            await engine.pauseForManga(args['ref'] as String);
          case 'pause':
            engine.pauseJob(id);
          case 'resume':
            engine.resumeJob(id);
          case 'stop':
            engine.stopJob(id);
          case 'up':
            engine.moveJobUp(id);
          case 'down':
            engine.moveJobDown(id);
          case 'prioritize':
            engine.prioritizeJob(id);
          case 'clearArchive':
            engine.clearArchive();
          case 'removeArchive':
            engine.removeArchiveEntry(id);
          case 'root':
            await engine.setDownloadRoot(args['root'] as String);
          case 'wifi':
            await engine.setWifiOnlyDownloads(args['value'] as bool);
          case 'threads':
            await engine.setDownloadThreads(args['value'] as int);
          case 'limit':
            await engine.setSpeedLimitKbps(args['value'] as int);
          case 'retry':
            await engine.checkForRetryableJobs();
          case 'pauseAll':
            for (final job in engine.jobs) {
              engine.pauseJob(job.id);
            }
          case 'shutdown':
            for (final job in engine.jobs) {
              engine.pauseJob(job.id);
            }
            await engine.waitForIdle();
          default:
            throw MissingPluginException(
              'Comando no compatible: ${call.method}',
            );
        }
        await engine.flush();
        result.complete(snapshot());
      } catch (error, stack) {
        result.completeError(error, stack);
      }
    });
    return result.future;
  });
  await engine.load();
  await channel.invokeMethod<void>('ready', snapshot());
}
