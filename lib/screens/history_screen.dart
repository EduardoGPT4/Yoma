import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/library_provider.dart';
import '../services/hitomi_service.dart';
import '../utils/time_format.dart';
import '../widgets/cached_thumbnail.dart';
import 'reader_screen.dart';
import '../models/manga.dart';
import '../services/online_catalog_service.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  bool _adult = false;

  bool _isHitomi(dynamic progress) =>
      progress.sourceId == 'hitomi' ||
      HitomiService.isReference(progress.mangaPath as String?) ||
      HitomiService.isReference(progress.chapterPath as String?);

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryProvider>();
    final items = library
        .getRecentProgress()
        .where((progress) => _isHitomi(progress) == _adult)
        .toList();
    final theme = Theme.of(context);
    final shelf = Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Wrap(
        spacing: 8,
        children: [
          ChoiceChip(
            label: const Text('Mangas'),
            selected: !_adult,
            onSelected: (_) => setState(() => _adult = false),
          ),
          ChoiceChip(
            label: const Text('+18 Hitomi.la'),
            selected: _adult,
            onSelected: (_) => setState(() => _adult = true),
          ),
        ],
      ),
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Historial de lectura')),
      body: items.isEmpty
          ? Column(
              children: [
                shelf,
                Expanded(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(28),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 64,
                            height: 64,
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primary.withAlpha(28),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.history_rounded,
                              color: theme.colorScheme.primary,
                              size: 30,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Aún no hay historial',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _adult
                                ? 'Cuando leas una galería de +18 Hitomi.la aparecerá aquí.'
                                : 'Cuando leas un manga aparecerá aquí para retomar rápido.',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurface.withAlpha(170),
                              fontWeight: FontWeight.w600,
                              height: 1.4,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            )
          : Column(
              children: [
                shelf,
                Expanded(
                  child: ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: items.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final progress = items[index];
                      return ListTile(
                        tileColor: theme.colorScheme.surface,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                          side: BorderSide(
                            color: theme.colorScheme.onSurface.withAlpha(18),
                          ),
                        ),
                        leading: ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: SizedBox(
                            width: 48,
                            height: 64,
                            child: CachedThumbnail(
                              sourcePath: progress.coverPath,
                              size: 160,
                              placeholderBuilder: (_) => ColoredBox(
                                color:
                                    theme.colorScheme.surfaceContainerHighest,
                              ),
                            ),
                          ),
                        ),
                        title: Text(
                          progress.mangaTitle.isEmpty
                              ? 'Manga'
                              : progress.mangaTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          '${progress.chapterTitle} · pag. ${progress.pageIndex + 1}\n'
                          '${formatTimeAgo(progress.updatedAt)}',
                        ),
                        isThreeLine: true,
                        onTap: () async {
                          final path = progress.mangaPath;
                          Manga? local;
                          for (final manga in library.mangas) {
                            if (manga.path == path) {
                              local = manga;
                              break;
                            }
                          }
                          if (local != null) {
                            final chapterIndex = local.chapters.indexWhere(
                              (c) => c.path == progress.chapterPath,
                            );
                            if (!context.mounted) {
                              return;
                            }
                            await Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => ReaderScreen(
                                  manga: local!,
                                  initialChapterIndex: chapterIndex < 0
                                      ? 0
                                      : chapterIndex,
                                  initialPageIndex: progress.pageIndex,
                                ),
                              ),
                            );
                            return;
                          }
                          if (path.startsWith('http')) {
                            try {
                              final detail =
                                  await OnlineCatalogService.fetchMangaDetail(
                                    path,
                                  );
                              if (!context.mounted) {
                                return;
                              }
                              final chapterIndex = detail.chapters.indexWhere(
                                (c) => c.path == progress.chapterPath,
                              );
                              await Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => ReaderScreen(
                                    manga: detail.toOfflineManga(),
                                    initialChapterIndex: chapterIndex < 0
                                        ? 0
                                        : chapterIndex,
                                    initialPageIndex: progress.pageIndex,
                                  ),
                                ),
                              );
                            } catch (error) {
                              if (!context.mounted) {
                                return;
                              }
                              ScaffoldMessenger.of(
                                context,
                              ).showSnackBar(SnackBar(content: Text('$error')));
                            }
                          }
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }
}
