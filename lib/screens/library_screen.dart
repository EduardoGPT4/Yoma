import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../data/library_store.dart';
import '../models/content_identity.dart';
import '../models/library_entry.dart';
import '../providers/categories_provider.dart';
import '../providers/chapter_read_provider.dart';
import '../providers/favorites_provider.dart';
import '../providers/library_provider.dart';
import '../services/hitomi_service.dart';
import '../services/online_catalog_service.dart';
import '../services/myanimelist_service.dart';
import 'myanimelist_screen.dart';
import '../utils/network_errors.dart';
import '../utils/preferences.dart';
import '../utils/time_format.dart';
import '../utils/title_sanitizer.dart';
import '../widgets/category_assign_sheet.dart';
import '../widgets/contextual_tip.dart';
import '../widgets/continue_reading_section.dart';
import '../widgets/home_content_layout.dart';
import '../widgets/manga_card.dart';
import '../widgets/search_bar_field.dart';
import 'offline_library_screen.dart';
import 'online_manga_detail_screen.dart';
import 'reader_screen.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});
  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen>
    with WidgetsBindingObserver {
  final _search = TextEditingController();
  LibraryView _view = LibraryView.all;
  bool _adultShelf = false;
  String? _category;
  Map<String, String> _links = {};
  List<Map<String, dynamic>> _updates = [];
  String? _opening, _error;
  Map<String, String> _statuses = {};
  int _generation = 0;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    MyAnimeListService.shared.changes.addListener(_reload);
    MyAnimeListService.shared.client.sessionChanges.addListener(_reload);
    unawaited(_metadata());
  }

  void _reload() {
    unawaited(_metadata());
  }

  @override
  void dispose() {
    _generation++;
    MyAnimeListService.shared.changes.removeListener(_reload);
    MyAnimeListService.shared.client.sessionChanges.removeListener(_reload);
    WidgetsBinding.instance.removeObserver(this);
    _search.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_metadata());
  }

  Future<void> _metadata() async {
    final gen = ++_generation;
    try {
      final links = await PreferencesService.getMangaSourceLinks();
      final updates = await (await LibraryStore.ensureInitialized())
          .readRecords('favorite_updates');
      final service = MyAnimeListService.shared;
      final auth = await service.client.credentials.load();
      final owner = (auth?['profile'] as Map?)?['id'];
      final store = await LibraryStore.ensureInitialized();
      final mappings = {
        for (final row in await store.readRecords('mal_links')) row['id']: row,
      };
      final statuses = <String, String>{};
      for (final row in await store.readRecords('mal_sync')) {
        final mapping = mappings[row['id']];
        if (auth?['connected'] == true &&
            owner != null &&
            row['owner'] == owner &&
            mapping?['owner'] == owner &&
            row['version'] == mapping?['version'] &&
            row['status'] is String) {
          statuses[ContentIdentity.canonical(row['id'] as String)] =
              row['status'] as String;
        }
      }
      if (mounted && gen == _generation) {
        setState(() {
          _statuses = statuses;
          _links = links;
          _updates = updates;
          _error = null;
        });
      }
    } catch (_) {
      if (mounted && gen == _generation) {
        setState(
          () => _error =
              'No se pudieron consultar las novedades. Desliza para reintentar.',
        );
      }
    }
  }

  Future<void> _refresh() async {
    await context.read<LibraryProvider>().rescan();
    await _metadata();
  }

  Future<void> _open(LibraryEntry entry, {bool resume = false}) async {
    if (_opening != null) return;
    setState(() => _opening = entry.key);
    try {
      final library = context.read<LibraryProvider>();
      final local = entry.local;
      final remoteResume =
          entry.progress != null &&
          ContentIdentity.isRemote(entry.key) &&
          (resume || local != null) &&
          (local == null ||
              !local.chapters.any(
                (c) =>
                    ContentIdentity.canonical(c.sourceUrl ?? c.path) ==
                    ContentIdentity.canonical(entry.progress!.chapterPath),
              ));
      if (local != null && !remoteResume) {
        final position = library.resumePosition(local);
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ReaderScreen(
              manga: local,
              initialChapterIndex: position.chapterIndex,
              initialPageIndex: position.pageIndex,
            ),
          ),
        );
      } else if (remoteResume) {
        final progress = entry.progress!;
        var detail = await OnlineCatalogService.fetchMangaDetail(entry.key);
        detail = await OnlineCatalogService.resolveChapter(
          detail,
          progress.chapterPath,
        );
        final index = detail.chapters.indexWhere(
          (c) =>
              ContentIdentity.canonical(c.path) ==
              ContentIdentity.canonical(progress.chapterPath),
        );
        if (!mounted) return;
        if (index < 0) {
          throw StateError(
            'El capítulo guardado ya no está disponible en esta fuente.',
          );
        }
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ReaderScreen(
              manga: detail.toOfflineManga(),
              initialChapterIndex: index,
              initialPageIndex: progress.pageIndex,
            ),
          ),
        );
      } else {
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => OnlineMangaDetailScreen(mangaUrl: entry.key),
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(NetworkErrors.friendly(error))));
      }
    } finally {
      if (mounted) {
        setState(() => _opening = null);
        unawaited(_metadata());
      }
    }
  }

  bool _matchesView(LibraryEntry entry, LibraryView view) =>
      entry.matches(view, readingStatus: _statuses[entry.key]);

  bool _isHitomiEntry(LibraryEntry entry) =>
      entry.progress?.sourceId == 'hitomi' ||
      entry.references.any(HitomiService.isReference);

  int _newCount(LibraryEntry entry, ChapterReadProvider read) {
    final refs = {entry.key, entry.favorite?.key, entry.local?.path};
    final chapters = <String>{};
    for (final row in _updates) {
      if (refs.contains(row['id']) ||
          (row['url'] is String &&
              ContentIdentity.canonical(row['url']) == entry.key)) {
        chapters.addAll((row['new'] as List? ?? []).whereType<String>());
      }
    }
    return chapters.where((c) => !read.isRead(c)).length;
  }

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryProvider>();
    final favorites = context.watch<FavoritesProvider>();
    final categories = context.watch<CategoriesProvider>();
    final read = context.watch<ChapterReadProvider>();
    final entries = LibraryEntry.combine(
      local: library.mangas,
      favorites: favorites.entries,
      progress: library.getRecentProgress(),
      sourceLinks: _links,
    ).where((entry) => _isHitomiEntry(entry) == _adultShelf).toList();
    final recent = entries.where((e) => e.progress != null).toList()
      ..sort((a, b) => b.progress!.updatedAt.compareTo(a.progress!.updatedAt));
    final visible = entries
        .where(
          (e) =>
              _matchesView(e, _view) &&
              TitleSanitizer.clean(
                e.title,
              ).toLowerCase().contains(_search.text.trim().toLowerCase()) &&
              (_category == null ||
                  e.references.any(
                    (key) => categories.isMangaInCategory(_category!, key),
                  )),
        )
        .toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Biblioteca'),
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            tooltip: 'Gestionar archivos descargados',
            icon: const Icon(Icons.folder_open),
            onPressed: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const OfflineLibraryScreen()),
              );
              if (mounted) unawaited(_metadata());
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: CustomScrollView(
          key: const PageStorageKey('library'),
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverPadding(
              padding: HomeContentLayout.paddingOf(context),
              sliver: SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_opening != null)
                      const LinearProgressIndicator(
                        semanticsLabel: 'Abriendo manga',
                      ),
                    if (recent.isNotEmpty)
                      ContinueReadingSection(
                        entries: recent.take(4).map((e) {
                          final p = e.progress!;
                          return ContinueReadingEntry(
                            title: e.title,
                            chapterLabel: TitleSanitizer.chapterLabel(
                              p.chapterTitle,
                            ),
                            pageNumber: p.pageIndex + 1,
                            progress: 0,
                            timeAgo: formatTimeAgo(p.updatedAt),
                            coverPath: e.cover,
                            onTap: () => unawaited(_open(e, resume: true)),
                          );
                        }).toList(),
                      ),
                    const SizedBox(height: 16),
                    SearchBarField(
                      controller: _search,
                      hintText: 'Buscar en tu biblioteca',
                      onChanged: (_) => setState(() {}),
                      onClear: () {
                        _search.clear();
                        setState(() {});
                      },
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        ChoiceChip(
                          label: const Text('Mangas'),
                          selected: !_adultShelf,
                          onSelected: (_) =>
                              setState(() => _adultShelf = false),
                        ),
                        ChoiceChip(
                          label: const Text('+18 Hitomi.la'),
                          selected: _adultShelf,
                          onSelected: (_) => setState(() => _adultShelf = true),
                        ),
                        for (final view in LibraryView.values)
                          ChoiceChip(
                            label: Text(
                              '${view.label} (${entries.where((e) => _matchesView(e, view)).length})',
                            ),
                            selected: _view == view,
                            onSelected: (_) => setState(() => _view = view),
                          ),
                      ],
                    ),
                    if (categories.categories.isNotEmpty)
                      DropdownButton<String>(
                        isExpanded: true,
                        value: categories.categoryById(_category) != null
                            ? _category
                            : null,
                        hint: const Text('Todas las categorías'),
                        items: [
                          const DropdownMenuItem(
                            value: null,
                            child: Text('Todas las categorías'),
                          ),
                          for (final category in categories.categories)
                            DropdownMenuItem(
                              value: category.id,
                              child: Text(category.name),
                            ),
                        ],
                        onChanged: (value) => setState(() => _category = value),
                      ),
                    const ContextualTip(
                      id: 'library',
                      message:
                          'Guarda mangas con el corazón para tenerlos aquí sin descargarlos. El menú de cada portada permite organizar categorías.',
                    ),
                    if (_error != null) Text(_error!),
                    const SizedBox(height: 12),
                    if (visible.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 32),
                        child: Text(
                          _adultShelf
                              ? 'No hay galerías +18 en esta vista. Guárdalas desde +18 Hitomi.la.'
                              : 'No hay mangas en esta vista. Prueba otro filtro o guarda uno desde Inicio.',
                          textAlign: TextAlign.center,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
              sliver: SliverMangaGrid(
                delegate: SliverChildBuilderDelegate((context, index) {
                  final entry = visible[index];
                  final fresh = _newCount(entry, read);
                  final readingStatus = _statuses[entry.key];
                  final stateLabel = readingStatus == null
                      ? null
                      : MyAnimeListScreen.statesLabel(readingStatus);
                  final completed =
                      entry.local?.chapters
                          .where(
                            (c) =>
                                read.isRead(c.sourceUrl ?? c.path) ||
                                read.isRead(c.path),
                          )
                          .length ??
                      0;
                  return MangaCard(
                    title: entry.title,
                    coverPath: entry.cover,
                    onTap: () => unawaited(_open(entry)),
                    badge: fresh > 0
                        ? '$fresh nuevos'
                        : stateLabel != null
                        ? '$stateLabel${entry.downloaded ? ' · Descargado' : ''}'
                        : entry.downloaded
                        ? 'Descargado'
                        : entry.progress != null
                        ? 'Leyendo'
                        : 'Por leer',
                    badgeIcon: fresh > 0
                        ? Icons.new_releases_outlined
                        : entry.downloaded
                        ? Icons.offline_pin_outlined
                        : Icons.menu_book_outlined,
                    progress:
                        entry.local != null && entry.local!.chapters.isNotEmpty
                        ? completed / entry.local!.chapters.length
                        : null,
                    isFavorite: entry.favorite != null,
                    onFavoriteToggle: () => unawaited(
                      entry.favorite != null
                          ? favorites.removeMany(entry.favoriteKeys)
                          : favorites.toggle(
                              key: entry.favorite?.key ?? entry.key,
                              title: entry.title,
                              coverPath: entry.cover,
                            ),
                    ),
                    onLongPress: () => CategoryAssignSheet.show(
                      context: context,
                      mangaKey:
                          entry.local?.path ?? entry.favorite?.key ?? entry.key,
                      mangaTitle: entry.title,
                    ),
                  );
                }, childCount: visible.length),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
