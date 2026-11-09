import 'package:flutter/material.dart';

import '../design/yoma_components.dart';
import '../design/yoma_tokens.dart';
import '../utils/title_sanitizer.dart';
import 'app_metrics.dart';
import 'cached_thumbnail.dart';
import 'section_header.dart';

class ContinueReadingEntry {
  final String title;
  final String chapterLabel;
  final int pageNumber;
  final double progress;
  final String? timeAgo;
  final String? coverPath;
  final VoidCallback onTap;

  const ContinueReadingEntry({
    required this.title,
    required this.chapterLabel,
    required this.pageNumber,
    required this.progress,
    required this.coverPath,
    required this.onTap,
    this.timeAgo,
  });
}

class ContinueReadingSection extends StatelessWidget {
  final List<ContinueReadingEntry> entries;

  const ContinueReadingSection({super.key, required this.entries});

  @override
  Widget build(BuildContext context) {
    final metrics = AppMetrics.of(context);
    if (entries.isEmpty) return const SizedBox.shrink();
    final rest = entries.skip(1).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader(
          icon: Icons.play_circle_outline_rounded,
          title: 'Continuar leyendo',
        ),
        const SizedBox(height: YomaSpacing.md),
        _FeaturedContinue(entry: entries.first),
        if (rest.isNotEmpty) ...[
          const SizedBox(height: 12),
          SizedBox(
            height:
                metrics.continueHeight *
                MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.8),
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: rest.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (_, index) => _ContinueCard(entry: rest[index]),
            ),
          ),
        ],
      ],
    );
  }
}

class _ContinueCard extends StatelessWidget {
  final ContinueReadingEntry entry;

  const _ContinueCard({required this.entry});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final metrics = AppMetrics.of(context);
    final title = TitleSanitizer.clean(entry.title);
    final progress = entry.progress.clamp(0.0, 1.0);
    final progressLabel = '${entry.chapterLabel} · Pág. ${entry.pageNumber}';

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: entry.onTap,
        borderRadius: YomaRadii.mdAll,
        child: Ink(
          width: metrics.continueWidth,
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: YomaRadii.mdAll,
            border: Border.all(color: YomaColors.borderSubtle),
          ),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: const BorderRadius.horizontal(
                  left: Radius.circular(YomaRadii.md - 1),
                ),
                child: SizedBox(
                  width: metrics.continueCover,
                  height: double.infinity,
                  child: CachedThumbnail(
                    sourcePath: entry.coverPath,
                    size: 180,
                    fit: BoxFit.cover,
                    placeholderBuilder: (_) => const YomaImageFallback(
                      icon: Icons.auto_stories_outlined,
                      iconSize: 18,
                    ),
                  ),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          fontSize: metrics.titleSize,
                          height: 1.15,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        progressLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.primary,
                        ),
                      ),
                      const SizedBox(height: 6),
                      YomaProgressBar(value: progress),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FeaturedContinue extends StatelessWidget {
  final ContinueReadingEntry entry;
  const _FeaturedContinue({required this.entry});
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: YomaRadii.lgAll,
        side: const BorderSide(color: YomaColors.borderSubtle),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(YomaSpacing.md),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(YomaRadii.sm),
              child: SizedBox(
                width: 72,
                height: 108,
                child: CachedThumbnail(
                  sourcePath: entry.coverPath,
                  size: 216,
                  placeholderBuilder: (_) =>
                      const YomaImageFallback(icon: Icons.menu_book_outlined),
                ),
              ),
            ),
            const SizedBox(width: YomaSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    TitleSanitizer.clean(entry.title),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${entry.chapterLabel} · Pág. ${entry.pageNumber}',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  if (entry.timeAgo != null)
                    Text(entry.timeAgo!, style: theme.textTheme.bodySmall),
                  const SizedBox(height: YomaSpacing.sm),
                  YomaProgressBar(value: entry.progress),
                  const SizedBox(height: YomaSpacing.md),
                  FilledButton.icon(
                    onPressed: entry.onTap,
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('Continuar'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
