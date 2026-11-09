import 'package:flutter/material.dart';
import '../../../design/yoma_components.dart';
import '../../../design/yoma_tokens.dart';
import '../models/anime_models.dart';
import 'anime_cover.dart';

Widget animeArtwork(String url, {BoxFit fit = BoxFit.cover, int width = 360}) =>
    Image(
      image: ResizeImage(AnimeCover(url), width: width),
      fit: fit,
      // Mientras carga se reserva el espacio con la superficie de Yoma.
      frameBuilder: (_, child, frame, sync) => sync || frame != null
          ? child
          : const ColoredBox(color: YomaColors.surfaceHigh),
      errorBuilder: (_, _, _) =>
          const YomaImageFallback(icon: Icons.movie_outlined, iconSize: 36),
      gaplessPlayback: true,
    );

/// Degradado de los banners: deja ver la ilustración arriba y funde con el
/// fondo de Yoma abajo para que el texto sea legible.
class AnimeBackdropGradient extends StatelessWidget {
  const AnimeBackdropGradient({super.key});

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        stops: const [0, .45, 1],
        colors: [
          YomaColors.scrim.withAlpha(66),
          YomaColors.background.withAlpha(120),
          Theme.of(context).scaffoldBackgroundColor,
        ],
      ),
    ),
  );
}

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
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      button: true,
      label: anime.title,
      child: InkWell(
        onTap: onTap,
        borderRadius: YomaRadii.mdAll,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: YomaRadii.mdAll,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    animeArtwork(anime.cover),
                    Positioned(
                      left: YomaSpacing.sm,
                      top: YomaSpacing.sm,
                      right: favorite ? 36 : YomaSpacing.sm,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: YomaCoverTag(
                          label: anime.category.isEmpty
                              ? 'Anime'
                              : anime.category,
                        ),
                      ),
                    ),
                    if (favorite)
                      const Positioned(
                        right: YomaSpacing.sm,
                        top: YomaSpacing.sm,
                        child: Icon(
                          Icons.star_rounded,
                          color: YomaColors.rating,
                          semanticLabel: 'Favorito',
                        ),
                      ),
                    if (progress != null)
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: YomaProgressBar(
                          value: progress,
                          overImage: true,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: YomaSpacing.sm),
            Text(
              anime.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleSmall,
            ),
            if (anime.year.isNotEmpty || anime.episodes > 0)
              Text(
                [
                  if (anime.year.isNotEmpty) anime.year,
                  if (anime.episodes > 0) '${anime.episodes} episodios',
                ].join(' · '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall,
              ),
          ],
        ),
      ),
    );
  }
}

/// Mensaje de YomaTV con el estado compartido de Yoma.
class AnimeMessage extends StatelessWidget {
  final String text;
  final String? action;
  final VoidCallback? onAction;
  const AnimeMessage(this.text, {super.key, this.action, this.onAction});
  @override
  Widget build(BuildContext context) => YomaStateMessage(
    icon: Icons.movie_filter_outlined,
    message: text,
    actionLabel: action,
    onAction: onAction,
    framed: false,
  );
}

String animeBytes(int bytes) => bytes >= 1024 * 1024 * 1024
    ? '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB'
    : '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
