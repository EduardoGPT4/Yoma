import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/manga.dart';

class LibraryCacheData {
  final List<String> libraryPaths;
  final List<Manga> mangas;
  final DateTime savedAt;

  const LibraryCacheData({
    required this.libraryPaths,
    required this.mangas,
    required this.savedAt,
  });
}

class LibraryCacheService {
  static const _cacheFolderName = 'manga_reader_cache';
  static const _cacheFileName = 'library_metadata_v2.json';

  static Future<LibraryCacheData?> load() async {
    try {
      final file = await _cacheFile();
      if (!await file.exists()) {
        return null;
      }

      final raw = await file.readAsString();
      if (raw.trim().isEmpty) {
        return null;
      }

      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        return null;
      }

      final mangas =
          (decoded['mangas'] as List<dynamic>?)
              ?.whereType<Map>()
              .map((entry) => Manga.fromMap(entry.cast<String, dynamic>()))
              .toList() ??
          <Manga>[];
      final libraryPaths =
          (decoded['libraryPaths'] as List<dynamic>?)?.cast<String>() ??
          <String>[];
      final savedAt = DateTime.fromMillisecondsSinceEpoch(
        decoded['savedAt'] as int? ?? 0,
      );

      return LibraryCacheData(
        libraryPaths: libraryPaths,
        mangas: mangas,
        savedAt: savedAt,
      );
    } catch (_) {
      return null;
    }
  }

  static Future<void> save({
    required List<String> libraryPaths,
    required List<Manga> mangas,
  }) async {
    try {
      final file = await _cacheFile();
      final payload = <String, dynamic>{
        'libraryPaths': libraryPaths,
        'savedAt': DateTime.now().millisecondsSinceEpoch,
        'mangas': mangas.map((manga) => manga.toMap()).toList(),
      };
      await file.writeAsString(jsonEncode(payload), flush: true);
    } catch (_) {
      // Cache failures should never block the app.
    }
  }

  static Future<void> clear() async {
    try {
      final file = await _cacheFile();
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {
      // Ignore cleanup errors.
    }
  }

  static Future<File> _cacheFile() async {
    final supportDir = await getApplicationSupportDirectory();
    final cacheDir = Directory(p.join(supportDir.path, _cacheFolderName));
    if (!await cacheDir.exists()) {
      await cacheDir.create(recursive: true);
    }
    return File(p.join(cacheDir.path, _cacheFileName));
  }
}
