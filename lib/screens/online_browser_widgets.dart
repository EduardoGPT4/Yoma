part of 'online_browser_screen.dart';

// Piezas del catálogo online: carga, vacío y avisos de fuente.

class _CatalogSkeleton extends StatelessWidget {
  const _CatalogSkeleton();

  @override
  Widget build(BuildContext context) {
    final side = AppMetrics.of(context).horizontalPadding;

    return Padding(
      padding: EdgeInsets.fromLTRB(side, 22, side, 0),
      child: Column(
        children: [
          Row(
            children: List.generate(3, (index) {
              return Expanded(
                child: Padding(
                  padding: EdgeInsets.only(
                    left: index == 0 ? 0 : 7,
                    right: index == 2 ? 0 : 7,
                  ),
                  child: const AspectRatio(
                    aspectRatio: MangaCardLayout.gridAspectRatio,
                    child: YomaSkeleton(),
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 14),
          Row(
            children: List.generate(3, (index) {
              return Expanded(
                child: Padding(
                  padding: EdgeInsets.only(
                    left: index == 0 ? 0 : 7,
                    right: index == 2 ? 0 : 7,
                  ),
                  child: const AspectRatio(
                    aspectRatio: MangaCardLayout.gridAspectRatio,
                    child: YomaSkeleton(),
                  ),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }
}

class _CatalogEmptyState extends StatelessWidget {
  const _CatalogEmptyState();

  @override
  Widget build(BuildContext context) {
    return const _MessageCard(
      icon: Icons.menu_book_outlined,
      title: 'Catálogo vacío',
      message: 'No hay mangas para mostrar. Desliza hacia abajo para recargar.',
    );
  }
}

/// Aviso compacto de una fuente que no pudo buscar. Va al final de los resultados.
class _SearchSourceNotice extends StatelessWidget {
  final List<({String name, VoidCallback retry})> sources;

  const _SearchSourceNotice({required this.sources});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outline.withAlpha(170)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 8, 12, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (sources.length > 1) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(2, 2, 2, 6),
                child: Text(
                  'Fuentes que no respondieron',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: scheme.onSurface.withAlpha(150),
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.1,
                  ),
                ),
              ),
            ],
            for (var i = 0; i < sources.length; i++) ...[
              if (i > 0)
                Divider(height: 12, color: scheme.outline.withAlpha(120)),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: scheme.errorContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: SizedBox(
                      width: 32,
                      height: 32,
                      child: Icon(
                        Icons.cloud_off_outlined,
                        size: 16,
                        color: scheme.error,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          sources[i].name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            height: 1.2,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'No se pudo buscar en esta fuente. Puedes reintentarlo.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurface.withAlpha(160),
                            height: 1.25,
                          ),
                        ),
                        TextButton.icon(
                          onPressed: sources[i].retry,
                          icon: const Icon(Icons.refresh, size: 18),
                          label: const Text('Reintentar búsqueda'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _MessageCard extends StatelessWidget {
  final IconData icon;
  final String message;
  final String? title;
  final bool isError;

  const _MessageCard({
    required this.icon,
    required this.message,
    this.title,
    this.isError = false,
  });

  @override
  Widget build(BuildContext context) => YomaStateMessage(
    icon: icon,
    title: title,
    message: message,
    isError: isError,
  );
}
