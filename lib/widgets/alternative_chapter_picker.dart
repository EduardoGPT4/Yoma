import 'package:flutter/material.dart';
import '../models/chapter.dart';
import '../services/alternative_chapter_service.dart';

class AlternativeChapterPicker extends StatefulWidget {
  final String title, origin;
  final Chapter chapter;
  const AlternativeChapterPicker({
    super.key,
    required this.title,
    required this.origin,
    required this.chapter,
  });
  @override
  State<AlternativeChapterPicker> createState() =>
      _AlternativeChapterPickerState();
}

class _AlternativeChapterPickerState extends State<AlternativeChapterPicker> {
  late final TextEditingController _query = TextEditingController(
    text: widget.title,
  );
  late Future<List<AlternativeChapter>> _results =
      AlternativeChapterService.find(
        widget.title,
        widget.origin,
        widget.chapter,
      );
  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          const Text(
            'Buscar este capítulo en otra fuente',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const Text(
            'Comprueba la traducción y edición. La lectura se abrirá desde el inicio del capítulo elegido.',
          ),
          TextField(
            controller: _query,
            decoration: InputDecoration(
              labelText: 'Título o título alternativo',
              suffixIcon: IconButton(
                icon: const Icon(Icons.search),
                onPressed: () => setState(
                  () => _results = AlternativeChapterService.find(
                    _query.text,
                    widget.origin,
                    widget.chapter,
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: FutureBuilder<List<AlternativeChapter>>(
              future: _results,
              builder: (c, s) {
                if (s.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (s.hasError) {
                  return Center(
                    child: Text('No se pudo completar la búsqueda: ${s.error}'),
                  );
                }
                final results = s.data ?? [];
                if (results.isEmpty) {
                  return const Center(
                    child: Text(
                      'No se encontró una coincidencia verificable. Prueba un título alternativo.',
                    ),
                  );
                }
                return ListView(
                  children: [
                    for (final item in results)
                      ListTile(
                        title: Text(item.manga.title),
                        subtitle: Text(
                          '${item.sourceId} · ${item.chapter.title} · ${item.chapter.language ?? 'Idioma no declarado'}',
                        ),
                        trailing: const Icon(Icons.open_in_new),
                        onTap: () => Navigator.pop(context, item),
                      ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    ),
  );
}
