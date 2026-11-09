import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/manga.dart';
import '../providers/library_provider.dart';
import '../providers/download_queue_provider.dart';
import '../services/image_repository.dart';
import '../services/storage_maintenance.dart';
import '../services/storage_metrics.dart';
import '../utils/thumbnail_service.dart';
import '../services/repair_service.dart';
import '../services/reader_crop_service.dart';
import '../utils/title_sanitizer.dart';

class StorageSnapshot {
  final Map<String, int> sizes;
  final int cache;
  final int thumbnails;
  final int? free;
  const StorageSnapshot({
    required this.sizes,
    required this.cache,
    required this.thumbnails,
    this.free,
  });
}

enum _StorageOrder { size, title }

class StorageScreen extends StatefulWidget {
  final Future<StorageSnapshot> Function(List<Manga>, String?)? loadMetrics;
  const StorageScreen({super.key, this.loadMetrics});
  @override
  State<StorageScreen> createState() => _StorageScreenState();
}

class _StorageScreenState extends State<StorageScreen> {
  Map<String, int> _sizes = {};
  int _cache = 0, _thumbnails = 0;
  int? _free;
  bool _busy = true;
  String _activity = 'Calculando almacenamiento…';
  bool _hasMeasurement = false;
  String _query = '';
  _StorageOrder _order = _StorageOrder.size;
  String? _error;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  Future<void> _refresh() async {
    if (!mounted) return;
    final library = context.read<LibraryProvider>();
    final root = context.read<DownloadQueueProvider>().downloadRoot;
    setState(() {
      _busy = true;
      _activity = 'Calculando almacenamiento…';
      _hasMeasurement = false;
      _error = null;
    });
    try {
      final snapshot = await (widget.loadMetrics ?? _loadMetrics)(
        List<Manga>.of(library.mangas),
        root,
      );
      if (mounted) {
        setState(() {
          _sizes = snapshot.sizes;
          _cache = snapshot.cache;
          _thumbnails = snapshot.thumbnails;
          _free = snapshot.free;
          _hasMeasurement = true;
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  static Future<StorageSnapshot> _loadMetrics(
    List<Manga> mangas,
    String? root,
  ) async {
    final sizes = await StorageMaintenance.measure(mangas);
    final cache = await ImageRepository.shared.cacheSize();
    final thumbnails = await ThumbnailService.cacheSize();
    final free = root == null ? null : await StorageMetrics.freeBytes(root);
    return StorageSnapshot(
      sizes: sizes,
      cache: cache,
      thumbnails: thumbnails,
      free: free,
    );
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _activity = 'Aplicando cambios…';
    });
    String? actionError;
    try {
      await action();
    } catch (error) {
      actionError = error.toString();
    } finally {
      if (mounted) await _refresh();
      if (mounted && actionError != null) setState(() => _error = actionError);
    }
  }

  Future<void> _migrate() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Actualizar carpetas antiguas'),
        content: const Text(
          'Añade los metadatos de YomaShi a las carpetas que aún no los tienen. Las imágenes, los nombres de las carpetas y tu progreso se conservan.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Actualizar'),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    await _run(() async {
      final library = context.read<LibraryProvider>();
      final count = await StorageMaintenance.migrateLegacy(library.mangas);
      await library.rescan();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('$count carpetas actualizadas.')));
    });
  }

  Future<void> _delete(Manga manga, String path) async {
    final downloader = context.read<DownloadQueueProvider>();
    final library = context.read<LibraryProvider>();
    final yes = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Eliminar capítulo'),
        content: const Text(
          'Se pausarán las descargas de esta obra y se eliminarán los archivos del capítulo. El historial de lectura se conserva.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    await _run(() async {
      await downloader.pauseForManga(manga.sourceUrl ?? manga.path);
      await StorageMaintenance.deleteChapter(manga, path);
      await library.refreshMangaFolder(manga.path);
    });
  }

  @override
  Widget build(BuildContext context) {
    final allMangas = context.select<LibraryProvider, List<Manga>>(
      (p) => p.mangas,
    );
    final mangas =
        allMangas
            .where(
              (manga) => TitleSanitizer.clean(
                manga.title,
              ).toLowerCase().contains(_query.toLowerCase()),
            )
            .toList()
          ..sort((a, b) {
            if (_order == _StorageOrder.size) {
              final bySize = (_sizes[b.path] ?? 0).compareTo(
                _sizes[a.path] ?? 0,
              );
              if (bySize != 0) return bySize;
            }
            return a.title.toLowerCase().compareTo(b.title.toLowerCase());
          });
    final measured = _hasMeasurement && !_busy;
    String sizeLabel(int bytes) =>
        measured ? StorageMetrics.format(bytes) : '—';
    final libraryBytes = _sizes.values.fold(0, (a, b) => a + b);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Almacenamiento'),
        actions: [
          IconButton(
            tooltip: 'Actualizar tamaños',
            onPressed: _busy ? null : _refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: ListView.builder(
        itemCount: mangas.length + 1,
        itemBuilder: (context, index) {
          if (index == 0) {
            return Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_busy) ...[
                    const LinearProgressIndicator(),
                    const SizedBox(height: 12),
                    Text(_activity),
                    const SizedBox(height: 12),
                  ],
                  if (_error != null) Text(_error!),
                  Text(
                    'Total de biblioteca y caché: ${sizeLabel(libraryBytes + _cache + _thumbnails)}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text('Biblioteca: ${sizeLabel(libraryBytes)}'),
                  Text('Imágenes temporales: ${sizeLabel(_cache)}'),
                  Text('Miniaturas: ${sizeLabel(_thumbnails)}'),
                  if (_free != null)
                    Text('Espacio libre: ${sizeLabel(_free!)}'),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      TextButton(
                        onPressed: _busy
                            ? null
                            : () => _run(() async {
                                await ImageRepository.shared.trim(clear: true);
                                await ThumbnailService.clearCache();
                                final crops =
                                    await ReaderCropService.directory();
                                if (await crops.exists()) {
                                  await crops.delete(recursive: true);
                                }
                                PaintingBinding.instance.imageCache.clear();
                              }),
                        child: const Text('Limpiar caché'),
                      ),
                      TextButton(
                        onPressed: _busy
                            ? null
                            : () => _run(() async {
                                await StorageMaintenance.cleanParts(
                                  context.read<LibraryProvider>().libraryPaths,
                                );
                              }),
                        child: const Text('Limpiar parciales antiguos'),
                      ),
                      TextButton(
                        onPressed: _busy ? null : _migrate,
                        child: const Text('Actualizar carpetas antiguas'),
                      ),
                    ],
                  ),
                  Text(
                    'La actualización añade metadatos a carpetas antiguas sin mover tus imágenes.${_busy ? ' Las herramientas estarán disponibles al terminar el cálculo.' : ''}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    decoration: const InputDecoration(
                      labelText: 'Buscar en tu biblioteca',
                      prefixIcon: Icon(Icons.search),
                    ),
                    onChanged: (value) => setState(() => _query = value.trim()),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<_StorageOrder>(
                    initialValue: _order,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Ordenar por'),
                    items: const [
                      DropdownMenuItem(
                        value: _StorageOrder.size,
                        child: Text(
                          'Mayor tamaño',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      DropdownMenuItem(
                        value: _StorageOrder.title,
                        child: Text(
                          'Título A–Z',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                    onChanged: (value) {
                      if (value != null) setState(() => _order = value);
                    },
                  ),
                  const SizedBox(height: 12),
                  Text('${mangas.length} de ${allMangas.length} mangas'),
                  if (mangas.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Text(
                        'No hay mangas que coincidan con la búsqueda.',
                      ),
                    ),
                ],
              ),
            );
          }
          final manga = mangas[index - 1];
          return ExpansionTile(
            key: PageStorageKey(manga.path),
            title: Text(TitleSanitizer.clean(manga.title)),
            subtitle: Text(sizeLabel(_sizes[manga.path] ?? 0)),
            children: [
              ListTile(
                leading: const Icon(Icons.healing),
                title: const Text('Revisar y reparar descarga'),
                subtitle: const Text(
                  'Conserva las páginas válidas y recupera solo las ausentes o dañadas.',
                ),
                onTap: _busy
                    ? null
                    : () => _run(() async {
                        final queue = context.read<DownloadQueueProvider>();
                        final report = await RepairService.inspect(manga.path);
                        if (!context.mounted) return;
                        if (report.damaged.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                '${report.checkedPages} páginas verificadas. No hay daños.',
                              ),
                            ),
                          );
                          return;
                        }
                        final yes = await showDialog<bool>(
                          context: context,
                          builder: (c) => AlertDialog(
                            title: const Text('Reparar descarga'),
                            content: Text(
                              '${report.missingPages} páginas ausentes o dañadas en ${report.damaged.length} capítulos. Se conservarán las páginas válidas y el progreso.',
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(c, false),
                                child: const Text('Cancelar'),
                              ),
                              FilledButton(
                                onPressed: () => Navigator.pop(c, true),
                                child: const Text('Reparar'),
                              ),
                            ],
                          ),
                        );
                        if (yes == true) await queue.repair(manga.path);
                      }),
              ),
              for (final chapter in manga.chapters)
                ListTile(
                  title: Text(chapter.title),
                  subtitle: Text(chapter.complete ? 'Completo' : 'Parcial'),
                  trailing: IconButton(
                    tooltip: 'Eliminar capítulo',
                    onPressed: _busy
                        ? null
                        : () => _delete(manga, chapter.path),
                    icon: const Icon(Icons.delete_outline),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
