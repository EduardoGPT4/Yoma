import 'package:flutter/material.dart';

import '../design/yoma_tokens.dart';

/// Encabezado de sección compartido por YomaShi y YomaTV.
class SectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? trailing;
  final Widget? trailingWidget;

  const SectionHeader({
    super.key,
    required this.icon,
    required this.title,
    this.trailing,
    this.trailingWidget,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      children: [
        Icon(icon, size: YomaSizes.iconSm, color: theme.colorScheme.primary),
        const SizedBox(width: YomaSpacing.sm),
        Expanded(
          child: Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        if (trailingWidget != null)
          trailingWidget!
        else if (trailing != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withAlpha(28),
              borderRadius: BorderRadius.circular(YomaRadii.pill),
            ),
            child: Text(
              trailing!,
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
          ),
      ],
    );
  }
}
