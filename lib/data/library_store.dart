import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/favorite_entry.dart';
import '../models/reading_progress.dart';
import 'app_database.dart';

/// Persistencia SQLite (Drift) de progreso, caps leídos y favoritos.
class LibraryStore {
  LibraryStore(this._db);

  final AppDatabase _db;
  static LibraryStore? _instance;
  static LibraryStore? get current => _instance;
  static Future<LibraryStore>? _initFuture;
  static bool _migrated = false;

  static Future<LibraryStore> initialize({AppDatabase? database}) {
    final existing = _instance;
    if (existing != null) {
      return Future<LibraryStore>.value(existing);
    }
    return _initFuture ??= Future<LibraryStore>(() async {
      final store = LibraryStore(database ?? AppDatabase());
      try {
        await store._db.customSelect('SELECT 1').get();
        await store._migrateFromPreferencesIfNeeded();
        _instance = store;
        return store;
      } catch (_) {
        _initFuture = null;
        await store._db.close();
        rethrow;
      }
    });
  }

  static Future<LibraryStore> ensureInitialized() => initialize();

  static const _migrationFlag = 'library_store_migrated_v1';

  Future<void> _migrateFromPreferencesIfNeeded() async {
    if (_migrated) {
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_migrationFlag) == true) {
      _migrated = true;
      return;
    }

    final progressRaw = prefs.getString('reading_progress_v1');
    if (progressRaw != null && progressRaw.isNotEmpty) {
      final map = _decodeProgress(progressRaw);
      if (map.isNotEmpty) {
        await replaceProgressMap(map);
      }
    }

    final favoritesRaw = prefs.getString('favorites_v1');
    if (favoritesRaw != null && favoritesRaw.isNotEmpty) {
      final map = _decodeFavorites(favoritesRaw);
      if (map.isNotEmpty) {
        await replaceFavoritesMap(map);
      }
    }

    final readKeys = prefs.getStringList('read_chapters_v1') ?? <String>[];
    if (readKeys.isNotEmpty) {
      await replaceReadChapterKeys(readKeys.toSet());
    }

    await prefs.setBool(_migrationFlag, true);
    _migrated = true;
  }

  Map<String, ReadingProgress> _decodeProgress(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        return <String, ReadingProgress>{};
      }
      final result = <String, ReadingProgress>{};
      for (final entry in decoded.entries) {
        final value = entry.value;
        if (value is Map) {
          result[entry.key.toString()] = ReadingProgress.fromMap(
            Map<String, dynamic>.from(value),
          );
        }
      }
      return result;
    } catch (_) {
      return <String, ReadingProgress>{};
    }
  }

  Map<String, FavoriteEntry> _decodeFavorites(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List<dynamic>) {
        return <String, FavoriteEntry>{};
      }
      final result = <String, FavoriteEntry>{};
      for (final item in decoded) {
        if (item is Map<String, dynamic>) {
          final entry = FavoriteEntry.fromMap(item);
          if (entry.key.isNotEmpty) {
            result[entry.key] = entry;
          }
        }
      }
      return result;
    } catch (_) {
      return <String, FavoriteEntry>{};
    }
  }

  Future<Map<String, ReadingProgress>> getProgressMap() async {
    final rows = await _db.select(_db.readingProgressRows).get();
    return {
      for (final row in rows)
        row.mangaPath: ReadingProgress(
          mangaPath: row.mangaPath,
          mangaTitle: row.mangaTitle,
          coverPath: row.coverPath,
          chapterPath: row.chapterPath,
          chapterTitle: row.chapterTitle,
          pageIndex: row.pageIndex,
          updatedAt: row.updatedAt,
          sourceId: row.sourceId,
        ),
    };
  }

  Future<void> replaceProgressMap(Map<String, ReadingProgress> progress) async {
    await _db.transaction(() async {
      await _db.delete(_db.readingProgressRows).go();
      for (final entry in progress.values) {
        await _db
            .into(_db.readingProgressRows)
            .insert(
              ReadingProgressRowsCompanion.insert(
                mangaPath: entry.mangaPath,
                mangaTitle: entry.mangaTitle,
                coverPath: Value(entry.coverPath),
                chapterPath: entry.chapterPath,
                chapterTitle: entry.chapterTitle,
                pageIndex: entry.pageIndex,
                updatedAt: entry.updatedAt,
                sourceId: Value(entry.sourceId),
              ),
            );
      }
    });
  }

  Future<Map<String, FavoriteEntry>> getFavoritesMap() async {
    final rows = await _db.select(_db.favoriteRows).get();
    return {
      for (final row in rows)
        row.mangaKey: FavoriteEntry(
          key: row.mangaKey,
          title: row.title,
          coverPath: row.coverPath,
        ),
    };
  }

  Future<void> replaceFavoritesMap(Map<String, FavoriteEntry> favorites) async {
    await _db.transaction(() async {
      await _db.delete(_db.favoriteRows).go();
      for (final entry in List<FavoriteEntry>.from(favorites.values)) {
        await _db
            .into(_db.favoriteRows)
            .insert(
              FavoriteRowsCompanion.insert(
                mangaKey: entry.key,
                title: entry.title,
                coverPath: Value(entry.coverPath),
              ),
            );
      }
    });
  }

  Future<Set<String>> getReadChapterKeys() async {
    final rows = await _db.select(_db.readChapterRows).get();
    return rows.map((row) => row.chapterPath).toSet();
  }

  Future<void> replaceReadChapterKeys(Set<String> keys) async {
    await _db.transaction(() async {
      await _db.delete(_db.readChapterRows).go();
      for (final key in keys) {
        if (key.isEmpty) {
          continue;
        }
        await _db
            .into(_db.readChapterRows)
            .insert(ReadChapterRowsCompanion.insert(chapterPath: key));
      }
    });
  }

  Future<T> transaction<T>(
    Future<T> Function() action,
  ) => _db.transaction(() async {
    // Reservar la escritura antes de leer: UI y motor Android usan conexiones
    // distintas. Evita SQLITE_BUSY_SNAPSHOT al convertir una lectura WAL.
    await _db.customStatement(
      'UPDATE app_records SET payload=payload WHERE namespace=? AND record_key=?',
      ['__write_lock', '__write_lock'],
    );
    return action();
  });
  Future<void> upsertProgress(ReadingProgress entry) => _db
      .into(_db.readingProgressRows)
      .insertOnConflictUpdate(
        ReadingProgressRowsCompanion.insert(
          mangaPath: entry.mangaPath,
          mangaTitle: entry.mangaTitle,
          coverPath: Value(entry.coverPath),
          chapterPath: entry.chapterPath,
          chapterTitle: entry.chapterTitle,
          pageIndex: entry.pageIndex,
          updatedAt: entry.updatedAt,
          sourceId: Value(entry.sourceId),
        ),
      );

  /// Cambios de YomaShi (manga online) pendientes de sincronizar con la
  /// cuenta: [kind] `manga` (biblioteca) o `manga_read`. El progreso no se
  /// anota aquí: cada fila ya guarda su fecha.
  static const mangaSyncLog = 'manga_sync_log';

  /// Solo el manga online tiene la misma identidad en otros dispositivos.
  static bool syncableUrl(String value) =>
      value.startsWith('https://') || value.startsWith('http://');

  Future<void> noteMangaChange(
    String kind,
    String url, {
    required bool deleted,
    Map<String, dynamic> payload = const {},
  }) async {
    if (!syncableUrl(url)) return;
    final id = '$kind|$url';
    await putRecord(mangaSyncLog, id, {
      'id': id,
      'kind': kind,
      'url': url,
      'deleted': deleted,
      'payload': payload,
      'updatedAt': DateTime.now().millisecondsSinceEpoch,
    });
  }

  /// [sync]: false cuando el cambio viene de la propia sincronización.
  Future<void> setFavorite(FavoriteEntry entry, {bool sync = true}) async {
    await _db
        .into(_db.favoriteRows)
        .insertOnConflictUpdate(
          FavoriteRowsCompanion.insert(
            mangaKey: entry.key,
            title: entry.title,
            coverPath: Value(entry.coverPath),
          ),
        );
    if (sync) {
      await noteMangaChange(
        'manga',
        entry.key,
        deleted: false,
        payload: {'title': entry.title, 'cover': entry.coverPath ?? ''},
      );
    }
  }

  Future<void> removeFavorite(String key, {bool sync = true}) async {
    await (_db.delete(
      _db.favoriteRows,
    )..where((row) => row.mangaKey.equals(key))).go();
    if (sync) await noteMangaChange('manga', key, deleted: true);
  }

  /// [sync]: false para lo que no se lee en el teléfono (traído de MAL o de
  /// otro dispositivo): cada dispositivo ya lo recibe por su cuenta.
  Future<void> setChapterRead(String key, bool read, {bool sync = true}) async {
    if (sync) await noteMangaChange('manga_read', key, deleted: !read);
    if (read) {
      await _db
          .into(_db.readChapterRows)
          .insertOnConflictUpdate(
            ReadChapterRowsCompanion.insert(chapterPath: key),
          );
    } else {
      await (_db.delete(
        _db.readChapterRows,
      )..where((row) => row.chapterPath.equals(key))).go();
    }
  }

  Future<dynamic> getRecord(String namespace, String key) async {
    final row = await _db
        .customSelect(
          'SELECT payload FROM app_records WHERE namespace = ? AND record_key = ?',
          variables: [Variable(namespace), Variable(key)],
        )
        .getSingleOrNull();
    return row == null ? null : jsonDecode(row.read<String>('payload'));
  }

  Future<void> putRecord(
    String namespace,
    String key,
    Object? value,
  ) => _db.customStatement(
    'INSERT INTO app_records(namespace,record_key,payload) VALUES(?,?,?) ON CONFLICT(namespace,record_key) DO UPDATE SET payload=excluded.payload',
    [namespace, key, jsonEncode(value)],
  );
  Future<void> deleteRecord(String namespace, String key) =>
      _db.customStatement(
        'DELETE FROM app_records WHERE namespace=? AND record_key=?',
        [namespace, key],
      );

  /// Conserva solo los [keep] registros más recientes (`savedAt`) del espacio
  /// [namespace] cuyo id empieza por [prefix].
  Future<void> pruneRecords(String namespace, String prefix, int keep) =>
      _db.customStatement(
        'DELETE FROM app_records WHERE namespace=? AND record_key LIKE ? '
        'AND record_key NOT IN (SELECT record_key FROM app_records '
        'WHERE namespace=? AND record_key LIKE ? '
        "ORDER BY json_extract(payload, '\$.savedAt') DESC LIMIT ?)",
        [namespace, '$prefix%', namespace, '$prefix%', keep],
      );
  Future<List<Map<String, dynamic>>> readRecords(String namespace) async {
    final rows = await _db
        .customSelect(
          'SELECT record_key,payload FROM app_records WHERE namespace = ? ORDER BY record_key',
          variables: [Variable(namespace)],
        )
        .get();
    return rows
        .map(
          (row) => {
            'id': row.read<String>('record_key'),
            ...Map<String, dynamic>.from(
              jsonDecode(row.read<String>('payload')) as Map,
            ),
          },
        )
        .toList();
  }

  /// Cambia la carpeta [from] por [to] (rutas absolutas sin barra final) en
  /// el progreso, los capítulos leídos, los favoritos y todos los registros.
  /// Solo afecta a rutas que empiezan exactamente por [from]; es idempotente.
  /// Devuelve cuántas filas cambiaron.
  Future<int> relocatePathPrefix(String from, String to) {
    if (from.isEmpty || from == to || from.endsWith('/') || to.endsWith('/')) {
      throw ArgumentError('Rutas de carpeta no válidas.');
    }
    return transaction(() async {
      var changed = 0;
      Future<void> column(String table, String name) async {
        changed += await _db.customUpdate(
          'UPDATE OR REPLACE $table SET $name = ? || substr($name, ?) '
          'WHERE $name = ? OR substr($name, 1, ?) = ?',
          variables: [
            Variable.withString(to),
            Variable.withInt(from.length + 1),
            Variable.withString(from),
            Variable.withInt(from.length + 1),
            Variable.withString('$from/'),
          ],
          updates: {
            _db.readingProgressRows,
            _db.readChapterRows,
            _db.favoriteRows,
          },
        );
      }

      await column('reading_progress_rows', 'manga_path');
      await column('reading_progress_rows', 'cover_path');
      await column('reading_progress_rows', 'chapter_path');
      await column('read_chapter_rows', 'chapter_path');
      await column('favorite_rows', 'manga_key');
      await column('favorite_rows', 'cover_path');
      await column('app_records', 'record_key');
      // Dentro de los registros JSON: rutas que continúan y rutas exactas.
      changed += await _db.customUpdate(
        'UPDATE app_records SET payload = replace(replace(payload, ?, ?), ?, ?) '
        'WHERE instr(payload, ?) > 0 OR instr(payload, ?) > 0',
        variables: [
          Variable.withString('$from/'),
          Variable.withString('$to/'),
          Variable.withString('"$from"'),
          Variable.withString('"$to"'),
          Variable.withString('$from/'),
          Variable.withString('"$from"'),
        ],
      );
      return changed;
    });
  }

  Future<void> replaceRecords(
    String namespace,
    List<Map<String, dynamic>> records,
  ) async {
    final snapshot = records.map((e) => Map<String, dynamic>.from(e)).toList();
    await transaction(() async {
      final old = await _db
          .customSelect(
            'SELECT record_key,payload FROM app_records WHERE namespace=?',
            variables: [Variable(namespace)],
          )
          .get();
      final next = <String, String>{};
      for (var i = 0; i < snapshot.length; i++) {
        final item = {...snapshot[i], '_position': i};
        next[(item['id'] ?? i).toString()] = jsonEncode(item);
      }
      for (final row in old) {
        final key = row.read<String>('record_key');
        if (!next.containsKey(key)) {
          await _db.customStatement(
            'DELETE FROM app_records WHERE namespace=? AND record_key=?',
            [namespace, key],
          );
        }
      }
      final previous = {
        for (final row in old)
          row.read<String>('record_key'): row.read<String>('payload'),
      };
      for (final entry in next.entries) {
        if (previous[entry.key] != entry.value) {
          await _db.customStatement(
            'INSERT INTO app_records(namespace,record_key,payload) VALUES(?,?,?) ON CONFLICT(namespace,record_key) DO UPDATE SET payload=excluded.payload',
            [namespace, entry.key, entry.value],
          );
        }
      }
    });
  }
}
