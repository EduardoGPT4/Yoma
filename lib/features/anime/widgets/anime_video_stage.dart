import 'dart:async';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import '../../../services/picture_in_picture.dart';

/// Video con los controles superpuestos.
///
/// Los controles se ocultan solos a los pocos segundos mientras se
/// reproduce, y aparecen al tocar el video; en pausa se quedan visibles.
/// Ocupa todo el espacio que se le da: el video se centra sin deformarse.
class AnimeVideoStage extends StatefulWidget {
  final VideoPlayerController? video;
  final bool loading, full;
  final VoidCallback onToggleFullscreen;

  /// Mueve el video a una posición (sustituible en pruebas).
  final Future<void> Function(Duration position)? seek;

  /// Algo que se muestra siempre encima de los controles (por ejemplo, la
  /// cuenta atrás al siguiente episodio).
  final Widget? overlay;
  final Duration hideAfter;

  /// Abre la imagen en imagen; sin él no se muestra el botón.
  final VoidCallback? onPictureInPicture;

  const AnimeVideoStage({
    super.key,
    required this.video,
    required this.onToggleFullscreen,
    this.loading = false,
    this.full = false,
    this.seek,
    this.overlay,
    this.hideAfter = const Duration(seconds: 3),
    this.onPictureInPicture,
  });

  /// Duración del opening que salta «Saltar opening».
  static const opening = Duration(seconds: 85);

  /// Pasado este punto del episodio ya no se ofrece saltar el opening.
  static const openingWindow = Duration(minutes: 3);

  /// Se ofrece saltar el opening: al principio del episodio y si después
  /// queda video.
  static bool canSkipOpening(VideoPlayerValue value) =>
      value.isInitialized &&
      value.position < openingWindow &&
      value.duration - value.position > opening;

  static String clock(Duration value) {
    final s = value.inSeconds;
    return s >= 3600
        ? '${s ~/ 3600}:${((s % 3600) ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}'
        : '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  }

  @override
  State<AnimeVideoStage> createState() => _AnimeVideoStageState();
}

class _AnimeVideoStageState extends State<AnimeVideoStage> {
  bool _visible = true;
  bool _playing = false;
  Timer? _hide;

  VideoPlayerController? get _video => widget.video;

  @override
  void initState() {
    super.initState();
    _video?.addListener(_changed);
    PictureInPicture.active.addListener(_pictureInPicture);
    _changed();
  }

  void _pictureInPicture() {
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(AnimeVideoStage old) {
    super.didUpdateWidget(old);
    if (old.video != widget.video) {
      old.video?.removeListener(_changed);
      widget.video?.addListener(_changed);
      _playing = false;
      _show();
    }
  }

  @override
  void dispose() {
    _hide?.cancel();
    _video?.removeListener(_changed);
    PictureInPicture.active.removeListener(_pictureInPicture);
    super.dispose();
  }

  /// Solo actúa cuando empieza o termina la reproducción, no en cada
  /// fotograma.
  void _changed() {
    final playing = _video?.value.isPlaying ?? false;
    if (playing == _playing) return;
    _playing = playing;
    if (playing) {
      _schedule();
    } else {
      _show(keep: true);
    }
  }

  void _schedule() {
    _hide?.cancel();
    _hide = Timer(widget.hideAfter, () {
      _hide = null;
      if (mounted && _playing && _visible) setState(() => _visible = false);
    });
  }

  /// Muestra los controles; mientras se reproduce vuelven a ocultarse.
  void _show({bool keep = false}) {
    if (!_visible && mounted) setState(() => _visible = true);
    if (keep || !_playing) {
      _hide?.cancel();
      _hide = null;
    } else {
      _schedule();
    }
  }

  void _toggle() {
    if (_visible && _playing) {
      _hide?.cancel();
      _hide = null;
      setState(() => _visible = false);
    } else {
      _show();
    }
  }

  Future<void> _seekTo(Duration position) {
    final video = _video!;
    final end = video.value.duration;
    final target = position < Duration.zero
        ? Duration.zero
        : position > end
        ? end
        : position;
    return (widget.seek ?? video.seekTo)(target);
  }

  @override
  Widget build(BuildContext context) {
    final video = _video;
    return ColoredBox(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Center(
            child: video == null
                ? (widget.loading
                      ? const CircularProgressIndicator()
                      : const Icon(
                          Icons.ondemand_video,
                          size: 56,
                          color: Colors.white54,
                        ))
                : ValueListenableBuilder<VideoPlayerValue>(
                    valueListenable: video,
                    builder: (context, value, _) => AspectRatio(
                      aspectRatio: value.aspectRatio > 0
                          ? value.aspectRatio
                          : 16 / 9,
                      child: VideoPlayer(video),
                    ),
                  ),
          ),
          if (video != null)
            ValueListenableBuilder<VideoPlayerValue>(
              valueListenable: video,
              builder: (context, value, _) => value.isBuffering
                  ? const Center(child: CircularProgressIndicator())
                  : const SizedBox.shrink(),
            ),
          // En la ventana pequeña solo se ve el video.
          if (!PictureInPicture.active.value) ...[
            // Tocar el video muestra u oculta los controles.
            Positioned.fill(
              child: GestureDetector(
                key: const ValueKey('anime-video-surface'),
                behavior: HitTestBehavior.opaque,
                onTap: video == null ? null : _toggle,
              ),
            ),
            if (video != null)
              Positioned.fill(
                child: IgnorePointer(
                  ignoring: !_visible,
                  child: AnimatedOpacity(
                    opacity: _visible ? 1 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: _controls(video),
                  ),
                ),
              ),
          ],
          if (widget.overlay != null)
            Positioned(
              left: 0,
              right: 0,
              bottom: _visible && video != null ? 96 : 0,
              child: SafeArea(top: false, child: widget.overlay!),
            ),
        ],
      ),
    );
  }

  Widget _controls(VideoPlayerController video) {
    final primary = Theme.of(context).colorScheme.primary;
    return ValueListenableBuilder<VideoPlayerValue>(
      valueListenable: video,
      builder: (context, value, _) => Column(
        children: [
          const Spacer(),
          // Botón grande central: siempre a mano en pausa.
          Listener(
            onPointerDown: (_) => _show(),
            child: IconButton(
              iconSize: 56,
              tooltip: value.isPlaying ? 'Pausar' : 'Reproducir',
              onPressed: () => value.isPlaying ? video.pause() : video.play(),
              icon: Icon(
                value.isPlaying
                    ? Icons.pause_circle_filled
                    : Icons.play_circle_filled,
                color: Colors.white,
              ),
            ),
          ),
          const Spacer(),
          Listener(
            onPointerDown: (_) => _show(),
            child: DecoratedBox(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [Color(0xCC000000), Color(0x00000000)],
                ),
              ),
              child: SafeArea(
                top: false,
                bottom: widget.full,
                left: widget.full,
                right: widget.full,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: VideoProgressIndicator(
                        video,
                        allowScrubbing: true,
                        padding: const EdgeInsets.only(top: 12, bottom: 4),
                        colors: VideoProgressColors(playedColor: primary),
                      ),
                    ),
                    Row(
                      children: [
                        IconButton(
                          tooltip: 'Retroceder 10 segundos',
                          onPressed: () => _seekTo(
                            value.position - const Duration(seconds: 10),
                          ),
                          icon: const Icon(
                            Icons.replay_10,
                            color: Colors.white,
                          ),
                        ),
                        IconButton(
                          tooltip: 'Avanzar 10 segundos',
                          onPressed: () => _seekTo(
                            value.position + const Duration(seconds: 10),
                          ),
                          icon: const Icon(
                            Icons.forward_10,
                            color: Colors.white,
                          ),
                        ),
                        if (AnimeVideoStage.canSkipOpening(value))
                          TextButton.icon(
                            style: TextButton.styleFrom(
                              foregroundColor: Colors.white,
                              visualDensity: VisualDensity.compact,
                            ),
                            onPressed: () => _seekTo(
                              value.position + AnimeVideoStage.opening,
                            ),
                            icon: const Icon(Icons.fast_forward, size: 18),
                            label: const Text('Saltar opening'),
                          ),
                        Expanded(
                          child: Text(
                            '${AnimeVideoStage.clock(value.position)} / '
                            '${AnimeVideoStage.clock(value.duration)}',
                            textAlign: TextAlign.end,
                            maxLines: 1,
                            overflow: TextOverflow.fade,
                            softWrap: false,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                            ),
                          ),
                        ),
                        if (widget.onPictureInPicture != null)
                          IconButton(
                            tooltip: 'Imagen en imagen',
                            onPressed: widget.onPictureInPicture,
                            icon: const Icon(
                              Icons.picture_in_picture_alt,
                              color: Colors.white,
                            ),
                          ),
                        IconButton(
                          tooltip: widget.full
                              ? 'Salir de pantalla completa'
                              : 'Pantalla completa',
                          onPressed: widget.onToggleFullscreen,
                          icon: Icon(
                            widget.full
                                ? Icons.fullscreen_exit
                                : Icons.fullscreen,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
