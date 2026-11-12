import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../providers/profile_provider.dart';
import '../../config/yoma_web.dart';
import '../../design/yoma_components.dart';
import '../../design/yoma_tokens.dart';
import '../../widgets/app_metrics.dart';
import '../../widgets/section_header.dart';
import '../../utils/time_format.dart';
import 'anime_screen.dart';
import 'data/anime_controller.dart';
import 'data/anime_mal_client.dart';
import 'data/anime_mal_shelf.dart';
import 'data/anime_web_request.dart';
import 'data/local_anime_downloads.dart';
import 'models/anime_models.dart';
import 'screens/anime_detail_screen.dart';
import 'screens/anime_mal_screen.dart';
import 'screens/anime_player_screen.dart';
import 'screens/anime_schedule_screen.dart';
import 'widgets/anime_widgets.dart';

part 'tabs/anime_home_tab.dart';
part 'tabs/anime_catalog_tab.dart';
part 'tabs/anime_library_tab.dart';
part 'tabs/anime_downloads_tab.dart';
part 'tabs/anime_more_tab.dart';

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

class NativeAnimeScreenState extends State<NativeAnimeScreen>
    with WidgetsBindingObserver {
  final _navigator = GlobalKey<NavigatorState>();
  late final AnimeController app = widget.controller ?? AnimeController();
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(app.initialize());
  }

  /// Al volver a Yoma con YomaTV abierto se actualiza lo que cambió fuera.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    if (widget.active) {
      app.setActive(true);
    } else {
      // Aunque YomaTV no esté a la vista, lo visto sin conexión se envía a
      // MAL al volver a la app (sin pendientes no hace ninguna petición).
      unawaited(app.syncMal());
      unawaited(app.syncAccount());
    }
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
            : YomaWeb.resolve('#watch/${episode.id}'),
        onOpen: (request) => unawaited(openFromWeb(request)),
        onDownloads: showDownloads,
      ),
    ),
  );

  /// La web integrada pide reproducir, descargar o elegir episodios: se
  /// usan el reproductor, la cola local y la ficha de Flutter.
  Future<void> openFromWeb(AnimeWebRequest request) async {
    if (request.action == 'episodes') {
      _detail(request.slug);
      return;
    }
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      final detail = await app.detail(request.slug);
      final episode = detail.episodes
          .where((e) => e.id == request.episodeId)
          .firstOrNull;
      if (episode == null) {
        throw 'El episodio ya no aparece en el listado. Actualízalo e '
            'inténtalo de nuevo.';
      }
      if (!mounted) return;
      if (request.action == 'play') {
        _play(detail, episode);
        return;
      }
      final outcome = await app.enqueue(
        detail.anime,
        episode,
        request.language,
      );
      messenger?.showSnackBar(
        SnackBar(
          content: Text(
            AnimeController.downloadNotice([outcome], paused: app.paused),
          ),
          action: SnackBarAction(label: 'Ver', onPressed: showDownloads),
        ),
      );
    } catch (e) {
      messenger?.showSnackBar(
        SnackBar(content: Text('No se pudo abrir el episodio: $e')),
      );
    }
  }

  /// Vuelve a la pestaña Descargas de YomaTV.
  void showDownloads() {
    _navigator.currentState?.popUntil((route) => route.isFirst);
    app.selectTab(3);
  }

  /// Con [mal], la ficha viene de la sección de MyAnimeList: al empezar a
  /// ver ese mismo anime se vincula para sincronizar los episodios vistos.
  void _detail(String slug, {MalAnimeEntry? mal}) =>
      _navigator.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => AnimeDetailScreen(
            controller: app,
            slug: slug,
            play: mal == null
                ? _play
                : (detail, episode) {
                    if (detail.anime.slug == slug) {
                      unawaited(_autoLink(slug, mal));
                    }
                    _play(detail, episode);
                  },
            openSeason: _detail,
            openWeb: () => _web(),
            openMal: _openMal,
          ),
        ),
      );

  /// Horario de emisión de la temporada (datos públicos, sin cuenta).
  void _schedule() => _navigator.currentState!.push(
    MaterialPageRoute<void>(
      builder: (_) => AnimeScheduleScreen(controller: app, detail: _detail),
    ),
  );

  void _openMal() => _navigator.currentState!.push(
    MaterialPageRoute<void>(
      builder: (_) => AnimeMalScreen(controller: app, home: widget.home),
    ),
  );

  Future<void> _autoLink(String slug, MalAnimeEntry mal) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      if (await app.autoLinkMal(slug, mal)) {
        messenger?.showSnackBar(
          SnackBar(
            content: Text(
              'Vinculado con MyAnimeList: ${mal.title}. '
              'Los episodios vistos se sincronizarán.',
            ),
          ),
        );
      }
    } catch (e) {
      messenger?.showSnackBar(
        SnackBar(content: Text('No se pudo vincular con MyAnimeList: $e')),
      );
    }
  }

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

  /// YomaTV usa el tema único de Yoma (mismos neutros, acento y tipografía
  /// que YomaShi); su carácter cinematográfico está en la composición.
  @override
  Widget build(BuildContext context) => Navigator(
    key: _navigator,
    observers: widget.navigatorObservers,
    onGenerateRoute: (_) => MaterialPageRoute<void>(
      builder: (_) => _AnimeMain(
        app: app,
        detail: _detail,
        openMal: (slug, entry) => _detail(slug, mal: entry),
        play: _play,
        web: () => _web(),
        home: widget.home,
        mal: _openMal,
        schedule: _schedule,
      ),
    ),
  );
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (widget.controller == null) app.dispose();
    super.dispose();
  }
}

class _AnimeMain extends StatelessWidget {
  final AnimeController app;
  final ValueChanged<String> detail;
  final void Function(String slug, MalAnimeEntry entry) openMal;
  final void Function(AnimeDetail, AnimeEpisode) play;
  final VoidCallback web, home, mal, schedule;
  const _AnimeMain({
    required this.app,
    required this.detail,
    required this.openMal,
    required this.play,
    required this.web,
    required this.home,
    required this.mal,
    required this.schedule,
  });
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: app,
    builder: (context, _) => Scaffold(
      appBar: AppBar(
        title: const YomaModuleTitle(
          logoAsset: 'assets/branding/1-Anime.png',
          label: Text('YomaTV'),
        ),
        actions: [
          IconButton(
            tooltip: 'Horario de emisión',
            onPressed: schedule,
            icon: const Icon(Icons.calendar_month_outlined),
          ),
          IconButton(
            tooltip: 'Buscar anime',
            onPressed: () => app.selectTab(1),
            icon: const Icon(Icons.search),
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
              PopupMenuItem(value: 'web', child: Text('YomaTV en la web')),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          if (app.loading) const LinearProgressIndicator(minHeight: 2),
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
                _AnimeHome(
                  app: app,
                  detail: detail,
                  openMal: openMal,
                  play: play,
                ),
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
      bottomNavigationBar: YomaHideOnScroll(
        child: YomaNavigationBar(
          selectedIndex: app.tab,
          onDestinationSelected: app.selectTab,
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.explore_outlined),
              selectedIcon: Icon(Icons.explore_rounded),
              label: 'Inicio',
            ),
            NavigationDestination(
              icon: Icon(Icons.search_rounded),
              selectedIcon: Icon(Icons.manage_search_rounded),
              label: 'Explorar',
            ),
            NavigationDestination(
              icon: Icon(Icons.bookmarks_outlined),
              selectedIcon: Icon(Icons.bookmarks_rounded),
              label: 'Biblioteca',
            ),
            NavigationDestination(
              icon: Icon(Icons.download_outlined),
              selectedIcon: Icon(Icons.download_rounded),
              label: 'Descargas',
            ),
            NavigationDestination(
              icon: Icon(Icons.tune_rounded),
              selectedIcon: Icon(Icons.tune_rounded),
              label: 'Más',
            ),
          ],
        ),
      ),
    ),
  );
}
