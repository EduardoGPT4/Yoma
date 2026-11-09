import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/page_translation.dart';
import '../services/page_translation_service.dart';
import 'translation_attribution.dart';

class OnlineTranslationSheet extends StatefulWidget {
  final PageTranslationService service;
  final List<({int number, String url})> pages;
  final Map<String, PageTranslation> previous;

  const OnlineTranslationSheet({
    super.key,
    required this.service,
    required this.pages,
    this.previous = const {},
  });

  @override
  State<OnlineTranslationSheet> createState() => _OnlineTranslationSheetState();
}

class _OnlineTranslationSheetState extends State<OnlineTranslationSheet> {
  String _source = 'ja', _target = 'es';
  int _page = 0;
  bool _wifiOnly = true, _busy = false, _loading = true;
  bool _clearingModels = false;
  String? _error;
  String? _notice;
  PageTranslation? _result;

  @override
  void initState() {
    super.initState();
    _result = widget.previous[widget.pages.first.url];
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      final source = prefs.getString('translation_source_v1');
      final target = prefs.getString('translation_target_v1');
      setState(() {
        if (translationLanguages.containsKey(source)) _source = source!;
        if (translationLanguages.containsKey(target)) _target = target!;
        _wifiOnly = prefs.getBool('translation_wifi_only_v1') ?? true;
      });
    } catch (_) {
      /* Default options remain usable if preferences are unavailable. */
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    if (_busy && !_clearingModels) widget.service.cancel();
    super.dispose();
  }

  Future<void> _translate() async {
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
      _result = null;
    });
    try {
      final result = await widget.service.translate(
        url: widget.pages[_page].url,
        sourceLanguage: _source,
        targetLanguage: _target,
        wifiOnly: _wifiOnly,
      );
      if (!mounted) return;
      setState(() => _result = result);
      // Preference storage failure must not discard a successful translation.
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('translation_source_v1', _source);
        await prefs.setString('translation_target_v1', _target);
        await prefs.setBool('translation_wifi_only_v1', _wifiOnly);
      } catch (_) {
        /* Keep the translated page available. */
      }
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is TranslationFailure
              ? error.message
              : 'No se pudo preparar la traducción. Vuelve a intentarlo.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _clearModels() async {
    setState(() {
      _busy = true;
      _clearingModels = true;
      _error = null;
      _notice = null;
    });
    try {
      await widget.service.clearModels();
      if (mounted) {
        setState(
          () => _notice =
              'Modelos eliminados. Se descargarán cuando vuelvas a traducir.',
        );
      }
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is TranslationFailure
              ? error.message
              : 'No se pudieron eliminar los modelos.',
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _clearingModels = false;
        });
      }
    }
  }

  Widget _languageField(
    String label,
    String value,
    ValueChanged<String> changed,
  ) => DropdownButtonFormField<String>(
    key: ValueKey('$label:$value'),
    initialValue: value,
    isExpanded: true,
    decoration: InputDecoration(labelText: label),
    items: [
      for (final entry in translationLanguages.entries)
        DropdownMenuItem(value: entry.key, child: Text(entry.value)),
    ],
    onChanged: _busy || _loading
        ? null
        : (next) {
            if (next == null) return;
            setState(() {
              changed(next);
              _error = null;
              _result = null;
            });
          },
  );

  @override
  Widget build(BuildContext context) {
    final result = _result;
    final theme = Theme.of(context);
    return FractionallySizedBox(
      heightFactor: .92,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 8, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Traducir página online',
                    style: theme.textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  tooltip: 'Cerrar traducción',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
              children: [
                const Text(
                  'Reconoce el texto y coloca la traducción sobre la imagen. La página original se conserva.',
                ),
                const SizedBox(height: 16),
                if (widget.pages.length > 1)
                  DropdownButtonFormField<int>(
                    initialValue: _page,
                    decoration: const InputDecoration(
                      labelText: 'Página de la doble página',
                    ),
                    items: [
                      for (var i = 0; i < widget.pages.length; i++)
                        DropdownMenuItem(
                          value: i,
                          child: Text('Página ${widget.pages[i].number}'),
                        ),
                    ],
                    onChanged: _busy
                        ? null
                        : (value) {
                            if (value == null) return;
                            setState(() {
                              _page = value;
                              _result =
                                  widget.previous[widget.pages[value].url];
                              _error = null;
                            });
                          },
                  )
                else
                  Text(
                    'Página ${widget.pages.first.number}',
                    style: theme.textTheme.titleSmall,
                  ),
                const SizedBox(height: 12),
                _languageField(
                  'Idioma de la imagen',
                  _source,
                  (value) => _source = value,
                ),
                const SizedBox(height: 12),
                _languageField(
                  'Traducir a',
                  _target,
                  (value) => _target = value,
                ),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Descargar modelos solo por Wi-Fi'),
                  subtitle: const Text(
                    'La primera vez se descargan modelos de unos 30 MB por idioma. Con esta opción, conecta el teléfono a Wi-Fi.',
                  ),
                  value: _wifiOnly,
                  onChanged: _busy || _loading
                      ? null
                      : (value) => setState(() => _wifiOnly = value),
                ),
                const Text(
                  'Procesamiento en el teléfono con Google Translate. La precisión puede variar con texto vertical, estilizado o páginas muy largas.',
                ),
                TextButton(
                  onPressed: _busy || _loading ? null : _clearModels,
                  child: const Text('Eliminar modelos descargados'),
                ),
                if (_notice != null) Text(_notice!),
                const SizedBox(height: 16),
                if (_busy) ...[
                  const LinearProgressIndicator(),
                  const SizedBox(height: 8),
                  Text(
                    _clearingModels
                        ? 'Eliminando modelos descargados…'
                        : 'Reconociendo texto y preparando la traducción… La primera descarga puede tardar unos minutos.',
                  ),
                  if (!_clearingModels)
                    TextButton(
                      onPressed: widget.service.cancel,
                      child: const Text('Cancelar traducción'),
                    ),
                ] else
                  FilledButton.icon(
                    onPressed: _loading || _source == _target
                        ? null
                        : _translate,
                    icon: const Icon(Icons.translate),
                    label: const Text('Traducir con Google'),
                  ),
                if (_source == _target)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text('Elige dos idiomas diferentes.'),
                  ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      _error!,
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                  ),
                if (result != null) ...[
                  const Center(child: TranslationAttribution()),
                  const SizedBox(height: 16),
                  Text(
                    '${translationLanguages[result.sourceLanguage]} → ${translationLanguages[result.targetLanguage]} · Google Translate',
                    style: theme.textTheme.titleSmall,
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 200,
                    child: Image.file(
                      File(result.imagePath),
                      fit: BoxFit.contain,
                      errorBuilder: (_, _, _) => const Center(
                        child: Text(
                          'La vista previa ya no está disponible. Vuelve a traducir.',
                        ),
                      ),
                    ),
                  ),
                  if (result.textOnlyBlocks > 0)
                    Text(
                      '${result.textOnlyBlocks} bloques no caben sobre la imagen. Puedes leerlos completos en la comparación de texto.',
                    ),
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    title: const Text('Comparar original y traducción'),
                    children: [
                      for (var i = 0; i < result.blocks.length; i++)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                '${i + 1}. ${result.blocks[i].original}',
                                style: theme.textTheme.bodySmall,
                              ),
                              const SizedBox(height: 4),
                              SelectableText(result.blocks[i].translated),
                            ],
                          ),
                        ),
                    ],
                  ),
                  FilledButton.icon(
                    onPressed: () => Navigator.pop(context, result),
                    icon: const Icon(Icons.menu_book_outlined),
                    label: const Text('Ver en el lector'),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
