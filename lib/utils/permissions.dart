import 'dart:io';

import 'package:permission_handler/permission_handler.dart';

class StoragePermissionResult {
  final bool granted;
  final bool permanentlyDenied;

  const StoragePermissionResult({
    required this.granted,
    required this.permanentlyDenied,
  });
}

class StoragePermissionService {
  static Future<bool> isManageAllFilesGranted() async {
    if (!Platform.isAndroid) {
      return true;
    }
    if (await Permission.manageExternalStorage.isGranted) {
      return true;
    }
    return await Permission.storage.isGranted;
  }

  /// Pide **gestionar todos los archivos** (Android 11+ abre Ajustes).
  static Future<StoragePermissionResult> requestManageAllFiles() async {
    if (!Platform.isAndroid) {
      return const StoragePermissionResult(
        granted: true,
        permanentlyDenied: false,
      );
    }

    final manage = await Permission.manageExternalStorage.request();
    if (manage.isGranted) {
      return const StoragePermissionResult(
        granted: true,
        permanentlyDenied: false,
      );
    }

    final storage = await Permission.storage.request();
    return StoragePermissionResult(
      granted: storage.isGranted,
      permanentlyDenied:
          manage.isPermanentlyDenied || storage.isPermanentlyDenied,
    );
  }

  /// Permiso de notificaciones (Android 13+). Hay que pedirlo con la Activity lista.
  static Future<bool> requestNotifications() async {
    if (!Platform.isAndroid) {
      return true;
    }
    final status = await Permission.notification.status;
    if (status.isGranted) {
      return true;
    }
    final result = await Permission.notification.request();
    return result.isGranted;
  }

  static Future<bool> notificationsGranted() async {
    if (!Platform.isAndroid) {
      return true;
    }
    return Permission.notification.isGranted;
  }

  static Future<StoragePermissionResult> request() async {
    if (!Platform.isAndroid) {
      return const StoragePermissionResult(
        granted: true,
        permanentlyDenied: false,
      );
    }

    final manage = await requestManageAllFiles();
    if (manage.granted) {
      return manage;
    }

    final photos = await Permission.photos.request();
    return StoragePermissionResult(
      granted: photos.isGranted,
      permanentlyDenied: manage.permanentlyDenied || photos.isPermanentlyDenied,
    );
  }
}
