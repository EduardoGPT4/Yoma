import 'dart:async';
import 'package:flutter/material.dart';

import '../models/manga_source.dart';
import '../models/online_manga.dart';
import '../services/mal_source_matcher.dart';
import '../services/myanimelist_client.dart';
import '../services/myanimelist_service.dart';
import '../services/online_catalog_service.dart';
import '../utils/app_failure.dart';
import '../utils/network_errors.dart';
import '../widgets/manga_cover_thumbnail.dart';
import 'online_manga_detail_screen.dart';

class MalMangaSourcesScreen extends StatefulWidget {
  final MalManga manga;
  final int ownerId;
  final MyAnimeListClient? client;
  final MalSourceMatcher? matcher;
  final void Function(OnlineMangaSummary manga, String sourceId)? onOpen;
  const MalMangaSourcesScreen({
    super.key,
    required this.manga,
    required this.ownerId,
    this.client,
    this.matcher,
    this.onOpen,
  });

  @override
  State<MalMangaSourcesScreen> createState() => _MalMangaSourcesScreenState();
}

class _MalMangaSourcesScreenState extends State<MalMangaSourcesScreen> {
  late final _client = widget.client ?? MyAnimeListService.shared.client;
  late final _matcher = widget.matcher ?? MalSourceMatcher();
  final _results = <String, SourceSearchResult>{};
  CancellationToken _cancellation = CancellationToken();
  int _generation = 0;
  bool _checking = true;
  String? _sessionError;

  @override
  void initState() {
    super.initState();
    _client.sessionChanges.addListener(_sessionChanged);
    unawaited(_start());
  }

  void _sessionChanged() => unawaited(_start());

  Future<void> _start() async {
    final generation = ++_generation;
    _cancellation.cancel();
    _cancellation = CancellationToken();
    setState(() {
      _checking = true;
      _results.clear();
      _sessionError = null;
    });
    try {
      final auth = await _client.credentials.load();
      if (!mounted || generation != _generation) return;
      if (auth?['connected'] != true ||
          (auth?['profile'] as Map?)?['id'] != widget.ownerId) {
        setState(() {
          _checking = false;
          _sessionError =
              'La cuenta cambió o se desconectó. Vuelve a Mangas MAL.';
        });
        return;
      }
      setState(() => _checking = false);
      for (final id in OnlineCatalogService.searchableSourceIds) {
        unawaited(_find(id, generation));
      }
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(() {
          _checking = false;
          _sessionError = error.toString();
        });
      }
    }
  }

  Future<void> _find(String id, int generation) async {
    if (!mounted || generation != _generation) return;
    setState(
      () => _results[id] = SourceSearchResult(sourceId: id, loading: true),
    );
    try {
      final result = await _matcher.findInSource(
        widget.manga,
        id,
        cancellation: _cancellation,
      );
      if (mounted && generation == _generation) {
        setState(() => _results[id] = result);
      }
    } catch (error) {
      if (mounted && generation == _generation && !_cancellation.isCancelled) {
        setState(
          () => _results[id] = SourceSearchResult(sourceId: id, error: error),
        );
      }
    }
  }

  @override
  void dispose() {
    _generation++;
    _cancellation.cancel();
    _client.sessionChanges.removeListener(_sessionChanged);
    super.dispose();
  }

  void _open(OnlineMangaSummary manga, String id) {
    if (widget.onOpen != null) {
      widget.onOpen!(manga, id);
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            OnlineMangaDetailScreen(mangaUrl: manga.url, sourceId: id),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Coincidencias exactas'),
      actions: [
        IconButton(
          tooltip: 'Buscar de nuevo',
          onPressed: _start,
          icon: const Icon(Icons.refresh_rounded),
        ),
      ],
    ),
    body: _checking
        ? const Center(child: CircularProgressIndicator())
        : _sessionError != null
        ? Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(_sessionError!),
            ),
          )
        : ListView(
            padding: const EdgeInsets.all(12),
            children: [
              Text(
                widget.manga.title,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              const Text(
                'Títulos completos y nombres alternativos de MAL. Se respetan los idiomas elegidos para cada fuente.',
              ),
              const SizedBox(height: 16),
              for (final id in OnlineCatalogService.searchableSourceIds)
                _source(context, id),
            ],
          ),
  );

  Widget _source(BuildContext context, String id) {
    final result =
        _results[id] ?? SourceSearchResult(sourceId: id, loading: true);
    final loading = result.loading;
    return Card(
      key: ValueKey('mal-source-$id'),
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              MangaSources.byId(id).name,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 10),
            if (loading)
              const LinearProgressIndicator()
            else if (result.error != null) ...[
              Text(NetworkErrors.friendly(result.error!)),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => _find(id, _generation),
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Reintentar fuente'),
                ),
              ),
            ] else if (result.items.isEmpty)
              const Text('Sin coincidencias exactas en esta fuente.')
            else
              for (final manga in result.items)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: MangaCoverThumbnail(url: manga.coverUrl),
                  title: Text(manga.title),
                  subtitle: const Text('Coincidencia exacta por título'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => _open(manga, id),
                ),
          ],
        ),
      ),
    );
  }
}
