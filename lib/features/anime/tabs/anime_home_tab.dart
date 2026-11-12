part of '../native_anime_screen.dart';

// Inicio: continuar viendo, estrenos y novedades.

class _AnimeHome extends StatelessWidget {
  final AnimeController app;
  final ValueChanged<String> detail;
  final void Function(String slug, MalAnimeEntry entry) openMal;
  final void Function(AnimeDetail, AnimeEpisode) play;
  const _AnimeHome({
    required this.app,
    required this.detail,
    required this.openMal,
    required this.play,
  });
  Future<void> _resume(BuildContext context, Map<String, dynamic> row) async {
    try {
      final d = await app.detail('${row['slug']}');
      final ep = AnimeEpisode.fromJson(animeMap(row['episode']));
      play(d, ep);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  Widget _shelf(
    BuildContext context,
    String title,
    IconData icon,
    List<AnimeTitle> items, {
    void Function(int index)? open,
    double? Function(int index)? progress,
    Widget? trailing,
    String? note,
  }) {
    final side = AppMetrics.maybeOf(context).horizontalPadding;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(side, YomaSpacing.xxl, side, 12),
          child: SectionHeader(
            icon: icon,
            title: title,
            trailing: '${items.length}',
            trailingWidget: trailing,
          ),
        ),
        if (note != null)
          Padding(
            padding: EdgeInsets.fromLTRB(side, 0, side, 12),
            child: Text(note, style: Theme.of(context).textTheme.bodySmall),
          ),
        SizedBox(
          height: 260,
          child: ListView.separated(
            key: PageStorageKey(title),
            padding: EdgeInsets.symmetric(horizontal: side),
            scrollDirection: Axis.horizontal,
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(width: YomaSpacing.md),
            itemBuilder: (_, i) => SizedBox(
              width: 145,
              child: AnimeCard(
                anime: items[i],
                onTap: open == null
                    ? () => detail(items[i].slug)
                    : () => open(i),
                favorite: app.isFavorite(items[i].slug),
                progress: progress?.call(i),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Animes de «Viendo» y «Plan to watch» en MAL que existen en YomaTV con
  /// el mismo nombre. Salen de la copia guardada en el teléfono.
  List<Widget> _malShelves(BuildContext context) {
    final side = AppMetrics.maybeOf(context).horizontalPadding;
    final firstLoad = app.malShelfLoading && app.malShelfSavedAt == null;
    final status = app.malShelfLoading
        ? const SizedBox.square(
            dimension: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : null;
    Widget shelf(
      String title,
      IconData icon,
      List<MalShelfItem> items, {
      required bool watching,
    }) => _shelf(
      context,
      title,
      icon,
      [for (final item in items) item.anime],
      open: (i) => openMal(items[i].anime.slug, items[i].entry),
      progress: watching
          ? (i) {
              final entry = items[i].entry;
              return entry.total > 0 ? entry.watched / entry.total : null;
            }
          : null,
      trailing: status,
    );
    return [
      if (firstLoad)
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(side, YomaSpacing.xxl, side, 0),
            child: const Row(
              children: [
                SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: YomaSpacing.md),
                Expanded(
                  child: Text('Buscando tus animes de MyAnimeList en YomaTV…'),
                ),
              ],
            ),
          ),
        ),
      if (app.malShelfError != null && !app.malShelfLoading)
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(side, YomaSpacing.md, side, 0),
            child: Text(
              app.malShelfError!,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ),
      if (app.malWatching.isNotEmpty)
        SliverToBoxAdapter(
          child: shelf(
            'Viendo en MyAnimeList',
            Icons.play_circle_outline_rounded,
            app.malWatching,
            watching: true,
          ),
        ),
      if (app.malPlanned.isNotEmpty)
        SliverToBoxAdapter(
          child: shelf(
            'Por ver en MyAnimeList',
            Icons.bookmark_border_rounded,
            app.malPlanned,
            watching: false,
          ),
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final recent = app.front?.items ?? [];
    final airing = recent.where((a) => a.active).toList();
    final theme = Theme.of(context);
    final side = AppMetrics.maybeOf(context).horizontalPadding;
    return RefreshIndicator(
      onRefresh: () =>
          Future.wait([app.loadFront(), app.loadMalShelf(force: true)]),
      child: CustomScrollView(
        key: const PageStorageKey('anime-home'),
        slivers: [
          if (recent.isNotEmpty)
            SliverToBoxAdapter(
              child: SizedBox(
                height: 340,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    animeArtwork(recent.first.cover, width: 900),
                    const AnimeBackdropGradient(),
                    Positioned(
                      left: side,
                      right: side,
                      bottom: YomaSpacing.lg,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            [
                              recent.first.category,
                              recent.first.season,
                            ].where((e) => e.isNotEmpty).join(' · '),
                            style: theme.textTheme.labelLarge?.copyWith(
                              color: theme.colorScheme.primary,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            recent.first.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.headlineMedium,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            recent.first.synopsis,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: YomaColors.textPrimary.withAlpha(215),
                            ),
                          ),
                          const SizedBox(height: 16),
                          FilledButton.icon(
                            onPressed: () => detail(recent.first.slug),
                            icon: const Icon(Icons.play_arrow),
                            label: const Text('Ver episodios'),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (app.continuing.isNotEmpty)
            SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      side,
                      YomaSpacing.xxl,
                      side,
                      12,
                    ),
                    child: const SectionHeader(
                      icon: Icons.play_circle_outline_rounded,
                      title: 'Continuar viendo',
                    ),
                  ),
                  SizedBox(
                    height: 170,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      padding: EdgeInsets.symmetric(horizontal: side),
                      itemCount: app.continuing.length,
                      separatorBuilder: (_, _) =>
                          const SizedBox(width: YomaSpacing.md),
                      itemBuilder: (context, i) {
                        final row = app.continuing[i],
                            anime = AnimeTitle.fromJson(animeMap(row['anime']));
                        final duration = animeInt(row['durationMs']);
                        return SizedBox(
                          width: 265,
                          child: Card(
                            clipBehavior: Clip.antiAlias,
                            child: InkWell(
                              onTap: () => _resume(context, row),
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  animeArtwork(anime.cover, width: 420),
                                  DecoratedBox(
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        colors: [
                                          YomaColors.scrim.withAlpha(222),
                                          YomaColors.scrim.withAlpha(30),
                                        ],
                                      ),
                                    ),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.all(
                                      YomaSpacing.lg,
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      mainAxisAlignment: MainAxisAlignment.end,
                                      children: [
                                        Text(
                                          anime.title,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: theme.textTheme.titleSmall,
                                        ),
                                        Text(
                                          'Episodio ${animeMap(row['episode'])['number']}',
                                          style: theme.textTheme.bodySmall
                                              ?.copyWith(
                                                color: YomaColors.textPrimary
                                                    .withAlpha(215),
                                              ),
                                        ),
                                        const SizedBox(height: 10),
                                        YomaProgressBar(
                                          overImage: true,
                                          value: duration <= 0
                                              ? 0
                                              : animeInt(row['positionMs']) /
                                                    duration,
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ..._malShelves(context),
          if (recent.isNotEmpty)
            SliverToBoxAdapter(
              child: _shelf(
                context,
                'Recién añadidos',
                Icons.new_releases_outlined,
                recent,
              ),
            ),
          if (airing.isNotEmpty)
            SliverToBoxAdapter(
              child: _shelf(
                context,
                'En emisión',
                Icons.live_tv_rounded,
                airing,
              ),
            ),
          if (recent.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: AnimeMessage(
                app.loading
                    ? 'Preparando tu espacio de anime…'
                    : 'El catálogo no está disponible ahora. Tu biblioteca local sigue accesible.',
                action: 'Actualizar',
                onAction: app.loadFront,
              ),
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ],
      ),
    );
  }
}
