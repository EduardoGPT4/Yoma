import 'dart:async';
import 'package:flutter/material.dart';

import '../services/myanimelist_client.dart';
import '../services/myanimelist_service.dart';
import '../widgets/manga_cover_thumbnail.dart';
import 'mal_manga_sources_screen.dart';

class MalLibraryScreen extends StatefulWidget {
  final MyAnimeListClient? client;
  final ValueChanged<MalManga>? onOpen;
  const MalLibraryScreen({super.key, this.client, this.onOpen});
  @override
  State<MalLibraryScreen> createState() => _MalLibraryScreenState();
}

class _Bucket {
  List<MalManga> items = [];
  int? nextOffset = 0;
  bool loading = false;
  Object? error;
}

class _MalLibraryScreenState extends State<MalLibraryScreen> {
  static const _labels = {'reading': 'Leyendo', 'plan_to_read': 'Por leer'};
  late final _client = widget.client ?? MyAnimeListService.shared.client;
  final _buckets = {
    for (final status in MyAnimeListClient.libraryStatuses) status: _Bucket(),
  };
  int? _owner;
  int _generation = 0;
  bool _checking = true;
  bool _connected = false;
  String _filter = 'all';
  String? _connectionError;

  @override
  void initState() {
    super.initState();
    _client.sessionChanges.addListener(_sessionChanged);
    unawaited(_reload(clear: true));
  }

  void _sessionChanged() => unawaited(_reload(clear: true));

  Future<void> _reload({bool clear = false}) async {
    final generation = ++_generation;
    setState(() {
      _checking = true;
      _connectionError = null;
      if (clear) {
        _owner = null;
        _connected = false;
        for (final status in _buckets.keys.toList()) {
          _buckets[status] = _Bucket();
        }
      }
    });
    try {
      final auth = await _client.credentials.load();
      if (!mounted || generation != _generation) return;
      final owner = (auth?['profile'] as Map?)?['id'];
      final connected = auth?['connected'] == true && owner is int && owner > 0;
      setState(() {
        _checking = false;
        _connected = connected;
        if (!connected || owner != _owner) {
          for (final status in _buckets.keys.toList()) {
            _buckets[status] = _Bucket();
          }
        }
        _owner = connected ? owner : null;
      });
      if (!connected) return;
      await Future.wait(
        _buckets.keys.map((status) => _load(status, generation, reset: true)),
      );
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(() {
          _checking = false;
          _connectionError = error.toString();
          _connected = false;
          _owner = null;
          for (final status in _buckets.keys.toList()) {
            _buckets[status] = _Bucket();
          }
        });
      }
    }
  }

  Future<void> _load(
    String status,
    int generation, {
    bool reset = false,
  }) async {
    final bucket = _buckets[status]!;
    if ((!reset && (bucket.loading || bucket.nextOffset == null)) ||
        _owner == null) {
      return;
    }
    final owner = _owner!;
    setState(() {
      bucket.loading = true;
      bucket.error = null;
    });
    try {
      final page = await _client.library(
        status: status,
        offset: reset ? 0 : bucket.nextOffset!,
        expectedOwner: owner,
      );
      if (!mounted || generation != _generation || owner != _owner) return;
      setState(() {
        final combined = <int, MalManga>{
          if (!reset)
            for (final manga in bucket.items) manga.id: manga,
          for (final manga in page.items.where(
            (manga) => manga.status == status,
          ))
            manga.id: manga,
        };
        bucket.items = combined.values.toList();
        bucket.nextOffset = page.nextOffset;
      });
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(() => bucket.error = error);
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => bucket.loading = false);
      }
    }
  }

  Future<void> _more() async {
    await Future.wait([
      for (final status in _buckets.keys)
        if (_filter == 'all' || _filter == status) _load(status, _generation),
    ]);
  }

  @override
  void dispose() {
    _generation++;
    _client.sessionChanges.removeListener(_sessionChanged);
    super.dispose();
  }

  void _open(MalManga manga) {
    if (_owner == null || !_connected) return;
    if (widget.onOpen != null) {
      widget.onOpen!(manga);
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MalMangaSourcesScreen(
          manga: manga,
          ownerId: _owner!,
          client: _client,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final visible = _buckets.entries
        .where((entry) => _filter == 'all' || _filter == entry.key)
        .toList();
    final byId = <int, MalManga>{};
    for (final bucket in visible) {
      for (final manga in bucket.value.items) {
        byId.putIfAbsent(manga.id, () => manga);
      }
    }
    final mangas = byId.values.toList()
      ..sort((a, b) {
        final status = (a.status == 'reading' ? 0 : 1).compareTo(
          b.status == 'reading' ? 0 : 1,
        );
        return status != 0
            ? status
            : a.title.toLowerCase().compareTo(b.title.toLowerCase());
      });
    final loading = visible.any((entry) => entry.value.loading);
    final hasMore = visible.any((entry) => entry.value.nextOffset != null);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mangas MAL'),
        actions: [
          IconButton(
            tooltip: 'Actualizar lista MAL',
            onPressed:
                _checking || _buckets.values.any((bucket) => bucket.loading)
                ? null
                : () => _reload(),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _checking
          ? const Center(child: CircularProgressIndicator())
          : !_connected
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  _connectionError ??
                      'Vincula una cuenta de MyAnimeList para ver tus mangas.',
                ),
              ),
            )
          : RefreshIndicator(
              onRefresh: _reload,
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Reading y Plan to read de tu cuenta de MyAnimeList.',
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (final entry in const {
                                'all': 'Todos',
                                ..._labels,
                              }.entries)
                                ChoiceChip(
                                  label: Text(entry.value),
                                  selected: _filter == entry.key,
                                  onSelected: (_) =>
                                      setState(() => _filter = entry.key),
                                ),
                            ],
                          ),
                          for (final entry in visible.where(
                            (entry) => entry.value.error != null,
                          ))
                            Padding(
                              padding: const EdgeInsets.only(top: 12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${_labels[entry.key]}: ${entry.value.error}',
                                  ),
                                  TextButton(
                                    onPressed: entry.value.loading
                                        ? null
                                        : () => _load(
                                            entry.key,
                                            _generation,
                                            reset: true,
                                          ),
                                    child: Text(
                                      'Reintentar ${_labels[entry.key]}',
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  if (loading)
                    const SliverToBoxAdapter(child: LinearProgressIndicator()),
                  if (mangas.isEmpty &&
                      !loading &&
                      !visible.any((entry) => entry.value.error != null))
                    const SliverFillRemaining(
                      hasScrollBody: false,
                      child: Center(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: Text(
                            'No tienes mangas en estos estados de lectura.',
                          ),
                        ),
                      ),
                    ),
                  SliverList.builder(
                    itemCount: mangas.length,
                    itemBuilder: (context, index) {
                      final manga = mangas[index];
                      final progress = manga.totalChapters > 0
                          ? '${manga.chaptersRead} / ${manga.totalChapters} capítulos'
                          : '${manga.chaptersRead} capítulos leídos';
                      return Card(
                        margin: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 5,
                        ),
                        child: ListTile(
                          key: ValueKey('mal-manga-${manga.id}'),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          leading: MangaCoverThumbnail(url: manga.picture),
                          title: Text(manga.title),
                          subtitle: Text(
                            '${_labels[manga.status]} · $progress',
                          ),
                          trailing: const Icon(Icons.chevron_right_rounded),
                          onTap: () => _open(manga),
                        ),
                      );
                    },
                  ),
                  if (hasMore)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: OutlinedButton(
                          onPressed: loading ? null : _more,
                          child: const Text('Cargar más mangas'),
                        ),
                      ),
                    ),
                  const SliverToBoxAdapter(child: SizedBox(height: 20)),
                ],
              ),
            ),
    );
  }
}
