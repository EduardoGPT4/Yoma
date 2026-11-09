import 'dart:io';
import 'package:flutter/services.dart';
import '../data/library_store.dart';
import '../models/automation_settings.dart';
import '../models/online_manga.dart';
import '../models/content_identity.dart';
import '../utils/preferences.dart';
import 'download_engine.dart';
import 'online_catalog_service.dart';
import 'rotating_backup_service.dart';
import 'diagnostics.dart';
import 'myanimelist_service.dart';

class MaintenancePlatform {
  static const channel = MethodChannel('app.yomashi.reader/maintenance');
  static Future<Map<String, dynamic>> conditions() async {
    if (!Platform.isAndroid) {
      return {
        'connected': true,
        'wifi': true,
        'charging': true,
        'battery': 100,
      };
    }
    return Map<String, dynamic>.from(
      await channel.invokeMapMethod('conditions') ?? {},
    );
  }

  static bool allowed(AutomationSettings s, Map<String, dynamic> c) =>
      c['connected'] == true &&
      (!s.wifiOnly || c['wifi'] == true) &&
      (!s.chargingOnly || c['charging'] == true) &&
      ((c['battery'] as num?)?.toInt() ?? 0) >= s.batteryMinimum;
  static Future<void> schedule(AutomationSettings s) async {
    if (Platform.isAndroid) await channel.invokeMethod('schedule', s.toMap());
  }

  static Future<void> notify(int count) async {
    if (Platform.isAndroid && count > 0) {
      await channel.invokeMethod('notify', {'count': count});
    }
  }
}

class MaintenanceService {
  final DownloadEngine engine;
  final Future<OnlineMangaDetail> Function(String) detail;
  final Future<Map<String, dynamic>> Function() conditions;
  MaintenanceService(
    this.engine, {
    Future<OnlineMangaDetail> Function(String)? detail,
    Future<Map<String, dynamic>> Function()? conditions,
  }) : detail =
           detail ??
           ((ref) => OnlineCatalogService.fetchMangaDetail(ref, refresh: true)),
       conditions = conditions ?? MaintenancePlatform.conditions;
  Future<OnlineMangaDetail> _full(String ref) async =>
      OnlineCatalogService.completeDetail(await detail(ref));
  Future<void> run({bool manual = false}) async {
    final s = await AutomationSettings.load();
    final store = await LibraryStore.ensureInitialized();
    var count = 0;
    try {
      await MyAnimeListService.shared.flush();
      if (s.backups) await RotatingBackupService.run(retain: s.backupRetention);
      final c = await conditions();
      if ((s.updates || manual) &&
          (manual || MaintenancePlatform.allowed(s, c))) {
        final links = await PreferencesService.getMangaSourceLinks();
        for (final favorite
            in (await PreferencesService.getFavoritesMap()).values) {
          final ref = ContentIdentity.isRemote(favorite.key)
              ? favorite.key
              : links[favorite.key];
          if (ref == null) continue;
          try {
            final manga = await _full(ref);
            final previous = await store.getRecord(
              'favorite_updates',
              favorite.key,
            );
            final known = (previous?['known'] as List? ?? [])
                .cast<String>()
                .toSet();
            final current = manga.chapters.map((c) => c.path).toSet();
            // La primera comprobación establece una base, nunca descarga toda la colección.
            final fresh = previous == null
                ? <String>{}
                : current.difference(known);
            final notices = {
              ...(previous?['new'] as List? ?? []).cast<String>(),
              ...fresh,
            };
            await store.putRecord('favorite_updates', favorite.key, {
              'id': favorite.key,
              'url': manga.url,
              'title': manga.title,
              'known': {...known, ...current}.toList(),
              'new': notices.toList(),
              'checkedAt': DateTime.now().millisecondsSinceEpoch,
            });
            count += fresh.length;
            if (s.autoDownload &&
                notices.isNotEmpty &&
                MaintenancePlatform.allowed(s, await conditions())) {
              await enqueueAutomatic(manga, {
                for (var i = 0; i < manga.chapters.length; i++)
                  if (notices.contains(manga.chapters[i].path)) i,
              }, s);
            }
          } catch (e) {
            await Diagnostics.record('favorite_updates', e);
          }
        }
      }
      await store.putRecord('maintenance', 'last', {
        'id': 'last',
        'time': DateTime.now().millisecondsSinceEpoch,
        'new': count,
      });
      if (count > 0) await MaintenancePlatform.notify(count);
    } catch (e) {
      await Diagnostics.record('maintenance', e);
      rethrow;
    }
  }

  Future<int> automaticBytes() async {
    var bytes = 0;
    for (final row
        in await (await LibraryStore.ensureInitialized()).readRecords(
          'automatic_chapters',
        )) {
      final folder = Directory(row['folder'] as String);
      if (await folder.exists()) {
        await for (final file in folder.list(followLinks: false)) {
          if (file is File && file.path.endsWith('.image')) {
            bytes += await file.length();
          }
        }
      }
    }
    return bytes;
  }

  Future<void> enqueueAutomatic(
    OnlineMangaDetail manga,
    Set<int> selected,
    AutomationSettings s,
  ) async {
    if (engine.downloadRoot == null ||
        !MaintenancePlatform.allowed(s, await conditions())) {
      return;
    }
    final states = await engine.storage.chapterStates(
      engine.downloadRoot!,
      manga,
    );
    selected = selected
        .where((i) => states[manga.chapters[i].path] != 'Descargado')
        .toSet();
    final reserved = engine.jobs
        .where((j) => j.automatic && !j.stopped)
        .fold(
          0,
          (int n, j) =>
              n + ((j.maxBytes ?? 0) - j.receivedBytes).clamp(0, 1 << 40),
        );
    final remaining =
        s.budgetMiB * 1024 * 1024 - await automaticBytes() - reserved;
    if (selected.isEmpty || remaining <= 0) return;
    await engine.enqueueManga(
      manga,
      chapterIndexes: selected,
      automatic: true,
      maxBytes: remaining,
    );
  }

  Future<void> ahead(String ref, String chapter) async {
    final s = await AutomationSettings.load();
    if (s.aheadCount == 0 ||
        !MaintenancePlatform.allowed(s, await conditions())) {
      return;
    }
    var manga = await OnlineCatalogService.resolveChapter(
      await detail(ref),
      chapter,
    );
    var index = manga.chapters.indexWhere((c) => c.path == chapter);
    if (index < 0) return;
    while (manga.hasMoreChapters &&
        manga.chapters.length < index + s.aheadCount + 1) {
      manga = await OnlineCatalogService.loadMoreChapters(manga);
      index = manga.chapters.indexWhere((c) => c.path == chapter);
    }
    await enqueueAutomatic(manga, {
      for (
        var i = index + 1;
        i < manga.chapters.length && i <= index + s.aheadCount;
        i++
      )
        i,
    }, s);
  }

  static Future<void> rememberAutomatic(String path, String chapter) async =>
      (await LibraryStore.ensureInitialized()).putRecord(
        'automatic_chapters',
        ContentIdentity.id(chapter),
        {'id': ContentIdentity.id(chapter), 'folder': path, 'chapter': chapter},
      );
}
