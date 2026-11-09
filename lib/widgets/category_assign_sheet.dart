import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/categories_provider.dart';

class CategoryAssignSheet extends StatefulWidget {
  final String mangaKey;
  final String mangaTitle;

  const CategoryAssignSheet({
    super.key,
    required this.mangaKey,
    required this.mangaTitle,
  });

  static Future<void> show({
    required BuildContext context,
    required String mangaKey,
    required String mangaTitle,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) =>
          CategoryAssignSheet(mangaKey: mangaKey, mangaTitle: mangaTitle),
    );
  }

  @override
  State<CategoryAssignSheet> createState() => _CategoryAssignSheetState();
}

class _CategoryAssignSheetState extends State<CategoryAssignSheet> {
  final TextEditingController _nameController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final categories = context.watch<CategoriesProvider>().categories;

    return SafeArea(
      child: SingleChildScrollView(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            12,
            20,
            20 + MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.onSurface.withAlpha(60),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Categorías',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                widget.mangaTitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurface.withAlpha(170),
                ),
              ),
              const SizedBox(height: 14),
              ...categories.map((category) {
                final selected = context
                    .read<CategoriesProvider>()
                    .isMangaInCategory(category.id, widget.mangaKey);
                return CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: selected,
                  onChanged: (_) {
                    context.read<CategoriesProvider>().toggleMangaInCategory(
                      category.id,
                      widget.mangaKey,
                    );
                  },
                  title: Text(category.name),
                  secondary: Text('${category.mangaKeys.length}'),
                );
              }),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _nameController,
                      decoration: const InputDecoration(
                        hintText: 'Nueva categoría',
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.tonal(
                    onPressed: () async {
                      final name = _nameController.text.trim();
                      if (name.isEmpty) {
                        return;
                      }
                      try {
                        await context.read<CategoriesProvider>().createCategory(
                          name,
                        );
                        if (!mounted) return;
                        _nameController.clear();
                      } catch (_) {
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'No se pudo guardar la categoría. Reinténtalo.',
                            ),
                          ),
                        );
                      }
                    },
                    child: const Text('Crear'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
