import 'dart:io';

import 'package:path/path.dart' as p;

/// Carpeta pública de YomaShi dentro de la carpeta común de Yoma.
///
/// Android: `/storage/emulated/0/Yoma/YomaShi` (mangas en `Manga/` y copias de
/// seguridad en `Backups/`). Los episodios de YomaTV van en
/// `/storage/emulated/0/Yoma/YomaTV/Anime`.
class YomashiPublicStorage {
  static const String yomaFolderName = 'Yoma';
  static const String folderName = 'YomaShi';

  /// Ruta relativa a la raíz del teléfono.
  static String get relativePath => p.join(yomaFolderName, folderName);

  /// Raíces con las que Android puede guardar la misma carpeta.
  static const List<String> rootAliases = _androidRoots;

  static const List<String> _androidRoots = <String>[
    '/storage/emulated/0',
    '/sdcard',
  ];

  /// Raíz pública del teléfono (`/storage/emulated/0`) si existe.
  static Directory? publicRoot() {
    if (!Platform.isAndroid) {
      return null;
    }
    for (final path in _androidRoots) {
      final dir = Directory(path);
      if (dir.existsSync()) {
        return dir;
      }
    }
    return Directory(_androidRoots.first);
  }

  static String? get appFolderPath {
    final root = publicRoot();
    if (root == null) {
      return null;
    }
    return p.join(root.path, yomaFolderName, folderName);
  }

  /// Ubicación anterior a Yoma 3.2 (`/storage/emulated/0/YomaShi`).
  static String? get legacyFolderPath {
    final root = publicRoot();
    return root == null ? null : p.join(root.path, folderName);
  }

  /// Crea `/storage/emulated/0/Yoma/YomaShi` si no existe.
  static Future<Directory?> ensureAppFolder() async {
    final path = appFolderPath;
    if (path == null) {
      return null;
    }
    final dir = Directory(path);
    try {
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      if (await dir.exists()) {
        return dir;
      }
    } catch (_) {}
    return null;
  }
}
