import 'dart:async';
import 'package:flutter/material.dart';
import 'cached_thumbnail.dart';

/// Dragging previews a bounded thumbnail; only releasing changes reading position.
class ReaderPageScrubber extends StatefulWidget {
  final List<String> pages;
  final int page;
  final ValueChanged<int> onCommit;
  final ValueChanged<bool> onInteraction;
  const ReaderPageScrubber({
    super.key,
    required this.pages,
    required this.page,
    required this.onCommit,
    required this.onInteraction,
  });
  @override
  State<ReaderPageScrubber> createState() => _ReaderPageScrubberState();
}

class _ReaderPageScrubberState extends State<ReaderPageScrubber> {
  double? _draft;
  int? _preview;
  Timer? _debounce;
  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  int _index(double value) => value.round().clamp(0, widget.pages.length - 1);
  void _previewAt(double value) {
    setState(() => _draft = value);
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 160), () {
      if (mounted) setState(() => _preview = _index(value));
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.pages.length < 2) return const SizedBox.shrink();
    final value = (_draft ?? widget.page.toDouble()).clamp(
      0.0,
      (widget.pages.length - 1).toDouble(),
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_draft != null)
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: 54,
                height: 72,
                child: _preview == null
                    ? const Icon(Icons.image_outlined)
                    : CachedThumbnail(
                        key: ValueKey(
                          widget.pages[_preview!.clamp(
                            0,
                            widget.pages.length - 1,
                          )],
                        ),
                        sourcePath: widget
                            .pages[_preview!.clamp(0, widget.pages.length - 1)],
                        size: 160,
                        fit: BoxFit.contain,
                        placeholderBuilder: (_) =>
                            const Icon(Icons.image_outlined),
                      ),
              ),
              const SizedBox(width: 12),
              Flexible(
                child: Text(
                  'Página ${_index(value) + 1} de ${widget.pages.length}',
                ),
              ),
            ],
          ),
        Slider(
          min: 0,
          max: (widget.pages.length - 1).toDouble(),
          divisions: widget.pages.length - 1,
          value: value,
          label: 'Pág. ${_index(value) + 1}',
          semanticFormatterCallback: (v) =>
              'Página ${_index(v) + 1} de ${widget.pages.length}',
          onChangeStart: (v) {
            widget.onInteraction(true);
            setState(() {
              _draft = v;
              _preview = null;
            });
          },
          onChanged: _previewAt,
          onChangeEnd: (v) {
            _debounce?.cancel();
            setState(() {
              _draft = null;
              _preview = null;
            });
            widget.onCommit(_index(v));
            widget.onInteraction(false);
          },
        ),
      ],
    );
  }
}
