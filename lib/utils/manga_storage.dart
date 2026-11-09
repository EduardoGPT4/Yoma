import 'dart:io';

import 'package:path/path.dart' as p;

class MangaStoragePaths {
  static const String folderName = 'Manga';
  static const String legacyFolderName = 'mangareader';

  /// Archivo vacío que indica a Android/MediaScanner que no indexe esta carpeta
  /// (ni subcarpetas) en la galería del sistema.
  static const String noMediaFileName = '.nomedia';

  static const List<String> coverFileNames = <String>[
    'cover.image',
    'cover.jpg',
    'cover.jpeg',
    'cover.png',
    'cover.webp',
  ];

  static String downloadFolder(String root) => p.join(root, folderName);

  static String legacyDownloadFolder(String root) =>
      p.join(root, legacyFolderName);

  /// Crea `.nomedia` en [directory] si no existe, para ocultar imágenes de la galería.
  static Future<void> ensureNoMedia(Directory directory) async {
    try {
      if (!await directory.exists()) {
        await directory.create(recursive: true);
      }
      final noMedia = File(p.join(directory.path, noMediaFileName));
      if (!await noMedia.exists()) {
        await noMedia.create();
      }
    } catch (_) {
      // Si falla (permisos, etc.), no bloquear descargas.
    }
  }

  /// Variante síncrona para rutas ya validadas.
  static void ensureNoMediaSync(Directory directory) {
    try {
      if (!directory.existsSync()) {
        directory.createSync(recursive: true);
      }
      final noMedia = File(p.join(directory.path, noMediaFileName));
      if (!noMedia.existsSync()) {
        noMedia.createSync();
      }
    } catch (_) {}
  }

  static String? findMangaCoverPath(String mangaDirPath) {
    final mangaDir = Directory(mangaDirPath);
    if (!mangaDir.existsSync()) {
      return null;
    }

    for (final name in coverFileNames) {
      final file = File(p.join(mangaDir.path, name));
      if (file.existsSync()) {
        return file.path;
      }
    }

    try {
      for (final entity in mangaDir.listSync(followLinks: false)) {
        if (entity is! File) {
          continue;
        }
        final baseName = p.basename(entity.path).toLowerCase();
        if (!baseName.startsWith('cover.')) {
          continue;
        }
        final ext = p.extension(baseName);
        if (ext == '.jpg' ||
            ext == '.jpeg' ||
            ext == '.png' ||
            ext == '.webp') {
          return entity.path;
        }
      }
    } catch (_) {
      return null;
    }

    return null;
  }

  static String coverFileNameForUrl(String url) {
    final ext = p
        .extension(Uri.tryParse(url)?.path ?? url)
        .replaceAll('.', '')
        .toLowerCase();

    if (ext == 'jpeg' || ext == 'jpg' || ext.isEmpty) {
      return 'cover.jpg';
    }
    if (ext == 'png' || ext == 'webp') {
      return 'cover.$ext';
    }
    return 'cover.jpg';
  }
}
