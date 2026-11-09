import '../providers/favorites_provider.dart';
import '../widgets/mal_sync_status.dart';
import '../widgets/contextual_tip.dart';
import '../data/download_storage.dart';
import '../services/download_events.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/online_manga.dart';
import '../providers/chapter_read_provider.dart';
import '../providers/download_queue_provider.dart';
import '../providers/library_provider.dart';
import '../services/online_catalog_service.dart';
import '../services/myanimelist_service.dart';
import '../utils/network_errors.dart';

import '../widgets/cached_thumbnail.dart';
import 'reader_screen.dart';
import 'myanimelist_screen.dart';

class OnlineMangaDetailScreen extends StatefulWidget {
  final String mangaUrl;
  final String? sourceId;

  const OnlineMangaDetailScreen({
    super.key,
    required this.mangaUrl,
    this.sourceId,
  });

  @override
  State<OnlineMangaDetailScreen> createState() =>
      _OnlineMangaDetailScreenState();
}

class _OnlineMangaDetailScreenState extends State<OnlineMangaDetailScreen> {
  late Future<OnlineMangaDetail> _detailFuture;
  StreamSubscription<String>? _downloadEvents;
  Map<String, String> _downloadStates = {};
  bool _descriptionExpanded = false;
  bool _loadingMoreChapters = false;
  bool _selectMode = false;
  final Set<int> _selectedChapters = <int>{};

  @override
  void initState() {
    super.initState();
    _detailFuture = OnlineCatalogService.fetchMangaDetail(
      widget.mangaUrl,
      sourceId: widget.sourceId,
    );
    _detailFuture.then((detail) {
      if (mounted) unawaited(_refreshDownloadStates(detail));
    }, onError: (Object _) {});
    _downloadEvents = DownloadEvents.completedFolders.listen((_) {
      _detailFuture.then((detail) {
        if (mounted) unawaited(_refreshDownloadStates(detail));
      }, onError: (Object _) {});
    });
  }

  @override
  void dispose() {
    unawaited(_downloadEvents?.cancel());
    super.dispose();
  }

  Future<void> _refreshDownloadStates(OnlineMangaDetail detail) async {
    final root = context.read<DownloadQueueProvider>().downloadRoot;
    if (root == null) return;
    try {
      final states = await DownloadStorage().chapterStates(root, detail);
      if (mounted) setState(() => _downloadStates = states);
    } catch (error) {
      debugPrint('Estado de descarga: $error');
    }
  }

  Future<void> _toggleChapterRead(OnlineMangaDetail detail, int index) async {
    final chapter = detail.chapters[index];
    final reads = context.read<ChapterReadProvider>();
    final wasRead = reads.isRead(chapter.path);
    await MyAnimeListService.shared
        .registerManga(detail.toOfflineManga(), chapters: [chapter])
        .catchError((_) {});
    if (!mounted) return;
    await reads.toggle(chapter.path);
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            wasRead
                ? 'Capítulo marcado como no leído'
                : 'Capítulo marcado como leído',
          ),
          action: SnackBarAction(
            label: 'Deshacer',
            onPressed: () {
              if (wasRead) {
                unawaited(reads.markRead(chapter.path));
              } else {
                unawaited(reads.markUnread(chapter.path));
              }
            },
          ),
        ),
      );
  }

  Future<void> _loadMoreChapters(
    OnlineMangaDetail detail, {
    bool all = false,
  }) async {
    if (_loadingMoreChapters) return;
    setState(() => _loadingMoreChapters = true);
    try {
      final next = all
          ? await OnlineCatalogService.completeDetail(detail)
          : await OnlineCatalogService.loadMoreChapters(detail);
      if (mounted) setState(() => _detailFuture = Future.value(next));
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(NetworkErrors.friendly(error))));
      }
    } finally {
      if (mounted) setState(() => _loadingMoreChapters = false);
    }
  }

  Future<void> _downloadOptions(OnlineMangaDetail detail) async {
    if (detail.hasMoreChapters) {
      await _loadMoreChapters(detail, all: true);
      detail = await _detailFuture;
      if (detail.hasMoreChapters || !mounted) return;
    }
    final read = context.read<ChapterReadProvider>();
    final library = context.read<LibraryProvider>();
    final downloader = context.read<DownloadQueueProvider>();
    try {
      await _ensureDownloadRoot(downloader, library);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(NetworkErrors.friendly(error))));
      }
      return;
    }
    await _refreshDownloadStates(detail);
    if (!mounted) return;
    final option = await showModalBottomSheet<String>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final item in <(String, String)>[
              ('missing', 'Solo capítulos faltantes'),
              ('unread', 'Solo no leídos'),
              ('next', 'Siguientes N capítulos'),
              ('range', 'Elegir rango'),
              ('all', 'Todos los capítulos'),
            ])
              ListTile(
                title: Text(item.$2),
                onTap: () => Navigator.pop(sheetContext, item.$1),
              ),
          ],
        ),
      ),
    );
    if (option == null || !mounted) return;
    var selected = {for (var i = 0; i < detail.chapters.length; i++) i};
    if (option == 'missing') {
      selected.removeWhere(
        (i) => _downloadStates[detail.chapters[i].path] == 'Descargado',
      );
    }
    if (option == 'unread') {
      selected.removeWhere((i) => read.isRead(detail.chapters[i].path));
    }
    if (option == 'range' || option == 'next') {
      final from = TextEditingController(
        text: option == 'next'
            ? (_continueChapterIndex(detail, library) + 1).toString()
            : '1',
      );
      final to = TextEditingController(
        text: option == 'next' ? '10' : detail.chapters.length.toString(),
      );
      final range = await showDialog<(int, int)>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(
            option == 'next' ? 'Siguientes capítulos' : 'Rango de capítulos',
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: from,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Desde (posición en la lista)',
                ),
              ),
              TextField(
                controller: to,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: option == 'next'
                      ? 'Cantidad'
                      : 'Hasta (posición en la lista)',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, (
                int.tryParse(from.text) ?? 0,
                int.tryParse(to.text) ?? 0,
              )),
              child: const Text('Descargar'),
            ),
          ],
        ),
      );
      from.dispose();
      to.dispose();
      if (range == null) return;
      final last = option == 'next' ? range.$1 + range.$2 - 1 : range.$2;
      if (range.$1 < 1 ||
          last < range.$1 ||
          range.$1 > detail.chapters.length) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Rango inválido.')));
        }
        return;
      }
      selected = {
        for (
          var i = range.$1 - 1;
          i < last.clamp(0, detail.chapters.length);
          i++
        )
          i,
      };
    }
    if (selected.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No hay capítulos pendientes para esa selección.'),
          ),
        );
      }
      return;
    }
    if (mounted) await _downloadManga(detail, chapterIndexes: selected);
  }

  Future<void> _ensureDownloadRoot(
    DownloadQueueProvider downloader,
    LibraryProvider library,
  ) async {
    if (downloader.downloadFolderPath == null) {
      final selected = await downloader.chooseDownloadRoot();
      if (!selected || downloader.downloadFolderPath == null) {
        throw StateError('Carpeta de descargas no configurada.');
      }
      await library.addLibraryPath(downloader.downloadFolderPath!);
    }
  }

  Future<void> _downloadManga(
    OnlineMangaDetail detail, {
    Set<int>? chapterIndexes,
  }) async {
    final downloader = context.read<DownloadQueueProvider>();
    final library = context.read<LibraryProvider>();
    final messenger = ScaffoldMessenger.of(context);

    try {
      await _ensureDownloadRoot(downloader, library);
      await downloader.enqueueManga(detail, chapterIndexes: chapterIndexes);

      if (mounted) {
        final count = chapterIndexes?.length ?? detail.chapters.length;
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              chapterIndexes == null
                  ? 'Manga agregado a la cola de descargas.'
                  : '$count capitulo(s) agregados a la cola.',
            ),
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text(NetworkErrors.friendly(error))),
        );
      }
    }
  }

  void _openReader(
    OnlineMangaDetail detail,
    int chapterIndex, {
    int pageIndex = 0,
  }) {
    final manga = detail.toOfflineManga();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ReaderScreen(
          manga: manga,
          initialChapterIndex: chapterIndex,
          initialPageIndex: pageIndex,
        ),
      ),
    );
  }

  Future<void> _resumeReader(
    OnlineMangaDetail detail,
    String path,
    int page,
  ) async {
    if (_loadingMoreChapters) return;
    setState(() => _loadingMoreChapters = true);
    try {
      final next = await OnlineCatalogService.resolveChapter(detail, path);
      if (!mounted) return;
      setState(() => _detailFuture = Future.value(next));
      _openReader(
        next,
        next.chapters.indexWhere((c) => c.path == path),
        pageIndex: page,
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(NetworkErrors.friendly(error))));
      }
    } finally {
      if (mounted) setState(() => _loadingMoreChapters = false);
    }
  }

  int _continueChapterIndex(OnlineMangaDetail detail, LibraryProvider library) {
    final progress = library.getProgress(detail.url);
    if (progress == null) {
      return 0;
    }

    final index = detail.chapters.indexWhere(
      (chapter) => chapter.path == progress.chapterPath,
    );
    return index < 0 ? 0 : index;
  }

  int _continuePageIndex(OnlineMangaDetail detail, LibraryProvider library) {
    final progress = library.getProgress(detail.url);
    return progress?.pageIndex ?? 0;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: FutureBuilder<OnlineMangaDetail>(
        future: _detailFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const _DetailLoadingView();
          }

          if (snapshot.hasError) {
            return _DetailErrorView(
              message: NetworkErrors.friendly(snapshot.error!),
              onRetry: () {
                setState(() {
                  _detailFuture = OnlineCatalogService.fetchMangaDetail(
                    widget.mangaUrl,
                    sourceId: widget.sourceId,
                  );
                });
              },
            );
          }

          final detail = snapshot.data;
          if (detail == null) {
            return const Center(child: Text('Sin datos.'));
          }

          final library = context.watch<LibraryProvider>();
          final chapterRead = context.watch<ChapterReadProvider>();
          final progress = library.getProgress(detail.url);

          final continuePage = _continuePageIndex(detail, library);
          final description =
              detail.description ?? 'Sin descripción disponible.';
          final canExpandDescription = description.length > 220;

          return CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              SliverAppBar(
                expandedHeight: 300,
                actions: [
                  IconButton(
                    tooltip: 'MyAnimeList',
                    icon: const Icon(Icons.sync_alt),
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) =>
                            MyAnimeListScreen(manga: detail.toOfflineManga()),
                      ),
                    ),
                  ),
                ],
                pinned: true,
                stretch: true,
                backgroundColor: theme.colorScheme.surface,
                surfaceTintColor: Colors.transparent,
                leading: Padding(
                  padding: const EdgeInsets.all(8),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.black.withAlpha(120),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white.withAlpha(30)),
                    ),
                    child: IconButton(
                      icon: const Icon(Icons.arrow_back_rounded),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ),
                ),
                flexibleSpace: FlexibleSpaceBar(
                  stretchModes: const [
                    StretchMode.zoomBackground,
                    StretchMode.blurBackground,
                  ],
                  background: Stack(
                    fit: StackFit.expand,
                    children: [
                      CachedThumbnail(
                        sourcePath: detail.coverUrl,
                        size: 720,
                        fit: BoxFit.cover,
                        placeholderBuilder: (_) => Container(
                          color: theme.colorScheme.surfaceContainerHighest,
                        ),
                      ),
                      DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.black.withAlpha(40),
                              Colors.black.withAlpha(140),
                              theme.colorScheme.surface,
                            ],
                            stops: const [0.0, 0.55, 1.0],
                          ),
                        ),
                      ),
                      Positioned(
                        left: 20,
                        right: 20,
                        bottom: 18,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            _CoverCard(coverUrl: detail.coverUrl),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (detail.type != null)
                                    _MetaPill(
                                      label: detail.type!,
                                      icon: Icons.auto_stories_outlined,
                                    ),
                                  const SizedBox(height: 8),
                                  Text(
                                    detail.title,
                                    maxLines: 3,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.headlineSmall
                                        ?.copyWith(
                                          fontWeight: FontWeight.w800,
                                          letterSpacing: -0.4,
                                          height: 1.05,
                                          shadows: const [
                                            Shadow(
                                              blurRadius: 16,
                                              color: Colors.black54,
                                            ),
                                          ],
                                        ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _ActionRow(
                        onRead: detail.chapters.isEmpty
                            ? null
                            : () {
                                if (progress != null) {
                                  unawaited(
                                    _resumeReader(
                                      detail,
                                      progress.chapterPath,
                                      continuePage,
                                    ),
                                  );
                                } else {
                                  _openReader(detail, 0);
                                }
                              },
                        onDownload: () {
                          if (_selectMode && _selectedChapters.isNotEmpty) {
                            unawaited(
                              _downloadManga(
                                detail,
                                chapterIndexes: Set<int>.from(
                                  _selectedChapters,
                                ),
                              ),
                            );
                          } else if (!_selectMode) {
                            unawaited(_downloadOptions(detail));
                          }
                        },
                        readLabel: progress != null
                            ? 'Continuar lectura'
                            : 'Leer ahora',
                        readIcon: progress != null
                            ? Icons.play_arrow_rounded
                            : Icons.menu_book_rounded,
                        downloadLabel:
                            _selectMode && _selectedChapters.isNotEmpty
                            ? 'Descargar (${_selectedChapters.length})'
                            : 'Descargar',
                      ),
                      const SizedBox(height: 12),
                      Consumer<FavoritesProvider>(
                        builder: (context, favorites, _) {
                          final saved = favorites.isFavorite(detail.url);
                          return OutlinedButton.icon(
                            icon: Icon(
                              saved ? Icons.favorite : Icons.favorite_border,
                            ),
                            label: Text(
                              saved
                                  ? 'Guardado en biblioteca · Favorito'
                                  : 'Guardar en biblioteca',
                            ),
                            onPressed: () => favorites.toggle(
                              key: detail.url,
                              title: detail.title,
                              coverPath: detail.coverUrl,
                            ),
                          );
                        },
                      ),
                      const ContextualTip(
                        id: 'save-manga',
                        message:
                            'Guardar añade el manga a tu biblioteca sin descargar capítulos. Usa Descargar cuando quieras leer sin conexión.',
                      ),
                      MalSyncStatus(manga: detail.toOfflineManga()),
                      const SizedBox(height: 18),
                      _InfoStrip(
                        items: [
                          if (detail.status != null)
                            _InfoItem(
                              icon: Icons.bolt_outlined,
                              label: detail.status!,
                            ),
                          _InfoItem(
                            icon: Icons.layers_outlined,
                            label: '${detail.chapters.length} caps.',
                          ),
                          if (detail.year != null)
                            _InfoItem(
                              icon: Icons.calendar_today_outlined,
                              label: detail.year!,
                            ),
                          if (detail.author != null &&
                              detail.author!.isNotEmpty)
                            _InfoItem(
                              icon: Icons.person_outline_rounded,
                              label: detail.author!,
                            ),
                        ],
                      ),
                      if (detail.genres.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        SizedBox(
                          height: 36,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            itemCount: detail.genres.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(width: 8),
                            itemBuilder: (context, index) {
                              return _MetaPill(label: detail.genres[index]);
                            },
                          ),
                        ),
                      ],
                      if (detail.altTitles.isNotEmpty) ...[
                        const SizedBox(height: 14),
                        Text(
                          detail.altTitles.join(' · '),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurface.withAlpha(150),
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ],
                      if (detail.hasMoreChapters)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Text(
                            'Lista parcial: ${detail.chapters.length} capítulos cargados. Puedes cargar más abajo.',
                          ),
                        ),
                      if (_loadingMoreChapters) const LinearProgressIndicator(),
                      const SizedBox(height: 18),
                      _SectionHeader(
                        icon: Icons.subject_rounded,
                        title: 'Sinopsis',
                      ),
                      const SizedBox(height: 10),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surface,
                          borderRadius: BorderRadius.circular(22),
                          border: Border.all(
                            color: theme.colorScheme.onSurface.withAlpha(18),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              description,
                              maxLines: _descriptionExpanded ? null : 5,
                              overflow: _descriptionExpanded
                                  ? TextOverflow.visible
                                  : TextOverflow.ellipsis,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                height: 1.55,
                                color: theme.colorScheme.onSurface.withAlpha(
                                  220,
                                ),
                              ),
                            ),
                            if (canExpandDescription) ...[
                              const SizedBox(height: 8),
                              Align(
                                alignment: Alignment.centerLeft,
                                child: TextButton(
                                  style: TextButton.styleFrom(
                                    padding: EdgeInsets.zero,
                                    minimumSize: Size.zero,
                                    tapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                  ),
                                  onPressed: () {
                                    setState(() {
                                      _descriptionExpanded =
                                          !_descriptionExpanded;
                                    });
                                  },
                                  child: Text(
                                    _descriptionExpanded
                                        ? 'Ver menos'
                                        : 'Ver más',
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      Row(
                        children: [
                          Expanded(
                            child: _SectionHeader(
                              icon: Icons.format_list_numbered_rounded,
                              title: 'Capítulos',
                              trailing: '${detail.chapters.length}',
                            ),
                          ),
                          ActionChip(
                            visualDensity: VisualDensity.compact,
                            avatar: Icon(
                              _selectMode
                                  ? Icons.close_rounded
                                  : Icons.checklist_rounded,
                              size: 16,
                            ),
                            label: Text(
                              _selectMode ? 'Cancelar' : 'Seleccionar',
                            ),
                            onPressed: detail.chapters.isEmpty
                                ? null
                                : () {
                                    setState(() {
                                      _selectMode = !_selectMode;
                                      if (!_selectMode) {
                                        _selectedChapters.clear();
                                      }
                                    });
                                  },
                          ),
                        ],
                      ),
                      if (_selectMode) ...[
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            TextButton(
                              onPressed: () {
                                setState(() {
                                  _selectedChapters
                                    ..clear()
                                    ..addAll(
                                      List<int>.generate(
                                        detail.chapters.length,
                                        (i) => i,
                                      ),
                                    );
                                });
                              },
                              child: Text(
                                detail.hasMoreChapters
                                    ? 'Todos los cargados'
                                    : 'Todos',
                              ),
                            ),
                            TextButton(
                              onPressed: () {
                                setState(() => _selectedChapters.clear());
                              },
                              child: const Text('Ninguno'),
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 12),
                    ],
                  ),
                ),
              ),
              if (detail.chapters.isEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surface,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: theme.colorScheme.onSurface.withAlpha(18),
                        ),
                      ),
                      child: Text(
                        'No hay capítulos disponibles.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurface.withAlpha(170),
                        ),
                      ),
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
                  sliver: SliverList.separated(
                    itemCount: detail.chapters.length,
                    separatorBuilder: (_, _) => Divider(
                      height: 1,
                      thickness: 1,
                      color: theme.colorScheme.onSurface.withAlpha(16),
                    ),
                    itemBuilder: (context, index) {
                      final chapter = detail.chapters[index];
                      final isCurrent = progress?.chapterPath == chapter.path;
                      final isRead = chapterRead.isRead(chapter.path);
                      final selected = _selectedChapters.contains(index);

                      return _ChapterTile(
                        index: index,
                        title: chapter.title,
                        isCurrent: isCurrent,
                        isRead: isRead,
                        selected: _selectMode ? selected : null,
                        pageLabel:
                            _downloadStates[chapter.path] ??
                            (isCurrent && progress != null
                                ? 'Pág. ${progress.pageIndex + 1}'
                                : null),
                        onTap: () {
                          if (_selectMode) {
                            setState(() {
                              if (selected) {
                                _selectedChapters.remove(index);
                              } else {
                                _selectedChapters.add(index);
                              }
                            });
                            return;
                          }
                          _openReader(detail, index);
                        },
                        onLongPress: () =>
                            unawaited(_toggleChapterRead(detail, index)),
                        onToggleRead: () =>
                            unawaited(_toggleChapterRead(detail, index)),
                      );
                    },
                  ),
                ),
              if (detail.hasMoreChapters)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: FilledButton.icon(
                      onPressed: _loadingMoreChapters
                          ? null
                          : () => _loadMoreChapters(detail),
                      icon: const Icon(Icons.expand_more),
                      label: Text(
                        _loadingMoreChapters
                            ? 'Cargando capítulos…'
                            : 'Cargar más capítulos',
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _DetailLoadingView extends StatelessWidget {
  const _DetailLoadingView();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return CustomScrollView(
      slivers: [
        SliverAppBar(
          expandedHeight: 280,
          pinned: true,
          leading: const BackButton(),
          flexibleSpace: FlexibleSpaceBar(
            background: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    theme.colorScheme.surfaceContainerHighest,
                    theme.colorScheme.surface,
                  ],
                ),
              ),
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.all(16),
          sliver: SliverList(
            delegate: SliverChildListDelegate([
              _SkeletonBlock(height: 52, radius: 18),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(child: _SkeletonBlock(height: 34, radius: 999)),
                  const SizedBox(width: 8),
                  Expanded(child: _SkeletonBlock(height: 34, radius: 999)),
                  const SizedBox(width: 8),
                  Expanded(child: _SkeletonBlock(height: 34, radius: 999)),
                ],
              ),
              const SizedBox(height: 18),
              _SkeletonBlock(height: 120, radius: 22),
              const SizedBox(height: 24),
              _SkeletonBlock(height: 22, width: 140, radius: 10),
              const SizedBox(height: 12),
              _SkeletonBlock(height: 64, radius: 18),
              const SizedBox(height: 8),
              _SkeletonBlock(height: 64, radius: 18),
            ]),
          ),
        ),
      ],
    );
  }
}

class _SkeletonBlock extends StatelessWidget {
  final double height;
  final double? width;
  final double radius;

  const _SkeletonBlock({required this.height, this.width, this.radius = 16});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width ?? double.infinity,
      height: height,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.onSurface.withAlpha(18),
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

class _DetailErrorView extends StatelessWidget {
  final VoidCallback onRetry;
  final String? message;

  const _DetailErrorView({required this.onRetry, this.message});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: theme.colorScheme.errorContainer.withAlpha(80),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.cloud_off_outlined,
                size: 34,
                color: theme.colorScheme.error,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              'No se pudo cargar el manga',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              message ?? 'Revisa tu conexion e intenta de nuevo.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface.withAlpha(160),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Reintentar'),
            ),
          ],
        ),
      ),
    );
  }
}

class _CoverCard extends StatelessWidget {
  final String? coverUrl;

  const _CoverCard({required this.coverUrl});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      width: 108,
      height: 154,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withAlpha(40)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(120),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(17),
        child: CachedThumbnail(
          sourcePath: coverUrl,
          size: 480,
          placeholderBuilder: (_) => Container(
            color: theme.colorScheme.surfaceContainerHighest,
            child: const Icon(Icons.image_not_supported_outlined),
          ),
        ),
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  final VoidCallback? onRead;
  final VoidCallback onDownload;
  final String readLabel;
  final IconData readIcon;
  final String downloadLabel;

  const _ActionRow({
    required this.onRead,
    required this.onDownload,
    required this.readLabel,
    required this.readIcon,
    this.downloadLabel = 'Descargar',
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      children: [
        Expanded(
          flex: 3,
          child: FilledButton.icon(
            onPressed: onRead,
            icon: Icon(readIcon),
            label: Text(readLabel),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          flex: 2,
          child: OutlinedButton.icon(
            onPressed: onDownload,
            icon: const Icon(Icons.download_rounded, size: 20),
            label: Text(downloadLabel),
            style: OutlinedButton.styleFrom(
              foregroundColor: theme.colorScheme.primary,
              side: BorderSide(color: theme.colorScheme.outline),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _InfoStrip extends StatelessWidget {
  final List<_InfoItem> items;

  const _InfoStrip({required this.items});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: theme.colorScheme.onSurface.withAlpha(18)),
      ),
      child: Wrap(
        spacing: 14,
        runSpacing: 8,
        children: items.map((item) => item).toList(),
      ),
    );
  }
}

class _InfoItem extends StatelessWidget {
  final IconData icon;
  final String label;

  const _InfoItem({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: theme.colorScheme.primary),
        const SizedBox(width: 6),
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _MetaPill extends StatelessWidget {
  final String label;
  final IconData? icon;

  const _MetaPill({required this.label, this.icon});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.black.withAlpha(110),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withAlpha(24)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: theme.colorScheme.primary),
            const SizedBox(width: 6),
          ],
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? trailing;

  const _SectionHeader({
    required this.icon,
    required this.title,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      children: [
        Icon(icon, size: 20, color: theme.colorScheme.primary),
        const SizedBox(width: 8),
        Text(
          title,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w800,
            letterSpacing: -0.2,
          ),
        ),
        if (trailing != null) ...[
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withAlpha(30),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              trailing!,
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _ChapterTile extends StatelessWidget {
  final int index;
  final String title;
  final bool isCurrent;
  final bool isRead;
  final bool? selected;
  final String? pageLabel;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onToggleRead;

  const _ChapterTile({
    required this.index,
    required this.title,
    required this.isCurrent,
    required this.pageLabel,
    required this.onTap,
    this.isRead = false,
    this.selected,
    this.onLongPress,
    this.onToggleRead,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final meta = [if (isRead) 'Leído', ?pageLabel].join(' · ');

    return Material(
      color: isCurrent
          ? theme.colorScheme.primary.withAlpha(18)
          : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 52),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            child: Row(
              children: [
                if (selected != null) ...[
                  Icon(
                    selected!
                        ? Icons.check_box_rounded
                        : Icons.check_box_outline_blank_rounded,
                    size: 20,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      color: isRead
                          ? theme.colorScheme.onSurface.withAlpha(140)
                          : null,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    meta.isEmpty ? '${index + 1}' : meta,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: isCurrent
                          ? theme.colorScheme.primary
                          : theme.colorScheme.onSurface.withAlpha(150),
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                ),
                if (selected == null && onToggleRead != null)
                  PopupMenuButton<String>(
                    tooltip: 'Opciones del capítulo',
                    onSelected: (_) => onToggleRead!(),
                    itemBuilder: (_) => [
                      PopupMenuItem(
                        value: 'read',
                        child: Text(
                          isRead ? 'Marcar como no leído' : 'Marcar como leído',
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
