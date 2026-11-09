import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/reader_settings_enums.dart';
import '../providers/reader_settings_provider.dart';

class ReaderSettingsPanel extends StatelessWidget {
  const ReaderSettingsPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final settings = context.watch<ReaderSettingsProvider>();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildBrightnessControl(theme, settings),
        const SizedBox(height: 12),
        _group(
          theme: theme,
          title: 'Imagen',
          icon: Icons.image_outlined,
          initiallyExpanded: true,
          children: [
            _buildDropdown<String>(
              theme: theme,
              label: 'Orientación de pantalla',
              value: settings.orientation,
              items: const ['system', 'portrait', 'landscape'],
              itemLabel: (value) => switch (value) {
                'portrait' => 'Vertical',
                'landscape' => 'Horizontal',
                _ => 'Automática',
              },
              onChanged: settings.setOrientation,
            ),
            _buildDropdown<PageFitMode>(
              theme: theme,
              label: 'Ajuste de página',
              value: settings.pageFitMode,
              items: PageFitMode.values,
              itemLabel: (value) => value.label,
              onChanged: settings.setPageFitMode,
            ),
            _buildSwitchTile(
              theme: theme,
              title: 'Zoom y movimiento libre',
              subtitle: 'Permite ampliar y desplazar la imagen.',
              value: settings.freeZoom,
              onChanged: settings.setFreeZoom,
            ),
            _buildSwitchTile(
              theme: theme,
              title: 'Recortar márgenes blancos',
              subtitle:
                  'Conserva el original; solo afecta a imágenes estáticas.',
              value: settings.cropWhite,
              onChanged: settings.setCropWhite,
            ),
          ],
        ),
        const SizedBox(height: 12),
        _group(
          theme: theme,
          title: 'Lectura',
          icon: Icons.auto_stories_outlined,
          children: [
            _buildDropdown<ReadingDirection>(
              theme: theme,
              label: 'Dirección de lectura',
              value: settings.readingDirection,
              items: ReadingDirection.values,
              itemLabel: (value) => value.label,
              onChanged: settings.setReadingDirection,
            ),
            _buildDropdown<PageTransitionSpeed>(
              theme: theme,
              label: 'Velocidad de transición',
              value: settings.transitionSpeed,
              items: PageTransitionSpeed.values,
              itemLabel: (value) => value.label,
              onChanged: settings.setTransitionSpeed,
            ),
            _buildSwitchTile(
              theme: theme,
              title: 'Webtoon continuo',
              subtitle: 'Desplazamiento vertical sin separar las páginas.',
              value: settings.continuousVertical,
              onChanged: settings.setContinuousVertical,
            ),
            _buildSwitchTile(
              theme: theme,
              title: 'Doble página',
              subtitle: settings.verticalMode
                  ? 'Disponible con dirección de lectura horizontal.'
                  : 'Muestra dos páginas a la vez.',
              value: settings.doublePage && settings.isHorizontal,
              onChanged: settings.isHorizontal ? settings.setDoublePage : null,
            ),
            _buildSwitchTile(
              theme: theme,
              title: 'Portada en página separada',
              subtitle: 'En doble página, la primera imagen se muestra sola.',
              value: settings.coverAlone,
              onChanged: settings.setCoverAlone,
            ),
          ],
        ),
        const SizedBox(height: 12),
        _group(
          theme: theme,
          title: 'Controles',
          icon: Icons.touch_app_outlined,
          children: [
            _buildSwitchTile(
              theme: theme,
              title: 'Mostrar número de página',
              subtitle: 'Toca el contador del lector para ir a una página.',
              value: settings.showPageNumber,
              onChanged: settings.setShowPageNumber,
            ),
            _buildSwitchTile(
              theme: theme,
              title: 'Toque en los lados',
              subtitle: 'Las zonas laterales siguen la dirección de lectura.',
              value: settings.tapNavigation,
              onChanged: settings.setTapNavigation,
            ),
            _buildSwitchTile(
              theme: theme,
              title: 'Botones de volumen',
              subtitle: 'Subir volumen: siguiente; bajar: anterior.',
              value: settings.volumeNavigation,
              onChanged: settings.setVolumeNavigation,
            ),
          ],
        ),
      ],
    );
  }

  Widget _group({
    required ThemeData theme,
    required String title,
    required IconData icon,
    required List<Widget> children,
    bool initiallyExpanded = false,
  }) => Material(
    color: theme.colorScheme.surfaceContainerHighest,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
      side: BorderSide(color: theme.colorScheme.onSurface.withAlpha(20)),
    ),
    clipBehavior: Clip.antiAlias,
    child: ExpansionTile(
      key: PageStorageKey('reader-settings-$title'),
      initiallyExpanded: initiallyExpanded,
      maintainState: true,
      shape: const Border(),
      collapsedShape: const Border(),
      tilePadding: const EdgeInsets.symmetric(horizontal: 12),
      childrenPadding: const EdgeInsets.only(bottom: 8),
      leading: Icon(icon, color: theme.colorScheme.primary),
      title: Text(title, style: theme.textTheme.titleMedium),
      children: children,
    ),
  );

  Widget _buildBrightnessControl(
    ThemeData theme,
    ReaderSettingsProvider settings,
  ) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.colorScheme.onSurface.withAlpha(20)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.brightness_4_outlined,
                size: 20,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Brillo en la app',
                  style: theme.textTheme.titleSmall,
                ),
              ),
              Text('${(settings.appBrightness * 100).round()} %'),
            ],
          ),
          Slider(
            value: settings.appBrightness,
            divisions: 100,
            semanticFormatterCallback: (value) =>
                '${(value * 100).round()} por ciento',
            onChanged: settings.setAppBrightness,
          ),
        ],
      ),
    );
  }

  Widget _buildDropdown<T>({
    required ThemeData theme,
    required String label,
    required T value,
    required List<T> items,
    required String Function(T value) itemLabel,
    required ValueChanged<T> onChanged,
  }) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: theme.textTheme.labelLarge),
        DropdownButtonHideUnderline(
          child: DropdownButton<T>(
            isExpanded: true,
            value: value,
            borderRadius: BorderRadius.circular(12),
            items: [
              for (final item in items)
                DropdownMenuItem<T>(value: item, child: Text(itemLabel(item))),
            ],
            onChanged: (next) {
              if (next != null) onChanged(next);
            },
          ),
        ),
      ],
    ),
  );

  Widget _buildSwitchTile({
    required ThemeData theme,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool>? onChanged,
  }) => SwitchListTile.adaptive(
    contentPadding: const EdgeInsets.symmetric(horizontal: 16),
    value: value,
    onChanged: onChanged,
    title: Text(title, style: theme.textTheme.titleSmall),
    subtitle: Text(
      subtitle,
      style: theme.textTheme.bodySmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    ),
  );
}
