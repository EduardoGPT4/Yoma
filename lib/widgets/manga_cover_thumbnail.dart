import 'package:flutter/material.dart';
import 'cached_thumbnail.dart';

class MangaCoverThumbnail extends StatelessWidget {
  final String? url;
  const MangaCoverThumbnail({super.key, required this.url});

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 48,
    height: 72,
    child: ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: CachedThumbnail(
        sourcePath: url,
        size: 160,
        placeholderBuilder: (context) => ColoredBox(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: const Icon(Icons.menu_book_rounded),
        ),
      ),
    ),
  );
}
