import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../providers/profile_provider.dart';
import '../data/anime_controller.dart';
import '../data/anime_mal_client.dart';
import '../models/anime_models.dart';
import '../widgets/anime_widgets.dart';

class AnimeMalScreen extends StatefulWidget {
  final AnimeController controller;
  final VoidCallback home;
  const AnimeMalScreen({
    super.key,
    required this.controller,
    required this.home,
  });
  @override
  State<AnimeMalScreen> createState() => _AnimeMalScreenState();
}

class _AnimeMalScreenState extends State<AnimeMalScreen> {
  late final AnimeMalClient _mal = widget.controller.mal;
  bool _busy = true, _available = false;
  final _malId = TextEditingController();
  String? _error;
  String _status = 'watching';
  int _offset = 0, _generation = 0;

  /// Página siguiente según el servidor; `null` en la última.
  int? _next;
  List<MalAnimeEntry> _entries = [];
  List<Map<String, dynamic>> _pending = [];
  @override
  void initState() {
    super.initState();
    _load();
    _mal.client.sessionChanges.addListener(_sessionChanged);
    widget.controller.addListener(_controllerChanged);
  }

  /// El aviso de sincronización cambia fuera de esta pantalla.
  void _controllerChanged() {
    if (mounted) setState(() {});
  }

  void _sessionChanged() {
    if (mounted) _load();
  }

  Future<void> _load() async {
    final generation = ++_generation;
    if (mounted) {
      setState(() {
        _busy = true;
        _entries = [];
      });
    }
    try {
      final available = await _mal.available();
      final page = available
          ? await _mal.libraryPage(status: _status, offset: _offset)
          : const MalAnimePage([], null);
      final pending = available
          ? await _mal.pending()
          : <Map<String, dynamic>>[];
      if (mounted && generation == _generation) {
        setState(() {
          _pending = pending;
          _available = available;
          _entries = page.items;
          _next = page.nextOffset;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted && generation == _generation) {
        setState(() => _error = e.toString());
      }
    } finally {
      if (mounted && generation == _generation) setState(() => _busy = false);
    }
  }

  Future<void> _link(MalAnimeEntry entry) async {
    final local = widget.controller.saved.values
        .where((r) => r['saved'] == true || r['favorite'] == true)
        .toList();
    if (local.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Guarda primero el anime correspondiente en tu biblioteca local.',
          ),
        ),
      );
      return;
    }
    final slug = await showDialog<String>(
      context: context,
      builder: (c) => SimpleDialog(
        title: Text('Vincular ${entry.title}'),
        children: local
            .map(
              (r) => SimpleDialogOption(
                onPressed: () => Navigator.pop(c, '${r['slug']}'),
                child: Text(AnimeTitle.fromJson(animeMap(r['anime'])).title),
              ),
            )
            .toList(),
      ),
    );
    if (slug == null) return;
    try {
      await _mal.link(slug, entry);
      widget.controller.malLinkChanges.value++;
      // Lo que MAL ya tiene visto pasa a YomaTV al vincular.
      final pulled = await widget.controller
          .applyMalProgress(slug, entry)
          .catchError((Object _) => 0);
      var watched = 0;
      for (final progress in widget.controller.positions.values) {
        if (progress['slug'] != slug || progress['watched'] != true) continue;
        final number = malEpisodeCount(
          '${animeMap(progress['episode'])['number']}',
        );
        if (number > watched) watched = number;
      }
      if (watched > 0) {
        await _mal.queueWatched(slug, watched);
        await widget.controller.syncMal();
      }
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              pulled > 0
                  ? 'Vinculado. $pulled ${pulled == 1 ? 'episodio visto' : 'episodios vistos'} en MyAnimeList ya ${pulled == 1 ? 'aparece' : 'aparecen'} como vistos.'
                  : 'Vinculación guardada para esta cuenta MAL.',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = context.watch<ProfileProvider>();
    return Scaffold(
      appBar: AppBar(title: const Text('MyAnimeList · Anime')),
      body: ListView(
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
                  : 'MyAnimeList es opcional',
            ),
            subtitle: Text(
              profile.usesMyAnimeListIdentity
                  ? 'La misma cuenta conectada en Yoma'
                  : 'Conecta tu cuenta desde el inicio de Yoma.',
            ),
          ),
          if (!profile.usesMyAnimeListIdentity)
            FilledButton(
              onPressed: widget.home,
              child: const Text('Ir al inicio de Yoma'),
            ),
          if (_busy) const LinearProgressIndicator(),
          if (_error != null)
            AnimeMessage(_error!, action: 'Reintentar', onAction: _load),
          if (widget.controller.malStatus != null)
            AnimeMessage(
              widget.controller.malStatus!,
              action: 'Sincronizar ahora',
              onAction: () async {
                await widget.controller.syncMal();
                if (mounted) await _load();
              },
            ),
          if (!_busy && !_available && profile.usesMyAnimeListIdentity)
            const AnimeMessage(
              'Tu cuenta está conectada. La consulta y sincronización de anime todavía no están disponibles en esta conexión. Tu biblioteca y progreso local se conservan.',
            ),
          if (_available) ...[
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _malId,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'ID de anime en MAL',
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Buscar anime por ID',
                  icon: const Icon(Icons.search),
                  onPressed: () async {
                    try {
                      final entry = await _mal.detail(
                        int.tryParse(_malId.text.trim()) ?? 0,
                      );
                      if (mounted) await _link(entry);
                    } catch (error) {
                      if (mounted) setState(() => _error = error.toString());
                    }
                  },
                ),
              ],
            ),
            for (final row in _pending)
              ListTile(
                title: Text('${row['title']}'),
                subtitle: Text(
                  row['conflict'] == null
                      ? (row['decrease'] == true
                            ? 'Por deshacer en MyAnimeList: volver al episodio ${row['episodes']}'
                            : 'Por enviar: hasta el episodio ${row['episodes']}')
                      : 'Conflicto: ${row['conflict']}',
                ),
                trailing: TextButton(
                  onPressed: () async {
                    final keep = await showDialog<bool>(
                      context: context,
                      builder: (c) => AlertDialog(
                        title: const Text('Resolver progreso pendiente'),
                        content: const Text(
                          'Puedes dejar MyAnimeList como está o volver a enviar tu progreso de Yoma. Tu historial en el teléfono no cambia. Si MyAnimeList cambia otra vez, se pedirá revisarlo de nuevo.',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(c, true),
                            child: const Text('Dejar MAL como está'),
                          ),
                          FilledButton(
                            onPressed: () => Navigator.pop(c, false),
                            child: const Text('Enviar mi progreso'),
                          ),
                        ],
                      ),
                    );
                    if (keep == null) return;
                    try {
                      await _mal.resolve('${row['id']}', keepRemote: keep);
                      await _load();
                    } catch (error) {
                      if (mounted) setState(() => _error = error.toString());
                    }
                  },
                  child: const Text('Revisar'),
                ),
              ),
            DropdownButtonFormField<String>(
              initialValue: _status,
              decoration: const InputDecoration(labelText: 'Lista de anime'),
              items: const [
                DropdownMenuItem(value: 'watching', child: Text('Viendo')),
                DropdownMenuItem(
                  value: 'plan_to_watch',
                  child: Text('Por ver'),
                ),
                DropdownMenuItem(
                  value: 'completed',
                  child: Text('Completados'),
                ),
                DropdownMenuItem(value: 'on_hold', child: Text('En pausa')),
                DropdownMenuItem(value: 'dropped', child: Text('Abandonados')),
              ],
              onChanged: (v) {
                _status = v!;
                _offset = 0;
                _next = null;
                _load();
              },
            ),
            const SizedBox(height: 12),
            for (final entry in _entries)
              ListTile(
                leading: SizedBox(
                  width: 42,
                  height: 60,
                  child: animeArtwork(entry.picture, width: 100),
                ),
                title: Text(entry.title),
                subtitle: Text(
                  '${entry.watched} / ${entry.total == 0 ? '?' : entry.total} episodios',
                ),
                trailing: const Icon(Icons.link),
                onTap: () => _link(entry),
              ),
            Row(
              children: [
                TextButton(
                  onPressed: _offset == 0
                      ? null
                      : () {
                          _offset = (_offset - 50).clamp(0, 1000000);
                          _next = null;
                          _load();
                        },
                  child: const Text('Anterior'),
                ),
                const Spacer(),
                TextButton(
                  onPressed: _next == null
                      ? null
                      : () {
                          _offset = _next!;
                          _load();
                        },
                  child: const Text('Siguiente'),
                ),
              ],
            ),
            OutlinedButton.icon(
              onPressed: () async {
                try {
                  await _mal.flush();
                  await _load();
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Sincronización completada.'),
                      ),
                    );
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(SnackBar(content: Text(e.toString())));
                  }
                }
              },
              icon: const Icon(Icons.sync),
              label: const Text('Sincronizar pendientes'),
            ),
          ],
          const SizedBox(height: 20),
          const Text(
            'El acceso a Anime, las descargas y los datos locales funcionan sin MyAnimeList.',
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _malId.dispose();
    _mal.client.sessionChanges.removeListener(_sessionChanged);
    widget.controller.removeListener(_controllerChanged);
    super.dispose();
  }
}
