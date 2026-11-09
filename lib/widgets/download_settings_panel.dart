import 'dart:async';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../providers/download_queue_provider.dart';
import '../providers/library_provider.dart';

/// Carpeta, WiFi, hilos y límite de velocidad. Se muestra en Perfil.
class DownloadSettingsPanel extends StatelessWidget {
  const DownloadSettingsPanel({super.key});

  Future<void> _report(
    BuildContext context,
    Future<void> Function() action,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await action();
    } catch (error) {
      if (context.mounted) {
        messenger.showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }

  Future<void> _changeFolder(BuildContext context) async {
    final downloader = context.read<DownloadQueueProvider>();
    final library = context.read<LibraryProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final changed = await downloader.chooseDownloadRoot();
    if (!context.mounted || !changed) {
      return;
    }

    final folder = downloader.downloadFolderPath;
    if (folder != null) {
      await library.addLibraryPath(folder);
    }
    messenger.showSnackBar(
      const SnackBar(content: Text('Carpeta de descargas actualizada.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<DownloadQueueProvider>();

    return Column(
      children: [
        _SettingsSurface(
          children: [
            _FolderRow(
              folderPath: provider.downloadFolderPath,
              onChange: () =>
                  unawaited(_report(context, () => _changeFolder(context))),
            ),
            const Divider(height: 1),
            SwitchListTile.adaptive(
              dense: true,
              visualDensity: VisualDensity.compact,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12),
              secondary: const Icon(Icons.wifi_rounded, size: 20),
              title: const Text('Solo WiFi'),
              value: provider.wifiOnlyDownloads,
              onChanged: (value) {
                unawaited(
                  _report(context, () => provider.setWifiOnlyDownloads(value)),
                );
              },
            ),
            const Divider(height: 1),
            ListTile(
              dense: true,
              visualDensity: VisualDensity.compact,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12),
              leading: const Icon(Icons.speed_rounded, size: 20),
              title: const Text('Descarga multi-hilo'),
              trailing: Text('${provider.downloadThreads} hilos'),
              onTap: () =>
                  _report(context, () => _pickThreads(context, provider)),
            ),
            const Divider(height: 1),
            ListTile(
              dense: true,
              visualDensity: VisualDensity.compact,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12),
              leading: const Icon(Icons.network_check_rounded, size: 20),
              title: const Text('Límite de velocidad'),
              trailing: Text(_speedLabel(provider.speedLimitKbps)),
              onTap: () =>
                  _report(context, () => _pickSpeed(context, provider)),
            ),
          ],
        ),
      ],
    );
  }

  static String _speedLabel(int kbps) {
    if (kbps <= 0) {
      return 'Ilimitado';
    }
    if (kbps < 1024) {
      return '$kbps KB/s';
    }
    final mbps = kbps / 1024;
    if (mbps == mbps.roundToDouble()) {
      return '${mbps.round()} MB/s';
    }
    return '${mbps.toStringAsFixed(1)} MB/s';
  }

  Future<void> _pickThreads(
    BuildContext context,
    DownloadQueueProvider provider,
  ) async {
    const options = <int>[1, 2, 3, 4, 6, 8];
    final picked = await showModalBottomSheet<int>(
      context: context,
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final n in options)
                ListTile(
                  dense: true,
                  title: Text('$n hilos'),
                  trailing: n == provider.downloadThreads
                      ? const Icon(Icons.check_rounded)
                      : null,
                  onTap: () => Navigator.of(sheetContext).pop(n),
                ),
            ],
          ),
        );
      },
    );
    if (picked != null) {
      await provider.setDownloadThreads(picked);
    }
  }

  Future<void> _pickSpeed(
    BuildContext context,
    DownloadQueueProvider provider,
  ) async {
    const options = <int>[0, 256, 512, 1024, 2048, 5120, 10240];
    final picked = await showModalBottomSheet<int>(
      context: context,
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final n in options)
                ListTile(
                  dense: true,
                  title: Text(_speedLabel(n)),
                  trailing: n == provider.speedLimitKbps
                      ? const Icon(Icons.check_rounded)
                      : null,
                  onTap: () => Navigator.of(sheetContext).pop(n),
                ),
            ],
          ),
        );
      },
    );
    if (picked != null) {
      await provider.setSpeedLimitKbps(picked);
    }
  }
}

class _SettingsSurface extends StatelessWidget {
  final List<Widget> children;

  const _SettingsSurface({required this.children});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.colorScheme.onSurface.withAlpha(18)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: children),
    );
  }
}

class _FolderRow extends StatelessWidget {
  final String? folderPath;
  final VoidCallback onChange;

  const _FolderRow({required this.folderPath, required this.onChange});

  String get _friendlyLabel {
    if (folderPath == null || folderPath!.trim().isEmpty) {
      return 'Sin configurar';
    }
    final parent = p.basename(p.dirname(folderPath!));
    final folderName = p.basename(folderPath!);
    if (parent.isEmpty || parent == folderName) {
      return folderName;
    }
    return '$parent / $folderName';
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      visualDensity: VisualDensity.compact,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12),
      leading: const Icon(Icons.folder_rounded, size: 20),
      title: const Text('Carpeta de descargas'),
      subtitle: Text(
        _friendlyLabel,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: TextButton(onPressed: onChange, child: const Text('Cambiar')),
    );
  }
}
