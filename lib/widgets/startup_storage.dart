import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/download_queue_provider.dart';
import '../providers/library_provider.dart';
import '../services/download_notification_service.dart';
import '../utils/yomashi_public_storage.dart';
import 'permissions_screen.dart';

/// Permisos de Yoma + carpeta pública `YomaShi` en la raíz.
class StartupStorage {
  StartupStorage._();

  /// Pantalla de permisos (si falta alguno) y después la carpeta `YomaShi`.
  static Future<void> runFirstLaunch(BuildContext context) async {
    if (!Platform.isAndroid) {
      return;
    }
    await PermissionsGate.showIfNeeded(context);
    if (context.mounted) {
      await ensureFolderAndDefaults(context);
    }
    // Solo prepara el canal: el permiso ya se pidió en la pantalla.
    await DownloadNotificationService.ensureReady();
  }

  static Future<void> ensureFolderAndDefaults(BuildContext context) async {
    if (!Platform.isAndroid) {
      return;
    }

    final folder = await YomashiPublicStorage.ensureAppFolder();
    if (folder == null || !context.mounted) {
      return;
    }

    final downloader = context.read<DownloadQueueProvider>();
    final library = context.read<LibraryProvider>();
    await downloader.applyDefaultDownloadRoot(folder.path);

    final mangaFolder = downloader.downloadFolderPath;
    if (mangaFolder != null &&
        mangaFolder.isNotEmpty &&
        !library.libraryPaths.contains(mangaFolder)) {
      await library.addLibraryPath(mangaFolder);
    }
  }
}
