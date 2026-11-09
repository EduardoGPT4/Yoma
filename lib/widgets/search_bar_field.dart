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
    final theme = Theme.of(context);
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
          decoration: InputDecoration(
            hintText: hintText,
            prefixIcon: Icon(
              Icons.search_rounded,
              color: theme.colorScheme.primary.withAlpha(200),
            ),
            suffixIcon: value.text.isEmpty
                ? null
                : IconButton(
                    onPressed: onClear,
                    icon: const Icon(Icons.close_rounded),
                  ),
            isDense: true,
            filled: true,
            fillColor: theme.colorScheme.surfaceContainerHighest,
            contentPadding: EdgeInsets.symmetric(
              horizontal: 12,
              vertical: metrics.searchVerticalPadding,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: theme.colorScheme.onSurface.withAlpha(28),
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: theme.colorScheme.onSurface.withAlpha(28),
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: theme.colorScheme.primary,
                width: 1.5,
              ),
            ),
          ),
        );
      },
    );
  }
}
