import '../providers/favorites_provider.dart';
import '../design/yoma_tokens.dart';
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
import '../services/mal_reading_sync.dart';
import '../services/myanimelist_service.dart';
import '../utils/network_errors.dart';

import '../widgets/cached_thumbnail.dart';
import 'reader_screen.dart';
import 'myanimelist_screen.dart';

part 'online_manga_detail_widgets.dart';

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
      _applyMalReading(detail);
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

  /// Los capítulos que MyAnimeList ya tiene leídos se marcan como leídos.
  void _applyMalReading(OnlineMangaDetail detail) {
    if (!mounted) return;
    final reads = context.read<ChapterReadProvider>();
    unawaited(
      MalReadingSync.shared
          .apply(detail.toOfflineManga(), detail.chapters, reads)
          .catchError((Object error) {
            debugPrint('MAL → YomaShi: $error');
            return 0;
          }),
    );
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
      if (mounted) {
        setState(() {
          _detailFuture = Future.value(next);
        });
      }
      _applyMalReading(next);
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
          openedFromDetail: true,
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
      setState(() {
        _detailFuture = Future.value(next);
      });
      _applyMalReading(next);
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
                          borderRadius: BorderRadius.circular(YomaRadii.lg),
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
                        borderRadius: BorderRadius.circular(YomaRadii.lg),
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
                        readFromMal:
                            isRead && chapterRead.isFromMal(chapter.path),
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
