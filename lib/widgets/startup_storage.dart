import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/download_queue_provider.dart';
import '../providers/library_provider.dart';
import '../services/download_notification_service.dart';
import '../utils/permissions.dart';
import '../utils/preferences.dart';
import '../utils/yomashi_public_storage.dart';

/// Permiso "todos los archivos" + carpeta pública `YomaShi` en la raíz.
class StartupStorage {
  StartupStorage._();

  static Future<void> runFirstLaunch(BuildContext context) async {
    if (!Platform.isAndroid) {
      return;
    }

    final granted = await StoragePermissionService.isManageAllFilesGranted();
    if (!granted && context.mounted) {
      final explained = await PreferencesService.getManageStorageExplained();
      if (!explained && context.mounted) {
        await _showExplainDialog(context);
        await PreferencesService.setManageStorageExplained(true);
        if (context.mounted) {
          await StoragePermissionService.requestManageAllFiles();
        }
      }
    }

    if (context.mounted) {
      await ensureFolderAndDefaults(context);
    }

    // Tras el diálogo de almacenamiento: la Activity ya existe y el sistema
    // puede mostrar el prompt de notificaciones (Android 13+).
    await DownloadNotificationService.ensureReady(requestPermission: true);
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

  static Future<void> _showExplainDialog(BuildContext context) async {
    final path =
        YomashiPublicStorage.appFolderPath ??
        '/storage/emulated/0/${YomashiPublicStorage.folderName}';

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        final theme = Theme.of(dialogContext);
        return AlertDialog(
          title: const Text('Acceso a todos los archivos'),
          content: Text(
            'YomaShi necesita el permiso de gestionar todos los archivos '
            'para guardar mangas en la raíz del teléfono.\n\n'
            'La carpeta se creará aquí:\n$path',
            style: theme.textTheme.bodyMedium?.copyWith(height: 1.45),
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Continuar'),
            ),
          ],
        );
      },
    );
  }
}
