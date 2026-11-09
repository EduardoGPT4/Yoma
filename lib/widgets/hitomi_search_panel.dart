import 'dart:async';

import 'package:flutter/material.dart';

import '../services/content_exclusions.dart';
import '../services/hitomi_service.dart';
import '../utils/app_failure.dart';
import 'search_bar_field.dart';

typedef HitomiSuggestionLoader =
    Future<List<HitomiTagSuggestion>> Function(String query, {int limit});

class _QueryChip {
  final String queryText;
  final String label;
  const _QueryChip(this.queryText, this.label);
}

/// Buscador de Hitomi: al escribir muestra etiquetas y, al pulsarlas,
/// las deja aplicadas para poder seguir añadiendo otras.
class HitomiSearchPanel extends StatefulWidget {
  final bool showPopular;
  final ValueChanged<String> onQueryChanged;
  final Widget? trailing;
  final HitomiSuggestionLoader? suggestions;

  const HitomiSearchPanel({
    super.key,
    required this.showPopular,
    required this.onQueryChanged,
    this.trailing,
    this.suggestions,
  });

  @override
  State<HitomiSearchPanel> createState() => HitomiSearchPanelState();
}

class HitomiSearchPanelState extends State<HitomiSearchPanel> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focus = FocusNode();
  Timer? _debounce;
  int _generation = 0;
  List<_QueryChip> _chips = const [];
  List<HitomiTagSuggestion> _suggestions = const [];
  bool _loading = false;
  String? _error;
  String _popularField = 'global';

  @override
  void initState() {
    super.initState();
    if (widget.showPopular) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          unawaited(_load(_fieldQuery(_popularField), popular: true));
        }
      });
    }
  }

  @override
  void didUpdateWidget(HitomiSearchPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.showPopular == oldWidget.showPopular) return;
    if (_draftInput(_controller.text).isEmpty) {
      _showIdleSuggestions();
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _generation++;
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void clear({bool notify = true}) {
    _debounce?.cancel();
    _generation++;
    _controller.clear();
    setState(() {
      _chips = const [];
      _suggestions = const [];
      _loading = false;
      _error = null;
    });
    if (notify) widget.onQueryChanged('');
  }

  Future<List<HitomiTagSuggestion>> _fetch(String query, {required int limit}) {
    final loader = widget.suggestions;
    if (loader != null) return loader(query, limit: limit);
    return HitomiService.fetchTagSuggestions(query, limit: limit);
  }

  String _draftInput(String raw) {
    final text = raw.trim();
    if (text.isEmpty || text == '-') return '';
    return text;
  }

  String _fieldQuery(String field) => field == 'global' ? '' : '$field:';

  bool _stillRelevant(String query, {required bool popular}) {
    final draft = _draftInput(_controller.text);
    if (popular) {
      return draft.isEmpty && query == _fieldQuery(_popularField);
    }
    return draft.isNotEmpty && query == draft;
  }

  void _onDraftChanged(String value) {
    _debounce?.cancel();
    final input = _draftInput(value);
    if (input.isEmpty) {
      _showIdleSuggestions();
      return;
    }
    if (_draftBlocked(input)) {
      _generation++;
      setState(() {
        _suggestions = const [];
        _loading = false;
        _error = null;
      });
      return;
    }
    setState(() {
      _suggestions = const [];
      _loading = true;
      _error = null;
    });
    _debounce = Timer(const Duration(milliseconds: 220), () {
      unawaited(_load(input, popular: false));
    });
  }

  void _showIdleSuggestions() {
    _debounce?.cancel();
    if (widget.showPopular) {
      unawaited(_load(_fieldQuery(_popularField), popular: true));
      return;
    }
    _generation++;
    if (!mounted) return;
    setState(() {
      _suggestions = const [];
      _loading = false;
      _error = null;
    });
  }

  Future<void> _load(String query, {required bool popular}) async {
    final generation = ++_generation;
    if (mounted) {
      setState(() {
        _suggestions = const [];
        _loading = true;
        _error = null;
      });
    }
    try {
      final items = await _fetch(query, limit: popular ? 12 : 8);
      if (!mounted || generation != _generation) return;
      if (!_stillRelevant(query, popular: popular)) return;
      setState(() {
        _suggestions = _available(items);
        _loading = false;
      });
    } catch (error) {
      if (!mounted || generation != _generation) return;
      if (error is AppFailure && error.kind == FailureKind.cancelled) return;
      setState(() {
        _suggestions = const [];
        _loading = false;
        _error = 'No se pudieron cargar las etiquetas.';
      });
    }
  }

  List<HitomiTagSuggestion> _available(List<HitomiTagSuggestion> items) {
    return [
      for (final item in items)
        if (HitomiService.suggestionAllowed(item.namespace, item.name) &&
            !_alreadyUsed(item))
          item,
    ];
  }

  bool _alreadyUsed(HitomiTagSuggestion item) {
    return _chips.any((chip) {
      final text = chip.queryText.startsWith('-')
          ? chip.queryText.substring(1)
          : chip.queryText;
      return text == item.token;
    });
  }

  void _select(HitomiTagSuggestion suggestion) {
    final negative =
        _controller.text.trimLeft().startsWith('-') &&
        suggestion.namespace != 'language';
    final token = '${negative ? '-' : ''}${suggestion.token}';
    _commit(token, _chipLabel(token));
  }

  void _commitDraft() {
    final draft = _controller.text.trim();
    if (draft.isEmpty || draft == '-' || _draftBlocked(draft)) return;
    final negative = draft.startsWith('-');
    final body = (negative ? draft.substring(1) : draft).trim();
    final colon = body.indexOf(':');
    if (colon > 0) {
      final namespace = body.substring(0, colon).trim().toLowerCase();
      final name = body.substring(colon + 1).trim();
      if (HitomiService.suggestionAllowed(namespace, name)) {
        final token = HitomiService.tagToken(namespace, name);
        final stored = negative && namespace != 'language' ? '-$token' : token;
        _commit(stored, _chipLabel(stored));
        return;
      }
    }
    _commit(draft, 'Título: $draft');
  }

  bool _draftBlocked(String draft) => ContentExclusions.matches(draft);

  void _commit(String queryText, String label) {
    final keepFocus = _focus.hasFocus || _controller.text.trim().isNotEmpty;
    final next = [..._chips];
    final body = queryText.startsWith('-') ? queryText.substring(1) : queryText;
    if (body.startsWith('language:')) {
      next.removeWhere((chip) {
        final text = chip.queryText.startsWith('-')
            ? chip.queryText.substring(1)
            : chip.queryText;
        return text.startsWith('language:');
      });
    }
    if (!next.any((chip) => chip.queryText == queryText)) {
      next.add(_QueryChip(queryText, label));
    }
    setState(() => _chips = next);
    _controller.clear();
    if (keepFocus) _focus.requestFocus();
    widget.onQueryChanged(next.map((chip) => chip.queryText).join(' '));
    _showIdleSuggestions();
  }

  void _removeAt(int index) {
    final next = [..._chips]..removeAt(index);
    setState(() => _chips = next);
    widget.onQueryChanged(next.map((chip) => chip.queryText).join(' '));
    if (_draftInput(_controller.text).isEmpty) _showIdleSuggestions();
  }

  String _chipLabel(String queryText) {
    final negative = queryText.startsWith('-');
    final body = negative ? queryText.substring(1) : queryText;
    final colon = body.indexOf(':');
    if (colon <= 0) return queryText;
    final namespace = body.substring(0, colon);
    final kind = HitomiService.tagNamespaces[namespace] ?? 'Etiqueta';
    if (negative) return 'Excluir $kind: $body';
    return '$kind: $body';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final draft = _controller.text.trim();
    final typing = _draftInput(draft).isNotEmpty;
    final blocked = typing && _draftBlocked(draft);
    final popular = widget.showPopular && !typing;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SearchBarField(
          controller: _controller,
          focusNode: _focus,
          hintText: 'Etiqueta o título: big breasts, artist:nombre',
          onChanged: _onDraftChanged,
          onSubmitted: (_) => _commitDraft(),
          onClear: () {
            _controller.clear();
            _onDraftChanged('');
          },
        ),
        if (_chips.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (var i = 0; i < _chips.length; i++)
                InputChip(
                  label: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: MediaQuery.sizeOf(context).width - 96,
                    ),
                    child: Text(
                      _chips[i].label,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  onDeleted: () => _removeAt(i),
                  deleteButtonTooltipMessage: 'Quitar etiqueta',
                ),
              TextButton(
                onPressed: () => clear(),
                child: const Text('Limpiar etiquetas'),
              ),
            ],
          ),
        ],
        const SizedBox(height: 6),
        Align(
          alignment: Alignment.centerRight,
          child: widget.trailing ?? const SizedBox.shrink(),
        ),
        if (popular) ...[
          const SizedBox(height: 8),
          Text('Más buscadas', style: theme.textTheme.labelLarge),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final entry in HitomiService.popularTagGroups.entries) ...[
                  ChoiceChip(
                    label: Text(entry.value),
                    selected: _popularField == entry.key,
                    onSelected: (_) {
                      if (_popularField == entry.key) return;
                      setState(() => _popularField = entry.key);
                      unawaited(_load(_fieldQuery(entry.key), popular: true));
                    },
                  ),
                  const SizedBox(width: 6),
                ],
              ],
            ),
          ),
        ],
        if (typing && !blocked) ...[
          const SizedBox(height: 8),
          _SuggestionRow(
            title: 'Buscar título: $draft',
            subtitle: 'Conserva las etiquetas ya elegidas',
            icon: Icons.search_rounded,
            onTap: _commitDraft,
          ),
        ],
        if (blocked)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Esa etiqueta no está disponible.',
              style: theme.textTheme.bodySmall,
            ),
          ),
        if (_loading)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: LinearProgressIndicator(minHeight: 2),
          ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(_error!, style: theme.textTheme.bodySmall),
          ),
        if (!blocked && _suggestions.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            popular ? 'Pulsa para añadir' : 'Sugerencias',
            style: theme.textTheme.labelLarge,
          ),
          const SizedBox(height: 6),
          for (final item in _suggestions) ...[
            _SuggestionRow(
              title: item.caption,
              trailing: item.countLabel,
              onTap: () => _select(item),
            ),
            const SizedBox(height: 4),
          ],
        ] else if (!_loading && _error == null && typing && !blocked)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Sin etiquetas para «$draft».',
              style: theme.textTheme.bodySmall,
            ),
          )
        else if (!_loading && _error == null && popular && _suggestions.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'No hay etiquetas para mostrar.',
              style: theme.textTheme.bodySmall,
            ),
          ),
      ],
    );
  }
}

class _SuggestionRow extends StatelessWidget {
  final String title;
  final String? subtitle;
  final String? trailing;
  final IconData? icon;
  final VoidCallback onTap;

  const _SuggestionRow({
    required this.title,
    required this.onTap,
    this.subtitle,
    this.trailing,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              if (icon != null) ...[
                Icon(icon, size: 18, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (subtitle != null)
                      Text(subtitle!, style: theme.textTheme.bodySmall),
                  ],
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: 8),
                Text(trailing!, style: theme.textTheme.bodySmall),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
