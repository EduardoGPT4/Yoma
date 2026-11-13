part of 'reader_screen.dart';

// Lo que dibuja el lector: zonas de toque, visores, barras superior e inferior
// y estados de carga o vacío. Solo lee el estado de _ReaderScreenState; los
// cambios de estado siguen en reader_screen.dart.
extension _ReaderScreenViews on _ReaderScreenState {
  Widget _buildTapZones() {
    final rtl = context.read<ReaderSettingsProvider>().isRightToLeft;
    return Positioned.fill(
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: () => _goToRelativePage(rtl ? 1 : -1),
            ),
          ),
          Expanded(
            flex: 2,
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: _toggleControls,
            ),
          ),
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: () => _goToRelativePage(rtl ? -1 : 1),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReaderContent(ThemeData theme, ReaderSettingsProvider settings) {
    if (settings.verticalMode && settings.continuousVertical) {
      return WebtoonViewer(
        key: ValueKey('webtoon-${_currentChapter?.path ?? ''}-$_imageRevision'),
        initialPage: _webtoonAnchor,
        pages: _pages,
        imageProvider: _imageProviderForPath,
        onPageChanged: (page) {
          if (page != _pageIndex) _onViewerChanged(page);
        },
        onLoaded: (page) {
          _loadedPages.add(_pages[page]);
          _markVisibleLoaded();
        },
        errorBuilder: (error) => _buildImageError(theme, error),
      );
    }
    if (_useDoublePage(settings)) {
      return _buildDoublePageViewer(theme, settings);
    }
    return _buildSinglePageGallery(theme, settings);
  }

  Widget _buildSinglePageGallery(
    ThemeData theme,
    ReaderSettingsProvider settings,
  ) {
    return PhotoViewGallery.builder(
      key: ValueKey<String>(
        '$_imageRevision-gallery-${_currentChapter?.path ?? ''}',
      ),
      pageController: _pageController,
      scrollDirection: settings.verticalMode ? Axis.vertical : Axis.horizontal,
      reverse: settings.isRightToLeft,
      itemCount: _pages.length,
      backgroundDecoration: BoxDecoration(color: theme.scaffoldBackgroundColor),
      onPageChanged: _onViewerChanged,
      loadingBuilder: (context, event) => _buildPageLoading(theme, event),
      builder: (context, index) {
        final pageScales = _photoScales(settings, index: index);
        return PhotoViewGalleryPageOptions(
          imageProvider: _imageProviderForPath(_pages[index]),
          minScale: pageScales.minScale,
          maxScale: pageScales.maxScale,
          initialScale: pageScales.initialScale,
          basePosition: Alignment.center,
          filterQuality: FilterQuality.high,
          errorBuilder: (context, error, stackTrace) =>
              _buildImageError(theme, error),
        );
      },
    );
  }

  Widget _buildDoublePageViewer(
    ThemeData theme,
    ReaderSettingsProvider settings,
  ) {
    final spreadCount = _viewerItemCount(settings);

    return PageView.builder(
      key: ValueKey<String>(
        '$_imageRevision-spreads-${_currentChapter?.path ?? ''}',
      ),
      controller: _pageController,
      scrollDirection: Axis.horizontal,
      reverse: settings.isRightToLeft,
      itemCount: spreadCount,
      onPageChanged: _onViewerChanged,
      itemBuilder: (context, spreadIndex) {
        final firstIndex = ReaderPaging.firstPageForSpread(
          spreadIndex,
          coverAlone: settings.coverAlone,
        );
        final secondIndex = firstIndex + 1;
        final hasSecond =
            secondIndex < _pages.length &&
            !(settings.coverAlone && spreadIndex == 0);

        Widget buildPage(int index) {
          final scales = _photoScales(settings, index: index);
          return PhotoView(
            imageProvider: _imageProviderForPath(_pages[index]),
            minScale: scales.minScale,
            maxScale: scales.maxScale,
            initialScale: scales.initialScale,
            basePosition: Alignment.center,
            filterQuality: FilterQuality.high,
            backgroundDecoration: BoxDecoration(
              color: theme.scaffoldBackgroundColor,
            ),
            loadingBuilder: (context, event) => _buildPageLoading(theme, event),
            errorBuilder: (context, error, stackTrace) =>
                _buildImageError(theme, error),
          );
        }

        if (settings.isRightToLeft) {
          return Row(
            children: [
              if (hasSecond) Expanded(child: buildPage(secondIndex)),
              Expanded(child: buildPage(firstIndex)),
            ],
          );
        }

        return Row(
          children: [
            Expanded(child: buildPage(firstIndex)),
            if (hasSecond) Expanded(child: buildPage(secondIndex)),
          ],
        );
      },
    );
  }

  Widget _buildPageLoading(ThemeData theme, ImageChunkEvent? event) {
    final value = event == null || event.expectedTotalBytes == null
        ? null
        : event.cumulativeBytesLoaded / (event.expectedTotalBytes ?? 1);
    return Center(
      child: CircularProgressIndicator(
        value: value,
        color: theme.colorScheme.primary,
      ),
    );
  }

  Widget _buildTopOverlay(
    ThemeData theme,
    Chapter? chapter,
    ReaderSettingsProvider settings,
  ) {
    final totalPages = _currentPages.length;
    final currentPage = totalPages == 0 ? 0 : _pageIndex + 1;

    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              theme.scaffoldBackgroundColor.withValues(alpha: 0.95),
              theme.scaffoldBackgroundColor.withValues(alpha: 0.0),
            ],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: Row(
          children: [
            IconButton(
              tooltip: 'Volver',
              onPressed: () => Navigator.of(context).maybePop(),
              icon: const Icon(Icons.arrow_back),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.manga.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium,
                  ),
                  if (chapter != null)
                    Text(
                      chapter.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall,
                    ),
                ],
              ),
            ),
            if (settings.showPageNumber)
              Semantics(
                label: 'Página $currentPage de $totalPages',
                hint: 'Ir a una página',
                button: true,
                child: Tooltip(
                  message: 'Ir a una página',
                  child: TextButton(
                    onPressed: totalPages == 0
                        ? null
                        : () => unawaited(_goToPageDialog()),
                    style: TextButton.styleFrom(
                      minimumSize: const Size(48, 48),
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      backgroundColor: theme.colorScheme.primary.withAlpha(28),
                      tapTargetSize: MaterialTapTargetSize.padded,
                    ),
                    child: ExcludeSemantics(
                      child: Text('$currentPage/$totalPages'),
                    ),
                  ),
                ),
              ),
            if (_detailRef != null)
              IconButton(
                tooltip: 'Ficha del manga',
                onPressed: () => unawaited(_openDetail()),
                icon: const Icon(Icons.info_outline_rounded),
              ),
            IconButton(
              tooltip: 'Ajustes del lector',
              onPressed: () => unawaited(_openReaderSettings()),
              icon: const Icon(Icons.tune_rounded),
            ),
            PopupMenuButton<String>(
              tooltip: 'Más opciones de lectura',
              onOpened: () {
                _controlsHideTimer?.cancel();
                _readerPanelOpen = true;
              },
              onCanceled: () {
                _readerPanelOpen = false;
                _scheduleControlsHide();
              },
              onSelected: (action) => unawaited(_handleReaderAction(action)),
              itemBuilder: (_) {
                final isRead =
                    chapter != null &&
                    context.read<ChapterReadProvider>().isRead(chapter.path);
                PopupMenuItem<String> item(
                  String value,
                  IconData icon,
                  String label, {
                  bool enabled = true,
                }) => PopupMenuItem<String>(
                  value: value,
                  enabled: enabled,
                  child: Row(
                    children: [
                      Icon(icon, size: 20),
                      const SizedBox(width: 12),
                      Expanded(child: Text(label)),
                    ],
                  ),
                );
                return [
                  if (_canTranslate) ...[
                    item('translate', Icons.translate, 'Traducir página'),
                    if (_translatedPages.isNotEmpty)
                      item(
                        'translation-original',
                        Icons.image_outlined,
                        'Ver páginas originales',
                      ),
                    const PopupMenuDivider(),
                  ],
                  item(
                    'quality',
                    _originalQuality ? Icons.hd : Icons.hd_outlined,
                    _originalQuality
                        ? 'Usar imágenes optimizadas'
                        : 'Usar calidad original',
                  ),
                  item(
                    'read',
                    Icons.done_all,
                    isRead ? 'Marcar como no leído' : 'Marcar como leído',
                    enabled: chapter != null,
                  ),
                  const PopupMenuDivider(),
                  item(
                    'save',
                    Icons.bookmark_add_outlined,
                    'Añadir o quitar marcador',
                  ),
                  item('list', Icons.bookmarks_outlined, 'Mis marcadores'),
                  item(
                    'source',
                    Icons.travel_explore,
                    'Buscar capítulo en otra fuente',
                  ),
                  item('mal', Icons.sync_alt, 'Vincular con MyAnimeList'),
                  const PopupMenuDivider(),
                  item(
                    'previous',
                    Icons.skip_previous,
                    'Capítulo anterior',
                    enabled: _chapterIndex > 0,
                  ),
                  item(
                    'next',
                    Icons.skip_next,
                    'Capítulo siguiente',
                    enabled:
                        _chapterIndex + 1 < _chapters.length ||
                        _readingDetail.hasMoreChapters,
                  ),
                ];
              },
            ),
          ],
        ),
      ),
    );
  }

  bool _availableOffline(Chapter chapter) {
    if (!ContentIdentity.isRemote(chapter.path)) {
      return chapter.complete && chapter.pageCount > 0;
    }
    final ref = ContentIdentity.canonical(chapter.sourceUrl ?? chapter.path);
    return context.read<LibraryProvider>().mangas.any(
      (m) => m.chapters.any(
        (c) =>
            !ContentIdentity.isRemote(c.path) &&
            c.complete &&
            c.pageCount > 0 &&
            ContentIdentity.canonical(c.sourceUrl ?? c.path) == ref,
      ),
    );
  }

  Widget _buildBottomOverlay(ThemeData theme, ReaderSettingsProvider settings) {
    final totalPages = _currentPages.length;

    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              theme.scaffoldBackgroundColor.withValues(alpha: 0.0),
              theme.scaffoldBackgroundColor.withValues(alpha: 0.95),
            ],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * .65,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const ContextualTip(
                  id: 'reader-controls',
                  message:
                      'Toca el centro para mostrar los controles. Arrastra la barra para previsualizar una página y suelta para saltar.',
                ),
                if (_hasVisibleTranslation)
                  TextButton.icon(
                    onPressed: _showOriginalTranslation,
                    icon: const Icon(Icons.image_outlined),
                    label: const Wrap(
                      spacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        TranslationAttribution(),
                        Text('Ver original'),
                      ],
                    ),
                  ),
                if (!_loadingChapter &&
                    totalPages > 0 &&
                    _viewerIndexForPage(_pageIndex, settings) >=
                        _viewerItemCount(settings) - 1)
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: MediaQuery.sizeOf(context).height * .38,
                    ),
                    child: SingleChildScrollView(
                      child: ReaderChapterEnd(
                        nextTitle: _chapterIndex + 1 < _chapters.length
                            ? _chapters[_chapterIndex + 1].title
                            : null,
                        hasMore: _readingDetail.hasMoreChapters,
                        offline:
                            _chapterIndex + 1 < _chapters.length &&
                            _availableOffline(_chapters[_chapterIndex + 1]),
                        onNext: () => unawaited(_goNextChapter()),
                        onExit: () => Navigator.of(context).pop(),
                      ),
                    ),
                  ),
                ReaderPageScrubber(
                  key: ValueKey(_currentChapter?.path),
                  pages: _loadingChapter ? const [] : _pages,
                  page: _pageIndex,
                  onCommit: _commitPageJump,
                  onInteraction: (active) {
                    _readerPanelOpen = active;
                    if (active) {
                      _controlsHideTimer?.cancel();
                    } else {
                      _scheduleControlsHide();
                    }
                  },
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      tooltip: 'Página anterior',
                      onPressed: () => _goToRelativePage(-1),
                      icon: const Icon(Icons.chevron_left),
                    ),
                    TextButton.icon(
                      onPressed: _openDrawer,
                      icon: const Icon(Icons.menu_book_outlined),
                      label: const Text('Capítulos'),
                      style: TextButton.styleFrom(
                        minimumSize: const Size(48, 48),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Página siguiente',
                      onPressed: () => _goToRelativePage(1),
                      icon: const Icon(Icons.chevron_right),
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

  Widget _buildEmptyState(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.broken_image_outlined,
              size: 48,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: 12),
            const Text(
              'Este capítulo no tiene páginas disponibles.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadingState(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(color: theme.colorScheme.primary),
          const SizedBox(height: 12),
          Text('Cargando capítulo…', style: theme.textTheme.bodyMedium),
        ],
      ),
    );
  }
}
