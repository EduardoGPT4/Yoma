import 'dart:io';

import 'package:path/path.dart' as p;

/// Carpeta pública de YomaShi en la raíz del almacenamiento interno.
///
/// Android: `/storage/emulated/0/YomaShi`
class YomashiPublicStorage {
  static const String folderName = 'YomaShi';

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
    return p.join(root.path, folderName);
  }

  /// Crea `/storage/emulated/0/YomaShi` si no existe.
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
