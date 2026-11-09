import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../providers/profile_provider.dart';
import 'anime_screen.dart';
import 'data/anime_controller.dart';
import 'models/anime_models.dart';
import 'screens/anime_detail_screen.dart';
import 'screens/anime_mal_screen.dart';
import 'screens/anime_player_screen.dart';
import 'widgets/anime_widgets.dart';

class NativeAnimeScreen extends StatefulWidget {
  final bool active;
  final VoidCallback home;
  final AnimeController? controller;
  final List<NavigatorObserver> navigatorObservers;
  const NativeAnimeScreen({
    super.key,
    required this.active,
    required this.home,
    this.controller,
    this.navigatorObservers = const [],
  });
  @override
  State<NativeAnimeScreen> createState() => NativeAnimeScreenState();
}

class NativeAnimeScreenState extends State<NativeAnimeScreen> {
  final _navigator = GlobalKey<NavigatorState>();
  late final AnimeController app = widget.controller ?? AnimeController();
  @override
  void initState() {
    super.initState();
    unawaited(app.initialize());
  }

  @override
  void didUpdateWidget(covariant NativeAnimeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active != oldWidget.active) app.setActive(widget.active);
  }

  void _web({AnimeEpisode? episode}) => _navigator.currentState!.push(
    MaterialPageRoute<void>(
      builder: (_) => AnimeScreen(
        active: true,
        syncMal: false,
        initialUrl: episode == null
            ? null
            : Uri.parse(
                'https://hk-br035.gt.tc/seasonav1/#watch/${episode.id}',
              ),
      ),
    ),
  );
  void _detail(String slug) => _navigator.currentState!.push(
    MaterialPageRoute<void>(
      builder: (_) => AnimeDetailScreen(
        controller: app,
        slug: slug,
        play: _play,
        openSeason: _detail,
        openWeb: () => _web(),
      ),
    ),
  );
  void _play(AnimeDetail detail, AnimeEpisode episode) =>
      _navigator.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => AnimePlayerScreen(
            controller: app,
            detail: detail,
            episode: episode,
            openWeb: (e) => _web(episode: e),
          ),
        ),
      );
  Future<bool> goBack() async {
    if (await (_navigator.currentState?.maybePop() ?? Future.value(false))) {
      return true;
    }
    if (app.tab != 0) {
      app.selectTab(0);
      return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) => Theme(
    data: ThemeData.dark(useMaterial3: true).copyWith(
      colorScheme: const ColorScheme.dark(
        primary: Color(0xFFFF6A55),
        secondary: Color(0xFFAEE6C9),
        surface: Color(0xFF1B1925),
        onSurface: Color(0xFFF4EEE5),
        onPrimary: Color(0xFF160C09),
      ),
      scaffoldBackgroundColor: const Color(0xFF0E0D14),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFF0E0D14),
        foregroundColor: Color(0xFFF4EEE5),
        surfaceTintColor: Colors.transparent,
      ),
      navigationBarTheme: const NavigationBarThemeData(
        backgroundColor: Color(0xFF17141F),
        indicatorColor: Color(0xFF52332F),
        iconTheme: WidgetStatePropertyAll(
          IconThemeData(color: Color(0xFFF4EEE5)),
        ),
      ),
    ),
    child: Navigator(
      key: _navigator,
      observers: widget.navigatorObservers,
      onGenerateRoute: (_) => MaterialPageRoute<void>(
        builder: (_) => _AnimeMain(
          app: app,
          detail: _detail,
          play: _play,
          web: () => _web(),
          home: widget.home,
          mal: () => _navigator.currentState!.push(
            MaterialPageRoute<void>(
              builder: (_) =>
                  AnimeMalScreen(controller: app, home: widget.home),
            ),
          ),
        ),
      ),
    ),
  );
  @override
  void dispose() {
    if (widget.controller == null) app.dispose();
    super.dispose();
  }
}

class _AnimeMain extends StatelessWidget {
  final AnimeController app;
  final ValueChanged<String> detail;
  final void Function(AnimeDetail, AnimeEpisode) play;
  final VoidCallback web, home, mal;
  const _AnimeMain({
    required this.app,
    required this.detail,
    required this.play,
    required this.web,
    required this.home,
    required this.mal,
  });
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: app,
    builder: (context, _) => Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(9),
              child: Image.asset(
                'assets/branding/1-Anime.png',
                width: 34,
                height: 34,
                fit: BoxFit.cover,
              ),
            ),
            const SizedBox(width: 10),
            const Text('YomaTV', style: TextStyle(fontWeight: FontWeight.w800)),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Buscar anime',
            onPressed: () => app.selectTab(1),
            icon: const Icon(Icons.search),
          ),
          IconButton(
            tooltip: 'MyAnimeList de Anime',
            onPressed: mal,
            icon: const Icon(Icons.account_circle_outlined),
          ),
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'web') web();
              if (v == 'refresh') {
                app.loadFront();
                app.search();
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'refresh',
                child: Text('Actualizar catálogo'),
              ),
              PopupMenuItem(value: 'web', child: Text('YomaTV Web · respaldo')),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          if (app.loading) const LinearProgressIndicator(),
          if (app.error != null)
            MaterialBanner(
              content: Text(
                app.error!,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    app.error = null;
                    app.changed();
                  },
                  child: const Text('Cerrar'),
                ),
                TextButton(
                  onPressed: () {
                    app.loadFront();
                    app.search();
                  },
                  child: const Text('Reintentar'),
                ),
              ],
            ),
          Expanded(
            child: IndexedStack(
              index: app.tab,
              children: [
                _AnimeHome(app: app, detail: detail, play: play),
                _AnimeCatalog(app: app, detail: detail),
                _AnimeLibrary(app: app, detail: detail, play: play),
                _AnimeDownloads(app: app, play: play),
                _AnimeMore(
                  app: app,
                  detail: detail,
                  play: play,
                  web: web,
                  home: home,
                  mal: mal,
                ),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: app.tab,
        onDestinationSelected: app.selectTab,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.explore_outlined),
            selectedIcon: Icon(Icons.explore),
            label: 'Inicio',
          ),
          NavigationDestination(icon: Icon(Icons.search), label: 'Explorar'),
          NavigationDestination(
            icon: Icon(Icons.bookmarks_outlined),
            label: 'Biblioteca',
          ),
          NavigationDestination(
            icon: Icon(Icons.download_outlined),
            label: 'Descargas',
          ),
          NavigationDestination(icon: Icon(Icons.tune), label: 'Más'),
        ],
      ),
    ),
  );
}

class _AnimeHome extends StatelessWidget {
  final AnimeController app;
  final ValueChanged<String> detail;
  final void Function(AnimeDetail, AnimeEpisode) play;
  const _AnimeHome({
    required this.app,
    required this.detail,
    required this.play,
  });
  Future<void> _resume(BuildContext context, Map<String, dynamic> row) async {
    try {
      final d = await app.detail('${row['slug']}');
      final ep = AnimeEpisode.fromJson(animeMap(row['episode']));
      play(d, ep);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  Widget _shelf(BuildContext context, String title, List<AnimeTitle> items) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 14),
            child: Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          SizedBox(
            height: 260,
            child: ListView.separated(
              key: PageStorageKey(title),
              padding: const EdgeInsets.symmetric(horizontal: 20),
              scrollDirection: Axis.horizontal,
              itemCount: items.length,
              separatorBuilder: (_, _) => const SizedBox(width: 14),
              itemBuilder: (_, i) => SizedBox(
                width: 145,
                child: AnimeCard(
                  anime: items[i],
                  onTap: () => detail(items[i].slug),
                  favorite: app.isFavorite(items[i].slug),
                ),
              ),
            ),
          ),
        ],
      );
  @override
  Widget build(BuildContext context) {
    final recent = app.front?.items ?? [];
    final airing = recent.where((a) => a.active).toList();
    return RefreshIndicator(
      onRefresh: app.loadFront,
      child: CustomScrollView(
        key: const PageStorageKey('anime-home'),
        slivers: [
          if (recent.isNotEmpty)
            SliverToBoxAdapter(
              child: SizedBox(
                height: 340,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    animeArtwork(recent.first.cover, width: 900),
                    const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Colors.black26, Color(0xFF0E0D14)],
                        ),
                      ),
                    ),
                    Positioned(
                      left: 22,
                      right: 22,
                      bottom: 16,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            [
                              recent.first.category,
                              recent.first.season,
                            ].where((e) => e.isNotEmpty).join(' · '),
                            style: const TextStyle(color: Color(0xFFAEE6C9)),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            recent.first.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.headlineMedium
                                ?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white,
                                ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            recent.first.synopsis,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Color(0xFFE0DCE5)),
                          ),
                          const SizedBox(height: 16),
                          FilledButton.icon(
                            onPressed: () => detail(recent.first.slug),
                            icon: const Icon(Icons.play_arrow),
                            label: const Text('Ver episodios'),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (app.continuing.isNotEmpty)
            SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
                    child: Text(
                      'Continuar viendo',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  SizedBox(
                    height: 170,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      itemCount: app.continuing.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 12),
                      itemBuilder: (context, i) {
                        final row = app.continuing[i],
                            anime = AnimeTitle.fromJson(animeMap(row['anime']));
                        final duration = animeInt(row['durationMs']);
                        return SizedBox(
                          width: 265,
                          child: Card(
                            clipBehavior: Clip.antiAlias,
                            child: InkWell(
                              onTap: () => _resume(context, row),
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  animeArtwork(anime.cover, width: 420),
                                  const DecoratedBox(
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        colors: [
                                          Colors.black87,
                                          Colors.black12,
                                        ],
                                      ),
                                    ),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.all(16),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      mainAxisAlignment: MainAxisAlignment.end,
                                      children: [
                                        Text(
                                          anime.title,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            color: Colors.white,
                                          ),
                                        ),
                                        Text(
                                          'Episodio ${animeMap(row['episode'])['number']}',
                                          style: const TextStyle(
                                            color: Colors.white,
                                          ),
                                        ),
                                        const SizedBox(height: 10),
                                        LinearProgressIndicator(
                                          value: duration <= 0
                                              ? 0
                                              : (animeInt(row['positionMs']) /
                                                        duration)
                                                    .clamp(0, 1),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          if (recent.isNotEmpty)
            SliverToBoxAdapter(
              child: _shelf(context, 'Recién añadidos', recent),
            ),
          if (airing.isNotEmpty)
            SliverToBoxAdapter(child: _shelf(context, 'En emisión', airing)),
          if (recent.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: AnimeMessage(
                app.loading
                    ? 'Preparando tu espacio de anime…'
                    : 'El catálogo no está disponible ahora. Tu biblioteca local sigue accesible.',
                action: 'Actualizar',
                onAction: app.loadFront,
              ),
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ],
      ),
    );
  }
}

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

class _AnimeLibrary extends StatefulWidget {
  final AnimeController app;
  final ValueChanged<String> detail;
  final void Function(AnimeDetail, AnimeEpisode) play;
  const _AnimeLibrary({
    required this.app,
    required this.detail,
    required this.play,
  });
  @override
  State<_AnimeLibrary> createState() => _AnimeLibraryState();
}

class _AnimeLibraryState extends State<_AnimeLibrary> {
  bool _favorites = false;
  String _status = '';
  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    final items =
        app.saved.values
            .where(
              (r) =>
                  (r['saved'] == true || r['favorite'] == true) &&
                  (!_favorites || r['favorite'] == true) &&
                  (_status.isEmpty || r['status'] == _status),
            )
            .map((r) => AnimeTitle.fromJson(animeMap(r['anime'])))
            .toList()
          ..sort((a, b) => a.title.compareTo(b.title));
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            children: [
              FilterChip(
                label: const Text('Favoritos'),
                selected: _favorites,
                onSelected: (v) => setState(() => _favorites = v),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: _status,
                  decoration: const InputDecoration(labelText: 'Estado'),
                  items: const [
                    DropdownMenuItem(value: '', child: Text('Todos')),
                    DropdownMenuItem(value: 'planned', child: Text('Planeado')),
                    DropdownMenuItem(value: 'watching', child: Text('Viendo')),
                    DropdownMenuItem(
                      value: 'completed',
                      child: Text('Completado'),
                    ),
                    DropdownMenuItem(value: 'paused', child: Text('En pausa')),
                    DropdownMenuItem(
                      value: 'dropped',
                      child: Text('Abandonado'),
                    ),
                  ],
                  onChanged: (v) => setState(() => _status = v!),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: items.isEmpty
              ? const AnimeMessage(
                  'Guarda títulos desde sus fichas para crear tu biblioteca local.',
                )
              : GridView.builder(
                  key: const PageStorageKey('anime-library'),
                  padding: const EdgeInsets.all(16),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 190,
                    mainAxisSpacing: 20,
                    crossAxisSpacing: 14,
                    childAspectRatio: .56,
                  ),
                  itemCount: items.length,
                  itemBuilder: (_, i) => GestureDetector(
                    onLongPress: () => _edit(items[i]),
                    child: AnimeCard(
                      anime: items[i],
                      favorite: app.isFavorite(items[i].slug),
                      onTap: () => widget.detail(items[i].slug),
                    ),
                  ),
                ),
        ),
        if (items.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(
              'Mantén pulsado para editar estado, notas y puntuación.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
      ],
    );
  }

  Future<void> _edit(AnimeTitle anime) async {
    final app = widget.app, row = app.saved[anime.slug] ?? {};
    var status = '${row['status'] ?? 'planned'}';
    var score = animeInt(row['score']).clamp(0, 10).toDouble();
    final notes = TextEditingController(text: '${row['notes'] ?? ''}');
    final result = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: Text(anime.title),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: status,
                  isExpanded: true,
                  items: const [
                    DropdownMenuItem(value: 'planned', child: Text('Planeado')),
                    DropdownMenuItem(value: 'watching', child: Text('Viendo')),
                    DropdownMenuItem(
                      value: 'completed',
                      child: Text('Completado'),
                    ),
                    DropdownMenuItem(value: 'paused', child: Text('En pausa')),
                    DropdownMenuItem(
                      value: 'dropped',
                      child: Text('Abandonado'),
                    ),
                  ],
                  onChanged: (v) => set(() => status = v!),
                ),
                const SizedBox(height: 14),
                Text(
                  score == 0
                      ? 'Sin puntuación'
                      : 'Puntuación: ${score.toInt()}',
                ),
                Slider(
                  value: score,
                  min: 0,
                  max: 10,
                  divisions: 10,
                  onChanged: (v) => set(() => score = v),
                ),
                TextField(
                  controller: notes,
                  maxLines: 4,
                  maxLength: 4000,
                  decoration: const InputDecoration(labelText: 'Notas'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );
    if (result == true) {
      await app.updateLibrary(
        anime,
        status: status,
        score: score.toInt(),
        notes: notes.text,
      );
    }
    notes.dispose();
  }
}

class _AnimeDownloads extends StatefulWidget {
  final AnimeController app;
  final void Function(AnimeDetail, AnimeEpisode) play;
  const _AnimeDownloads({required this.app, required this.play});
  @override
  State<_AnimeDownloads> createState() => _AnimeDownloadsState();
}

class _AnimeDownloadsState extends State<_AnimeDownloads> {
  String _filter = 'all';
  Future<void> _action(String action, {String? key, bool? value}) async {
    try {
      await widget.app.downloadControl(action, key: key, value: value);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  Future<void> _play(AnimeDownload d) async {
    final app = widget.app;
    final cache = await app.store.cache('detail:${d.slug}');
    final data = cache == null
        ? {
            'anime': d.raw,
            'episodes': app.downloads
                .where((x) => x.slug == d.slug)
                .map(
                  (x) => {
                    'id': x.raw['episode_id'],
                    'slug': x.slug,
                    'number': x.number,
                  },
                )
                .toList(),
          }
        : animeMap(cache['data']);
    final detail = AnimeDetail.fromJson({
      ...data,
      'local_language': d.language,
    });
    final episode = detail.episodes.firstWhere(
      (e) => e.id == animeInt(d.raw['episode_id']),
      orElse: () => AnimeEpisode.fromJson({
        'id': d.raw['episode_id'],
        'slug': d.slug,
        'number': d.number,
      }),
    );
    widget.play(detail, episode);
  }

  @override
  Widget build(BuildContext context) {
    final app = widget.app, all = app.downloads;
    final jobs = all
        .where(
          (d) => _filter == 'all' || (_filter == 'done' ? d.ready : !d.ready),
        )
        .toList();
    final used = all.fold<int>(0, (n, d) => n + d.bytes);
    return RefreshIndicator(
      onRefresh: app.refreshDownloads,
      child: ListView(
        key: const PageStorageKey('anime-downloads'),
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            'Descargas',
            style: Theme.of(
              context,
            ).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          const Text('Tus episodios, donde quieras.'),
          const SizedBox(height: 20),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  const Icon(Icons.storage_outlined, size: 36),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${animeBytes(used)} utilizados',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        Text(
                          '${all.where((d) => d.ready).length} episodios completos',
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Actualizar descargas',
                    onPressed: app.refreshDownloads,
                    icon: const Icon(Icons.refresh),
                  ),
                ],
              ),
            ),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Descargar solo con Wi-Fi'),
            value: app.wifiOnly,
            onChanged: app.supportedDownloads
                ? (v) => _action('wifi', value: v)
                : null,
          ),
          if (app.downloadError != null)
            Text(
              app.downloadError!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          if (!app.supportedDownloads)
            const AnimeMessage(
              'Las descargas nativas requieren Android 8 o posterior.',
            ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ChoiceChip(
                label: const Text('Todas'),
                selected: _filter == 'all',
                onSelected: (_) => setState(() => _filter = 'all'),
              ),
              ChoiceChip(
                label: const Text('En curso'),
                selected: _filter == 'active',
                onSelected: (_) => setState(() => _filter = 'active'),
              ),
              ChoiceChip(
                label: const Text('Completadas'),
                selected: _filter == 'done',
                onSelected: (_) => setState(() => _filter = 'done'),
              ),
              if (all.isNotEmpty)
                OutlinedButton.icon(
                  onPressed: () =>
                      _action(app.paused ? 'resumeAll' : 'pauseAll'),
                  icon: Icon(app.paused ? Icons.play_arrow : Icons.pause),
                  label: Text(app.paused ? 'Reanudar cola' : 'Pausar cola'),
                ),
            ],
          ),
          const SizedBox(height: 16),
          if (jobs.isEmpty)
            const AnimeMessage(
              'Descarga episodios desde una ficha o el reproductor para verlos aquí.',
            ),
          for (final d in jobs)
            Card(
              child: ListTile(
                contentPadding: const EdgeInsets.all(14),
                leading: SizedBox(
                  width: 45,
                  height: 64,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: animeArtwork('${d.raw['cover'] ?? ''}', width: 120),
                  ),
                ),
                title: Text(
                  d.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Episodio ${d.number} · ${d.language}'),
                    Text(d.ready ? 'Descargado' : _label(d.state)),
                    if (d.total > 0 && !d.ready)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: LinearProgressIndicator(
                          value: (d.bytes / d.total).clamp(0, 1),
                        ),
                      ),
                    Text(
                      '${animeBytes(d.bytes)}${d.total > 0 ? ' / ${animeBytes(d.total)}' : ''}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    if (d.error.isNotEmpty)
                      Text(
                        d.error,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                  ],
                ),
                onTap: d.ready ? () => _play(d) : null,
                trailing: PopupMenuButton<String>(
                  onSelected: (v) async {
                    if (v == 'play') {
                      await _play(d);
                      return;
                    }
                    if (v == 'delete' || v == 'cancel') {
                      final yes = await showDialog<bool>(
                        context: context,
                        builder: (c) => AlertDialog(
                          title: Text(
                            d.ready ? 'Eliminar descarga' : 'Cancelar descarga',
                          ),
                          content: const Text(
                            'Se conserva tu historial y progreso local.',
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(c, false),
                              child: const Text('Conservar'),
                            ),
                            FilledButton(
                              onPressed: () => Navigator.pop(c, true),
                              child: const Text('Eliminar'),
                            ),
                          ],
                        ),
                      );
                      if (yes != true) return;
                    }
                    await _action(v, key: d.key);
                  },
                  itemBuilder: (_) => [
                    if (d.ready)
                      const PopupMenuItem(
                        value: 'play',
                        child: Text('Reproducir offline'),
                      ),
                    if (!d.ready)
                      const PopupMenuItem(
                        value: 'pause',
                        child: Text('Pausar'),
                      ),
                    if (!d.ready)
                      const PopupMenuItem(
                        value: 'retry',
                        child: Text('Reintentar'),
                      ),
                    if (d.ready)
                      const PopupMenuItem(
                        value: 'verify',
                        child: Text('Verificar archivo'),
                      ),
                    PopupMenuItem(
                      value: d.ready ? 'delete' : 'cancel',
                      child: Text(
                        d.ready
                            ? 'Eliminar archivo'
                            : 'Cancelar y eliminar parcial',
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _label(String value) => switch (value) {
    'queued' => 'En cola',
    'downloading' => 'Descargando',
    'verifying' => 'Verificando',
    'paused' => 'Pausado',
    'retry' => 'Esperando reintento',
    'failed' => 'No se pudo descargar',
    _ => value,
  };
}

class _AnimeMore extends StatelessWidget {
  final AnimeController app;
  final ValueChanged<String> detail;
  final void Function(AnimeDetail, AnimeEpisode) play;
  final VoidCallback web, home, mal;
  const _AnimeMore({
    required this.app,
    required this.detail,
    required this.play,
    required this.web,
    required this.home,
    required this.mal,
  });
  @override
  Widget build(BuildContext context) {
    final profile = context.watch<ProfileProvider>();
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: CircleAvatar(
            backgroundImage: profile.myAnimeListAvatarUrl == null
                ? null
                : NetworkImage(profile.myAnimeListAvatarUrl!),
            child: profile.myAnimeListAvatarUrl == null
                ? const Icon(Icons.person_outline)
                : null,
          ),
          title: Text(
            profile.usesMyAnimeListIdentity
                ? profile.displayName
                : 'Tu espacio local',
          ),
          subtitle: Text(
            profile.usesMyAnimeListIdentity
                ? 'MyAnimeList conectado en Yoma'
                : 'Biblioteca, historial y descargas sin cuenta',
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: mal,
        ),
        ListTile(
          leading: const Icon(Icons.sync),
          title: const Text('Mi lista de anime MAL'),
          trailing: const Icon(Icons.chevron_right),
          onTap: mal,
        ),
        ListTile(
          leading: const Icon(Icons.history),
          title: const Text('Historial de reproducción'),
          subtitle: Text('${app.history.length} episodios'),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => Scaffold(
                appBar: AppBar(title: const Text('Historial')),
                body: AnimatedBuilder(
                  animation: app,
                  builder: (c, _) => app.history.isEmpty
                      ? const AnimeMessage(
                          'Los episodios que reproduzcas aparecerán aquí.',
                        )
                      : ListView.builder(
                          itemCount: app.history.length,
                          itemBuilder: (c, i) {
                            final row = app.history[i],
                                anime = AnimeTitle.fromJson(
                                  animeMap(row['anime']),
                                ),
                                ep = AnimeEpisode.fromJson(
                                  animeMap(row['episode']),
                                );
                            return ListTile(
                              leading: SizedBox(
                                width: 40,
                                height: 56,
                                child: animeArtwork(anime.cover, width: 100),
                              ),
                              title: Text(
                                anime.title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text(
                                'Episodio ${ep.number} · ${row['watched'] == true ? 'Visto' : '${animeInt(row['positionMs']) ~/ 60000} min'}',
                              ),
                              onTap: () async {
                                try {
                                  final d = await app.detail(anime.slug);
                                  play(d, ep);
                                } catch (e) {
                                  if (c.mounted) {
                                    ScaffoldMessenger.of(c).showSnackBar(
                                      SnackBar(content: Text(e.toString())),
                                    );
                                  }
                                }
                              },
                            );
                          },
                        ),
                ),
              ),
            ),
          ),
        ),
        const Divider(height: 32),
        Text('Reproducción', style: Theme.of(context).textTheme.titleLarge),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Reproducir al abrir un episodio'),
          value: app.settings['autoplay'] != false,
          onChanged: (v) => app.saveSetting('autoplay', v),
        ),
        DropdownButtonFormField<String>(
          initialValue: '${app.settings['language'] ?? 'SUB'}',
          decoration: const InputDecoration(labelText: 'Idioma preferido'),
          items: [
            'SUB',
            'LAT',
            'DUB',
          ].map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
          onChanged: (v) => app.saveSetting('language', v),
        ),
        const SizedBox(height: 16),
        DropdownButtonFormField<double>(
          initialValue: (app.settings['speed'] as num?)?.toDouble() ?? 1,
          decoration: const InputDecoration(
            labelText: 'Velocidad predeterminada',
          ),
          items: [.5, .75, 1.0, 1.25, 1.5, 2.0]
              .map((v) => DropdownMenuItem(value: v, child: Text('${v}x')))
              .toList(),
          onChanged: (v) => app.saveSetting('speed', v),
        ),
        const SizedBox(height: 24),
        Text(
          'Datos del dispositivo',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.cleaning_services_outlined),
          title: const Text('Limpiar caché del catálogo'),
          subtitle: const Text(
            'Conserva biblioteca, historial y videos descargados.',
          ),
          onTap: () async {
            await app.store.clearMetadataCache();
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Caché de metadatos eliminada.')),
              );
            }
          },
        ),
        const Divider(height: 32),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.open_in_browser),
          title: const Text('YomaTV Web · respaldo'),
          subtitle: const Text(
            'Radio, cuenta web, herramientas de PC y proveedores web.',
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: web,
        ),
        const SizedBox(height: 12),
        Text('Fuente: YomaTV', style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}
