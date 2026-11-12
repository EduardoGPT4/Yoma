part of '../native_anime_screen.dart';

// Descargas: cola local y episodios guardados.

class _AnimeDownloads extends StatefulWidget {
  final AnimeController app;
  final void Function(AnimeDetail, AnimeEpisode) play;
  const _AnimeDownloads({required this.app, required this.play});
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

  /// Episodios agrupados por anime, en el orden de la cola, cada grupo
  /// ordenado por número de episodio (así se guardan también en el teléfono:
  /// una carpeta por anime).
  List<List<AnimeDownload>> _groups(List<AnimeDownload> jobs) {
    final groups = <String, List<AnimeDownload>>{};
    for (final d in jobs) {
      groups.putIfAbsent(d.slug, () => []).add(d);
    }
    for (final items in groups.values) {
      items.sort(
        (a, b) => (double.tryParse(a.number) ?? 0).compareTo(
          double.tryParse(b.number) ?? 0,
        ),
      );
    }
    return groups.values.toList();
  }

  /// Grupos abiertos o cerrados a mano; por defecto se abren los que tienen
  /// descargas en curso o con error.
  final Map<String, bool> _open = {};

  Widget _group(BuildContext context, List<AnimeDownload> items) {
    final theme = Theme.of(context);
    final first = items.first;
    final ready = items.where((d) => d.ready).length;
    final active = items.where((d) => !d.ready).toList();
    final bytes = items.fold<int>(0, (n, d) => n + d.bytes);
    final open = _open[first.slug] ?? (active.isNotEmpty || items.length == 1);
    final total = active.fold<int>(0, (n, d) => n + d.total);
    final done = active.fold<int>(0, (n, d) => n + d.bytes);
    return Padding(
      padding: const EdgeInsets.only(bottom: YomaSpacing.md),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InkWell(
              onTap: () => setState(() => _open[first.slug] = !open),
              child: Padding(
                padding: const EdgeInsets.all(YomaSpacing.md),
                child: Row(
                  children: [
                    SizedBox(
                      width: 45,
                      height: 64,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(YomaRadii.sm),
                        child: animeArtwork(
                          '${first.raw['cover'] ?? ''}',
                          width: 120,
                        ),
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
                          if (active.isNotEmpty && total > 0) ...[
                            const SizedBox(height: YomaSpacing.sm),
                            YomaProgressBar(value: done / total),
                          ],
                        ],
                      ),
                    ),
                    AnimatedRotation(
                      turns: open ? .5 : 0,
                      duration: YomaMotion.of(context, YomaMotion.fast),
                      child: const Icon(Icons.expand_more_rounded),
                    ),
                  ],
                ),
              ),
            ),
            AnimatedSize(
              duration: YomaMotion.of(context, YomaMotion.medium),
              curve: YomaMotion.curve,
              alignment: Alignment.topCenter,
              child: open
                  ? Column(
                      children: [
                        const Divider(height: 1),
                        for (final d in items) _episode(context, d),
                      ],
                    )
                  : const SizedBox(width: double.infinity),
            ),
          ],
        ),
      ),
    );
  }

  Widget _episode(BuildContext context, AnimeDownload d) {
    final theme = Theme.of(context);
    return ListTile(
      contentPadding: const EdgeInsets.fromLTRB(
        YomaSpacing.lg,
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
              d.ready ? 'Descargado' : _label(d.state),
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
            final yes = await showDialog<bool>(
              context: context,
              builder: (c) => AlertDialog(
                title: Text(
                  d.ready ? 'Eliminar descarga' : 'Cancelar descarga',
                ),
                content: const Text(
                  'Se conserva tu historial y progreso local.',
                ),
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
            );
            if (yes != true) return;
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

  String _label(String value) => animeDownloadStateLabel(value);
}
