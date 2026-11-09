import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/manga_source.dart';
import '../providers/source_provider.dart';
import '../services/mangadex_service.dart';
import '../widgets/home_content_layout.dart';
import '../widgets/mangadex_language_sheet.dart';
import '../widgets/section_header.dart';
import '../widgets/sources_list_card.dart';

/// Pantalla de fuentes: el usuario elige qué página se scrapea / consulta.
class SourcesScreen extends StatelessWidget {
  const SourcesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sources = context.watch<SourceProvider>();
    final active = sources.active;
    final isMangaDex = active.id == 'mangadex';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Fuentes'),
        actions: [
          if (isMangaDex)
            IconButton(
              tooltip: 'Ahorro de datos MangaDex',
              icon: Icon(
                context.watch<SourceProvider>().dataSaver
                    ? Icons.data_saver_on
                    : Icons.data_saver_off,
              ),
              onPressed: () => context.read<SourceProvider>().setDataSaver(
                !context.read<SourceProvider>().dataSaver,
              ),
            ),
        ],
        // Se abre desde el chip de Inicio; permite volver.
        automaticallyImplyLeading: true,
      ),
      body: ListView(
        padding: HomeContentLayout.paddingOf(context),
        children: [
          SectionHeader(
            icon: Icons.public_rounded,
            title: 'Catálogo y descargas',
          ),
          const SizedBox(height: 12),
          Text(
            'Elige la página del catálogo. La búsqueda puede consultar varias fuentes a la vez.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurface.withAlpha(170),
              height: 1.4,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (isMangaDex) ...[
            const SizedBox(height: HomeContentLayout.sectionSpacing),
            SectionHeader(
              icon: Icons.translate_rounded,
              title: 'Idiomas de MangaDex',
              trailing: '${sources.mangaDexLanguages.length}',
            ),
            const SizedBox(height: 10),
            Text(
              'Elige uno o varios idiomas para el catálogo, las búsquedas y los capítulos.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface.withAlpha(170),
                height: 1.4,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: MangaDexLanguage.selectable
                  .where((lang) => sources.isMangaDexLanguageEnabled(lang.code))
                  .map((lang) {
                    final selected = sources.isMangaDexLanguageEnabled(
                      lang.code,
                    );
                    return FilterChip(
                      selected: selected,
                      showCheckmark: true,
                      label: Text(lang.label),
                      selectedColor: theme.colorScheme.primary.withAlpha(48),
                      checkmarkColor: theme.colorScheme.primary,
                      labelStyle: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: selected
                            ? theme.colorScheme.primary
                            : theme.colorScheme.onSurface.withAlpha(200),
                      ),
                      side: BorderSide(
                        color: selected
                            ? theme.colorScheme.primary.withAlpha(120)
                            : theme.colorScheme.onSurface.withAlpha(28),
                      ),
                      onSelected: (_) async {
                        final before = sources.mangaDexLanguages.length;
                        await sources.toggleMangaDexLanguage(lang.code);
                        if (!context.mounted) {
                          return;
                        }
                        final after = sources.mangaDexLanguages.length;
                        final blocked = selected && before == 1 && after == 1;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              blocked
                                  ? 'Debe quedar al menos un idioma.'
                                  : 'MangaDex: ${sources.mangaDexLanguages.map(_langLabel).join(' · ')}',
                            ),
                            duration: const Duration(seconds: 2),
                          ),
                        );
                      },
                    );
                  })
                  .toList(),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              icon: const Icon(Icons.translate_rounded),
              label: const Text('Elegir idiomas'),
              onPressed: () => MangaDexLanguageSheet.show(context, sources),
            ),
          ],
          const SizedBox(height: HomeContentLayout.sectionSpacing),
          SectionHeader(
            icon: Icons.hub_rounded,
            title: 'Todas las fuentes',
            trailing: '${sources.sources.length}',
          ),
          const SizedBox(height: 14),
          ...sources.sources.map(
            (source) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: SourcesListCard(
                source: source,
                isActive: source.id == active.id,
                onSelect: () => _onSelect(context, sources, source),
              ),
            ),
          ),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: theme.colorScheme.onSurface.withAlpha(18),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  color: theme.colorScheme.primary,
                  size: 20,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Puedes cambiar las fuentes de búsqueda desde Inicio. '
                    'En MangaDex también puedes elegir el idioma y ahorrar datos.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withAlpha(170),
                      height: 1.4,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _langLabel(String code) {
    for (final lang in MangaDexLanguage.selectable) {
      if (lang.code == code) {
        return lang.label;
      }
    }
    return code;
  }

  Future<void> _onSelect(
    BuildContext context,
    SourceProvider provider,
    MangaSource source,
  ) async {
    await provider.select(source.id);
    if (!context.mounted) {
      return;
    }
    final label = source.implemented
        ? 'Fuente activa: ${source.name}'
        : '${source.name} seleccionada (próximamente)';
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(label)));
  }
}
