import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/profile_provider.dart';
import '../screens/main_shell.dart';
import '../screens/myanimelist_screen.dart';
import '../features/anime/native_anime_screen.dart';
import '../features/anime/data/anime_controller.dart';
import '../design/yoma_components.dart';
import '../design/yoma_tokens.dart';

/// Each experience owns a Navigator so a reader route survives section changes.
class YomaShell extends StatefulWidget {
  final AnimeController? animeController;
  const YomaShell({super.key, this.animeController});
  @override
  State<YomaShell> createState() => _YomaShellState();
}

class _YomaShellState extends State<YomaShell> {
  final _manga = GlobalKey<NavigatorState>();
  final _anime = GlobalKey<NativeAnimeScreenState>();
  final _mangaPages = _PageDepthObserver();
  final _animePages = _PageDepthObserver();
  static final _noPages = ValueNotifier<int>(0);

  /// Barras del módulo y global: se ocultan juntas al desplazar hacia abajo.
  final _barsVisible = ValueNotifier<bool>(true);
  int _section = 0;
  bool _mangaVisited = false, _animeVisited = false;

  void _select(int value) => setState(() {
    _barsVisible.value = true;
    _section = value;
    _mangaVisited |= value == 1;
    _animeVisited |= value == 2;
  });

  Future<void> _back() async {
    if (_section == 1 && await _manga.currentState!.maybePop()) return;
    if (_section == 2 &&
        await (_anime.currentState?.goBack() ?? Future.value(false))) {
      return;
    }
    _select(0);
  }

  @override
  void initState() {
    super.initState();
    // Al abrir o cerrar una página interna las barras vuelven a mostrarse.
    _mangaPages.pages.addListener(_showBars);
    _animePages.pages.addListener(_showBars);
  }

  void _showBars() => _barsVisible.value = true;

  @override
  void dispose() {
    _barsVisible.dispose();
    _mangaPages.dispose();
    _animePages.dispose();
    super.dispose();
  }

  /// Manga sigue montado al cambiar de sección; TickerMode avisa al lector
  /// para que suelte volumen, orientación y modo de pantalla.
  @override
  Widget build(BuildContext context) => PopScope(
    canPop: _section == 0,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) _back();
    },
    // La barra se decide fuera del Scaffold: si recibiera un widget vacío,
    // el Scaffold seguiría quitando el margen inferior del área segura al
    // lector, al reproductor y a las fichas.
    child: YomaBarsScope(
      visible: _barsVisible,
      child: ValueListenableBuilder<int>(
        valueListenable: switch (_section) {
          1 => _mangaPages.pages,
          2 => _animePages.pages,
          _ => _noPages,
        },
        builder: (context, pages, body) => Scaffold(
          body: body,
          bottomNavigationBar: _section == 0 || pages > 1
              ? null
              : YomaHideOnScroll(child: _sectionBar()),
        ),
        child: YomaScrollBars(
          visible: _barsVisible,
          child: IndexedStack(
            index: _section,
            children: [
              _Selector(onSelect: _select),
              if (_mangaVisited)
                TickerMode(
                  enabled: _section == 1,
                  child: Navigator(
                    key: _manga,
                    observers: [_mangaPages],
                    onGenerateRoute: _mainShellRoute,
                  ),
                )
              else
                const SizedBox.shrink(),
              if (_animeVisited)
                NativeAnimeScreen(
                  key: _anime,
                  navigatorObservers: [_animePages],
                  controller: widget.animeController,
                  active: _section == 2,
                  home: () => _select(0),
                )
              else
                const SizedBox.shrink(),
            ],
          ),
        ),
      ),
    ),
  );

  /// Solo en la pantalla principal de cada sección: no tapa lector ni video.
  /// Continúa la barra del módulo con un tono un paso más oscuro y una línea
  /// fina, para que ambas se lean como una sola unidad.
  Widget _sectionBar() => _SectionBar(
    toAnime: _section == 1,
    onHome: () => _select(0),
    onSwitch: () => _select(_section == 1 ? 2 : 1),
  );
}

class _SectionBar extends StatelessWidget {
  final bool toAnime;
  final VoidCallback onHome, onSwitch;
  const _SectionBar({
    required this.toAnime,
    required this.onHome,
    required this.onSwitch,
  });

  @override
  Widget build(BuildContext context) {
    final label = Theme.of(context).textTheme.labelLarge;
    ButtonStyle style(Color color) => TextButton.styleFrom(
      foregroundColor: color,
      textStyle: label,
      iconSize: YomaSizes.iconSm,
      minimumSize: const Size(48, YomaSizes.sectionBarHeight - 8),
      padding: const EdgeInsets.symmetric(horizontal: YomaSpacing.md),
    );
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: YomaColors.surfaceLow,
        border: Border(top: BorderSide(color: YomaColors.borderSubtle)),
      ),
      child: SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minHeight: YomaSizes.sectionBarHeight,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: YomaSpacing.sm),
            child: Row(
              children: [
                TextButton.icon(
                  style: style(YomaColors.textSecondary),
                  onPressed: onHome,
                  icon: const Icon(Icons.space_dashboard_outlined),
                  label: const Text('Yoma'),
                ),
                const Spacer(),
                TextButton.icon(
                  style: style(YomaColors.textPrimary),
                  onPressed: onSwitch,
                  icon: Icon(
                    toAnime
                        ? Icons.play_circle_outline
                        : Icons.menu_book_outlined,
                  ),
                  label: Text(toAnime ? 'Ir a Anime' : 'Ir a Manga'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

Route<void> _mainShellRoute(RouteSettings settings) =>
    MaterialPageRoute<void>(builder: (_) => const MainShell());

/// Cuenta las páginas abiertas en el Navigator interno de una sección.
class _PageDepthObserver extends NavigatorObserver {
  final pages = ValueNotifier<int>(0);
  int _count = 0;
  bool _disposed = false;

  void _change(Route<dynamic> route, int delta) {
    if (route is! PageRoute) return;
    _count += delta;
    // La ruta inicial se anuncia durante build; se publica tras el cuadro.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_disposed) pages.value = _count;
    });
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _change(route, 1);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _change(route, -1);
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _change(route, -1);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    if (oldRoute != null) _change(oldRoute, -1);
    if (newRoute != null) _change(newRoute, 1);
  }

  void dispose() {
    _disposed = true;
    pages.dispose();
  }
}

class _Selector extends StatelessWidget {
  final ValueChanged<int> onSelect;
  const _Selector({required this.onSelect});
  @override
  Widget build(BuildContext context) {
    final profile = context.watch<ProfileProvider>();
    final avatar = profile.myAnimeListAvatarUrl;
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const SizedBox(height: 18),
          Center(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(30),
              child: Image.asset(
                'assets/branding/3-AniManga.png',
                width: 104,
                height: 104,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Yoma',
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.displayMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Text(
            'Tu manga. Tu anime. Tu espacio.',
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.bodyLarge?.copyWith(color: YomaColors.textSecondary),
          ),
          const SizedBox(height: 28),
          _experience(
            context,
            1,
            'Manga',
            'YomaShi',
            'Tu biblioteca, tus fuentes y tu lector offline.',
            'assets/branding/2-Manga.png',
            Icons.menu_book_rounded,
            YomaColors.mangaTint,
          ),
          const SizedBox(height: 16),
          _experience(
            context,
            2,
            'Anime',
            'YomaTV',
            'Explora el catálogo y continúa tu anime.',
            'assets/branding/1-Anime.png',
            Icons.play_circle_fill_rounded,
            YomaColors.animeTint,
          ),
          const SizedBox(height: 24),
          Card(
            child: ListTile(
              leading: CircleAvatar(
                backgroundImage: avatar == null ? null : NetworkImage(avatar),
                child: avatar == null ? const Icon(Icons.person_outline) : null,
              ),
              title: Text(
                profile.usesMyAnimeListIdentity
                    ? profile.displayName
                    : 'Conectar MyAnimeList',
              ),
              subtitle: Text(
                profile.usesMyAnimeListIdentity
                    ? 'Administrar cuenta MAL'
                    : 'Guarda tu progreso y tus listas',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const MyAnimeListScreen(),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Una instalación · Dos experiencias',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  Widget _experience(
    BuildContext context,
    int section,
    String title,
    String brand,
    String detail,
    String image,
    IconData icon,
    Color accent,
  ) => Card(
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: () => onSelect(section),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [accent.withValues(alpha: .18), YomaColors.surface],
          ),
        ),
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(YomaRadii.lg),
              child: Image.asset(
                image,
                width: 76,
                height: 90,
                fit: BoxFit.cover,
              ),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    brand,
                    style: Theme.of(
                      context,
                    ).textTheme.labelLarge?.copyWith(color: accent),
                  ),
                  Text(
                    title,
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    detail,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: YomaColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            Icon(icon, color: accent, size: 30),
          ],
        ),
      ),
    ),
  );
}
