part of '../native_anime_screen.dart';

// Biblioteca: guardados, favoritos y estados.

class _AnimeLibrary extends StatefulWidget {
  final AnimeController app;
  final ValueChanged<String> detail;
  final void Function(AnimeDetail, AnimeEpisode) play;
  const _AnimeLibrary({
    required this.app,
    required this.detail,
    required this.play,
  });
  @override
  State<_AnimeLibrary> createState() => _AnimeLibraryState();
}

class _AnimeLibraryState extends State<_AnimeLibrary> {
  bool _favorites = false;
  String _status = '';
  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    final items =
        app.saved.values
            .where(
              (r) =>
                  (r['saved'] == true || r['favorite'] == true) &&
                  (!_favorites || r['favorite'] == true) &&
                  (_status.isEmpty || r['status'] == _status),
            )
            .map((r) => AnimeTitle.fromJson(animeMap(r['anime'])))
            .toList()
          ..sort((a, b) => a.title.compareTo(b.title));
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            children: [
              FilterChip(
                label: const Text('Favoritos'),
                selected: _favorites,
                onSelected: (v) => setState(() => _favorites = v),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: _status,
                  decoration: const InputDecoration(labelText: 'Estado'),
                  items: const [
                    DropdownMenuItem(value: '', child: Text('Todos')),
                    DropdownMenuItem(value: 'planned', child: Text('Planeado')),
                    DropdownMenuItem(value: 'watching', child: Text('Viendo')),
                    DropdownMenuItem(
                      value: 'completed',
                      child: Text('Completado'),
                    ),
                    DropdownMenuItem(value: 'paused', child: Text('En pausa')),
                    DropdownMenuItem(
                      value: 'dropped',
                      child: Text('Abandonado'),
                    ),
                  ],
                  onChanged: (v) => setState(() => _status = v!),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: items.isEmpty
              ? const AnimeMessage(
                  'Guarda títulos desde sus fichas para crear tu biblioteca local.',
                )
              : GridView.builder(
                  key: const PageStorageKey('anime-library'),
                  padding: const EdgeInsets.all(16),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 190,
                    mainAxisSpacing: 20,
                    crossAxisSpacing: 14,
                    childAspectRatio: .56,
                  ),
                  itemCount: items.length,
                  itemBuilder: (_, i) => GestureDetector(
                    onLongPress: () => _edit(items[i]),
                    child: AnimeCard(
                      anime: items[i],
                      favorite: app.isFavorite(items[i].slug),
                      onTap: () => widget.detail(items[i].slug),
                    ),
                  ),
                ),
        ),
        if (items.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(
              'Mantén pulsado para editar estado, notas y puntuación.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
      ],
    );
  }

  Future<void> _edit(AnimeTitle anime) async {
    final app = widget.app, row = app.saved[anime.slug] ?? {};
    var status = '${row['status'] ?? 'planned'}';
    var score = animeInt(row['score']).clamp(0, 10).toDouble();
    final notes = TextEditingController(text: '${row['notes'] ?? ''}');
    final result = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: Text(anime.title),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: status,
                  isExpanded: true,
                  items: const [
                    DropdownMenuItem(value: 'planned', child: Text('Planeado')),
                    DropdownMenuItem(value: 'watching', child: Text('Viendo')),
                    DropdownMenuItem(
                      value: 'completed',
                      child: Text('Completado'),
                    ),
                    DropdownMenuItem(value: 'paused', child: Text('En pausa')),
                    DropdownMenuItem(
                      value: 'dropped',
                      child: Text('Abandonado'),
                    ),
                  ],
                  onChanged: (v) => set(() => status = v!),
                ),
                const SizedBox(height: 14),
                Text(
                  score == 0
                      ? 'Sin puntuación'
                      : 'Puntuación: ${score.toInt()}',
                ),
                Slider(
                  value: score,
                  min: 0,
                  max: 10,
                  divisions: 10,
                  onChanged: (v) => set(() => score = v),
                ),
                TextField(
                  controller: notes,
                  maxLines: 4,
                  maxLength: 4000,
                  decoration: const InputDecoration(labelText: 'Notas'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );
    if (result == true) {
      await app.updateLibrary(
        anime,
        status: status,
        score: score.toInt(),
        notes: notes.text,
      );
    }
    notes.dispose();
  }
}
