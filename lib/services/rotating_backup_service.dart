import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../utils/backup_service.dart';
import '../utils/permissions.dart';
import '../utils/yomashi_public_storage.dart';

class RotatingBackupService {
  static Future<File?>? _running;
  static Future<Directory> _privateDirectory() async => Directory(
    p.join((await getApplicationSupportDirectory()).path, 'automatic_backups'),
  );
  static Future<Directory> directory() async {
    if (Platform.isAndroid &&
        !const bool.fromEnvironment('YOMASHI_QA') &&
        await StoragePermissionService.isManageAllFilesGranted()) {
      final root = await YomashiPublicStorage.ensureAppFolder();
      if (root != null) return Directory(p.join(root.path, 'Backups'));
    }
    return _privateDirectory();
  }

  static Future<List<File>> files({Directory? directory}) async {
    final dir = directory ?? await RotatingBackupService.directory();
    final files = !await dir.exists()
        ? <File>[]
        : await dir
              .list(followLinks: false)
              .where(
                (f) =>
                    f is File &&
                    p.basename(f.path).startsWith('yomashi_backup_') &&
                    f.path.endsWith('.json'),
              )
              .cast<File>()
              .toList();
    files.sort((a, b) => b.path.compareTo(a.path));
    if (directory == null) {
      final private = await _privateDirectory();
      if (private.path != dir.path) {
        files.addAll(await RotatingBackupService.files(directory: private));
      }
      files.sort((a, b) => p.basename(b.path).compareTo(p.basename(a.path)));
    }
    return files;
  }

  static Future<File?> run({
    bool force = false,
    int retain = 7,
    Directory? directory,
    DateTime? now,
  }) {
    if (_running != null) return _running!;
    final future = _run(
      force: force,
      retain: retain.clamp(2, 30),
      directory: directory,
      now: now ?? DateTime.now(),
    );
    _running = future;
    return future.whenComplete(() => _running = null);
  }

  static Future<File?> _run({
    required bool force,
    required int retain,
    Directory? directory,
    required DateTime now,
  }) async {
    final dir = directory ?? await RotatingBackupService.directory();
    final existing = await files(directory: dir);
    if (!force &&
        existing.isNotEmpty &&
        now.difference(await existing.first.lastModified()) <
            const Duration(hours: 24)) {
      return null;
    }
    final file = await BackupService.exportToFile(directory: dir);
    // Solo se rota después de validar la nueva copia, nunca la última válida.
    await BackupService.preview(file);
    final current = await files(directory: dir);
    for (final old in current.skip(retain)) {
      await old.delete();
    }
    return file;
  }
}
