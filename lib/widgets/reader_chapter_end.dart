import 'package:flutter/material.dart';

class ReaderChapterEnd extends StatelessWidget {
  final String? nextTitle;
  final bool hasMore, offline;
  final VoidCallback onNext, onExit;
  const ReaderChapterEnd({
    super.key,
    this.nextTitle,
    required this.hasMore,
    required this.offline,
    required this.onNext,
    required this.onExit,
  });
  @override
  Widget build(BuildContext context) {
    final next = nextTitle != null || hasMore;
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              next ? 'Fin del capítulo' : 'Estás al día',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              nextTitle ??
                  (hasMore
                      ? 'Hay más capítulos por consultar en la fuente.'
                      : 'Llegaste al último capítulo disponible en esta lista.'),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            if (nextTitle != null)
              Text(
                offline ? 'Disponible sin conexión' : 'Requiere conexión',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            const SizedBox(height: 8),
            if (next)
              FilledButton.icon(
                onPressed: onNext,
                icon: const Icon(Icons.skip_next),
                label: Text(
                  nextTitle != null
                      ? 'Siguiente capítulo'
                      : 'Consultar siguientes capítulos',
                ),
              ),
            TextButton(
              onPressed: onExit,
              child: const Text('Salir del lector'),
            ),
          ],
        ),
      ),
    );
  }
}
