part of '../native_anime_screen.dart';

// Más: historial, reproducción, ajustes y web.

class _AnimeMore extends StatelessWidget {
  final AnimeController app;
  final ValueChanged<String> detail;
  final void Function(AnimeDetail, AnimeEpisode) play;
  final VoidCallback web, home, mal;
  const _AnimeMore({
    required this.app,
    required this.detail,
    required this.play,
    required this.web,
    required this.home,
    required this.mal,
  });
  @override
  Widget build(BuildContext context) {
    final profile = context.watch<ProfileProvider>();
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: CircleAvatar(
            backgroundImage: profile.myAnimeListAvatarUrl == null
                ? null
                : NetworkImage(profile.myAnimeListAvatarUrl!),
            child: profile.myAnimeListAvatarUrl == null
                ? const Icon(Icons.person_outline)
                : null,
          ),
          title: Text(
            profile.usesMyAnimeListIdentity
                ? profile.displayName
                : 'Tu espacio local',
          ),
          // Único acceso a MyAnimeList; un avance que no llegó a MAL no se
          // queda en silencio.
          subtitle: Text(
            app.malStatus ??
                (profile.usesMyAnimeListIdentity
                    ? 'MyAnimeList conectado en Yoma'
                    : 'Biblioteca, historial y descargas sin cuenta'),
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: mal,
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.history),
          title: const Text('Historial de reproducción'),
          subtitle: Text('${app.history.length} episodios'),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => Scaffold(
                appBar: AppBar(title: const Text('Historial')),
                body: AnimatedBuilder(
                  animation: app,
                  builder: (c, _) => app.history.isEmpty
                      ? const AnimeMessage(
                          'Los episodios que reproduzcas aparecerán aquí.',
                        )
                      : ListView.builder(
                          itemCount: app.history.length,
                          itemBuilder: (c, i) {
                            final row = app.history[i],
                                anime = AnimeTitle.fromJson(
                                  animeMap(row['anime']),
                                ),
                                ep = AnimeEpisode.fromJson(
                                  animeMap(row['episode']),
                                );
                            return ListTile(
                              leading: SizedBox(
                                width: 40,
                                height: 56,
                                child: animeArtwork(anime.cover, width: 100),
                              ),
                              title: Text(
                                anime.title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text(
                                'Episodio ${ep.number} · ${row['watched'] == true ? 'Visto' : '${animeInt(row['positionMs']) ~/ 60000} min'}',
                              ),
                              onTap: () async {
                                try {
                                  final d = await app.detail(anime.slug);
                                  play(d, ep);
                                } catch (e) {
                                  if (c.mounted) {
                                    ScaffoldMessenger.of(c).showSnackBar(
                                      SnackBar(content: Text(e.toString())),
                                    );
                                  }
                                }
                              },
                            );
                          },
                        ),
                ),
              ),
            ),
          ),
        ),
        const Divider(height: 32),
        Text('Reproducción', style: Theme.of(context).textTheme.titleLarge),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Reproducir al abrir un episodio'),
          value: app.settings['autoplay'] != false,
          onChanged: (v) => app.saveSetting('autoplay', v),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Pasar al siguiente episodio al terminar'),
          subtitle: const Text('Con 5 segundos para cancelarlo.'),
          value: app.settings['autonext'] != false,
          onChanged: (v) => app.saveSetting('autonext', v),
        ),
        DropdownButtonFormField<String>(
          initialValue: '${app.settings['language'] ?? 'SUB'}',
          decoration: const InputDecoration(labelText: 'Idioma preferido'),
          items: ['SUB', 'LAT', 'DUB']
              .map(
                (v) => DropdownMenuItem(
                  value: v,
                  child: Text(animeLanguageLabel(v)),
                ),
              )
              .toList(),
          onChanged: (v) => app.saveSetting('language', v),
        ),
        const SizedBox(height: 16),
        DropdownButtonFormField<double>(
          initialValue: (app.settings['speed'] as num?)?.toDouble() ?? 1,
          decoration: const InputDecoration(
            labelText: 'Velocidad predeterminada',
          ),
          items: [.5, .75, 1.0, 1.25, 1.5, 2.0]
              .map((v) => DropdownMenuItem(value: v, child: Text('${v}x')))
              .toList(),
          onChanged: (v) => app.saveSetting('speed', v),
        ),
        const SizedBox(height: 24),
        Text(
          'Datos del dispositivo',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.cleaning_services_outlined),
          title: const Text('Limpiar caché del catálogo'),
          subtitle: const Text(
            'Conserva biblioteca, historial y videos descargados.',
          ),
          onTap: () async {
            await app.store.clearMetadataCache();
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Caché del catálogo borrada.')),
              );
            }
          },
        ),
        const Divider(height: 32),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.open_in_browser),
          title: const Text('YomaTV en la web'),
          subtitle: const Text(
            'Radio, cuenta web, herramientas de PC y proveedores web.',
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: web,
        ),
        const SizedBox(height: 12),
        Text('Fuente: YomaTV', style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}
