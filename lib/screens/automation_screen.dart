import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import '../models/automation_settings.dart';
import '../data/library_store.dart';
import '../providers/download_queue_provider.dart';
import '../providers/library_provider.dart';
import '../providers/favorites_provider.dart';
import '../providers/chapter_read_provider.dart';
import '../providers/categories_provider.dart';
import '../providers/reader_settings_provider.dart';
import '../providers/source_provider.dart';
import '../providers/theme_accent_provider.dart';
import '../providers/density_provider.dart';
import '../providers/profile_provider.dart';
import '../services/maintenance_service.dart';
import '../services/rotating_backup_service.dart';
import '../utils/backup_service.dart';

class AutomationScreen extends StatefulWidget {
  const AutomationScreen({super.key});
  @override
  State<AutomationScreen> createState() => _AutomationScreenState();
}

class _AutomationScreenState extends State<AutomationScreen> {
  AutomationSettings? _settings;
  List<File> _copies = [];
  List<Map<String, dynamic>> _updates = [];
  String? _error;
  String _backupPath = '';
  bool _busy = false;
  Timer? _timer;
  @override
  void initState() {
    super.initState();
    unawaited(_refresh());
    _timer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (mounted) unawaited(_refresh());
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    try {
      final settings = await AutomationSettings.load();
      final copies = await RotatingBackupService.files();
      final backupPath = (await RotatingBackupService.directory()).path;
      final updates = await (await LibraryStore.ensureInitialized())
          .readRecords('favorite_updates');
      if (mounted) {
        setState(() {
          _settings = settings;
          _copies = copies;
          _backupPath = backupPath;
          _updates = updates;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Future<void> _run(Future<void> Function() work) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await work();
      await _refresh();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _change(String key, Object value) => _run(() async {
    final next = AutomationSettings.fromMap({
      ..._settings!.toMap(),
      key: value,
    });
    await next.save();
    await MaintenancePlatform.schedule(next);
  });
  Future<void> _restore(File copy) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Restaurar copia'),
        content: const Text(
          'Se combinarán el progreso, favoritos, marcadores y ajustes con esta copia. Se conservará una copia previa.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Restaurar'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    final library = context.read<LibraryProvider>(),
        source = context.read<SourceProvider>(),
        accent = context.read<ThemeAccentProvider>(),
        density = context.read<DensityProvider>(),
        profile = context.read<ProfileProvider>(),
        favorites = context.read<FavoritesProvider>(),
        reads = context.read<ChapterReadProvider>(),
        categories = context.read<CategoriesProvider>(),
        settings = context.read<ReaderSettingsProvider>();
    await _run(() async {
      await BackupService.importFromFile(copy, merge: true);
      await library.load();
      await favorites.load();
      await reads.load();
      await categories.load();
      await settings.load();
      await source.load();
      await accent.load();
      await density.load();
      await profile.load();
      await MaintenancePlatform.schedule(await AutomationSettings.load());
    });
  }

  Future<void> _showBackupLocation() async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Ubicación de las copias'),
        content: SelectableText(_backupPath),
        actions: [
          TextButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: _backupPath));
              if (!dialogContext.mounted) return;
              Navigator.pop(dialogContext);
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Ubicación copiada.')),
              );
            },
            icon: const Icon(Icons.copy_outlined),
            label: const Text('Copiar ubicación'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }

  Widget _choice({
    required String title,
    String? subtitle,
    required int value,
    required Set<int> options,
    required String Function(int) label,
    required String setting,
  }) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
    child: DropdownButtonFormField<int>(
      initialValue: value,
      key: ValueKey('$setting:$value'),
      isExpanded: true,
      decoration: InputDecoration(
        labelText: title,
        helperText: subtitle,
        helperMaxLines: 3,
      ),
      items: options
          .map((n) => DropdownMenuItem(value: n, child: Text(label(n))))
          .toList(),
      onChanged: _busy ? null : (v) => _change(setting, v!),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final s = _settings;
    return Scaffold(
      appBar: AppBar(title: const Text('Automatización y copias')),
      body: s == null
          ? Center(
              child: _error == null
                  ? const CircularProgressIndicator()
                  : Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(_error!),
                          const SizedBox(height: 12),
                          FilledButton(
                            onPressed: _refresh,
                            child: const Text('Reintentar'),
                          ),
                        ],
                      ),
                    ),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (_busy) const LinearProgressIndicator(),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                _AutomationSection(
                  title: 'Novedades y lectura preparada',
                  icon: Icons.auto_stories_outlined,
                  children: [
                    SwitchListTile(
                      title: const Text('Buscar capítulos nuevos'),
                      subtitle: const Text(
                        'Android programa las comprobaciones en segundo plano.',
                      ),
                      value: s.updates,
                      onChanged: _busy ? null : (v) => _change('updates', v),
                    ),
                    SwitchListTile(
                      title: const Text('Descargar novedades de favoritos'),
                      subtitle: const Text(
                        'Descarga los capítulos nuevos detectados después de la primera comprobación.',
                      ),
                      value: s.autoDownload,
                      onChanged: _busy
                          ? null
                          : (v) => _change('autoDownload', v),
                    ),
                    _choice(
                      title: 'Preparar siguientes capítulos',
                      subtitle:
                          'Se preparan al abrir un capítulo. Tus descargas se conservan.',
                      value: s.aheadCount,
                      options: {0, 1, 3, 5, 10, s.aheadCount},
                      label: (n) => n == 0 ? 'Desactivado' : '$n capítulos',
                      setting: 'aheadCount',
                    ),
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: FilledButton.icon(
                        onPressed: _busy
                            ? null
                            : () => _run(
                                () => context
                                    .read<DownloadQueueProvider>()
                                    .runMaintenance(manual: true),
                              ),
                        icon: const Icon(Icons.update),
                        label: const Text('Comprobar favoritos ahora'),
                      ),
                    ),
                    for (final update in _updates)
                      ListTile(
                        title: Text(update['title'] as String? ?? ''),
                        subtitle: Text(
                          '${(update['new'] as List? ?? []).length} novedades · ${AutomationDisplay.timestamp(update['checkedAt'] as int? ?? 0)}',
                        ),
                        trailing: (update['new'] as List? ?? []).isEmpty
                            ? const Icon(
                                Icons.done,
                                semanticLabel: 'Sin novedades pendientes',
                              )
                            : IconButton(
                                tooltip: 'Marcar novedades vistas',
                                icon: const Icon(Icons.done),
                                onPressed: _busy
                                    ? null
                                    : () => _run(() async {
                                        await (await LibraryStore.ensureInitialized())
                                            .putRecord(
                                              'favorite_updates',
                                              update['id'] as String,
                                              {...update, 'new': []},
                                            );
                                      }),
                              ),
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                _AutomationSection(
                  title: 'Condiciones de descarga',
                  icon: Icons.tune_rounded,
                  children: [
                    SwitchListTile(
                      title: const Text('Solo con Wi-Fi'),
                      value: s.wifiOnly,
                      onChanged: _busy ? null : (v) => _change('wifiOnly', v),
                    ),
                    SwitchListTile(
                      title: const Text('Solo mientras carga'),
                      value: s.chargingOnly,
                      onChanged: _busy
                          ? null
                          : (v) => _change('chargingOnly', v),
                    ),
                    _choice(
                      title: 'Batería mínima',
                      value: s.batteryMinimum,
                      options: {10, 20, 30, 50, s.batteryMinimum},
                      label: (n) => '$n %',
                      setting: 'batteryMinimum',
                    ),
                    _choice(
                      title: 'Espacio para descargas automáticas',
                      value: s.budgetMiB,
                      options: {32, 128, 256, 512, 1024, 2048, s.budgetMiB},
                      label: AutomationDisplay.budget,
                      setting: 'budgetMiB',
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                _AutomationSection(
                  title: 'Copias de seguridad',
                  icon: Icons.backup_outlined,
                  children: [
                    SwitchListTile(
                      title: const Text('Copias automáticas diarias'),
                      subtitle: const Text(
                        'Guardan progreso, favoritos, marcadores y ajustes. Las imágenes se conservan en tu biblioteca.',
                      ),
                      value: s.backups,
                      onChanged: _busy ? null : (v) => _change('backups', v),
                    ),
                    _choice(
                      title: 'Copias conservadas',
                      value: s.backupRetention,
                      options: {2, 7, 14, 30, s.backupRetention},
                      label: (n) => '$n copias',
                      setting: 'backupRetention',
                    ),
                    ListTile(
                      leading: const Icon(Icons.folder_outlined),
                      title: const Text('Carpeta de copias'),
                      subtitle: Text(
                        _backupPath.contains('/YomaShi/Backups')
                            ? 'YomaShi / Backups'
                            : 'Carpeta privada de la app',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: _backupPath.isEmpty ? null : _showBackupLocation,
                    ),
                    if (!_backupPath.contains('/YomaShi/Backups'))
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 16),
                        child: Text(
                          'Exporta una copia para conservarla también fuera de la app.',
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        _copies.isEmpty
                            ? 'Todavía no hay copias automáticas.'
                            : 'Última copia: ${AutomationDisplay.backupDate(_copies.first)}',
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: OutlinedButton.icon(
                        onPressed: _busy
                            ? null
                            : () => _run(() async {
                                await RotatingBackupService.run(
                                  force: true,
                                  retain: s.backupRetention,
                                );
                              }),
                        icon: const Icon(Icons.save_outlined),
                        label: const Text('Crear copia ahora'),
                      ),
                    ),
                    if (_copies.isNotEmpty)
                      ExpansionTile(
                        title: Text('Copias disponibles (${_copies.length})'),
                        children: [
                          for (final copy in _copies)
                            ListTile(
                              title: Text(
                                'Copia · ${AutomationDisplay.backupDate(copy)}',
                              ),
                              subtitle: const Text('Toca para restaurar'),
                              onTap: _busy ? null : () => _restore(copy),
                              trailing: IconButton(
                                tooltip: 'Exportar copia',
                                icon: const Icon(Icons.save_alt),
                                onPressed: _busy
                                    ? null
                                    : () => _run(() async {
                                        await FilePicker.platform.saveFile(
                                          dialogTitle: 'Exportar copia',
                                          fileName: copy.uri.pathSegments.last,
                                          bytes: await copy.readAsBytes(),
                                        );
                                      }),
                              ),
                            ),
                        ],
                      ),
                    const SizedBox(height: 12),
                  ],
                ),
              ],
            ),
    );
  }
}

class _AutomationSection extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<Widget> children;
  const _AutomationSection({
    required this.title,
    required this.icon,
    required this.children,
  });
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            leading: Icon(icon, color: Theme.of(context).colorScheme.primary),
            title: Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
          ),
          ...children,
        ],
      ),
    ),
  );
}

/// Texto de presentación; las preferencias y los nombres de archivo no cambian.
class AutomationDisplay {
  static String timestamp(int milliseconds, {DateTime? now}) {
    if (milliseconds <= 0) return 'Sin registrar';
    final date = DateTime.fromMillisecondsSinceEpoch(milliseconds).toLocal();
    final current = (now ?? DateTime.now()).toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    bool sameDay(DateTime a, DateTime b) =>
        a.year == b.year && a.month == b.month && a.day == b.day;
    final day = sameDay(date, current)
        ? 'Hoy'
        : sameDay(date, DateTime(current.year, current.month, current.day - 1))
        ? 'Ayer'
        : '${two(date.day)}/${two(date.month)}${date.year == current.year ? '' : '/${date.year}'}';
    return '$day, ${two(date.hour)}:${two(date.minute)}';
  }

  static String budget(int mib) {
    if (mib < 1024) return '$mib MB';
    final gb = mib / 1024;
    return '${gb == gb.roundToDouble() ? gb.toInt() : gb.toStringAsFixed(1).replaceAll('.', ',')} GB';
  }

  static String backupDate(File file) {
    final name = file.uri.pathSegments.last;
    final match = RegExp(r'^yomashi_backup_(\d+)\.json$').firstMatch(name);
    final micros = int.tryParse(match?.group(1) ?? '');
    if (micros == null || micros <= 0) return 'Fecha desconocida';
    try {
      return timestamp(
        DateTime.fromMicrosecondsSinceEpoch(micros).millisecondsSinceEpoch,
      );
    } on ArgumentError {
      return 'Fecha desconocida';
    }
  }
}
