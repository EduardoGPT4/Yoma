import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/chapter.dart';

class ChapterDrawer extends StatefulWidget {
  final List<Chapter> chapters;
  final int currentIndex;
  final ValueChanged<int> onSelect;

  const ChapterDrawer({
    super.key,
    required this.chapters,
    required this.currentIndex,
    required this.onSelect,
  });

  @override
  State<ChapterDrawer> createState() => _ChapterDrawerState();
}

class _ChapterDrawerState extends State<ChapterDrawer> {
  final _search = TextEditingController();
  final _scroll = ScrollController();
  String _query = '';
  bool _centerPending = true;
  bool _centerScheduled = false;

  @override
  void didUpdateWidget(covariant ChapterDrawer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentIndex != widget.currentIndex) {
      _centerPending = true;
    }
  }

  @override
  void dispose() {
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  bool _matches(Chapter chapter) {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return true;
    final number = num.tryParse(query);
    if (number == null) return chapter.title.toLowerCase().contains(query);
    final chapterNumber =
        num.tryParse(chapter.number ?? '') ??
        num.tryParse(
          RegExp(r'\d+(?:\.\d+)?').firstMatch(chapter.title)?[0] ?? '',
        );
    return chapterNumber == number;
  }

  void _showCurrent() {
    _search.clear();
    setState(() {
      _query = '';
      _centerPending = true;
    });
    FocusScope.of(context).unfocus();
  }

  void _centerCurrent(List<int> indexes, double extent, double viewport) {
    if (!_centerPending || _centerScheduled) return;
    _centerScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _centerScheduled = false;
      if (!mounted || !_centerPending || !_scroll.hasClients) return;
      final position = indexes.indexOf(widget.currentIndex);
      if (position < 0) return;
      final target = position * extent - (viewport - extent) / 2;
      _scroll.jumpTo(
        target.clamp(0, _scroll.position.maxScrollExtent).toDouble(),
      );
      _centerPending = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final indexes = [
      for (var i = 0; i < widget.chapters.length; i++)
        if (_matches(widget.chapters[i])) i,
    ];
    final textScaler = MediaQuery.textScalerOf(context);
    // Scale a fixed extent so enlarged text fits and a long list opens at the
    // current chapter without building all preceding rows.
    final extent = math.max(
      80.0,
      textScaler.scale(16) * 2.4 + textScaler.scale(12) * 1.3 + 24,
    );

    return Drawer(
      backgroundColor: theme.colorScheme.surface,
      surfaceTintColor: Colors.transparent,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 8, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text('Capítulos', style: theme.textTheme.titleLarge),
                  ),
                  IconButton(
                    tooltip: 'Cerrar capítulos',
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _search,
                decoration: InputDecoration(
                  hintText: 'Buscar título o número',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Limpiar búsqueda',
                          onPressed: _showCurrent,
                          icon: const Icon(Icons.close),
                        ),
                ),
                onChanged: (value) {
                  setState(() {
                    _query = value;
                    _centerPending = false;
                  });
                  if (_scroll.hasClients) _scroll.jumpTo(0);
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
              child: Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                children: [
                  Text(
                    '${indexes.length} ${indexes.length == 1 ? 'capítulo' : 'capítulos'}',
                  ),
                  TextButton.icon(
                    onPressed: widget.chapters.isEmpty ? null : _showCurrent,
                    icon: const Icon(Icons.my_location, size: 18),
                    label: const Text('Ir al actual'),
                  ),
                ],
              ),
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  _centerCurrent(indexes, extent, constraints.maxHeight);
                  if (indexes.isEmpty) {
                    return const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text('No se encontraron capítulos.'),
                      ),
                    );
                  }
                  return ListView.builder(
                    controller: _scroll,
                    itemExtent: extent,
                    itemCount: indexes.length,
                    itemBuilder: (context, position) {
                      final index = indexes[position];
                      final chapter = widget.chapters[index];
                      final selected = index == widget.currentIndex;
                      return Semantics(
                        selected: selected,
                        child: Ink(
                          decoration: BoxDecoration(
                            color: selected
                                ? theme.colorScheme.primary.withAlpha(32)
                                : Colors.transparent,
                            border: Border(
                              left: BorderSide(
                                color: selected
                                    ? theme.colorScheme.primary
                                    : Colors.transparent,
                                width: 4,
                              ),
                            ),
                          ),
                          child: ListTile(
                            selected: selected,
                            selectedColor: theme.colorScheme.onSurface,
                            title: Text(
                              chapter.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              chapter.pageCount > 0
                                  ? '${chapter.pageCount} páginas'
                                  : 'Páginas al abrir',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: selected
                                ? Icon(
                                    Icons.play_arrow,
                                    semanticLabel: 'Capítulo actual',
                                    color: theme.colorScheme.primary,
                                  )
                                : null,
                            onTap: () => widget.onSelect(index),
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
