import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../design/yoma_components.dart';
import '../design/yoma_tokens.dart';
import '../models/manga_source.dart';
import '../providers/library_provider.dart';
import '../providers/profile_provider.dart';
import '../providers/source_provider.dart';
import '../services/myanimelist_client.dart';
import '../services/myanimelist_service.dart';
import 'mal_library_screen.dart';
import 'online_browser_screen.dart';
import 'sources_screen.dart';

class HomeScreen extends StatefulWidget {
  final MyAnimeListClient? malClient;
  const HomeScreen({super.key, this.malClient});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final GlobalKey<OnlineBrowserScreenState> _onlineBrowserKey =
      GlobalKey<OnlineBrowserScreenState>();

  Widget _buildSourceUnavailable(ThemeData theme, SourceProvider source) {
    return Center(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 28),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 28),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: YomaRadii.lgAll,
              border: Border.all(color: YomaColors.borderSubtle),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withAlpha(36),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    source.active.icon,
                    size: 32,
                    color: theme.colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  source.active.name,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'Esta fuente está seleccionada pero aún no tiene conector. '
                  'Cambia a MangaDex, InManga, ManhwaWeb o Lectortmo en Fuentes.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurface.withAlpha(170),
                    height: 1.4,
                    fontWeight: FontWeight.w600,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 18),
                Text(
                  source.active.detailLine,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 18),
                FilledButton.icon(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const SourcesScreen()),
                    );
                  },
                  icon: const Icon(Icons.hub_rounded),
                  label: const Text('Elegir fuente'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showQuickStatsSheet(ThemeData theme, LibraryProvider library) {
    final stats = library.readingStats;
    final totalMangas = library.mangas.length;
    final totalChapters = library.mangas.fold<int>(
      0,
      (sum, manga) => sum + manga.chapters.length,
    );
    final totalPages = library.mangas.fold<int>(
      0,
      (sum, manga) =>
          sum +
          manga.chapters.fold<int>(
            0,
            (pages, chapter) => pages + chapter.pageCount,
          ),
    );
    final inProgress = library.progressMap.length;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: theme.colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(YomaRadii.xl)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 42,
                    height: 4,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.onSurface.withAlpha(60),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'YomaShi',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Estadísticas rápidas',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withAlpha(170),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  'Actividad de lectura',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: theme.colorScheme.onSurface.withAlpha(170),
                    letterSpacing: 0.4,
                  ),
                ),
                const SizedBox(height: 10),
                GridView.count(
                  crossAxisCount: 2,
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: 2.35,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  children: [
                    _StatCard(
                      theme: theme,
                      label: 'Aperturas',
                      value: '${stats.mangaOpens}',
                      icon: Icons.auto_stories_outlined,
                    ),
                    _StatCard(
                      theme: theme,
                      label: 'Mangas distintos',
                      value: '${stats.uniqueMangasOpened}',
                      icon: Icons.library_books_outlined,
                    ),
                    _StatCard(
                      theme: theme,
                      label: 'Capítulos abiertos',
                      value: '${stats.chaptersOpened}',
                      icon: Icons.menu_book_outlined,
                    ),
                    _StatCard(
                      theme: theme,
                      label: 'Páginas leídas',
                      value: '${stats.pagesRead}',
                      icon: Icons.import_contacts_outlined,
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Text(
                  'Biblioteca local',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: theme.colorScheme.onSurface.withAlpha(170),
                    letterSpacing: 0.4,
                  ),
                ),
                const SizedBox(height: 10),
                GridView.count(
                  crossAxisCount: 2,
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: 2.35,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  children: [
                    _StatCard(
                      theme: theme,
                      label: 'Mangas',
                      value: '$totalMangas',
                      icon: Icons.collections_bookmark_outlined,
                    ),
                    _StatCard(
                      theme: theme,
                      label: 'Capítulos',
                      value: '$totalChapters',
                      icon: Icons.book_outlined,
                    ),
                    _StatCard(
                      theme: theme,
                      label: 'Páginas',
                      value: '$totalPages',
                      icon: Icons.layers_outlined,
                    ),
                    _StatCard(
                      theme: theme,
                      label: 'Con progreso',
                      value: '$inProgress',
                      icon: Icons.play_circle_outline,
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _openSources() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const SourcesScreen()));
    if (mounted) {
      _onlineBrowserKey.currentState?.refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final library = context.watch<LibraryProvider>();
    final source = context.watch<SourceProvider>();
    final linked = context.watch<ProfileProvider>().usesMyAnimeListIdentity;
    final actionHeight =
        48 * (MediaQuery.textScalerOf(context).scale(14) / 14).clamp(1.0, 2.0);

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: GestureDetector(
          onTap: () => _showQuickStatsSheet(theme, library),
          behavior: HitTestBehavior.opaque,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: YomaModuleTitle(
              logoAsset: 'assets/branding/2-Manga.png',
              label: Image.asset(
                'assets/brand/yomashi_wordmark.png',
                semanticLabel: 'YomaShi',
                width: 104,
                height: 48,
                fit: BoxFit.contain,
                alignment: Alignment.centerLeft,
                color: theme.colorScheme.onSurface,
                colorBlendMode: BlendMode.srcIn,
                cacheWidth: 576,
                filterQuality: FilterQuality.medium,
              ),
            ),
          ),
        ),
        centerTitle: false,
        bottom: linked
            ? PreferredSize(
                preferredSize: Size.fromHeight(actionHeight + 16),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                  child: SizedBox(
                    height: actionHeight,
                    child: Row(
                      children: [
                        Expanded(
                          child: SizedBox.expand(
                            child: _SourceChip(
                              source: source.isLoaded ? source.active : null,
                              onTap: _openSources,
                              shortLabel: true,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: SizedBox.expand(
                            child: OutlinedButton.icon(
                              style: _headerActionStyle(context),
                              icon: const Icon(
                                Icons.bookmarks_outlined,
                                size: 18,
                              ),
                              label: const Text(
                                'Mangas MAL',
                                maxLines: 2,
                                textAlign: TextAlign.center,
                              ),
                              onPressed: () => Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => MalLibraryScreen(
                                    client:
                                        widget.malClient ??
                                        MyAnimeListService.shared.client,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              )
            : null,
        actions: [
          if (!linked)
            Padding(
              padding: const EdgeInsets.only(right: 2),
              child: Center(
                child: _SourceChip(
                  source: source.isLoaded ? source.active : null,
                  onTap: _openSources,
                ),
              ),
            ),
          IconButton(
            tooltip: 'Recargar catálogo',
            onPressed: source.isLoaded
                ? () => _onlineBrowserKey.currentState?.refresh()
                : null,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: !source.isLoaded
            ? const Center(child: CircularProgressIndicator())
            : source.isActiveImplemented
            ? OnlineBrowserScreen(key: _onlineBrowserKey)
            : _buildSourceUnavailable(theme, source),
      ),
    );
  }
}

ButtonStyle _headerActionStyle(BuildContext context) =>
    OutlinedButton.styleFrom(
      foregroundColor: Theme.of(context).colorScheme.primary,
      textStyle: Theme.of(
        context,
      ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: YomaRadii.mdAll),
      alignment: Alignment.center,
    );

class _SourceChip extends StatelessWidget {
  final MangaSource? source;
  final VoidCallback onTap;
  final bool shortLabel;

  const _SourceChip({
    required this.source,
    required this.onTap,
    this.shortLabel = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loaded = source != null;
    final label = loaded
        ? (shortLabel ? MangaSources.shortLabel(source!.id) : source!.name)
        : '…';

    if (shortLabel) {
      return Tooltip(
        message: 'Cambiar fuente',
        child: OutlinedButton.icon(
          style: _headerActionStyle(context),
          onPressed: onTap,
          icon: Icon(source?.icon ?? Icons.public_rounded, size: 18),
          label: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(width: 4),
              const Icon(Icons.expand_more_rounded, size: 18),
            ],
          ),
        ),
      );
    }

    return Tooltip(
      message: 'Cambiar fuente',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(999),
          child: Ink(
            decoration: BoxDecoration(
              color: loaded
                  ? theme.colorScheme.primary.withAlpha(28)
                  : theme.colorScheme.onSurface.withAlpha(12),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: loaded
                    ? theme.colorScheme.primary.withAlpha(80)
                    : theme.colorScheme.onSurface.withAlpha(22),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 6, 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    source?.icon ?? Icons.public_rounded,
                    size: 14,
                    color: loaded
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurface.withAlpha(140),
                  ),
                  const SizedBox(width: 6),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 118),
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: loaded
                            ? theme.colorScheme.primary
                            : theme.colorScheme.onSurface.withAlpha(150),
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.1,
                      ),
                    ),
                  ),
                  Icon(
                    Icons.expand_more_rounded,
                    size: 16,
                    color: loaded
                        ? theme.colorScheme.primary.withAlpha(180)
                        : theme.colorScheme.onSurface.withAlpha(120),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final ThemeData theme;
  final String label;
  final String value;
  final IconData icon;

  const _StatCard({
    required this.theme,
    required this.label,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.colorScheme.onSurface.withAlpha(16)),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withAlpha(38),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: theme.colorScheme.primary, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  value,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withAlpha(170),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
