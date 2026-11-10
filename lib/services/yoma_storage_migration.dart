import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../data/library_store.dart';
import '../utils/library_cache.dart';
import '../utils/permissions.dart';
import '../utils/yomashi_public_storage.dart';
import 'diagnostics.dart';

/// Lleva la carpeta anterior `/storage/emulated/0/YomaShi` a
/// `/storage/emulated/0/Yoma/YomaShi` (mangas, copias y demás) y actualiza las
/// rutas guardadas: progreso, favoritos, categorías, cola de descargas,
/// carpetas de la biblioteca y ajustes.
///
/// Se ejecuta al arrancar, antes de cargar la biblioteca y con la cola de
/// descargas detenida. Primero mueve y después reescribe; la reescritura se
/// repite en cada arranque (no cambia nada si ya está hecha), así que un
/// cierre a mitad de camino se completa la próxima vez.
class YomaStorageMigration {
  YomaStorageMigration._();

  static const _storage = MethodChannel('app.yomashi.reader/storage');

  /// [onMoving] se llama justo antes de mover la carpeta anterior, para
  /// mostrar una pantalla de espera; no se llama si no hay nada que mover.
  static Future<void> run({Future<void> Function()? onMoving}) async {
    if (!Platform.isAndroid || const bool.fromEnvironment('YOMASHI_QA')) return;
    try {
      if (!await StoragePermissionService.isManageAllFilesGranted()) return;
      // El servicio de descargas guarda rutas en memoria: si sigue activo de
      // una sesión anterior, se espera al próximo arranque.
      final host = await _storage.invokeMethod<String>('hostKind');
      if (host != null && host != 'idle') return;
      final legacy = YomashiPublicStorage.legacyFolderPath;
      final target = YomashiPublicStorage.appFolderPath;
      if (legacy == null || target == null) return;
      if (onMoving != null && await Directory(legacy).exists()) {
        await onMoving();
      }
      final moved = await migrate(
        legacy: Directory(legacy),
        target: Directory(target),
        store: await LibraryStore.ensureInitialized(),
        prefixes: prefixPairs(),
      );
      // La caché del escaneo guarda rutas absolutas: se reconstruye.
      if (moved) await LibraryCacheService.clear();
    } catch (error) {
      await Diagnostics.record('storage_migration', error);
    }
  }

  /// Pares (anterior, nuevo) para cada forma en que Android nombra la raíz.
  static List<(String, String)> prefixPairs() => [
    for (final root in YomashiPublicStorage.rootAliases)
      (
        p.join(root, YomashiPublicStorage.folderName),
        p.join(root, YomashiPublicStorage.relativePath),
      ),
  ];

  @visibleForTesting
  static Future<bool> migrate({
    required Directory legacy,
    required Directory target,
    required LibraryStore store,
    required List<(String, String)> prefixes,
  }) async {
    var moved = false;
    if (await legacy.exists()) {
      await target.parent.create(recursive: true);
      if (!await target.exists()) {
        // Misma unidad: el cambio de nombre es instantáneo y no copia nada.
        await legacy.rename(target.path);
      } else {
        await _merge(legacy, target);
        await _removeIfEmpty(legacy);
      }
      moved = true;
    }
    for (final (from, to) in prefixes) {
      await store.relocatePathPrefix(from, to);
      await _relocatePreferences(from, to);
    }
    return moved;
  }

  /// Mueve lo que no exista en el destino; lo que ya existe allí se conserva.
  static Future<void> _merge(Directory from, Directory to) async {
    await for (final entity in from.list(followLinks: false)) {
      final destination = p.join(to.path, p.basename(entity.path));
      final type = await FileSystemEntity.type(destination, followLinks: false);
      if (type == FileSystemEntityType.notFound) {
        await entity.rename(destination);
      } else if (entity is Directory &&
          type == FileSystemEntityType.directory) {
        await _merge(entity, Directory(destination));
        await _removeIfEmpty(entity);
      }
    }
  }

  static Future<void> _removeIfEmpty(Directory directory) async {
    final contents = await directory.list(followLinks: false).toList();
    final onlyMarker = contents.every(
      (e) => e is File && p.basename(e.path) == '.nomedia',
    );
    if (onlyMarker) await directory.delete(recursive: true);
  }

  static String _relocate(String value, String from, String to) {
    if (value == from) return to;
    if (value.startsWith('$from/')) return to + value.substring(from.length);
    // Rutas dentro de JSON guardado como texto.
    return value.replaceAll('$from/', '$to/').replaceAll('"$from"', '"$to"');
  }

  static Future<void> _relocatePreferences(String from, String to) async {
    final prefs = await SharedPreferences.getInstance();
    for (final key in prefs.getKeys()) {
      final value = prefs.get(key);
      if (value is String) {
        final next = _relocate(value, from, to);
        if (next != value) await prefs.setString(key, next);
      } else if (value is List) {
        final list = value.map((e) => '$e').toList();
        final next = [for (final item in list) _relocate(item, from, to)];
        if (!listEquals(next, list)) await prefs.setStringList(key, next);
      }
    }
  }
}
