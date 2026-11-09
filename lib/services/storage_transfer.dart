import 'dart:io';
import 'package:path/path.dart' as p;
import '../utils/app_failure.dart';
import 'image_repository.dart';

class StorageTransfer {
  /// Copia en staging y publica el destino solo tras verificar todas las imágenes.
  static Future<void> copyVerified(Directory source, Directory target) async {
    if (p.equals(source.absolute.path, target.absolute.path)) return;
    if (p.isWithin(source.absolute.path, target.absolute.path) ||
        await target.exists()) {
      throw const AppFailure(
        FailureKind.storage,
        'El destino ya existe o está dentro del origen.',
      );
    }
    await target.parent.create(recursive: true);
    if (!await source.exists()) return;
    final stage = await target.parent.createTemp('.yomashi-migration-');
    try {
      await for (final entry in source.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entry is! File ||
            entry.path.endsWith('.part') ||
            entry.path.endsWith('.tmp')) {
          continue;
        }
        if (p.extension(entry.path) == '.image' &&
            !await ImageRepository.valid(entry)) {
          throw const AppFailure(
            FailureKind.storage,
            'El origen contiene una imagen dañada. Reanuda la descarga antes de copiar.',
          );
        }
        final relative = p.relative(entry.path, from: source.path);
        final file = File(p.join(stage.path, relative));
        await file.parent.create(recursive: true);
        await entry.openRead().pipe(file.openWrite());
        if (await file.length() != await entry.length() ||
            (p.extension(file.path) == '.image' &&
                !await ImageRepository.valid(file))) {
          throw const AppFailure(
            FailureKind.storage,
            'No se pudo verificar la copia.',
          );
        }
      }
      await stage.rename(target.path);
    } finally {
      if (p.isWithin(target.parent.absolute.path, stage.absolute.path) &&
          await stage.exists()) {
        await stage.delete(recursive: true);
      }
    }
  }
}
