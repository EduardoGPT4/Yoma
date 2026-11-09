import 'dart:io';

import 'package:flutter/material.dart';

import '../providers/profile_provider.dart';
import 'cached_thumbnail.dart';

/// The connected account's photo takes precedence without replacing the local
/// avatar. A new key prevents a previous account's image flashing while loading.
class ProfileAvatar extends StatelessWidget {
  final ProfileProvider profile;
  const ProfileAvatar({super.key, required this.profile});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget fallback(BuildContext context) => profile.hasAvatar
        ? Image.file(
            File(profile.avatarPath!),
            fit: BoxFit.cover,
            cacheWidth: 216,
            errorBuilder: (_, _, _) => placeholder(scheme),
          )
        : placeholder(scheme);
    final remote = profile.myAnimeListAvatarUrl;
    return Semantics(
      image: true,
      label: remote == null ? 'Foto de perfil' : 'Foto de MyAnimeList',
      child: ClipOval(
        child: SizedBox.square(
          dimension: 72,
          child: remote == null
              ? fallback(context)
              : CachedThumbnail(
                  key: ValueKey('${profile.myAnimeListUsername}:$remote'),
                  sourcePath: remote,
                  size: 216,
                  placeholderBuilder: fallback,
                ),
        ),
      ),
    );
  }

  Widget placeholder(ColorScheme scheme) => ColoredBox(
    color: scheme.primary.withAlpha(36),
    child: Icon(Icons.person_rounded, size: 36, color: scheme.primary),
  );
}
