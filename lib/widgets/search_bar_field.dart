import 'package:flutter/material.dart';

import 'app_metrics.dart';

class SearchBarField extends StatelessWidget {
  final TextEditingController controller;
  final String hintText;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onClear;
  final ValueChanged<String>? onSubmitted;
  final FocusNode? focusNode;

  const SearchBarField({
    super.key,
    required this.controller,
    required this.hintText,
    this.onChanged,
    this.onClear,
    this.onSubmitted,
    this.focusNode,
  });

  @override
  Widget build(BuildContext context) {
    final metrics = AppMetrics.of(context);

    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        return TextField(
          controller: controller,
          focusNode: focusNode,
          onChanged: onChanged,
          onSubmitted: onSubmitted,
          textInputAction: onSubmitted == null
              ? TextInputAction.done
              : TextInputAction.search,
          // Colores, bordes y radios vienen del tema de Yoma (igual que en
          // la búsqueda de YomaTV); aquí solo se ajusta la densidad.
          decoration: InputDecoration(
            hintText: hintText,
            prefixIcon: const Icon(Icons.search_rounded),
            suffixIcon: value.text.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Limpiar búsqueda',
                    onPressed: onClear,
                    icon: const Icon(Icons.close_rounded),
                  ),
            isDense: true,
            contentPadding: EdgeInsets.symmetric(
              horizontal: 12,
              vertical: metrics.searchVerticalPadding,
            ),
          ),
        );
      },
    );
  }
}
