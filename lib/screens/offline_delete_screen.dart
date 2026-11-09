import '../providers/download_queue_provider.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

import '../models/manga.dart';
import '../providers/categories_provider.dart';
import '../providers/chapter_read_provider.dart';
import '../providers/favorites_provider.dart';
import '../providers/library_provider.dart';
import '../utils/permissions.dart';
import '../utils/sorting.dart';
import '../utils/title_sanitizer.dart';
import '../widgets/home_content_layout.dart';
import '../widgets/search_bar_field.dart';

/// Lista de mangas locales para borrar la carpeta contenedora de cada uno.
class OfflineDeleteScreen extends StatefulWidget {
  const OfflineDeleteScreen({super.key});

  @override
  State<OfflineDeleteScreen> createState() => _OfflineDeleteScreenState();
}

class _OfflineDeleteScreenState extends State<OfflineDeleteScreen> {
  final TextEditingController _searchController = TextEditingController();
  final Set<String> _selectedPaths = <String>{};
  bool _deleting = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<Manga> _visibleMangas(List<Manga> all) {
    final query = _searchController.text.trim().toLowerCase();
    final items = List<Manga>.from(all);
    items.sort((a, b) => naturalCompare(a.title, b.title));
    if (query.isEmpty) {
      return items;
    }
    return items.where((manga) {
      final title = TitleSanitizer.clean(manga.title).toLowerCase();
      return title.contains(query);
    }).toList();
  }

  void _toggle(String path) {
    setState(() {
      if (_selectedPaths.contains(path)) {
        _selectedPaths.remove(path);
      } else {
        _selectedPaths.add(path);
      }
    });
  }

  void _toggleVisible(List<Manga> visible) {
    final allSelected =
        visible.isNotEmpty &&
        visible.every((m) => _selectedPaths.contains(m.path));
    setState(() {
      if (allSelected) {
        for (final manga in visible) {
          _selectedPaths.remove(manga.path);
        }
      } else {
        for (final manga in visible) {
          _selectedPaths.add(manga.path);
        }
      }
    });
  }

  Future<void> _confirmAndDelete(List<Manga> allMangas) async {
    if (_deleting || _selectedPaths.isEmpty) {
      return;
    }

    final selected = allMangas
        .where((manga) => _selectedPaths.contains(manga.path))
        .toList();
    if (selected.isEmpty) {
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final count = selected.length;
        return AlertDialog(
          title: Text(
            count == 1 ? '¿Eliminar este manga?' : '¿Eliminar $count mangas?',
          ),
          content: Text(
            count == 1
                ? 'Se borrará por completo la carpeta de "${TitleSanitizer.clean(selected.first.title)}", con todos sus capítulos. Esta acción no se puede deshacer.'
                : 'Se borrará por completo la carpeta de cada manga seleccionado, con todos sus capítulos. Esta acción no se puede deshacer.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(dialogContext).colorScheme.error,
                foregroundColor: Theme.of(dialogContext).colorScheme.onError,
              ),
              child: const Text('Eliminar'),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) {
      return;
    }

    final permission = await StoragePermissionService.request();
    if (!permission.granted) {
      if (permission.permanentlyDenied) {
        await openAppSettings();
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Permiso requerido para borrar carpetas.'),
          ),
        );
      }
      return;
    }

    if (!mounted) {
      return;
    }

    setState(() => _deleting = true);
    final library = context.read<LibraryProvider>();
    final favorites = context.read<FavoritesProvider>();
    final categories = context.read<CategoriesProvider>();
    final chapterRead = context.read<ChapterReadProvider>();

    final downloader = context.read<DownloadQueueProvider>();
    for (final manga in selected) {
      await downloader.pauseForManga(manga.sourceUrl ?? manga.path);
    }
    final result = await library.deleteMangas(selected);
    final removed = result.deletedPaths;

    await favorites.removeMany(removed);
    await categories.removeMangaKeys(removed);
    await chapterRead.removeUnderPrefixes(removed);

    if (!mounted) {
      return;
    }

    setState(() {
      _deleting = false;
      _selectedPaths.removeAll(removed);
    });

    final messenger = ScaffoldMessenger.of(context);
    if (result.deletedCount == 0) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            result.failedTitles.isEmpty
                ? 'No se pudo eliminar ningún manga.'
                : 'No se pudo eliminar: ${result.failedTitles.join(', ')}',
          ),
        ),
      );
      return;
    }

    final successText = result.deletedCount == 1
        ? 'Se eliminó 1 manga y su carpeta.'
        : 'Se eliminaron ${result.deletedCount} mangas y sus carpetas.';
    if (result.failedTitles.isEmpty) {
      messenger.showSnackBar(SnackBar(content: Text(successText)));
      Navigator.of(context).pop();
      return;
    }

    messenger.showSnackBar(
      SnackBar(
        content: Text(
          '$successText No se pudo borrar: ${result.failedTitles.join(', ')}',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final library = context.watch<LibraryProvider>();
    final allMangas = library.mangas;
    final visible = _visibleMangas(allMangas);
    final selectedCount = visible
        .where((manga) => _selectedPaths.contains(manga.path))
        .length;
    final allVisibleSelected =
        visible.isNotEmpty && selectedCount == visible.length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Eliminar mangas'),
        actions: [
          if (visible.isNotEmpty)
            TextButton(
              onPressed: _deleting ? null : () => _toggleVisible(visible),
              child: Text(allVisibleSelected ? 'Ninguno' : 'Todos'),
            ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
            child: SearchBarField(
              controller: _searchController,
              hintText: 'Buscar por nombre',
              onChanged: (_) => setState(() {}),
              onClear: () {
                _searchController.clear();
                setState(() {});
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                selectedCount == 0
                    ? '${visible.length} mangas en offline'
                    : '$selectedCount de ${visible.length} seleccionados',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withAlpha(170),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          Expanded(
            child: allMangas.isEmpty
                ? const _EmptyDeleteList()
                : visible.isEmpty
                ? Center(
                    child: Text(
                      'Ningún manga coincide con la búsqueda.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurface.withAlpha(170),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                    itemCount: visible.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final manga = visible[index];
                      final selected = _selectedPaths.contains(manga.path);
                      return _MangaDeleteTile(
                        title: TitleSanitizer.clean(manga.title),
                        chapterCount: manga.chapterCount,
                        selected: selected,
                        enabled: !_deleting,
                        onTap: () => _toggle(manga.path),
                      );
                    },
                  ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                20,
                8,
                20,
                HomeContentLayout.sectionSpacing,
              ),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _deleting || selectedCount == 0
                      ? null
                      : () => unawaited(_confirmAndDelete(allMangas)),
                  style: FilledButton.styleFrom(
                    backgroundColor: theme.colorScheme.error,
                    foregroundColor: theme.colorScheme.onError,
                    disabledBackgroundColor: theme.colorScheme.error.withAlpha(
                      60,
                    ),
                  ),
                  icon: _deleting
                      ? SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: theme.colorScheme.onError,
                          ),
                        )
                      : const Icon(Icons.delete_rounded),
                  label: Text(
                    selectedCount == 0
                        ? 'Eliminar'
                        : 'Eliminar ($selectedCount)',
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MangaDeleteTile extends StatelessWidget {
  final String title;
  final int chapterCount;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  const _MangaDeleteTile({
    required this.title,
    required this.chapterCount,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final chaptersLabel = chapterCount == 1
        ? '1 capítulo'
        : '$chapterCount capítulos';

    return Material(
      color: selected
          ? theme.colorScheme.error.withAlpha(22)
          : theme.colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: selected
              ? theme.colorScheme.error.withAlpha(90)
              : theme.colorScheme.onSurface.withAlpha(18),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: CheckboxListTile(
        value: selected,
        onChanged: enabled ? (_) => onTap() : null,
        title: Text(
          title.isEmpty ? 'Manga' : title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w800,
            letterSpacing: -0.2,
          ),
        ),
        subtitle: Text(
          chaptersLabel,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurface.withAlpha(160),
            fontWeight: FontWeight.w600,
          ),
        ),
        activeColor: theme.colorScheme.error,
        controlAffinity: ListTileControlAffinity.leading,
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      ),
    );
  }
}

class _EmptyDeleteList extends StatelessWidget {
  const _EmptyDeleteList();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.folder_off_outlined,
              size: 36,
              color: theme.colorScheme.onSurface.withAlpha(120),
            ),
            const SizedBox(height: 12),
            Text(
              'No hay mangas descargados',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Cuando descargues títulos aparecerán aquí para poder borrar su carpeta.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface.withAlpha(170),
                fontWeight: FontWeight.w600,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
