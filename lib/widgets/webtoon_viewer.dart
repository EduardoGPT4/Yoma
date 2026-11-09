import 'package:flutter/material.dart';

/// Dos slivers centrados en la página inicial permiten retomar sin cargar
/// las dimensiones de todos los elementos anteriores.
class WebtoonViewer extends StatefulWidget {
  final int initialPage;
  final List<String> pages;
  final ImageProvider Function(String) imageProvider;
  final ValueChanged<int> onPageChanged;
  final ValueChanged<int> onLoaded;
  final Widget Function(Object) errorBuilder;
  const WebtoonViewer({
    super.key,
    required this.initialPage,
    required this.pages,
    required this.imageProvider,
    required this.onPageChanged,
    required this.onLoaded,
    required this.errorBuilder,
  });
  @override
  State<WebtoonViewer> createState() => _WebtoonViewerState();
}

class _WebtoonViewerState extends State<WebtoonViewer> {
  final _center = GlobalKey();
  final Map<int, GlobalKey> _keys = {};
  bool _scheduled = false;
  int _current = -1;
  void _measure() {
    if (_scheduled) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (!mounted) return;
      final viewport = context.findRenderObject() as RenderBox?;
      if (viewport == null || !viewport.hasSize) return;
      final line = viewport.localToGlobal(Offset.zero).dy + 80;
      for (final entry in _keys.entries) {
        final box =
            entry.value.currentContext?.findRenderObject() as RenderBox?;
        if (box == null || !box.hasSize) continue;
        final y = box.localToGlobal(Offset.zero).dy;
        if (y <= line && y + box.size.height > line && _current != entry.key) {
          _current = entry.key;
          widget.onPageChanged(entry.key);
          break;
        }
      }
    });
  }

  Widget _page(int index) {
    return SizedBox(
      key: _keys.putIfAbsent(index, () => GlobalKey()),
      width: double.infinity,
      child: Image(
        image: widget.imageProvider(widget.pages[index]),
        fit: BoxFit.fitWidth,
        frameBuilder: (context, child, frame, sync) {
          if (frame != null || sync) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) widget.onLoaded(index);
            });
            _measure();
          }
          return child;
        },
        loadingBuilder: (context, child, progress) => progress == null
            ? child
            : const SizedBox(
                height: 400,
                child: Center(child: CircularProgressIndicator()),
              ),
        errorBuilder: (_, error, _) =>
            SizedBox(height: 360, child: widget.errorBuilder(error)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final anchor = widget.initialPage.clamp(0, widget.pages.length - 1);
    _measure();
    return NotificationListener<ScrollNotification>(
      onNotification: (_) {
        _measure();
        return false;
      },
      child: CustomScrollView(
        center: _center,
        slivers: [
          if (anchor > 0)
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) => _page(anchor - index - 1),
                childCount: anchor,
              ),
            ),
          SliverList(
            key: _center,
            delegate: SliverChildBuilderDelegate(
              (context, index) => _page(anchor + index),
              childCount: widget.pages.length - anchor,
            ),
          ),
        ],
      ),
    );
  }
}
