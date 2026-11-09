import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

import '../models/chapter.dart';
import '../models/manga.dart';
import '../models/manga_list_filters.dart';
import '../providers/categories_provider.dart';
import '../providers/chapter_read_provider.dart';
import '../providers/favorites_provider.dart';
import '../providers/library_provider.dart';
import '../utils/manga_filter_utils.dart';
import '../utils/permissions.dart';
import '../utils/time_format.dart';
import '../utils/title_sanitizer.dart';
import '../widgets/category_assign_sheet.dart';
import '../widgets/continue_reading_section.dart';
import '../widgets/home_content_layout.dart';
import '../widgets/manga_card.dart';
import '../widgets/filter_icon_button.dart';
import '../widgets/manga_filter_sheet.dart';
import '../widgets/search_bar_field.dart';
import '../widgets/section_header.dart';
import 'offline_delete_screen.dart';
import 'reader_screen.dart';

/// Biblioteca solo local (contenido descargado / carpetas), sin modo online.
class OfflineLibraryScreen extends StatefulWidget {
  const OfflineLibraryScreen({super.key});

  @override
  State<OfflineLibraryScreen> createState() => _OfflineLibraryScreenState();
}

class _OfflineLibraryScreenState extends State<OfflineLibraryScreen> {
  final TextEditingController _searchController = TextEditingController();
  MangaListFilters _filters = MangaListFilters.empty;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _pickFolder() async {
    final permission = await StoragePermissionService.request();
    if (!permission.granted) {
      if (permission.permanentlyDenied) {
        await openAppSettings();
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Permiso requerido para leer carpetas.'),
          ),
        );
      }
      return;
    }

    final selected = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Selecciona carpeta de mangas',
    );
    if (selected != null && mounted) {
      await context.read<LibraryProvider>().addLibraryPath(selected);
    }
  }

  Future<void> _openReader(Manga manga, int chapterIndex, int pageIndex) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ReaderScreen(
          manga: manga,
          initialChapterIndex: chapterIndex,
          initialPageIndex: pageIndex,
        ),
      ),
    );
  }

  Future<void> _openMangaAtProgress(Manga manga) async {
    final resume = context.read<LibraryProvider>().resumePosition(manga);
    await _openReader(manga, resume.chapterIndex, resume.pageIndex);
  }

  String _chapterLabel(String raw) => TitleSanitizer.chapterLabel(raw);

  List<ContinueReadingEntry> _buildContinueEntries(
    LibraryProvider provider,
    List<Manga> mangas,
  ) {
    final seen = <String>{};
    final entries = <ContinueReadingEntry>[];

    for (final progress in provider.getRecentProgress()) {
      final manga = provider.localMangaForProgress(progress, mangas);
      if (manga == null || !seen.add(manga.path)) {
        continue;
      }

      final resume = provider.resumePosition(manga);
      Chapter? matchedChapter;
      if (resume.chapterIndex >= 0 &&
          resume.chapterIndex < manga.chapters.length) {
        matchedChapter = manga.chapters[resume.chapterIndex];
      }
      final totalPages = matchedChapter?.pageCount ?? 1;
      final pageNumber = resume.pageIndex + 1;
      final progressValue = totalPages > 0 ? pageNumber / totalPages : 0.0;
      final chapterTitle = matchedChapter?.title ?? progress.chapterTitle;

      entries.add(
        ContinueReadingEntry(
          title: manga.title.isEmpty ? 'Manga' : manga.title,
          chapterLabel: _chapterLabel(chapterTitle),
          pageNumber: pageNumber,
          progress: progressValue,
          timeAgo: formatTimeAgo(progress.updatedAt),
          coverPath: manga.coverPath ?? progress.coverPath,
          onTap: () {
            unawaited(
              _openReader(manga, resume.chapterIndex, resume.pageIndex),
            );
          },
        ),
      );
    }

    return entries;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final library = context.watch<LibraryProvider>();
    final favorites = context.watch<FavoritesProvider>();
    final categories = context.watch<CategoriesProvider>();

    return StreamBuilder<List<Manga>>(
      stream: library.mangasStream,
      initialData: library.mangas,
      builder: (context, snapshot) {
        final currentMangas = snapshot.data ?? library.mangas;
        final searched = MangaFilterUtils.searchOffline(
          currentMangas,
          _searchController.text,
        );
        final mangas = MangaFilterUtils.filterOfflineMangas(
          mangas: searched,
          filters: _filters,
          favorites: favorites,
          categories: categories,
          progressMap: library.progressMap,
          chapterRead: context.read<ChapterReadProvider>(),
        );
        final favoriteMangas = searched
            .where((m) => favorites.isFavorite(m.path))
            .toList();
        final continueEntries = _buildContinueEntries(library, currentMangas);

        return Scaffold(
          appBar: AppBar(
            title: const Text('Archivos descargados'),
            automaticallyImplyLeading: false,
            actions: [
              IconButton(
                tooltip: 'Eliminar mangas',
                onPressed: library.mangas.isEmpty
                    ? null
                    : () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const OfflineDeleteScreen(),
                          ),
                        );
                      },
                icon: const Icon(Icons.delete_outline_rounded),
              ),
              IconButton(
                tooltip: 'Agregar carpeta',
                onPressed: () => unawaited(_pickFolder()),
                icon: const Icon(Icons.create_new_folder_outlined),
              ),
              IconButton(
                tooltip: 'Reescanear biblioteca',
                onPressed: library.rescan,
                icon: const Icon(Icons.refresh_rounded),
              ),
            ],
          ),
          body: SafeArea(
            child: RefreshIndicator(
              onRefresh: library.rescan,
              color: theme.colorScheme.primary,
              child: CustomScrollView(
                key: const PageStorageKey('offline'),
                slivers: [
                  SliverPadding(
                    padding: HomeContentLayout.paddingOf(context),
                    sliver: SliverToBoxAdapter(
                      child: Column(
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              SearchBarField(
                                controller: _searchController,
                                hintText: 'Buscar en tu biblioteca',
                                onChanged: (_) => setState(() {}),
                                onClear: () {
                                  _searchController.clear();
                                  setState(() {});
                                },
                              ),
                              Align(
                                alignment: Alignment.centerRight,
                                child: FilterIconButton(
                                  active: _filters.hasActiveFilters,
                                  onPressed: () async {
                                    await MangaFilterSheet.show(
                                      context: context,
                                      initialFilters: _filters,
                                      isOnline: false,
                                      onApply: (filters) {
                                        setState(() => _filters = filters);
                                      },
                                    );
                                  },
                                ),
                              ),
                            ],
                          ),
                          if (continueEntries.isNotEmpty &&
                              _searchController.text.trim().isEmpty)
                            ContinueReadingSection(entries: continueEntries),
                        ],
                      ),
                    ),
                  ),
                  if (favoriteMangas.isNotEmpty && !_filters.favoritesOnly) ...[
                    SliverPadding(
                      padding: HomeContentLayout.paddingOf(context),
                      sliver: const SliverToBoxAdapter(
                        child: SectionHeader(
                          icon: Icons.favorite_rounded,
                          title: 'Favoritos',
                        ),
                      ),
                    ),
                    SliverPadding(
                      padding: HomeContentLayout.paddingOf(context),
                      sliver: _MangaGrid(
                        mangas: favoriteMangas,
                        favorites: favorites,
                        onOpen: (m) => unawaited(_openMangaAtProgress(m)),
                      ),
                    ),
                  ],
                  SliverPadding(
                    padding: HomeContentLayout.paddingOf(context),
                    sliver: SliverToBoxAdapter(
                      child: SectionHeader(
                        icon: Icons.download_done_rounded,
                        title: 'Biblioteca offline',
                        trailing: library.isLoading
                            ? 'Escaneando…'
                            : mangas.length.toString(),
                      ),
                    ),
                  ),
                  if (library.libraryPaths.isEmpty && library.mangas.isEmpty)
                    SliverToBoxAdapter(
                      child: _EmptyOffline(
                        onAddFolder: () => unawaited(_pickFolder()),
                      ),
                    )
                  else if (mangas.isEmpty)
                    const SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.all(20),
                        child: Text(
                          'No hay mangas que coincidan con tu búsqueda o filtros.',
                        ),
                      ),
                    )
                  else
                    SliverPadding(
                      padding: HomeContentLayout.paddingOf(context),
                      sliver: _MangaGrid(
                        mangas: mangas,
                        favorites: favorites,
                        onOpen: (m) => unawaited(_openMangaAtProgress(m)),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _MangaGrid extends StatelessWidget {
  final List<Manga> mangas;
  final FavoritesProvider favorites;
  final ValueChanged<Manga> onOpen;

  const _MangaGrid({
    required this.mangas,
    required this.favorites,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryProvider>();
    return SliverMangaGrid(
      delegate: SliverChildBuilderDelegate((context, index) {
        final manga = mangas[index];
        final saved = library.progressForManga(manga);
        double? coverProgress;
        if (saved != null && manga.chapters.isNotEmpty) {
          final resume = library.resumePosition(manga);
          final chapter = manga.chapters[resume.chapterIndex];
          coverProgress = chapter.pageCount > 0
              ? (resume.pageIndex + 1) / chapter.pageCount
              : (resume.chapterIndex + 1) / manga.chapters.length;
        }
        return MangaCard(
          title: manga.title,
          coverPath: manga.coverPath,
          progress: coverProgress,
          isFavorite: favorites.isFavorite(manga.path),
          onFavoriteToggle: () {
            unawaited(
              favorites.toggle(
                key: manga.path,
                title: manga.title,
                coverPath: manga.coverPath,
              ),
            );
          },
          onLongPress: () {
            unawaited(
              CategoryAssignSheet.show(
                context: context,
                mangaKey: manga.path,
                mangaTitle: manga.title,
              ),
            );
          },
          onTap: () => onOpen(manga),
        );
      }, childCount: mangas.length),
    );
  }
}

class _EmptyOffline extends StatelessWidget {
  final VoidCallback onAddFolder;

  const _EmptyOffline({required this.onAddFolder});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.colorScheme.onSurface.withAlpha(18)),
      ),
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withAlpha(28),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.folder_off_outlined,
              size: 30,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Tu biblioteca offline está vacía',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'Descarga mangas desde Online o agrega una carpeta local.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurface.withAlpha(170),
              height: 1.4,
              fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: onAddFolder,
            icon: const Icon(Icons.create_new_folder_outlined),
            label: const Text('Agregar carpeta'),
          ),
        ],
      ),
    );
  }
}
