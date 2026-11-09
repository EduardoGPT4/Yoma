import 'package:flutter/material.dart';

import '../models/manga_list_filters.dart';
import '../models/reading_status_filter.dart';

class MangaFilterSheet extends StatefulWidget {
  final MangaListFilters initialFilters;
  final bool isOnline;
  final bool allowType, allowStatus;
  final bool showHitomiTags;
  final ValueChanged<MangaListFilters> onApply;

  const MangaFilterSheet({
    super.key,
    required this.initialFilters,
    required this.isOnline,
    this.allowType = true,
    this.allowStatus = true,
    this.showHitomiTags = false,
    required this.onApply,
  });

  static Future<void> show({
    required BuildContext context,
    required MangaListFilters initialFilters,
    required bool isOnline,
    bool allowType = true,
    bool allowStatus = true,
    bool showHitomiTags = false,
    required ValueChanged<MangaListFilters> onApply,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return MangaFilterSheet(
          initialFilters: initialFilters,
          isOnline: isOnline,
          allowType: allowType,
          allowStatus: allowStatus,
          showHitomiTags: showHitomiTags,
          onApply: onApply,
        );
      },
    );
  }

  @override
  State<MangaFilterSheet> createState() => _MangaFilterSheetState();
}

class _MangaFilterSheetState extends State<MangaFilterSheet> {
  late MangaListFilters _filters;

  @override
  void initState() {
    super.initState();
    _filters = widget.initialFilters;
  }

  void _apply() {
    widget.onApply(_filters);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      child: SingleChildScrollView(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            12,
            20,
            20 + MediaQuery.of(context).viewInsets.bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.onSurface.withAlpha(60),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Filtros y orden',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 16),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                value: _filters.favoritesOnly,
                onChanged: (value) {
                  setState(() {
                    _filters = _filters.copyWith(favoritesOnly: value);
                  });
                },
                title: const Text('Solo favoritos'),
              ),
              if (widget.showHitomiTags)
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  value: _filters.showPopularTags,
                  onChanged: (value) {
                    setState(() {
                      _filters = _filters.copyWith(showPopularTags: value);
                    });
                  },
                  title: const Text('Etiquetas más buscadas'),
                  subtitle: const Text(
                    'Muestra bajo el buscador artistas, grupos, series, personajes, géneros, tipos e idiomas con más galerías.',
                  ),
                ),
              if (!widget.isOnline) ...[
                const SizedBox(height: 8),
                Text('Progreso de lectura', style: theme.textTheme.labelLarge),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: ReadingStatusFilter.values.map((status) {
                    final selected = _filters.readingStatus == status;
                    return FilterChip(
                      label: Text(status.label),
                      selected: selected,
                      onSelected: (_) {
                        setState(() {
                          _filters = _filters.copyWith(readingStatus: status);
                        });
                      },
                    );
                  }).toList(),
                ),
              ],
              if (widget.isOnline) ...[
                if (!widget.allowType || !widget.allowStatus)
                  const Text('Esta fuente solo permite algunos filtros.'),
                const SizedBox(height: 8),
                if (widget.allowStatus)
                  _buildChoiceChips(
                    theme: theme,
                    title: 'Estado',
                    options: const ['Publicándose', 'Finalizado'],
                    selected: _filters.status,
                    onSelected: (value) {
                      setState(() {
                        _filters = _filters.copyWith(
                          status: value,
                          clearStatus: value == null,
                        );
                      });
                    },
                  ),
                const SizedBox(height: 12),
                if (widget.allowType)
                  _buildChoiceChips(
                    theme: theme,
                    title: 'Tipo',
                    options: const ['MANGA', 'MANHWA', 'MANHUA'],
                    selected: _filters.type,
                    onSelected: (value) {
                      setState(() {
                        _filters = _filters.copyWith(
                          type: value,
                          clearType: value == null,
                        );
                      });
                    },
                  ),
              ],
              const SizedBox(height: 12),
              Text('Ordenar por', style: theme.textTheme.labelLarge),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _sortChip(
                    widget.isOnline ? 'Catálogo' : 'Por defecto',
                    MangaSortOption.catalog,
                  ),
                  _sortChip('Título A–Z', MangaSortOption.titleAsc),
                  _sortChip('Título Z–A', MangaSortOption.titleDesc),
                  _sortChip('Más capítulos', MangaSortOption.chaptersDesc),
                  if (!widget.isOnline)
                    _sortChip('Recientes', MangaSortOption.recentProgress),
                ],
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () {
                        setState(() {
                          _filters = MangaListFilters.empty;
                        });
                      },
                      child: const Text('Limpiar'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      onPressed: _apply,
                      child: const Text('Aplicar'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sortChip(String label, MangaSortOption value) {
    final selected = _filters.sort == value;
    return FilterChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) {
        setState(() {
          _filters = _filters.copyWith(sort: value);
        });
      },
    );
  }

  Widget _buildChoiceChips({
    required ThemeData theme,
    required String title,
    required List<String> options,
    required String? selected,
    required ValueChanged<String?> onSelected,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: theme.textTheme.labelLarge),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: options.map((option) {
            final isSelected = selected == option;
            return FilterChip(
              label: Text(option),
              selected: isSelected,
              onSelected: (_) => onSelected(isSelected ? null : option),
            );
          }).toList(),
        ),
      ],
    );
  }
}
