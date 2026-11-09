import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import '../models/manga.dart';
import '../utils/fs_scanner.dart';
import '../utils/app_failure.dart';

class StorageMaintenance {
  static Future<Map<String, int>> measure(Iterable<Manga> mangas) =>
      compute(_measure, mangas.map((m) => m.path).toList());
  static Map<String, int> _measure(List<String> folders) {
    final sizes = <String, int>{};
    for (final folder in folders) {
      var bytes = 0;
      final directory = Directory(folder);
      if (directory.existsSync()) {
        for (final entry in directory.listSync(
          recursive: true,
          followLinks: false,
        )) {
          if (entry is File) bytes += entry.lengthSync();
        }
      }
      sizes[folder] = bytes;
    }
    return sizes;
  }

  static Future<void> deleteChapter(Manga manga, String chapterPath) async {
    final root = p.normalize(p.absolute(manga.path));
    final target = p.normalize(p.absolute(chapterPath));
    if (!manga.chapters.any((c) => p.equals(c.path, target)) ||
        !p.isWithin(root, target) ||
        await FileSystemEntity.isLink(target)) {
      throw const AppFailure(
        FailureKind.storage,
        'Carpeta de capítulo inválida.',
      );
    }
    final directory = Directory(target);
    if (await directory.exists()) await directory.delete(recursive: true);
  }

  static Future<int> cleanParts(List<String> roots) =>
      compute(_cleanParts, roots);
  static int _cleanParts(List<String> roots) {
    var count = 0;
    final cutoff = DateTime.now().subtract(const Duration(days: 1));
    for (final root in roots.toSet()) {
      final directory = Directory(root);
      if (!directory.existsSync()) continue;
      for (final entry in directory.listSync(
        recursive: true,
        followLinks: false,
      )) {
        if (entry is File &&
            p.extension(entry.path) == '.part' &&
            entry.lastModifiedSync().isBefore(cutoff)) {
          entry.deleteSync();
          count++;
        }
      }
    }
    return count;
  }

  /// Actualiza metadatos de carpetas antiguas sin renombrar rutas ni asumir su origen.
  static Future<int> migrateLegacy(List<Manga> mangas) async {
    var count = 0;
    for (final manga in mangas) {
      if (await File('${manga.path}/manga.yomashi.json').exists()) continue;
      await FsScanner.writeLegacyIdentity(manga);
      count++;
    }
    return count;
  }
}
