part of '../native_anime_screen.dart';

// Descargas: un anime por tarjeta; al pulsarla se abre su página con los
// episodios descargados y los que siguen en la cola.

class _AnimeDownloads extends StatefulWidget {
  final AnimeController app;
  final void Function(AnimeDetail, AnimeEpisode) play;
  final ValueChanged<String> detail;
  const _AnimeDownloads({
    required this.app,
    required this.play,
    required this.detail,
  });
  @override
  State<_AnimeDownloads> createState() => _AnimeDownloadsState();
}

class _AnimeDownloadsState extends State<_AnimeDownloads> {
  String _filter = 'all';
  Future<void> _action(String action, {String? key, bool? value}) async {
    try {
      await widget.app.downloadControl(action, key: key, value: value);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(animeErrorText(e))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = widget.app, all = app.downloads;
    final jobs = all
        .where(
          (d) => _filter == 'all' || (_filter == 'done' ? d.ready : !d.ready),
        )
        .toList();
    final used = all.fold<int>(0, (n, d) => n + d.bytes);
    return RefreshIndicator(
      onRefresh: app.refreshDownloads,
      child: ListView(
        key: const PageStorageKey('anime-downloads'),
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            'Descargas',
            style: Theme.of(
              context,
            ).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          const Text('Tus episodios, donde quieras.'),
          const SizedBox(height: 20),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  const Icon(Icons.storage_outlined, size: 36),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${animeBytes(used)} utilizados',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        Text(
                          '${all.where((d) => d.ready).length} episodios completos',
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Actualizar descargas',
                    onPressed: app.refreshDownloads,
                    icon: const Icon(Icons.refresh),
                  ),
                ],
              ),
            ),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Descargar solo con Wi-Fi'),
            value: app.wifiOnly,
            onChanged: app.supportedDownloads
                ? (v) => _action('wifi', value: v)
                : null,
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Descargar lo que estás viendo'),
            subtitle: const Text(
              'Los próximos episodios sin ver de tus animes en «Viendo», '
              'de la biblioteca y de MyAnimeList, en tu idioma preferido.',
            ),
            value: app.autoDownload,
            onChanged: app.supportedDownloads
                ? (v) => app.setAutoDownload(enabled: v)
                : null,
          ),
          if (app.autoDownload && app.supportedDownloads)
            Padding(
              padding: const EdgeInsets.only(bottom: YomaSpacing.sm),
              child: Row(
                children: [
                  const Expanded(child: Text('Episodios por adelantado')),
                  SegmentedButton<int>(
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment(value: 1, label: Text('1')),
                      ButtonSegment(value: 2, label: Text('2')),
                      ButtonSegment(value: 3, label: Text('3')),
                    ],
                    selected: {app.autoDownloadAhead},
                    onSelectionChanged: (v) =>
                        app.setAutoDownload(ahead: v.single),
                  ),
                ],
              ),
            ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Borrar los episodios vistos'),
            subtitle: const Text(
              'Una semana después de verlos, aquí, en otro dispositivo o en '
              'MyAnimeList.',
            ),
            value: app.autoDeleteWatched,
            onChanged: app.supportedDownloads
                ? (v) => app.setAutoDownload(deleteWatched: v)
                : null,
          ),
          if (app.downloadError != null)
            Text(
              app.downloadError!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          if (!app.supportedDownloads)
            const AnimeMessage(
              'Las descargas necesitan Android 8 o posterior.',
            ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ChoiceChip(
                label: const Text('Todas'),
                selected: _filter == 'all',
                onSelected: (_) => setState(() => _filter = 'all'),
              ),
              ChoiceChip(
                label: const Text('En curso'),
                selected: _filter == 'active',
                onSelected: (_) => setState(() => _filter = 'active'),
              ),
              ChoiceChip(
                label: const Text('Completadas'),
                selected: _filter == 'done',
                onSelected: (_) => setState(() => _filter = 'done'),
              ),
              if (all.isNotEmpty)
                OutlinedButton.icon(
                  onPressed: () =>
                      _action(app.paused ? 'resumeAll' : 'pauseAll'),
                  icon: Icon(app.paused ? Icons.play_arrow : Icons.pause),
                  label: Text(app.paused ? 'Reanudar cola' : 'Pausar cola'),
                ),
            ],
          ),
          const SizedBox(height: 16),
          if (jobs.isEmpty)
            const AnimeMessage(
              'Descarga episodios desde una ficha o el reproductor para verlos aquí.',
            ),
          for (final group in _groups(jobs)) _group(context, group),
        ],
      ),
    );
  }

  /// Episodios agrupados por anime, en el orden de la cola (así se guardan
  /// también en el teléfono: una carpeta por anime).
  List<List<AnimeDownload>> _groups(List<AnimeDownload> jobs) {
    final groups = <String, List<AnimeDownload>>{};
    for (final d in jobs) {
      groups.putIfAbsent(d.slug, () => []).add(d);
    }
    return groups.values.toList();
  }

  /// Tarjeta de un anime; abre su página con los episodios.
  Widget _group(BuildContext context, List<AnimeDownload> items) {
    final theme = Theme.of(context);
    final first = items.first;
    final ready = items.where((d) => d.ready).length;
    final active = items.where((d) => !d.ready).toList();
    final failed = active.where((d) => d.error.isNotEmpty).length;
    final bytes = items.fold<int>(0, (n, d) => n + d.bytes);
    final total = active.fold<int>(0, (n, d) => n + d.total);
    final done = active.fold<int>(0, (n, d) => n + d.bytes);
    final cover = '${first.raw['cover'] ?? ''}';
    return Padding(
      padding: const EdgeInsets.only(bottom: YomaSpacing.md),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => _AnimeDownloadedPage(
                app: widget.app,
                slug: first.slug,
                title: first.title,
                cover: cover,
                play: widget.play,
                detail: widget.detail,
              ),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(YomaSpacing.md),
            child: Row(
              children: [
                SizedBox(
                  width: 45,
                  height: 64,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(YomaRadii.sm),
                    child: animeArtwork(cover, width: 120),
                  ),
                ),
                const SizedBox(width: YomaSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        first.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        [
                          items.length == 1
                              ? '1 episodio'
                              : '${items.length} episodios',
                          '$ready descargados',
                          animeBytes(bytes),
                        ].join(' · '),
                        style: theme.textTheme.bodySmall,
                      ),
                      if (failed > 0)
                        Text(
                          failed == 1
                              ? '1 descarga con error'
                              : '$failed descargas con error',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.error,
                          ),
                        ),
                      if (active.isNotEmpty && total > 0) ...[
                        const SizedBox(height: YomaSpacing.sm),
                        YomaProgressBar(value: done / total),
                      ],
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Página de un anime descargado: primero los episodios descargados y después
/// los que están en cola, cada lista por número de episodio.
class _AnimeDownloadedPage extends StatefulWidget {
  final AnimeController app;
  final String slug, title, cover;
  final void Function(AnimeDetail, AnimeEpisode) play;
  final ValueChanged<String> detail;
  const _AnimeDownloadedPage({
    required this.app,
    required this.slug,
    required this.title,
    required this.cover,
    required this.play,
    required this.detail,
  });
  @override
  State<_AnimeDownloadedPage> createState() => _AnimeDownloadedPageState();
}

class _AnimeDownloadedPageState extends State<_AnimeDownloadedPage> {
  /// [action] sobre el episodio [key]; sin [action], borra [remove].
  Future<bool> _action(
    String? action, {
    String? key,
    List<AnimeDownload> remove = const [],
  }) async {
    try {
      if (action == null) {
        await widget.app.removeDownloads(remove);
      } else {
        await widget.app.downloadControl(action, key: key);
      }
      return true;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(animeErrorText(e))));
      }
      return false;
    }
  }

  Future<void> _play(AnimeDownload d) async {
    final app = widget.app;
    final cache = await app.store.cache('detail:${d.slug}');
    final data = cache == null
        ? {
            'anime': d.raw,
            'episodes': app.downloads
                .where((x) => x.slug == d.slug)
                .map(
                  (x) => {
                    'id': x.raw['episode_id'],
                    'slug': x.slug,
                    'number': x.number,
                  },
                )
                .toList(),
          }
        : animeMap(cache['data']);
    final detail = AnimeDetail.fromJson({
      ...data,
      'local_language': d.language,
    });
    final episode = detail.episodes.firstWhere(
      (e) => e.id == animeInt(d.raw['episode_id']),
      orElse: () => AnimeEpisode.fromJson({
        'id': d.raw['episode_id'],
        'slug': d.slug,
        'number': d.number,
      }),
    );
    widget.play(detail, episode);
  }

  Future<bool> _confirm(String title) async =>
      await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text(title),
          content: const Text('Se conserva tu historial y progreso local.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Conservar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Eliminar'),
            ),
          ],
        ),
      ) ==
      true;

  Future<void> _deleteAll(List<AnimeDownload> items) async {
    if (!await _confirm('Eliminar todas las descargas')) return;
    if (await _action(null, remove: items) && mounted) {
      await Navigator.of(context).maybePop();
    }
  }

  static int _byNumber(AnimeDownload a, AnimeDownload b) =>
      (double.tryParse(a.number) ?? 0).compareTo(
        double.tryParse(b.number) ?? 0,
      );

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.app,
    builder: (context, _) {
      final theme = Theme.of(context);
      final items = widget.app.downloads
          .where((d) => d.slug == widget.slug)
          .toList();
      final ready = items.where((d) => d.ready).toList()..sort(_byNumber);
      final active = items.where((d) => !d.ready).toList()..sort(_byNumber);
      final bytes = items.fold<int>(0, (n, d) => n + d.bytes);
      return Scaffold(
        appBar: AppBar(
          title: Text(
            widget.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          actions: [
            if (items.isNotEmpty)
              PopupMenuButton<String>(
                onSelected: (v) {
                  if (v == 'detail') widget.detail(widget.slug);
                  if (v == 'delete') unawaited(_deleteAll(items));
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'detail', child: Text('Ver ficha')),
                  PopupMenuItem(value: 'delete', child: Text('Eliminar todo')),
                ],
              ),
          ],
        ),
        body: RefreshIndicator(
          onRefresh: widget.app.refreshDownloads,
          child: ListView(
            key: PageStorageKey('anime-downloaded-${widget.slug}'),
            padding: const EdgeInsets.symmetric(vertical: YomaSpacing.lg),
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: YomaSpacing.xl),
                child: Row(
                  children: [
                    SizedBox(
                      width: 72,
                      height: 102,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(YomaRadii.sm),
                        child: animeArtwork(widget.cover, width: 200),
                      ),
                    ),
                    const SizedBox(width: YomaSpacing.lg),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.title,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleLarge,
                          ),
                          const SizedBox(height: YomaSpacing.xs),
                          Text(
                            [
                              ready.length == 1
                                  ? '1 descargado'
                                  : '${ready.length} descargados',
                              if (active.isNotEmpty) '${active.length} en cola',
                              animeBytes(bytes),
                            ].join(' · '),
                            style: theme.textTheme.bodySmall,
                          ),
                          const SizedBox(height: YomaSpacing.sm),
                          OutlinedButton.icon(
                            onPressed: () => widget.detail(widget.slug),
                            icon: const Icon(Icons.info_outline_rounded),
                            label: const Text('Ver ficha'),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: YomaSpacing.md),
              if (items.isEmpty)
                const AnimeMessage(
                  'Ya no quedan episodios descargados de este anime.',
                ),
              if (ready.isNotEmpty) _heading(context, 'Descargados'),
              for (final d in ready) _episode(context, d),
              if (active.isNotEmpty) _heading(context, 'En cola'),
              for (final d in active) _episode(context, d),
            ],
          ),
        ),
      );
    },
  );

  Widget _heading(BuildContext context, String text) => Padding(
    padding: const EdgeInsets.fromLTRB(
      YomaSpacing.xl,
      YomaSpacing.md,
      YomaSpacing.xl,
      YomaSpacing.xs,
    ),
    child: Text(text, style: Theme.of(context).textTheme.titleSmall),
  );

  Widget _episode(BuildContext context, AnimeDownload d) {
    final theme = Theme.of(context);
    final watched =
        widget.app.positions['${d.slug}:${d.number}']?['watched'] == true;
    return ListTile(
      contentPadding: const EdgeInsets.fromLTRB(
        YomaSpacing.xl,
        YomaSpacing.xs,
        YomaSpacing.xs,
        YomaSpacing.xs,
      ),
      leading: Icon(
        d.ready ? Icons.play_circle_outline_rounded : Icons.downloading_rounded,
        color: d.ready
            ? theme.colorScheme.primary
            : theme.colorScheme.onSurfaceVariant,
      ),
      title: Text('Episodio ${d.number} · ${animeLanguageLabel(d.language)}'),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            [
              d.ready ? 'Descargado' : animeDownloadStateLabel(d.state),
              if (watched) 'Visto',
              '${animeBytes(d.bytes)}${d.total > 0 && !d.ready ? ' / ${animeBytes(d.total)}' : ''}',
            ].join(' · '),
            style: theme.textTheme.bodySmall,
          ),
          if (d.total > 0 && !d.ready)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: YomaProgressBar(value: d.bytes / d.total),
            ),
          if (d.error.isNotEmpty)
            Text(
              d.error,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
        ],
      ),
      onTap: d.ready ? () => _play(d) : null,
      trailing: PopupMenuButton<String>(
        onSelected: (v) async {
          if (v == 'play') {
            await _play(d);
            return;
          }
          if (v == 'delete' || v == 'cancel') {
            final yes = await _confirm(
              d.ready ? 'Eliminar descarga' : 'Cancelar descarga',
            );
            if (!yes) return;
            await _action(null, remove: [d]);
            return;
          }
          await _action(v, key: d.key);
        },
        itemBuilder: (_) => [
          if (d.ready)
            const PopupMenuItem(
              value: 'play',
              child: Text('Reproducir sin conexión'),
            ),
          if (!d.ready)
            const PopupMenuItem(value: 'pause', child: Text('Pausar')),
          if (!d.ready)
            const PopupMenuItem(value: 'retry', child: Text('Reintentar')),
          if (d.ready)
            const PopupMenuItem(
              value: 'verify',
              child: Text('Verificar archivo'),
            ),
          PopupMenuItem(
            value: d.ready ? 'delete' : 'cancel',
            child: Text(d.ready ? 'Eliminar archivo' : 'Cancelar descarga'),
          ),
        ],
      ),
    );
  }
}
