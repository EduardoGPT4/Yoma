import 'dart:io';
import 'package:flutter/services.dart';
import '../utils/app_failure.dart';

class StorageMetrics {
  static const _channel = MethodChannel('app.yomashi.reader/storage');
  static Future<int?> freeBytes(String path) async {
    if (!Platform.isAndroid) return null;
    return _channel.invokeMethod<int>('freeBytes', path);
  }

  static Future<void> requireSpace(String path, int bytes) async {
    final available = await freeBytes(path);
    if (available != null && available < bytes + 16 * 1024 * 1024) {
      throw const AppFailure(
        FailureKind.storage,
        'Espacio insuficiente. Libera almacenamiento y reintenta.',
      );
    }
  }

  static String format(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KiB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MiB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GiB';
  }
}
