import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../data/library_store.dart';
import '../models/favorite_entry.dart';
import '../models/reading_progress.dart';
import '../models/reading_stats.dart';
import 'preferences.dart';
import '../models/automation_settings.dart';

class BackupPreview {
  final int progress, favorites, chapters, categories;
  const BackupPreview(
    this.progress,
    this.favorites,
    this.chapters,
    this.categories,
  );
  String get summary =>
      'Progresos: $progress\nFavoritos: $favorites\nCapítulos leídos: $chapters\nCategorías: $categories';
}

class BackupService {
  static bool _restoring = false;
  static const _boolKeys = {
    'reader_vertical_mode',
    'reader_free_zoom_v1',
    'reader_show_page_number_v1',
    'reader_tap_navigation_v1',
    'reader_volume_navigation_v1',
    'reader_double_page_v1',
    'reader_continuous_v1',
    'reader_cover_alone_v1',
    'reader_crop_white_v1',
    'mangadex_data_saver',
  };
  static const _stringKeys = {
    'reader_direction_v1',
    'reader_orientation_v1',
    'reader_page_fit_v1',
    'reader_transition_speed_v1',
    'ui_density_v1',
    'active_manga_source_v1',
    'profile_display_name_v1',
  };
  static bool _portableKey(String key) =>
      _boolKeys.contains(key) ||
      _stringKeys.contains(key) ||
      {
        'theme_accent_v1',
        'mangadex_languages_v1',
        'search_sources_v1',
        'app_brightness_v1',
      }.contains(key);
  static bool _validSetting(String key, Object? value) {
    if (_boolKeys.contains(key)) return value is bool;
    if (_stringKeys.contains(key)) return value is String;
    if (key == 'theme_accent_v1') {
      return value is int && value >= 0 && value <= 0xffffffff;
    }
    if (key == 'app_brightness_v1') {
      return value is double && value.isFinite && value >= 0 && value <= 1;
    }
    return value is List && value.every((e) => e is String);
  }

  static bool _validOverride(dynamic value) {
    if (value is! Map ||
        value['id'] is! String ||
        (value['id'] as String).isEmpty) {
      return false;
    }
    if (value['direction'] != null &&
        !{
          'vertical',
          'leftToRight',
          'rightToLeft',
        }.contains(value['direction'])) {
      return false;
    }
    if (value['fit'] != null &&
        !{'fitWidth', 'fitHeight', 'original'}.contains(value['fit'])) {
      return false;
    }
    if (value['orientation'] != null &&
        !{'system', 'portrait', 'landscape'}.contains(value['orientation'])) {
      return false;
    }
    return [
      'zoom',
      'double',
      'continuous',
      'coverAlone',
      'cropWhite',
    ].every((key) => value[key] == null || value[key] is bool);
  }

  static Future<Map<String, dynamic>> _snapshot() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'version': 4,
      'malLinks': await (await LibraryStore.ensureInitialized()).readRecords(
        'mal_links',
      ),
      'exportedAt': DateTime.now().toIso8601String(),
      'bookmarks': await (await LibraryStore.ensureInitialized()).readRecords(
        'bookmarks',
      ),
      'automation': (await AutomationSettings.load()).toMap(),
      'progress': (await PreferencesService.getProgressMap()).map(
        (k, v) => MapEntry(k, v.toMap()),
      ),
      'favorites': (await PreferencesService.getFavoritesMap()).values
          .map((e) => e.toMap())
          .toList(),
      'readChapters': (await PreferencesService.getReadChapterKeys()).toList(),
      'readingStats': (await PreferencesService.getReadingStats()).toMap(),
      'categories': await PreferencesService.getCategories(),
      'sourceLinks': await PreferencesService.getMangaSourceLinks(),
      'settings': {
        for (final key in prefs.getKeys().where(_portableKey))
          key: prefs.get(key),
      },
      'readerOverrides': await (await LibraryStore.ensureInitialized())
          .readRecords('reader'),
    };
  }

  static Future<File> exportToFile({Directory? directory}) async {
    final snapshot = await (await LibraryStore.ensureInitialized()).transaction(
      _snapshot,
    );
    final dir = directory ?? await getApplicationDocumentsDirectory();
    await dir.create(recursive: true);
    final file = File(
      p.join(
        dir.path,
        'yomashi_backup_${DateTime.now().microsecondsSinceEpoch}.json',
      ),
    );
    final part = File('${file.path}.part');
    try {
      await part.writeAsString(
        const JsonEncoder.withIndent('  ').convert(snapshot),
        flush: true,
      );
      await part.rename(file.path);
      return file;
    } catch (_) {
      if (await part.exists()) await part.delete();
      rethrow;
    }
  }

  static Future<Map<String, dynamic>> _validated(File file) async {
    if (await file.length() > 32 * 1024 * 1024) {
      throw StateError('El backup supera 32 MiB.');
    }
    final decoded = jsonDecode(await file.readAsString());
    if (decoded is! Map) throw StateError('Archivo de backup inválido.');
    final map = Map<String, dynamic>.from(decoded);
    if (![1, 2, 3, 4].contains(map['version'])) {
      throw StateError('Versión de backup no compatible.');
    }
    if (map['progress'] is! Map ||
        map['favorites'] is! List ||
        map['readChapters'] is! List ||
        map['categories'] is! List ||
        map['readingStats'] is! Map) {
      throw StateError('Backup incompleto.');
    }
    for (final entry in (map['progress'] as Map).entries) {
      if (entry.value is! Map) throw StateError('Progreso inválido.');
      final value = ReadingProgress.fromMap(
        Map<String, dynamic>.from(entry.value as Map),
      );
      if (value.mangaPath.isEmpty ||
          value.chapterPath.isEmpty ||
          entry.key != value.mangaPath ||
          value.pageIndex < 0 ||
          value.updatedAt < 0) {
        throw StateError('Progreso fuera de rango.');
      }
    }
    for (final item in map['favorites'] as List) {
      if (item is! Map ||
          FavoriteEntry.fromMap(Map<String, dynamic>.from(item)).key.isEmpty) {
        throw StateError('Favorito inválido.');
      }
    }
    if ((map['readChapters'] as List).any((e) => e is! String || e.isEmpty)) {
      throw StateError('Capítulos leídos inválidos.');
    }
    for (final item in map['categories'] as List) {
      if (item is! Map ||
          item['id'] is! String ||
          item['name'] is! String ||
          item['mangaKeys'] is! List ||
          (item['mangaKeys'] as List).any((e) => e is! String)) {
        throw StateError('Categoría inválida.');
      }
    }
    final stats = ReadingStats.fromMap(
      Map<String, dynamic>.from(map['readingStats'] as Map),
    );
    if (stats.mangaOpens < 0 ||
        stats.chaptersOpened < 0 ||
        stats.pagesRead < 0 ||
        stats.openedMangaPaths.any((path) => path.isEmpty)) {
      throw StateError('Estadísticas inválidas.');
    }
    final marks = map['bookmarks'];
    final malLinks = map['malLinks'];
    if (malLinks != null &&
        (malLinks is! List ||
            malLinks.any(
              (m) =>
                  m is! Map ||
                  m.keys.any(
                    (k) => !{
                      'id',
                      'manga',
                      'title',
                      'malId',
                      'malTitle',
                      'owner',
                      'automatic',
                      'version',
                      '_position',
                    }.contains(k),
                  ) ||
                  m['id'] is! String ||
                  m['manga'] != m['id'] ||
                  m['title'] is! String ||
                  m['malTitle'] is! String ||
                  m['malId'] is! int ||
                  m['malId'] < 1 ||
                  m['malId'] > 999999999 ||
                  m['owner'] is! int ||
                  m['owner'] < 1 ||
                  m['automatic'] is! bool ||
                  m['version'] is! int ||
                  m['version'] < 0,
            ))) {
      throw StateError('Vínculos MyAnimeList inválidos.');
    }
    if (marks != null &&
        (marks is! List ||
            marks.any(
              (m) =>
                  m is! Map ||
                  m['id'] is! String ||
                  m['manga'] is! String ||
                  m['chapter'] is! String ||
                  m['title'] is! String ||
                  m['chapterTitle'] is! String ||
                  m['page'] is! int ||
                  (m['page'] as int) < 0 ||
                  m['updatedAt'] is! int ||
                  (m['updatedAt'] as int) < 0,
            ))) {
      throw StateError('Marcadores inválidos.');
    }
    final automation = map['automation'];
    if (automation != null) {
      if (automation is! Map) throw StateError('Automatización inválida.');
      final clean = AutomationSettings.fromMap(
        Map<String, dynamic>.from(automation),
      ).toMap();
      if (automation.entries.any((e) => clean[e.key] != e.value)) {
        throw StateError('Automatización fuera de rango.');
      }
    }
    final overrides = map['readerOverrides'];
    if (overrides != null &&
        (overrides is! List || overrides.any((e) => !_validOverride(e)))) {
      throw StateError('Ajustes por obra inválidos.');
    }
    final settings = map['settings'];
    if (settings != null &&
        (settings is! Map ||
            settings.entries.any(
              (e) =>
                  e.key is! String ||
                  !_portableKey(e.key as String) ||
                  !_validSetting(e.key as String, e.value),
            ))) {
      throw StateError('Ajustes inválidos.');
    }
    if (map['sourceLinks'] != null &&
        (map['sourceLinks'] is! Map ||
            (map['sourceLinks'] as Map).entries.any(
              (e) => e.key is! String || e.value is! String,
            ))) {
      throw StateError('Vínculos inválidos.');
    }
    return map;
  }

  static Future<BackupPreview> preview(File file) async {
    final map = await _validated(file);
    return BackupPreview(
      (map['progress'] as Map).length,
      (map['favorites'] as List).length,
      (map['readChapters'] as List).length,
      (map['categories'] as List).length,
    );
  }

  static Future<void> _settings(
    SharedPreferences prefs,
    Map<String, dynamic> values,
  ) async {
    for (final entry in values.entries) {
      final value = entry.value;
      if (value is String) {
        await prefs.setString(entry.key, value);
      } else if (value is bool) {
        await prefs.setBool(entry.key, value);
      } else if (value is int) {
        await prefs.setInt(entry.key, value);
      } else if (value is double) {
        await prefs.setDouble(entry.key, value);
      } else if (value is List) {
        await prefs.setStringList(entry.key, value.cast<String>());
      }
    }
  }

  static Future<String> importFromFile(
    File file, {
    bool merge = false,
    Directory? recoveryDirectory,
  }) async {
    if (_restoring) throw StateError('Ya hay una restauración en curso.');
    final map = await _validated(
      file,
    ); // No se escribe nada antes de validar todo.
    _restoring = true;
    try {
      final recovery = await exportToFile(directory: recoveryDirectory);
      final store = await LibraryStore.ensureInitialized();
      final prefs = await SharedPreferences.getInstance();
      final previous = {
        for (final key in prefs.getKeys().where(_portableKey))
          key: prefs.get(key),
      };
      try {
        await store.transaction(() async {
          final progress = merge
              ? await PreferencesService.getProgressMap()
              : <String, ReadingProgress>{};
          for (final entry in (map['progress'] as Map).entries) {
            final next = ReadingProgress.fromMap(
              Map<String, dynamic>.from(entry.value as Map),
            );
            final old = progress[next.mangaPath];
            if (old == null || !merge || next.updatedAt >= old.updatedAt) {
              progress[next.mangaPath] = next;
            }
          }
          final favorites = merge
              ? await PreferencesService.getFavoritesMap()
              : <String, FavoriteEntry>{};
          for (final item in map['favorites'] as List) {
            final entry = FavoriteEntry.fromMap(
              Map<String, dynamic>.from(item as Map),
            );
            favorites[entry.key] = entry;
          }
          final reads = merge
              ? await PreferencesService.getReadChapterKeys()
              : <String>{};
          reads.addAll((map['readChapters'] as List).cast<String>());
          final categories = {
            for (final e
                in merge
                    ? await PreferencesService.getCategories()
                    : <Map<String, dynamic>>[])
              e['id']: e,
          };
          for (final raw in map['categories'] as List) {
            final item = Map<String, dynamic>.from(raw as Map);
            final old = categories[item['id']];
            if (merge && old != null) {
              item['mangaKeys'] = <dynamic>{
                ...old['mangaKeys'] as List,
                ...item['mangaKeys'] as List,
              }.toList();
            }
            categories[item['id']] = item;
          }
          final links = merge
              ? await PreferencesService.getMangaSourceLinks()
              : <String, String>{};
          links.addAll(
            Map<String, String>.from(map['sourceLinks'] as Map? ?? {}),
          );
          await store.replaceProgressMap(progress);
          await store.replaceFavoritesMap(favorites);
          await store.replaceReadChapterKeys(reads);
          await PreferencesService.setCategories(categories.values.toList());
          await PreferencesService.setMangaSourceLinks(links);
          // Al combinar, conservar contadores existentes para no duplicar actividad.
          if (!merge) {
            await PreferencesService.setReadingStats(
              ReadingStats.fromMap(
                Map<String, dynamic>.from(map['readingStats'] as Map),
              ),
            );
          }
          final overrides = (map['readerOverrides'] as List? ?? [])
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
          final readerRecords = merge
              ? await store.readRecords('reader')
              : <Map<String, dynamic>>[];
          final byId = {
            for (final e in readerRecords) e['id']: e,
            for (final e in overrides) e['id']: e,
          };
          await store.replaceRecords('reader', byId.values.toList());
          final bookmarks = {
            for (final m
                in merge
                    ? await store.readRecords('bookmarks')
                    : <Map<String, dynamic>>[])
              m['id']: m,
          };
          for (final raw in map['bookmarks'] as List? ?? []) {
            final m = Map<String, dynamic>.from(raw as Map);
            final old = bookmarks[m['id']];
            if (old == null ||
                (m['updatedAt'] as int) >= (old['updatedAt'] as int)) {
              bookmarks[m['id']] = m;
            }
          }
          await store.replaceRecords('bookmarks', bookmarks.values.toList());
          final malLinks = {
            for (final m
                in merge
                    ? await store.readRecords('mal_links')
                    : <Map<String, dynamic>>[])
              m['id']: m,
          };
          for (final raw in map['malLinks'] as List? ?? []) {
            final m = Map<String, dynamic>.from(raw as Map);
            final old = malLinks[m['id']];
            if (old == null ||
                (m['version'] as int) >= (old['version'] as int)) {
              malLinks[m['id']] = m;
            }
          }
          await store.replaceRecords('mal_links', malLinks.values.toList());
          if (map['automation'] is Map) {
            await store.putRecord(
              'automation',
              'settings',
              Map<String, dynamic>.from(map['automation'] as Map),
            );
          }
          if (!merge) {
            for (final key in prefs.getKeys().where(_portableKey).toList()) {
              await prefs.remove(key);
            }
          }
          await _settings(
            prefs,
            Map<String, dynamic>.from(map['settings'] as Map? ?? {}),
          );
        });
      } catch (_) {
        for (final key in prefs.getKeys().where(_portableKey).toList()) {
          await prefs.remove(key);
        }
        await _settings(prefs, previous);
        rethrow;
      }
      return 'Backup restaurado. Copia previa: ${recovery.path}';
    } finally {
      _restoring = false;
    }
  }
}
