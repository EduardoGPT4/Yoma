import 'dart:async';

import 'package:flutter/material.dart';

import '../design/yoma_components.dart';
import '../design/yoma_tokens.dart';
import '../utils/title_sanitizer.dart';
import 'app_metrics.dart';
import 'cached_thumbnail.dart';

class MangaCardLayout {
  static const int gridCrossAxisCount = 3;
  static const double gridSpacing = 8;
  static const double coverAspectRatio = 2 / 3;
  static const double gridAspectRatio = 0.58;

  static TextStyle titleStyle(BuildContext context) => TextStyle(
    fontWeight: FontWeight.w700,
    height: 1.15,
    fontSize: AppMetrics.of(context).titleSize,
    letterSpacing: -0.1,
  );

  static TextStyle sourceStyle(BuildContext context) => TextStyle(
    fontWeight: FontWeight.w800,
    height: 1.2,
    fontSize: AppMetrics.of(context).titleSize - 1,
  );

  static double heightForWidth(
    BuildContext context,
    double width, {
    bool sourceLine = false,
  }) {
    final base = DefaultTextStyle.of(context).style;
    final title = TextPainter(
      text: TextSpan(
        text: 'Ag\nAg',
        style: base.merge(titleStyle(context)),
        children: [
          if (sourceLine)
            TextSpan(text: '\nAg', style: base.merge(sourceStyle(context))),
        ],
      ),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: sourceLine ? 3 : 2,
    )..layout();
    final height = width / coverAspectRatio + title.height.ceilToDouble() + 12;
    title.dispose();
    return height;
  }
}

/// Reserva dos líneas de título también en pantallas estrechas y con texto grande.
class SliverMangaGrid extends StatelessWidget {
  final SliverChildDelegate delegate;

  /// Reserva una línea más para el nombre de la fuente de los descargados.
  final bool sourceLine;

  const SliverMangaGrid({
    super.key,
    required this.delegate,
    this.sourceLine = false,
  });

  @override
  Widget build(BuildContext context) {
    final metrics = AppMetrics.of(context);
    return SliverLayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.crossAxisExtent < 330
            ? 2
            : metrics.gridColumns;
        final width =
            (constraints.crossAxisExtent -
                metrics.gridSpacing * (columns - 1)) /
            columns;
        return SliverGrid(
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisSpacing: metrics.gridSpacing,
            crossAxisSpacing: metrics.gridSpacing,
            mainAxisExtent: MangaCardLayout.heightForWidth(
              context,
              width,
              sourceLine: sourceLine,
            ),
          ),
          delegate: delegate,
        );
      },
    );
  }
}

class MangaCard extends StatefulWidget {
  final String title;
  final String? coverPath;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final Duration longPressDuration;
  final String? badge;
  final IconData? badgeIcon;
  final bool isFavorite;
  final VoidCallback? onFavoriteToggle;

  /// Progreso 0–1 dibujado como barra fina al pie de la portada.
  final double? progress;

  /// Fuente de un manga descargado: su nombre va bajo el título y su color
  /// pinta el borde de la tarjeta.
  final String? sourceLabel;
  final Color? sourceColor;

  const MangaCard({
    super.key,
    required this.title,
    required this.coverPath,
    required this.onTap,
    this.onLongPress,
    this.longPressDuration = const Duration(milliseconds: 800),
    this.badge,
    this.badgeIcon,
    this.isFavorite = false,
    this.onFavoriteToggle,
    this.progress,
    this.sourceLabel,
    this.sourceColor,
  });

  @override
  State<MangaCard> createState() => _MangaCardState();
}

class _MangaCardState extends State<MangaCard> {
  Timer? _longPressTimer;
  bool _ignoreNextTap = false;

  String get _displayTitle => TitleSanitizer.clean(widget.title);

  @override
  void dispose() {
    _cancelLongPressTimer();
    super.dispose();
  }

  void _startLongPressTimer() {
    if (widget.onLongPress == null) {
      return;
    }
    _longPressTimer?.cancel();
    _ignoreNextTap = false;
    _longPressTimer = Timer(widget.longPressDuration, _triggerLongPress);
  }

  void _cancelLongPressTimer() {
    _longPressTimer?.cancel();
    _longPressTimer = null;
  }

  void _triggerLongPress() {
    _longPressTimer = null;
    if (!mounted) {
      return;
    }
    _ignoreNextTap = true;
    widget.onLongPress?.call();
  }

  void _handleTap() {
    if (_ignoreNextTap) {
      _ignoreNextTap = false;
      return;
    }
    widget.onTap();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final progress = widget.progress?.clamp(0.0, 1.0);

    return GestureDetector(
      onTapDown: (_) => _startLongPressTimer(),
      onTapCancel: _cancelLongPressTimer,
      onTapUp: (_) => _cancelLongPressTimer(),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _handleTap,
          borderRadius: YomaRadii.mdAll,
          child: Ink(
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: YomaRadii.mdAll,
              border: widget.sourceColor == null
                  ? Border.all(color: YomaColors.borderSubtle)
                  : Border.all(color: widget.sourceColor!, width: 2),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AspectRatio(
                  aspectRatio: MangaCardLayout.coverAspectRatio,
                  child: ClipRRect(
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(YomaRadii.md - 1),
                    ),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        _buildCover(theme),
                        if (progress != null && progress > 0)
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: 0,
                            child: YomaProgressBar(
                              value: progress,
                              overImage: true,
                            ),
                          ),
                        if (widget.onFavoriteToggle != null)
                          Positioned(
                            top: 0,
                            left: 0,
                            child: IconButton(
                              tooltip: widget.isFavorite
                                  ? 'Quitar de favoritos'
                                  : 'Añadir a favoritos',
                              onPressed: widget.onFavoriteToggle,
                              constraints: const BoxConstraints(
                                minWidth: 48,
                                minHeight: 48,
                              ),
                              visualDensity: VisualDensity.standard,
                              icon: DecoratedBox(
                                decoration: BoxDecoration(
                                  color: YomaColors.scrim.withAlpha(160),
                                  shape: BoxShape.circle,
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.all(5),
                                  child: Icon(
                                    widget.isFavorite
                                        ? Icons.favorite_rounded
                                        : Icons.favorite_border_rounded,
                                    size: 18,
                                    color: widget.isFavorite
                                        ? YomaColors.favorite
                                        : YomaColors.textPrimary,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        if (widget.badge != null && widget.badge!.isNotEmpty)
                          Positioned(
                            bottom: 6,
                            right: 4,
                            child: ConstrainedBox(
                              constraints: BoxConstraints(
                                maxWidth:
                                    MediaQuery.sizeOf(context).width / 3 - 18,
                              ),
                              child: YomaCoverTag(
                                label: widget.badge!,
                                icon: widget.badgeIcon,
                                emphasis: true,
                                maxLines: 2,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(6, 4, 6, 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _displayTitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: MangaCardLayout.titleStyle(context),
                      ),
                      if (widget.sourceLabel != null)
                        Text(
                          widget.sourceLabel!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: MangaCardLayout.sourceStyle(
                            context,
                          ).copyWith(color: widget.sourceColor),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCover(ThemeData theme) {
    return CachedThumbnail(
      sourcePath: widget.coverPath,
      size: 480,
      fit: BoxFit.cover,
      placeholderBuilder: (_) => _placeholder(theme),
    );
  }

  Widget _placeholder(ThemeData theme) =>
      const YomaImageFallback(icon: Icons.auto_stories_outlined);
}
