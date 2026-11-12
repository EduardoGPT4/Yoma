part of '../native_anime_screen.dart';

// Explorar: catálogo con filtros y temporadas.

class _AnimeCatalog extends StatefulWidget {
  final AnimeController app;
  final ValueChanged<String> detail;
  const _AnimeCatalog({required this.app, required this.detail});
  @override
  State<_AnimeCatalog> createState() => _AnimeCatalogState();
}

class _AnimeCatalogState extends State<_AnimeCatalog> {
  late final _query = TextEditingController(text: widget.app.query);
  final _focus = FocusNode();
  Timer? _debounce;
  @override
  void didUpdateWidget(covariant _AnimeCatalog oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_focus.hasFocus && _query.text != widget.app.query) {
      _query.text = widget.app.query;
    }
  }

  Future<void> _filters() async {
    final app = widget.app, meta = app.catalog ?? app.front;
    var category = app.category,
        season = app.season,
        year = app.year,
        genre = app.genre,
        order = app.order;
    final applied = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => SafeArea(
          child: ListView(
            shrinkWrap: true,
            padding: EdgeInsets.fromLTRB(
              20,
              0,
              20,
              20 + MediaQuery.viewInsetsOf(c).bottom,
            ),
            children: [
              Text('Explorar anime', style: Theme.of(c).textTheme.titleLarge),
              const SizedBox(height: 18),
              _drop(
                'Formato',
                category,
                meta?.categories ?? [],
                (v) => set(() => category = v),
              ),
              _drop(
                'Temporada',
                season,
                meta?.seasons ?? [],
                (v) => set(() => season = v),
              ),
              _drop('Año', year, meta?.years ?? [], (v) => set(() => year = v)),
              _drop(
                'Género',
                genre,
                meta?.genres ?? [],
                (v) => set(() => genre = v),
              ),
              DropdownButtonFormField<String>(
                initialValue: order,
                decoration: const InputDecoration(labelText: 'Orden'),
                items: const [
                  DropdownMenuItem(
                    value: 'recent',
                    child: Text('Recién añadidos'),
                  ),
                  DropdownMenuItem(value: 'title', child: Text('Nombre A–Z')),
                  DropdownMenuItem(
                    value: 'title_desc',
                    child: Text('Nombre Z–A'),
                  ),
                  DropdownMenuItem(
                    value: 'updated',
                    child: Text('Última actualización'),
                  ),
                  DropdownMenuItem(
                    value: 'episodes',
                    child: Text('Episodios disponibles'),
                  ),
                ],
                onChanged: (v) => set(() => order = v!),
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: () => Navigator.pop(c, true),
                child: const Text('Aplicar'),
              ),
              TextButton(
                onPressed: () {
                  set(() {
                    category = '';
                    season = '';
                    year = '';
                    genre = '';
                    order = 'recent';
                  });
                },
                child: const Text('Restablecer filtros'),
              ),
            ],
          ),
        ),
      ),
    );
    if (applied == true) {
      app.category = category;
      app.season = season;
      app.year = year;
      app.genre = genre;
      app.order = order;
      await app.search();
    }
  }

  Widget _drop(
    String label,
    String value,
    List<String> choices,
    ValueChanged<String> onChange,
  ) {
    final all = {'', ...choices, if (value.isNotEmpty) value}.toList();
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: DropdownButtonFormField<String>(
        initialValue: value,
        isExpanded: true,
        decoration: InputDecoration(labelText: label),
        items: all
            .map(
              (v) => DropdownMenuItem(
                value: v,
                child: Text(
                  v.isEmpty ? 'Todos' : v,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            )
            .toList(),
        onChanged: (v) => onChange(v!),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _query,
                  focusNode: _focus,
                  decoration: InputDecoration(
                    hintText: 'Buscar anime',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _query.text.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'Limpiar búsqueda',
                            onPressed: () {
                              _query.clear();
                              app.query = '';
                              app.search();
                            },
                            icon: const Icon(Icons.close),
                          ),
                  ),
                  onChanged: (value) {
                    app.query = value;
                    _debounce?.cancel();
                    _debounce = Timer(
                      const Duration(milliseconds: 400),
                      app.search,
                    );
                  },
                  onSubmitted: (_) {
                    _debounce?.cancel();
                    app.search();
                  },
                ),
              ),
              IconButton(
                tooltip: 'Filtros de anime',
                onPressed: _filters,
                icon: const Icon(Icons.tune),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              // Con letra grande los chips bajan de línea en vez de desbordar.
              Expanded(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    ChoiceChip(
                      label: const Text('Catálogo'),
                      selected: !app.seasonal,
                      onSelected: (_) {
                        app.seasonal = false;
                        app.search();
                      },
                    ),
                    ChoiceChip(
                      label: const Text('Temporadas'),
                      selected: app.seasonal,
                      onSelected: (_) {
                        app.seasonal = true;
                        app.search();
                      },
                    ),
                  ],
                ),
              ),
              Text(
                '${app.catalog?.total ?? 0}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
        if (app.searching) const LinearProgressIndicator(minHeight: 2),
        Expanded(
          child: app.catalogItems.isEmpty && !app.searching
              ? const AnimeMessage('No hay títulos para estos filtros.')
              : CustomScrollView(
                  key: const PageStorageKey('anime-catalog-scroll'),
                  slivers: [
                    SliverPadding(
                      padding: const EdgeInsets.all(16),
                      sliver: SliverGrid.builder(
                        gridDelegate:
                            const SliverGridDelegateWithMaxCrossAxisExtent(
                              maxCrossAxisExtent: 190,
                              mainAxisSpacing: 20,
                              crossAxisSpacing: 14,
                              childAspectRatio: .56,
                            ),
                        itemCount: app.catalogItems.length,
                        itemBuilder: (_, i) => AnimeCard(
                          anime: app.catalogItems[i],
                          onTap: () => widget.detail(app.catalogItems[i].slug),
                          favorite: app.isFavorite(app.catalogItems[i].slug),
                        ),
                      ),
                    ),
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                        child: app.loadingMore
                            ? const Center(child: CircularProgressIndicator())
                            : app.catalog != null &&
                                  app.catalog!.page < app.catalog!.pages
                            ? OutlinedButton(
                                onPressed: app.more,
                                child: const Text('Cargar más'),
                              )
                            : const SizedBox.shrink(),
                      ),
                    ),
                  ],
                ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    _focus.dispose();
    super.dispose();
  }
}
