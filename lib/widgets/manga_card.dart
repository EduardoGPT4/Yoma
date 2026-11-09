import 'dart:async';

import 'package:flutter/material.dart';

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

  static double heightForWidth(BuildContext context, double width) {
    final title = TextPainter(
      text: TextSpan(
        text: 'Ag\nAg',
        style: DefaultTextStyle.of(context).style.merge(titleStyle(context)),
      ),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 2,
    )..layout();
    final height = width / coverAspectRatio + title.height.ceilToDouble() + 12;
    title.dispose();
    return height;
  }
}

/// Reserva dos líneas de título también en pantallas estrechas y con texto grande.
class SliverMangaGrid extends StatelessWidget {
  final SliverChildDelegate delegate;

  const SliverMangaGrid({super.key, required this.delegate});

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
            mainAxisExtent: MangaCardLayout.heightForWidth(context, width),
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
          borderRadius: BorderRadius.circular(14),
          child: Ink(
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: theme.colorScheme.onSurface.withAlpha(18),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AspectRatio(
                  aspectRatio: MangaCardLayout.coverAspectRatio,
                  child: ClipRRect(
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(9),
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
                            child: LinearProgressIndicator(
                              value: progress,
                              minHeight: 3,
                              backgroundColor: Colors.black.withAlpha(90),
                              color: theme.colorScheme.primary,
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
                                  color: Colors.black.withAlpha(160),
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
                                        ? const Color(0xFFFF6B8A)
                                        : Colors.white,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        if (widget.onLongPress != null)
                          Positioned(
                            top: 0,
                            right: 0,
                            child: PopupMenuButton<String>(
                              tooltip: 'Opciones de $_displayTitle',
                              icon: DecoratedBox(
                                decoration: BoxDecoration(
                                  color: Colors.black.withAlpha(160),
                                  shape: BoxShape.circle,
                                ),
                                child: const Padding(
                                  padding: EdgeInsets.all(4),
                                  child: Icon(
                                    Icons.more_horiz,
                                    size: 20,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                              onSelected: (_) => widget.onLongPress?.call(),
                              itemBuilder: (_) => const [
                                PopupMenuItem(
                                  value: 'categories',
                                  child: ListTile(
                                    leading: Icon(Icons.label_outline),
                                    title: Text('Categorías'),
                                    contentPadding: EdgeInsets.zero,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        if (widget.badge != null && widget.badge!.isNotEmpty)
                          Positioned(
                            bottom: 6,
                            right: 4,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 5,
                                vertical: 1,
                              ),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.primary.withAlpha(230),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              constraints: BoxConstraints(
                                maxWidth:
                                    MediaQuery.sizeOf(context).width / 3 - 18,
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (widget.badgeIcon != null) ...[
                                    Icon(
                                      widget.badgeIcon,
                                      size: 12,
                                      color: theme.colorScheme.onPrimary,
                                    ),
                                    const SizedBox(width: 3),
                                  ],
                                  Flexible(
                                    child: Text(
                                      widget.badge!,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: theme.colorScheme.onPrimary,
                                        fontWeight: FontWeight.w600,
                                        fontSize: 10,
                                        height: 1.2,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(6, 4, 6, 6),
                  child: Text(
                    _displayTitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: MangaCardLayout.titleStyle(context),
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

  Widget _placeholder(ThemeData theme) {
    return Container(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Center(
        child: Icon(
          Icons.auto_stories_outlined,
          size: 28,
          color: theme.colorScheme.onSurface.withAlpha(80),
        ),
      ),
    );
  }
}
