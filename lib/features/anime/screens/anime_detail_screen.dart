import 'package:flutter/material.dart';
import '../../../design/yoma_tokens.dart';
import '../data/anime_controller.dart';
import '../data/local_anime_downloads.dart';
import '../models/anime_models.dart';
import '../widgets/anime_widgets.dart';

class AnimeDetailScreen extends StatefulWidget {
  final AnimeController controller;
  final String slug;
  final void Function(AnimeDetail, AnimeEpisode) play;
  final void Function(String) openSeason;
  final VoidCallback openWeb;
  const AnimeDetailScreen({
    super.key,
    required this.controller,
    required this.slug,
    required this.play,
    required this.openSeason,
    required this.openWeb,
  });
  @override
  State<AnimeDetailScreen> createState() => _AnimeDetailScreenState();
}

class _AnimeDetailScreenState extends State<AnimeDetailScreen> {
  late Future<AnimeDetail> _detail = widget.controller.detail(widget.slug);
  final _search = TextEditingController();
  bool _reverse = false, _unwatched = false;
  String _language = 'SUB';
  final Set<int> _selected = {};
  AnimeDetail? _shown;
  @override
  void initState() {
    super.initState();
    _language = '${widget.controller.settings['language'] ?? 'SUB'}';
    widget.controller.addListener(_refreshed);
  }

  /// La ficha guardada se muestra al instante y se sustituye al actualizarse.
  void _refreshed() {
    final latest = widget.controller.details[widget.slug];
    if (latest == null || identical(latest, _shown)) return;
    _shown = latest;
    setState(() => _detail = Future.value(latest));
  }

  @override
  void dispose() {
    widget.controller.removeListener(_refreshed);
    _search.dispose();
    super.dispose();
  }

  Future<void> _queue(AnimeDetail detail, List<AnimeEpisode> episodes) async {
    try {
      final outcomes = <String>[];
      for (final ep in episodes) {
        outcomes.add(
          await widget.controller.enqueue(detail.anime, ep, _language),
        );
      }
      if (mounted) {
        setState(_selected.clear);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AnimeController.downloadNotice(
                outcomes,
                paused: widget.controller.paused,
              ),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(animeErrorText(e))));
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: FutureBuilder<AnimeDetail>(
      future: _detail,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return Scaffold(
            appBar: AppBar(title: const Text('YomaTV')),
            body: snapshot.hasError
                ? AnimeMessage(
                    snapshot.error.toString(),
                    action: 'Reintentar',
                    onAction: () => setState(
                      () => _detail = widget.controller.detail(
                        widget.slug,
                        refresh: true,
                      ),
                    ),
                  )
                : const Center(child: CircularProgressIndicator()),
          );
        }
        final detail = snapshot.data!,
            anime = detail.anime,
            app = widget.controller;
        return AnimatedBuilder(
          animation: app,
          builder: (context, _) {
            var episodes = detail.episodes
                .where(
                  (e) =>
                      e.number.contains(_search.text) &&
                      (!_unwatched || app.positions[e.key]?['watched'] != true),
                )
                .toList();
            if (_reverse) episodes = episodes.reversed.toList();
            return CustomScrollView(
              key: PageStorageKey('anime-detail:${anime.slug}'),
              slivers: [
                SliverAppBar(
                  expandedHeight: 280,
                  pinned: true,
                  actions: [
                    IconButton(
                      tooltip: 'Ver en la web',
                      onPressed: widget.openWeb,
                      icon: const Icon(Icons.open_in_browser),
                    ),
                  ],
                  flexibleSpace: FlexibleSpaceBar(
                    background: Stack(
                      fit: StackFit.expand,
                      children: [
                        animeArtwork(anime.cover, width: 900),
                        const AnimeBackdropGradient(),
                        Positioned(
                          left: YomaSpacing.lg,
                          right: YomaSpacing.lg,
                          bottom: YomaSpacing.xxl,
                          child: Text(
                            anime.title,
                            style: Theme.of(context).textTheme.headlineMedium,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(
                    YomaSpacing.lg,
                    YomaSpacing.md,
                    YomaSpacing.lg,
                    YomaSpacing.xl,
                  ),
                  sliver: SliverList.list(
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          if (anime.category.isNotEmpty)
                            Chip(label: Text(anime.category)),
                          if (anime.year.isNotEmpty)
                            Chip(label: Text(anime.year)),
                          if (anime.episodes > 0)
                            Chip(label: Text('${anime.episodes} episodios')),
                          if (anime.score != null)
                            Chip(
                              avatar: const Icon(
                                Icons.star_rounded,
                                size: 16,
                                color: YomaColors.rating,
                              ),
                              label: Text('${anime.score}'),
                            ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          FilledButton.icon(
                            onPressed: () {
                              final episode = app.resumeEpisode(detail);
                              if (episode != null) widget.play(detail, episode);
                            },
                            icon: const Icon(Icons.play_arrow),
                            label: const Text('Reproducir'),
                          ),
                          OutlinedButton.icon(
                            onPressed: () => app.updateLibrary(
                              anime,
                              savedValue: !app.isSaved(anime.slug),
                            ),
                            icon: Icon(
                              app.isSaved(anime.slug)
                                  ? Icons.bookmark
                                  : Icons.bookmark_outline,
                            ),
                            label: Text(
                              app.isSaved(anime.slug) ? 'Guardado' : 'Guardar',
                            ),
                          ),
                          IconButton(
                            tooltip: 'Favorito',
                            onPressed: () => app.updateLibrary(
                              anime,
                              savedValue: true,
                              favorite: !app.isFavorite(anime.slug),
                            ),
                            icon: Icon(
                              app.isFavorite(anime.slug)
                                  ? Icons.star
                                  : Icons.star_outline,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      if (anime.synopsis.isNotEmpty)
                        SelectableText(
                          anime.synopsis,
                          style: Theme.of(
                            context,
                          ).textTheme.bodyLarge?.copyWith(height: 1.55),
                        ),
                      if (anime.genres.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 6,
                          children: anime.genres
                              .map((g) => Chip(label: Text(g)))
                              .toList(),
                        ),
                      ],
                      if (anime.alternatives.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Text(anime.alternatives.join('\n')),
                      ],
                      if (detail.warning.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Text(
                          detail.warning,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(color: YomaColors.warning),
                        ),
                      ],
                      if (detail.seasons.length > 1) ...[
                        const SizedBox(height: 24),
                        Text(
                          'Temporadas y entregas',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: detail.seasons
                              .map(
                                (s) => ChoiceChip(
                                  label: Text(s.label),
                                  selected: s.slug == anime.slug,
                                  onSelected: (_) {
                                    if (s.slug != anime.slug) {
                                      widget.openSeason(s.slug);
                                    }
                                  },
                                ),
                              )
                              .toList(),
                        ),
                      ],
                      const SizedBox(height: 24),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Episodios',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                          ),
                          IconButton(
                            tooltip: 'Invertir orden',
                            onPressed: () =>
                                setState(() => _reverse = !_reverse),
                            icon: const Icon(Icons.swap_vert),
                          ),
                          FilterChip(
                            label: const Text('Sin ver'),
                            selected: _unwatched,
                            onSelected: (v) => setState(() => _unwatched = v),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _search,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          prefixIcon: Icon(Icons.search),
                          hintText: 'Buscar episodio',
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              initialValue: _language,
                              decoration: const InputDecoration(
                                labelText: 'Idioma para descargas',
                              ),
                              items: ['SUB', 'LAT', 'DUB']
                                  .map(
                                    (s) => DropdownMenuItem(
                                      value: s,
                                      child: Text(animeLanguageLabel(s)),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (v) => setState(() => _language = v!),
                            ),
                          ),
                          const SizedBox(width: 8),
                          FilledButton.icon(
                            onPressed: _selected.isEmpty
                                ? null
                                : () => _queue(
                                    detail,
                                    detail.episodes
                                        .where((e) => _selected.contains(e.id))
                                        .toList(),
                                  ),
                            icon: const Icon(Icons.download),
                            label: Text(
                              _selected.isEmpty
                                  ? 'Descargar'
                                  : 'Descargar ${_selected.length}',
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      if (detail.episodes.isEmpty)
                        const AnimeMessage(
                          'La fuente todavía no tiene episodios publicados para este título.',
                        ),
                    ],
                  ),
                ),
                SliverList.builder(
                  itemCount: episodes.length,
                  itemBuilder: (context, index) {
                    final ep = episodes[index], p = app.positions[ep.key];
                    final downloaded = app.downloaded(ep, _language);
                    return ListTile(
                      leading: Checkbox(
                        value: _selected.contains(ep.id),
                        onChanged: (v) => setState(() {
                          if (v == true) {
                            _selected.add(ep.id);
                          } else {
                            _selected.remove(ep.id);
                          }
                        }),
                      ),
                      title: Text('Episodio ${ep.number}'),
                      subtitle: Text(
                        [
                          if (p?['watched'] == true) 'Visto',
                          if (animeInt(p?['positionMs']) > 0)
                            '${animeInt(p?['positionMs']) ~/ 60000} min',
                          if (downloaded != null)
                            downloaded.ready
                                ? 'Descargado'
                                : animeDownloadStateLabel(downloaded.state),
                        ].join(' · '),
                      ),
                      onTap: () => widget.play(detail, ep),
                      trailing: PopupMenuButton<String>(
                        onSelected: (action) async {
                          if (action == 'play') widget.play(detail, ep);
                          if (action == 'watched') {
                            await app.mark(anime, ep, p?['watched'] != true);
                          }
                          if (action == 'download') await _queue(detail, [ep]);
                        },
                        itemBuilder: (_) => [
                          const PopupMenuItem(
                            value: 'play',
                            child: Text('Reproducir'),
                          ),
                          PopupMenuItem(
                            value: 'watched',
                            child: Text(
                              p?['watched'] == true
                                  ? 'Marcar sin ver'
                                  : 'Marcar visto',
                            ),
                          ),
                          const PopupMenuItem(
                            value: 'download',
                            child: Text('Descargar'),
                          ),
                        ],
                      ),
                    );
                  },
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 32)),
              ],
            );
          },
        );
      },
    ),
  );
}
