import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import '../data/anime_controller.dart';
import '../models/anime_models.dart';

class AnimePlayerScreen extends StatefulWidget {
  final AnimeController controller;
  final AnimeDetail detail;
  final AnimeEpisode episode;
  final void Function(AnimeEpisode) openWeb;
  const AnimePlayerScreen({
    super.key,
    required this.controller,
    required this.detail,
    required this.episode,
    required this.openWeb,
  });
  @override
  State<AnimePlayerScreen> createState() => _AnimePlayerScreenState();
}

class _AnimePlayerScreenState extends State<AnimePlayerScreen>
    with WidgetsBindingObserver {
  VideoPlayerController? _video;
  late AnimeEpisode _episode = widget.episode;
  List<AnimeServer> _servers = [];
  AnimeServer? _selected;
  String? _error;
  bool _loading = true,
      _closed = false,
      _played = false,
      _marked = false,
      _wasPlaying = false,
      _full = false;
  int _generation = 0;
  Timer? _persist;
  AnimeController get app => widget.controller;
  AnimeTitle get anime => widget.detail.anime;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    app.activity.addListener(_activity);
    unawaited(_openEpisode());
    _persist = Timer.periodic(
      const Duration(seconds: 5),
      (_) => unawaited(_save()),
    );
  }

  void _activity() {
    if (!app.activity.value) {
      _video?.pause();
      unawaited(_save());
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      _video?.pause();
      unawaited(_save());
    }
  }

  Future<void> _release() async {
    final old = _video;
    _video = null;
    if (old != null) {
      old.removeListener(_tick);
      await old.pause();
      await old.dispose();
    }
  }

  Future<void> _openEpisode() async {
    final generation = ++_generation;
    await _save();
    await _release();
    _servers = [];
    _selected = null;
    _played = false;
    _marked = app.positions[_episode.key]?['watched'] == true;
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final language =
          '${widget.detail.raw['local_language'] ?? app.settings['language'] ?? 'SUB'}';
      final local = app.downloaded(_episode, language);
      if (local?.ready == true) {
        await _initialize(
          VideoPlayerController.file(File(local!.file)),
          generation,
        );
        return;
      }
      final servers = await app.transfers.sources(anime, _episode);
      if (generation != _generation || !mounted) return;
      _servers = servers;
      final matching = servers
          .where((s) => s.supported && s.language == language)
          .toList();
      if (matching.isEmpty) {
        setState(() {
          _loading = false;
          _error = servers.isEmpty
              ? 'La fuente no ofrece servidores para este episodio.'
              : 'Selecciona un servidor e idioma disponibles.';
        });
        return;
      }
      _selected = matching.first;
      await _playServer(_selected!, generation: generation);
    } catch (e) {
      if (await _playAnyDownload(generation)) return;
      if (generation == _generation && mounted) {
        setState(() {
          _loading = false;
          _error = e.toString();
        });
      }
    }
  }

  /// Sin red, reproduce una descarga lista del episodio aunque sea de otro
  /// idioma; es mejor que no poder verlo.
  Future<bool> _playAnyDownload(int generation) async {
    final local = app.readyDownload(_episode);
    if (local == null || generation != _generation || !mounted) return false;
    try {
      await _initialize(
        VideoPlayerController.file(File(local.file)),
        generation,
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _playServer(AnimeServer server, {int? generation}) async {
    if (!server.supported) {
      _video?.pause();
      widget.openWeb(_episode);
      return;
    }
    final ticket = generation ?? ++_generation;
    if (generation == null) {
      await _save();
      await _release();
    }
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
      _selected = server;
    });
    try {
      final local = app.downloaded(_episode, server.language);
      if (local?.ready == true) {
        await _initialize(
          VideoPlayerController.file(File(local!.file)),
          ticket,
        );
        return;
      }
      final source = await app.transfers.resolve(
        anime,
        _episode,
        server.language,
        embed: server.embed,
      );
      if (ticket != _generation || !mounted) return;
      await _initialize(
        VideoPlayerController.networkUrl(
          source.url,
          httpHeaders: source.headers,
        ),
        ticket,
      );
    } catch (e) {
      if (ticket == _generation && mounted) {
        setState(() {
          _loading = false;
          _error = e.toString();
        });
      }
    }
  }

  Future<void> _initialize(VideoPlayerController video, int generation) async {
    try {
      await video.initialize();
      if (generation != _generation || !mounted) {
        await video.dispose();
        return;
      }
      _video = video;
      video.addListener(_tick);
      final progress = app.positions[_episode.key];
      final position = animeInt(progress?['positionMs']);
      if (position > 0 && position < video.value.duration.inMilliseconds) {
        await video.seekTo(Duration(milliseconds: position));
      }
      final speed = (app.settings['speed'] as num?)?.toDouble() ?? 1;
      await video.setPlaybackSpeed(speed);
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = null;
      });
      if (app.activity.value && app.settings['autoplay'] != false) {
        await video.play();
      }
    } catch (e) {
      if (_video == video) _video = null;
      await video.dispose();
      rethrow;
    }
  }

  void _tick() {
    final v = _video;
    if (v == null || _closed) return;
    final value = v.value;
    if (value.isPlaying) _played = true;
    if (_wasPlaying && !value.isPlaying) unawaited(_save());
    _wasPlaying = value.isPlaying;
    if (value.hasError && mounted && _error != value.errorDescription) {
      setState(() => _error = value.errorDescription);
    }
    if (value.isPlaying &&
        !_marked &&
        value.duration.inMilliseconds > 0 &&
        value.position.inMilliseconds >= value.duration.inMilliseconds * .8) {
      _marked = true;
      unawaited(_save(watched: true));
    }
  }

  Future<void> _writes = Future.value();
  Future<void> _save({bool? watched}) {
    final video = _video;
    if (video == null || !video.value.isInitialized || !_played) {
      return _writes;
    }
    final episode = _episode;
    final position = video.value.position.inMilliseconds;
    final duration = video.value.duration.inMilliseconds;
    // Snapshot before awaiting: a server/episode change must not misattribute progress.
    final write = _writes.then(
      (_) => app.progress(anime, episode, position, duration, watched: watched),
    );
    _writes = write.catchError((Object error) {
      if (mounted && !_closed) {
        setState(() => _error = 'No se pudo guardar el progreso: $error');
      }
    });
    return _writes;
  }

  Future<void> _change(AnimeEpisode episode) async {
    await _save();
    await _release();
    _episode = episode;
    await _openEpisode();
  }

  AnimeEpisode? _adjacent(int delta) {
    final all = widget.detail.episodes;
    final index = all.indexWhere((e) => e.id == _episode.id) + delta;
    return index >= 0 && index < all.length ? all[index] : null;
  }

  Future<void> _seek(int seconds) async {
    final v = _video;
    if (v == null) return;
    await v.seekTo(
      Duration(
        milliseconds: (v.value.position.inMilliseconds + seconds * 1000).clamp(
          0,
          v.value.duration.inMilliseconds,
        ),
      ),
    );
  }

  String _clock(Duration value) {
    final s = value.inSeconds;
    return s >= 3600
        ? '${s ~/ 3600}:${((s % 3600) ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}'
        : '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  }

  Future<void> _fullscreen() async {
    if (_full) return;
    _full = true;
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    if (mounted) {
      await showDialog<void>(
        context: context,
        useRootNavigator: true,
        barrierDismissible: false,
        builder: (c) => Scaffold(
          backgroundColor: Colors.black,
          body: SafeArea(
            child: Stack(
              children: [
                Center(child: _stage(full: true)),
                Positioned(
                  top: 0,
                  right: 0,
                  child: IconButton(
                    tooltip: 'Salir de pantalla completa',
                    onPressed: () => Navigator.pop(c),
                    icon: const Icon(
                      Icons.fullscreen_exit,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }
    _full = false;
    await SystemChrome.setPreferredOrientations([]);
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }

  Widget _stage({bool full = false}) {
    final video = _video;
    if (video == null) {
      return AspectRatio(
        aspectRatio: 16 / 9,
        child: ColoredBox(
          color: Colors.black,
          child: Center(
            child: _loading
                ? const CircularProgressIndicator()
                : const Icon(
                    Icons.ondemand_video,
                    size: 56,
                    color: Colors.white54,
                  ),
          ),
        ),
      );
    }
    return ValueListenableBuilder<VideoPlayerValue>(
      valueListenable: video,
      builder: (context, value, _) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            fit: FlexFit.loose,
            child: AspectRatio(
              aspectRatio: value.aspectRatio > 0 ? value.aspectRatio : 16 / 9,
              child: VideoPlayer(video),
            ),
          ),
          if (value.isBuffering) const LinearProgressIndicator(minHeight: 2),
          ColoredBox(
            color: Colors.black,
            child: Column(
              children: [
                VideoProgressIndicator(
                  video,
                  allowScrubbing: true,
                  colors: VideoProgressColors(
                    playedColor: Theme.of(context).colorScheme.primary,
                  ),
                ),
                Row(
                  children: [
                    IconButton(
                      tooltip: 'Retroceder 10 segundos',
                      onPressed: () => _seek(-10),
                      icon: const Icon(Icons.replay_10, color: Colors.white),
                    ),
                    IconButton(
                      tooltip: value.isPlaying ? 'Pausar' : 'Reproducir',
                      onPressed: () =>
                          value.isPlaying ? video.pause() : video.play(),
                      icon: Icon(
                        value.isPlaying ? Icons.pause : Icons.play_arrow,
                        color: Colors.white,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Avanzar 10 segundos',
                      onPressed: () => _seek(10),
                      icon: const Icon(Icons.forward_10, color: Colors.white),
                    ),
                    Expanded(
                      child: Text(
                        '${_clock(value.position)} / ${_clock(value.duration)}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    if (!full)
                      IconButton(
                        tooltip: 'Pantalla completa',
                        onPressed: _fullscreen,
                        icon: const Icon(Icons.fullscreen, color: Colors.white),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: true,
    onPopInvokedWithResult: (didPop, _) {
      if (didPop) unawaited(_save());
    },
    child: Scaffold(
      appBar: AppBar(
        title: Text('Episodio ${_episode.number}'),
        actions: [
          IconButton(
            tooltip: 'Abrir respaldo web',
            onPressed: () {
              _video?.pause();
              widget.openWeb(_episode);
            },
            icon: const Icon(Icons.open_in_browser),
          ),
        ],
      ),
      body: ListView(
        children: [
          SizedBox(
            height: MediaQuery.sizeOf(context).width * 9 / 16 + 65,
            child: _stage(),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  anime.title,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                if (_error != null)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _error!,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            children: [
                              FilledButton(
                                onPressed: _openEpisode,
                                child: const Text('Reintentar'),
                              ),
                              OutlinedButton(
                                onPressed: () => widget.openWeb(_episode),
                                child: const Text('Abrir en la web'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                if (_servers.isNotEmpty)
                  DropdownButtonFormField<AnimeServer>(
                    initialValue: _selected,
                    decoration: const InputDecoration(
                      labelText: 'Idioma y servidor',
                    ),
                    isExpanded: true,
                    items: _servers
                        .map(
                          (s) => DropdownMenuItem(
                            value: s,
                            child: Text(
                              '${s.label}${s.supported ? '' : ' · Web'}',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (s) {
                      if (s != null) unawaited(_playServer(s));
                    },
                  ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _adjacent(-1) == null
                            ? null
                            : () => _change(_adjacent(-1)!),
                        icon: const Icon(Icons.skip_previous),
                        label: const Text('Anterior'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _adjacent(1) == null
                            ? null
                            : () => _change(_adjacent(1)!),
                        icon: const Icon(Icons.skip_next),
                        label: const Text('Siguiente'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () async {
                        final value =
                            app.positions[_episode.key]?['watched'] != true;
                        _marked = true;
                        await app.mark(anime, _episode, value);
                        if (mounted) setState(() {});
                      },
                      icon: Icon(
                        app.positions[_episode.key]?['watched'] == true
                            ? Icons.check_circle
                            : Icons.check_circle_outline,
                      ),
                      label: const Text('Visto'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () async {
                        try {
                          await app.enqueue(
                            anime,
                            _episode,
                            _selected?.language ??
                                '${app.settings['language'] ?? 'SUB'}',
                          );
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Episodio añadido a Descargas.'),
                              ),
                            );
                          }
                        } catch (e) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(e.toString())),
                            );
                          }
                        }
                      },
                      icon: const Icon(Icons.download_outlined),
                      label: const Text('Descargar'),
                    ),
                    PopupMenuButton<double>(
                      tooltip: 'Velocidad',
                      onSelected: (speed) {
                        _video?.setPlaybackSpeed(speed);
                        app.saveSetting('speed', speed);
                      },
                      itemBuilder: (_) => [.5, .75, 1.0, 1.25, 1.5, 2.0]
                          .map(
                            (speed) => PopupMenuItem(
                              value: speed,
                              child: Text('${speed}x'),
                            ),
                          )
                          .toList(),
                      child: const Padding(
                        padding: EdgeInsets.all(14),
                        child: Text('Velocidad'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  '${_episode.slug} · ${_selected?.language ?? app.settings['language'] ?? 'SUB'}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
  @override
  void dispose() {
    _closed = true;
    _generation++;
    _persist?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    app.activity.removeListener(_activity);
    unawaited(_save());
    final video = _video;
    _video = null;
    if (video != null) {
      video.removeListener(_tick);
      unawaited(video.dispose());
    }
    super.dispose();
  }
}
