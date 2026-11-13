part of 'online_browser_screen.dart';

// Piezas de la pantalla de fuentes online que solo dibujan: botón de filtros,
// tarjetas, «Seguir leyendo» y la fila de actualizados. Los cambios de estado
// siguen en online_browser_screen.dart.
extension _OnlineBrowserViews on OnlineBrowserScreenState {
  Widget _buildFilterButton() {
    return FilterIconButton(
      active: _filters.hasActiveFilters,
      onPressed: () => unawaited(_openFilters()),
    );
  }

  Widget _buildOnlineMangaCard(
    OnlineMangaSummary item, {
    String? badge,
    bool showSource = true,
    required FavoritesProvider favorites,
  }) {
    return MangaCard(
      title: item.title,
      coverPath: item.coverUrl,
      badge:
          badge ??
          (!showSource || item.sourceId == null || item.sourceId!.isEmpty
              ? null
              : MangaSources.shortLabel(item.sourceId!)),
      isFavorite: favorites.isFavorite(item.url),
      onFavoriteToggle: () {
        unawaited(
          favorites.toggle(
            key: item.url,
            title: item.title,
            coverPath: item.coverUrl,
          ),
        );
      },
      onLongPress: () {
        unawaited(
          CategoryAssignSheet.show(
            context: context,
            mangaKey: item.url,
            mangaTitle: item.title,
          ),
        );
      },
      onTap: () => _openDetail(item),
    );
  }

  bool _isRemoteProgress(ReadingProgress progress) {
    return ContentIdentity.isRemote(progress.mangaPath);
  }

  bool _matchesActiveSource(ReadingProgress progress, String sourceId) {
    final wanted = OnlineCatalogService.normalizeSourceId(sourceId);
    final stored = progress.sourceId;
    if (stored != null && stored.isNotEmpty) {
      return OnlineCatalogService.normalizeSourceId(stored) == wanted;
    }
    return OnlineCatalogService.belongsToSource(progress.mangaPath, wanted) ||
        OnlineCatalogService.belongsToSource(progress.chapterPath, wanted);
  }

  List<ReadingProgress> _remoteRecentProgress(
    LibraryProvider library,
    String sourceId,
  ) {
    return library
        .getRecentProgress()
        .where(_isRemoteProgress)
        .where((progress) => _matchesActiveSource(progress, sourceId))
        .take(5)
        .toList();
  }

  String _continueEntriesSignature(List<ReadingProgress> items) {
    return items
        .map(
          (progress) =>
              '${progress.mangaPath}|${progress.updatedAt}|${progress.coverPath ?? ''}',
        )
        .join(';;');
  }

  String _chapterLabel(String raw) => TitleSanitizer.chapterLabel(raw);

  Future<List<ContinueReadingEntry>> _loadContinueEntries(
    List<ReadingProgress> items,
  ) async {
    final entries = <ContinueReadingEntry>[];
    for (final progress in items) {
      String? coverPath = progress.coverPath;
      var progressValue = 0.0;

      if (coverPath == null || coverPath.isEmpty) {
        try {
          final detail = await OnlineCatalogService.fetchMangaDetail(
            progress.mangaPath,
          );
          coverPath = detail.coverUrl;
          Chapter? matchedChapter;
          for (final item in detail.chapters) {
            if (item.path == progress.chapterPath) {
              matchedChapter = item;
              break;
            }
          }
          if (matchedChapter != null && matchedChapter.pageCount > 0) {
            progressValue = (progress.pageIndex + 1) / matchedChapter.pageCount;
          }
        } catch (_) {
          coverPath = null;
        }
      }

      entries.add(
        ContinueReadingEntry(
          title: progress.mangaTitle.isNotEmpty ? progress.mangaTitle : 'Manga',
          chapterLabel: _chapterLabel(progress.chapterTitle),
          pageNumber: progress.pageIndex + 1,
          progress: progressValue,
          timeAgo: formatTimeAgo(progress.updatedAt),
          coverPath: coverPath,
          onTap: () => unawaited(_continueReading(progress)),
        ),
      );
    }
    return entries;
  }

  Widget _buildHorizontalUpdated(
    List<OnlineMangaSummary> items,
    FavoritesProvider favorites,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          icon: Icons.new_releases_outlined,
          title: widget.lockedSourceId == null
              ? 'Actualizados'
              : OnlineCatalogService.adapter(
                  widget.lockedSourceId!,
                ).capabilities.feedLabel,
          trailing: '${items.length}',
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: MangaCardLayout.heightForWidth(context, 120),
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: items.length.clamp(0, 24),
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              final item = items[index];
              return SizedBox(
                width: 120,
                child: KeyedSubtree(
                  key: ValueKey<String>('updated-${item.url}'),
                  child: _buildOnlineMangaCard(
                    item,
                    badge: 'Nuevo',
                    favorites: favorites,
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
