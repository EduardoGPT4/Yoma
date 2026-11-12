import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import '../../../services/picture_in_picture.dart';
import '../data/anime_controller.dart';
import '../data/local_anime_downloads.dart';
import '../data/next_episode_countdown.dart';
import '../models/anime_models.dart';
import '../widgets/anime_video_stage.dart';

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
      _full = false,
      _pictureInPictureSupported = false;
  int _generation = 0;
  Timer? _persist;

  /// Cuenta atrás hacia el siguiente episodio al terminar este.
  final _next = NextEpisodeCountdown();
  bool _endHandled = false;

  /// Cambia cuando cambia el video: la pantalla completa se reconstruye.
  final _stageVersion = ValueNotifier<int>(0);
  AnimeController get app => widget.controller;
  AnimeTitle get anime => widget.detail.anime;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    app.activity.addListener(_activity);
    PictureInPicture.active.addListener(_pictureInPictureChanged);
    unawaited(
      PictureInPicture.supported().then((value) {
        if (mounted && value) setState(() => _pictureInPictureSupported = true);
      }),
    );
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

  void _pictureInPictureChanged() {
    if (mounted) setState(() {});
  }

  /// Sigue viéndose en una ventana pequeña, como en el reproductor anterior.
  Future<void> _pictureInPicture() async {
    final size = _video?.value.size ?? Size.zero;
    final ok = await PictureInPicture.enter(
      width: size.width > 0 ? size.width.round() : 16,
      height: size.height > 0 ? size.height.round() : 9,
    );
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Este teléfono no permite ver en imagen en imagen.'),
        ),
      );
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (PictureInPicture.shouldPause(state)) {
      _video?.pause();
      unawaited(_save());
    }
  }

  Future<void> _release() async {
    final old = _video;
    _video = null;
    _stageVersion.value++;
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
    _next.cancel();
    _endHandled = false;
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
          _error = animeErrorText(e);
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
          _error = animeErrorText(e);
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
      _stageVersion.value++;
      video.addListener(_tick);
      final progress = app.positions[_episode.key];
      final position = animeInt(progress?['positionMs']);
      // Guardado en los últimos segundos: se vuelve a ver desde el principio
      // en lugar de terminar (y saltar al siguiente) nada más abrirlo.
      if (position > 0 &&
          position < video.value.duration.inMilliseconds - 3000) {
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
    // Se volvió a reproducir (por ejemplo, retrocediendo): no se pasa al
    // siguiente.
    if (value.isPlaying && _next.running) _next.cancel();
    final ended = NextEpisodeCountdown.ended(
      playing: value.isPlaying,
      positionMs: value.position.inMilliseconds,
      durationMs: value.duration.inMilliseconds,
    );
    if (!ended) {
      _endHandled = false;
    } else if (!_endHandled) {
      _endHandled = true;
      final next = _adjacent(1);
      if (next != null && app.settings['autonext'] != false) {
        _next.start(() => unawaited(_change(next)));
      }
    }
  }

  /// Aviso «Siguiente episodio en N s» con «Cancelar» y «Ver ahora».
  Widget _nextBanner() => ValueListenableBuilder<int?>(
    valueListenable: _next,
    builder: (context, left, _) {
      final next = _adjacent(1);
      if (left == null || next == null) return const SizedBox.shrink();
      return ColoredBox(
        color: Colors.black,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 8, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Episodio ${next.number} en $left s',
                  style: const TextStyle(color: Colors.white),
                ),
              ),
              TextButton(
                onPressed: _next.cancel,
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () {
                  _next.cancel();
                  unawaited(_change(next));
                },
                child: const Text('Ver ahora'),
              ),
            ],
          ),
        ),
      );
    },
  );

  Future<void> _writes = Future.value();
  String? _savedKey;
  int _savedPosition = -1;
  Future<void> _save({bool? watched}) {
    final video = _video;
    if (video == null || !video.value.isInitialized || !_played) {
      return _writes;
    }
    final episode = _episode;
    final position = video.value.position.inMilliseconds;
    final duration = video.value.duration.inMilliseconds;
    // En pausa la posición no cambia: no se reescribe cada 5 segundos ni se
    // mueve el episodio al principio del historial sin haberlo visto más.
    if (watched == null &&
        _savedKey == episode.key &&
        _savedPosition == position) {
      return _writes;
    }
    _savedKey = episode.key;
    _savedPosition = position;
    // Snapshot before awaiting: a server/episode change must not misattribute progress.
    final write = _writes.then(
      (_) => app.progress(anime, episode, position, duration, watched: watched),
    );
    _writes = write.catchError((Object error) {
      // Lo que no se guardó se vuelve a intentar en el siguiente guardado.
      _savedPosition = -1;
      if (mounted && !_closed) {
        setState(() => _error = 'No se pudo guardar el progreso: $error');
      }
    });
    return _writes;
  }

  Future<void> _change(AnimeEpisode episode) async {
    _next.cancel();
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

  /// Pantalla completa: una ruta opaca propia que ocupa toda la pantalla.
  /// Antes era un diálogo, y Flutter mete los diálogos en el área segura: en
  /// horizontal quedaba libre el hueco de la cámara y se veía la página de
  /// detrás.
  Future<void> _fullscreen() async {
    if (_full) return;
    _full = true;
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    if (mounted) {
      await Navigator.of(context, rootNavigator: true).push(
        PageRouteBuilder<void>(
          opaque: true,
          transitionDuration: Duration.zero,
          reverseTransitionDuration: Duration.zero,
          pageBuilder: (c, _, _) => Scaffold(
            backgroundColor: Colors.black,
            body: ValueListenableBuilder<int>(
              valueListenable: _stageVersion,
              builder: (_, _, _) =>
                  _stage(full: true, exit: () => Navigator.pop(c)),
            ),
          ),
        ),
      );
    }
    _full = false;
    await SystemChrome.setPreferredOrientations([]);
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }

  Widget _stage({bool full = false, VoidCallback? exit}) => AnimeVideoStage(
    // Un escenario por video: al cambiar de episodio empieza de cero.
    key: ValueKey(_video),
    video: _video,
    loading: _loading,
    full: full,
    onToggleFullscreen: full ? (exit ?? () {}) : _fullscreen,
    overlay: full ? _nextBanner() : null,
    onPictureInPicture: _pictureInPictureSupported && _video != null
        ? () => unawaited(_pictureInPicture())
        : null,
  );

  @override
  Widget build(BuildContext context) => PictureInPicture.active.value
      // En la ventana pequeña solo el video, sin barra ni listado.
      ? Scaffold(backgroundColor: Colors.black, body: _stage())
      : PopScope(
          canPop: true,
          onPopInvokedWithResult: (didPop, _) {
            if (didPop) unawaited(_save());
          },
          child: Scaffold(
            appBar: AppBar(
              title: Text('Episodio ${_episode.number}'),
              actions: [
                IconButton(
                  tooltip: 'Ver en la web',
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
                // Los controles van encima del video: la caja es solo el video.
                SizedBox(
                  height: MediaQuery.sizeOf(context).width * 9 / 16,
                  child: _stage(),
                ),
                _nextBanner(),
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
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurface,
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
                                      child: const Text('Ver en la web'),
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
                                  app.positions[_episode.key]?['watched'] !=
                                  true;
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
                                final outcome = await app.enqueue(
                                  anime,
                                  _episode,
                                  _selected?.language ??
                                      '${app.settings['language'] ?? 'SUB'}',
                                );
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        AnimeController.downloadNotice([
                                          outcome,
                                        ], paused: app.paused),
                                      ),
                                    ),
                                  );
                                }
                              } catch (e) {
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text(animeErrorText(e))),
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
                        animeLanguageLabel(
                          '${_selected?.language ?? app.settings['language'] ?? 'SUB'}',
                        ),
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
    _next.dispose();
    _stageVersion.dispose();
    WidgetsBinding.instance.removeObserver(this);
    app.activity.removeListener(_activity);
    PictureInPicture.active.removeListener(_pictureInPictureChanged);
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
