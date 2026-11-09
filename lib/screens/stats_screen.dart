import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/chapter_read_provider.dart';
import '../providers/library_provider.dart';

class StatsScreen extends StatelessWidget {
  const StatsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryProvider>();
    final chapterRead = context.watch<ChapterReadProvider>();
    final stats = library.readingStats;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Estadisticas')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _StatCard(
            icon: Icons.menu_book_rounded,
            label: 'Mangas abiertos',
            value: '${stats.mangaOpens}',
            subtitle: '${stats.uniqueMangasOpened} unicos',
          ),
          const SizedBox(height: 12),
          _StatCard(
            icon: Icons.layers_rounded,
            label: 'Capitulos abiertos',
            value: '${stats.chaptersOpened}',
          ),
          const SizedBox(height: 12),
          _StatCard(
            icon: Icons.auto_stories_rounded,
            label: 'Paginas leidas',
            value: '${stats.pagesRead}',
          ),
          const SizedBox(height: 12),
          _StatCard(
            icon: Icons.done_all_rounded,
            label: 'Capitulos marcados leidos',
            value: '${chapterRead.totalReadChapters}',
            subtitle: 'Mantén pulsado un capitulo para marcarlo',
          ),
          const SizedBox(height: 12),
          _StatCard(
            icon: Icons.folder_rounded,
            label: 'En biblioteca local',
            value: '${library.mangas.length}',
          ),
          const SizedBox(height: 20),
          Text(
            'Sigue leyendo para subir tus numeros.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurface.withAlpha(160),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final String? subtitle;

  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: theme.colorScheme.onSurface.withAlpha(18)),
      ),
      child: Row(
        children: [
          Icon(icon, color: theme.colorScheme.primary, size: 28),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: theme.textTheme.labelLarge),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withAlpha(140),
                    ),
                  ),
              ],
            ),
          ),
          Text(
            value,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}
