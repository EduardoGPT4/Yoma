import 'package:flutter/material.dart';
import '../models/anime_models.dart';
import 'anime_cover.dart';

Widget animeArtwork(String url, {BoxFit fit = BoxFit.cover, int width = 360}) =>
    Image(
      image: ResizeImage(AnimeCover(url), width: width),
      fit: fit,
      errorBuilder: (_, _, _) => const ColoredBox(
        color: Color(0xFF262231),
        child: Center(
          child: Icon(Icons.movie_outlined, color: Colors.white38, size: 36),
        ),
      ),
      gaplessPlayback: true,
    );

class AnimeCard extends StatelessWidget {
  final AnimeTitle anime;
  final VoidCallback onTap;
  final bool favorite;
  final double? progress;
  const AnimeCard({
    super.key,
    required this.anime,
    required this.onTap,
    this.favorite = false,
    this.progress,
  });
  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: anime.title,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  animeArtwork(anime.cover),
                  Positioned(
                    left: 8,
                    top: 8,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: .7),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 4,
                        ),
                        child: Text(
                          anime.category.isEmpty ? 'Anime' : anime.category,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (favorite)
                    const Positioned(
                      right: 8,
                      top: 8,
                      child: Icon(Icons.star_rounded, color: Color(0xFFFFCB77)),
                    ),
                  if (progress != null)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: LinearProgressIndicator(
                        value: progress!.clamp(0, 1),
                        backgroundColor: Colors.black54,
                        color: const Color(0xFFFF6A55),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            anime.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
          ),
          if (anime.year.isNotEmpty || anime.episodes > 0)
            Text(
              [
                if (anime.year.isNotEmpty) anime.year,
                if (anime.episodes > 0) '${anime.episodes} episodios',
              ].join(' · '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: const Color(0xFFBAB3C6)),
            ),
        ],
      ),
    ),
  );
}

class AnimeMessage extends StatelessWidget {
  final String text;
  final String? action;
  final VoidCallback? onAction;
  const AnimeMessage(this.text, {super.key, this.action, this.onAction});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(20),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(
          Icons.movie_filter_outlined,
          size: 40,
          color: Color(0xFFB8ADC8),
        ),
        const SizedBox(height: 12),
        Text(text, textAlign: TextAlign.center),
        if (action != null) ...[
          const SizedBox(height: 16),
          FilledButton(onPressed: onAction, child: Text(action!)),
        ],
      ],
    ),
  );
}

String animeBytes(int bytes) => bytes >= 1024 * 1024 * 1024
    ? '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB'
    : '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
