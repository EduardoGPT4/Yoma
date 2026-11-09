import 'package:flutter/material.dart';

class FilterIconButton extends StatelessWidget {
  final bool active;
  final VoidCallback onPressed;

  const FilterIconButton({
    super.key,
    required this.active,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Stack(
      clipBehavior: Clip.none,
      children: [
        FilledButton.tonalIcon(
          onPressed: onPressed,
          icon: const Icon(Icons.tune_rounded),
          label: Text(active ? 'Filtros activos' : 'Filtros'),
        ),
        if (active)
          Positioned(
            top: 6,
            right: 6,
            child: Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: theme.colorScheme.primary,
                shape: BoxShape.circle,
                border: Border.all(
                  color: theme.colorScheme.surface,
                  width: 1.5,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
