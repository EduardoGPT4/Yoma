import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/source_provider.dart';
import '../services/mangadex_service.dart';

/// Selector con búsqueda y lista acotada para no llenar Fuentes de chips.
class MangaDexLanguageSheet extends StatefulWidget {
  const MangaDexLanguageSheet({super.key});

  static Future<void> show(BuildContext context, SourceProvider sources) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: FractionallySizedBox(
          heightFactor: 0.85,
          child: ChangeNotifierProvider.value(
            value: sources,
            child: const MangaDexLanguageSheet(),
          ),
        ),
      ),
    );
  }

  @override
  State<MangaDexLanguageSheet> createState() => _MangaDexLanguageSheetState();
}

class _MangaDexLanguageSheetState extends State<MangaDexLanguageSheet> {
  final _search = TextEditingController();
  String _query = '';
  bool _minimumLanguage = false;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  // Permite buscar «ingles» o «japones» sin exigir las tildes del nombre.
  static String _searchKey(String value) {
    const accents = {
      'á': 'a',
      'é': 'e',
      'í': 'i',
      'ó': 'o',
      'ú': 'u',
      'ü': 'u',
    };
    var result = value.trim().toLowerCase();
    for (final entry in accents.entries) {
      result = result.replaceAll(entry.key, entry.value);
    }
    return result;
  }

  Future<void> _toggle(SourceProvider sources, String code) async {
    final lastSelected =
        sources.isMangaDexLanguageEnabled(code) &&
        sources.mangaDexLanguages.length == 1;
    setState(() => _minimumLanguage = lastSelected);
    if (!lastSelected) await sources.toggleMangaDexLanguage(code);
  }

  @override
  Widget build(BuildContext context) {
    final sources = context.watch<SourceProvider>();
    final languages = MangaDexLanguage.selectable.where((language) {
      return _searchKey('${language.label} ${language.code}').contains(_query);
    }).toList();

    return LayoutBuilder(
      builder: (context, constraints) => SafeArea(
        top: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (constraints.maxHeight >= 400) ...[
                    Text(
                      'Idiomas de MangaDex',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${sources.mangaDexLanguages.length} seleccionados · '
                      '${MangaDexLanguage.selectable.length} disponibles',
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Los cambios se guardan al seleccionar. '
                      'Mantén al menos un idioma activo.',
                    ),
                    const SizedBox(height: 12),
                  ],
                  TextField(
                    controller: _search,
                    decoration: InputDecoration(
                      labelText: 'Buscar idioma o código',
                      prefixIcon: const Icon(Icons.search_rounded),
                      suffixIcon: _query.isEmpty
                          ? null
                          : IconButton(
                              tooltip: 'Borrar búsqueda de idiomas',
                              icon: const Icon(Icons.clear_rounded),
                              onPressed: () {
                                _search.clear();
                                setState(() => _query = '');
                              },
                            ),
                    ),
                    onChanged: (value) =>
                        setState(() => _query = _searchKey(value)),
                  ),
                  const SizedBox(height: 8),
                  if (_minimumLanguage)
                    Semantics(
                      liveRegion: true,
                      child: Text(
                        'Debe quedar al menos un idioma.',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: languages.isEmpty
                  ? const Center(child: Text('No se encontraron idiomas.'))
                  : ListView.builder(
                      itemCount: languages.length,
                      itemBuilder: (context, index) {
                        final language = languages[index];
                        return CheckboxListTile(
                          key: ValueKey('mangadex-language-${language.code}'),
                          title: Text(language.label),
                          subtitle: Text(language.code),
                          value: sources.isMangaDexLanguageEnabled(
                            language.code,
                          ),
                          onChanged: (_) => _toggle(sources, language.code),
                        );
                      },
                    ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Listo'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
