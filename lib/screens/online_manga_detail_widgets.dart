part of 'online_manga_detail_screen.dart';

// Piezas de la ficha online: carga, error, portada, acciones y capítulos.

class _DetailLoadingView extends StatelessWidget {
  const _DetailLoadingView();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return CustomScrollView(
      slivers: [
        SliverAppBar(
          expandedHeight: 280,
          pinned: true,
          leading: const BackButton(),
          flexibleSpace: FlexibleSpaceBar(
            background: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    theme.colorScheme.surfaceContainerHighest,
                    theme.colorScheme.surface,
                  ],
                ),
              ),
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.all(16),
          sliver: SliverList(
            delegate: SliverChildListDelegate([
              _SkeletonBlock(height: 52, radius: 18),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(child: _SkeletonBlock(height: 34, radius: 999)),
                  const SizedBox(width: 8),
                  Expanded(child: _SkeletonBlock(height: 34, radius: 999)),
                  const SizedBox(width: 8),
                  Expanded(child: _SkeletonBlock(height: 34, radius: 999)),
                ],
              ),
              const SizedBox(height: 18),
              _SkeletonBlock(height: 120, radius: 22),
              const SizedBox(height: 24),
              _SkeletonBlock(height: 22, width: 140, radius: 10),
              const SizedBox(height: 12),
              _SkeletonBlock(height: 64, radius: 18),
              const SizedBox(height: 8),
              _SkeletonBlock(height: 64, radius: 18),
            ]),
          ),
        ),
      ],
    );
  }
}

class _SkeletonBlock extends StatelessWidget {
  final double height;
  final double? width;
  final double radius;

  const _SkeletonBlock({required this.height, this.width, this.radius = 16});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width ?? double.infinity,
      height: height,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.onSurface.withAlpha(18),
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

class _DetailErrorView extends StatelessWidget {
  final VoidCallback onRetry;
  final String? message;

  const _DetailErrorView({required this.onRetry, this.message});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: theme.colorScheme.errorContainer.withAlpha(80),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.cloud_off_outlined,
                size: 34,
                color: theme.colorScheme.error,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              'No se pudo cargar el manga',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              message ?? 'Revisa tu conexion e intenta de nuevo.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface.withAlpha(160),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Reintentar'),
            ),
          ],
        ),
      ),
    );
  }
}

class _CoverCard extends StatelessWidget {
  final String? coverUrl;

  const _CoverCard({required this.coverUrl});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      width: 108,
      height: 154,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(YomaRadii.md),
        border: Border.all(color: Colors.white.withAlpha(40)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(120),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(YomaRadii.md - 1),
        child: CachedThumbnail(
          sourcePath: coverUrl,
          size: 480,
          placeholderBuilder: (_) => Container(
            color: theme.colorScheme.surfaceContainerHighest,
            child: const Icon(Icons.image_not_supported_outlined),
          ),
        ),
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  final VoidCallback? onRead;
  final VoidCallback onDownload;
  final String readLabel;
  final IconData readIcon;
  final String downloadLabel;

  const _ActionRow({
    required this.onRead,
    required this.onDownload,
    required this.readLabel,
    required this.readIcon,
    this.downloadLabel = 'Descargar',
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      children: [
        Expanded(
          flex: 3,
          child: FilledButton.icon(
            onPressed: onRead,
            icon: Icon(readIcon),
            label: Text(readLabel),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(YomaRadii.md),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          flex: 2,
          child: OutlinedButton.icon(
            onPressed: onDownload,
            icon: const Icon(Icons.download_rounded, size: 20),
            label: Text(downloadLabel),
            style: OutlinedButton.styleFrom(
              foregroundColor: theme.colorScheme.primary,
              side: BorderSide(color: theme.colorScheme.outline),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(YomaRadii.md),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _InfoStrip extends StatelessWidget {
  final List<_InfoItem> items;

  const _InfoStrip({required this.items});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(YomaRadii.lg),
        border: Border.all(color: theme.colorScheme.onSurface.withAlpha(18)),
      ),
      child: Wrap(
        spacing: 14,
        runSpacing: 8,
        children: items.map((item) => item).toList(),
      ),
    );
  }
}

class _InfoItem extends StatelessWidget {
  final IconData icon;
  final String label;

  const _InfoItem({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: theme.colorScheme.primary),
        const SizedBox(width: 6),
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _MetaPill extends StatelessWidget {
  final String label;
  final IconData? icon;

  const _MetaPill({required this.label, this.icon});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.black.withAlpha(110),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withAlpha(24)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: theme.colorScheme.primary),
            const SizedBox(width: 6),
          ],
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? trailing;

  const _SectionHeader({
    required this.icon,
    required this.title,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      children: [
        Icon(icon, size: 20, color: theme.colorScheme.primary),
        const SizedBox(width: 8),
        Text(
          title,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w800,
            letterSpacing: -0.2,
          ),
        ),
        if (trailing != null) ...[
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withAlpha(30),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              trailing!,
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _ChapterTile extends StatelessWidget {
  final int index;
  final String title;
  final bool isCurrent;
  final bool isRead;

  /// Leído porque MyAnimeList ya lo tenía.
  final bool readFromMal;
  final bool? selected;
  final String? pageLabel;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onToggleRead;

  const _ChapterTile({
    required this.index,
    required this.title,
    required this.isCurrent,
    required this.pageLabel,
    required this.onTap,
    this.isRead = false,
    this.readFromMal = false,
    this.selected,
    this.onLongPress,
    this.onToggleRead,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final meta = [
      if (isRead) readFromMal ? 'Leído en MAL' : 'Leído',
      ?pageLabel,
    ].join(' · ');

    return Material(
      color: isCurrent
          ? theme.colorScheme.primary.withAlpha(18)
          : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 52),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            child: Row(
              children: [
                if (selected != null) ...[
                  Icon(
                    selected!
                        ? Icons.check_box_rounded
                        : Icons.check_box_outline_blank_rounded,
                    size: 20,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      color: isRead
                          ? theme.colorScheme.onSurface.withAlpha(140)
                          : null,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    meta.isEmpty ? '${index + 1}' : meta,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: isCurrent
                          ? theme.colorScheme.primary
                          : theme.colorScheme.onSurface.withAlpha(150),
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                ),
                if (selected == null && onToggleRead != null)
                  PopupMenuButton<String>(
                    tooltip: 'Opciones del capítulo',
                    onSelected: (_) => onToggleRead!(),
                    itemBuilder: (_) => [
                      PopupMenuItem(
                        value: 'read',
                        child: Text(
                          isRead ? 'Marcar como no leído' : 'Marcar como leído',
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
