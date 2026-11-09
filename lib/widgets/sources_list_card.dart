import 'package:flutter/material.dart';

import '../models/manga_source.dart';

/// Card de una fuente en la lista de [SourcesScreen].
class SourcesListCard extends StatelessWidget {
  final MangaSource source;
  final bool isActive;
  final VoidCallback onSelect;

  const SourcesListCard({
    super.key,
    required this.source,
    required this.isActive,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onSelect,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isActive
                  ? scheme.primary.withAlpha(120)
                  : scheme.onSurface.withAlpha(22),
              width: isActive ? 1.5 : 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha(50),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: isActive
                        ? scheme.primary.withAlpha(36)
                        : scheme.onSurface.withAlpha(18),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    source.icon,
                    color: isActive
                        ? scheme.primary
                        : scheme.onSurface.withAlpha(180),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        source.name,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.2,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        source.detailLine,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurface.withAlpha(170),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (!source.implemented) ...[
                        const SizedBox(height: 6),
                        Text(
                          'Próximamente',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: scheme.onSurface.withAlpha(140),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                if (isActive)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: scheme.primary.withAlpha(36),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      'Elegida',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: scheme.primary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  )
                else
                  Icon(
                    Icons.radio_button_unchecked_rounded,
                    color: scheme.onSurface.withAlpha(80),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
