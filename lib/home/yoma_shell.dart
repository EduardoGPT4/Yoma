import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/profile_provider.dart';
import '../screens/main_shell.dart';
import '../screens/myanimelist_screen.dart';
import '../features/anime/native_anime_screen.dart';
import '../features/anime/data/anime_controller.dart';
import '../design/yoma_components.dart';
import '../design/yoma_tokens.dart';
import '../widgets/mal_login_prompt.dart';
import 'selector_intro.dart';

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
            // Con texto grande, los botones se recortan con «…» en vez de
            // salirse de la barra.
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  child: TextButton.icon(
                    style: style(YomaColors.textSecondary),
                    onPressed: onHome,
                    icon: const Icon(Icons.space_dashboard_outlined),
                    label: const Text(
                      'Yoma',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                Flexible(
                  child: TextButton.icon(
                    style: style(YomaColors.textPrimary),
                    onPressed: onSwitch,
                    icon: Icon(
                      toAnime
                          ? Icons.play_circle_outline
                          : Icons.menu_book_outlined,
                    ),
                    label: Text(
                      toAnime ? 'Ir a Anime' : 'Ir a Manga',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
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

class _Selector extends StatefulWidget {
  final ValueChanged<int> onSelect;
  const _Selector({required this.onSelect});
  @override
  State<_Selector> createState() => _SelectorState();
}

/// La entrada «se programa» una sola vez: el selector sigue montado al
/// cambiar de sección, así que volver a él no la repite.
class _SelectorState extends State<_Selector>
    with SingleTickerProviderStateMixin {
  late final AnimationController _intro = AnimationController(
    vsync: this,
    duration: SelectorIntro.duration,
  );
  bool _started = false;

  /// Si la persona abre una sección antes de que termine la entrada, no se le
  /// interrumpe: se le propondrá entrar con MAL en el siguiente inicio.
  bool _skipLogin = false;

  @override
  void initState() {
    super.initState();
    _intro.addStatusListener(_introStatus);
  }

  void _introStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed || _skipLogin) return;
    _intro.removeStatusListener(_introStatus);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      MalLoginPrompt.maybeShow(
        context,
        onLogin: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => const MyAnimeListScreen(autoConnect: true),
          ),
        ),
      );
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    // Con «quitar animaciones» de Android se muestra directamente.
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      _intro.value = 1;
    } else {
      _intro.forward();
    }
  }

  @override
  void dispose() {
    _intro.dispose();
    super.dispose();
  }

  /// Los botones funcionan desde el principio; al usarlos la animación
  /// termina para no quedar a medias en segundo plano.
  void _finish() {
    if (_intro.isAnimating) _intro.value = 1;
  }

  void _open(int section) {
    _skipLogin = true;
    _finish();
    widget.onSelect(section);
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _intro,
    builder: (context, _) {
      final intro = SelectorIntro(_intro.value);
      final content = _content(context, intro);
      if (intro.done) return content;
      return Stack(
        children: [
          content,
          Positioned.fill(child: IntroScreenOverlay(intro: intro)),
        ],
      );
    },
  );

  Widget _content(BuildContext context, SelectorIntro intro) {
    final profile = context.watch<ProfileProvider>();
    final avatar = profile.myAnimeListAvatarUrl;
    final done = intro.done;
    final logo = ClipRRect(
      borderRadius: BorderRadius.circular(30),
      child: Image.asset(
        'assets/branding/3-AniManga.png',
        width: 104,
        height: 104,
      ),
    );
    final title = Text(
      'Yoma',
      textAlign: TextAlign.center,
      style: Theme.of(
        context,
      ).textTheme.displayMedium?.copyWith(fontWeight: FontWeight.w800),
    );
    final tagline = Text(
      'Tu manga. Tu anime. Tu espacio.',
      textAlign: TextAlign.center,
      style: Theme.of(
        context,
      ).textTheme.bodyLarge?.copyWith(color: YomaColors.textSecondary),
    );
    final mal = Card(
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
        onTap: () {
          _skipLogin = true;
          _finish();
          Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const MyAnimeListScreen()),
          );
        },
      ),
    );
    final footer = Text(
      'Una instalación · Dos experiencias',
      textAlign: TextAlign.center,
      style: Theme.of(context).textTheme.bodySmall,
    );
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const SizedBox(height: 18),
          Center(child: done ? logo : _introLogo(intro, logo)),
          const SizedBox(height: 16),
          if (done)
            title
          else
            Center(
              child: TypedReveal(
                progress: intro.at(.75, 1.07),
                steps: 4,
                caret: intro.t > .7 && intro.t < 1.25 && intro.caretOn,
                child: title,
              ),
            ),
          const SizedBox(height: 8),
          introReveal(intro.at(1.04, 1.34, Curves.easeOut), tagline, dy: 6),
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
            done ? null : intro.card(SelectorIntro.mangaStart),
            TypedCode.tag('YomaShi', 'type', 'manga'),
            '01 / mount(<Manga />)',
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
            done ? null : intro.card(SelectorIntro.animeStart),
            TypedCode.tag('YomaTV', 'type', 'anime'),
            '02 / mount(<Anime />)',
          ),
          const SizedBox(height: 24),
          if (done) mal else _introMal(intro, mal),
          const SizedBox(height: 12),
          introReveal(intro.at(2.55, 2.9, Curves.easeOut), footer, dy: 8),
        ],
      ),
    );
  }

  /// El contorno del logo se traza, aparece `<Yoma.Logo />` y la imagen se
  /// renderiza pasando de gris a color.
  Widget _introLogo(SelectorIntro intro, Widget logo) {
    final image = intro.at(.5, .86, Curves.easeOutCubic);
    final hint = intro.pulse(.17, .85, hold: .6);
    return SizedBox(
      width: 104,
      height: 104,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          introReveal(image, introColorize(image, logo), scaleFrom: .91),
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: TracePainter(
                  progress: intro.at(.11, .65),
                  radius: 30,
                  color: YomaColors.mangaTint,
                  opacity: 1 - intro.at(.8, 1.15),
                ),
              ),
            ),
          ),
          if (hint > 0)
            Positioned(
              left: -60,
              right: -60,
              bottom: -2,
              child: IgnorePointer(
                child: Opacity(
                  opacity: hint,
                  child: Center(
                    child: TypedCode(
                      spans: const [
                        ('<', YomaColors.textSecondary),
                        ('Yoma.Logo', YomaColors.success),
                        (' />', YomaColors.textSecondary),
                      ],
                      progress: intro.at(.17, .45),
                      caret: intro.caretOn,
                      fontSize: 10,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// La tarjeta de MyAnimeList se despliega a lo ancho con su anotación.
  Widget _introMal(SelectorIntro intro, Widget mal) {
    final open = intro.at(
      SelectorIntro.malStart,
      SelectorIntro.malStart + .35,
      Curves.easeOutCubic,
    );
    final note = intro.pulse(
      SelectorIntro.malStart - .05,
      SelectorIntro.malStart + .65,
    );
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Opacity(
          opacity: open,
          child: Transform(
            alignment: Alignment.center,
            transform: Matrix4.diagonal3Values(.4 + .6 * open, 1, 1),
            child: mal,
          ),
        ),
        if (note > 0)
          Positioned(
            left: 4,
            top: -20 - 6 * (1 - note),
            child: IgnorePointer(
              child: Opacity(
                opacity: .85 * note,
                child: TypedCode(
                  spans: const [
                    ('03 / render(', YomaColors.textSecondary),
                    ('<MyAnimeList />', YomaColors.mangaTint),
                    (')', YomaColors.textSecondary),
                  ],
                  progress: intro.at(
                    SelectorIntro.malStart - .05,
                    SelectorIntro.malStart + .25,
                  ),
                  caret: false,
                  fontSize: 10,
                ),
              ),
            ),
          ),
      ],
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
    CardIntro? intro,
    List<CodeSpan> code,
    String annotation,
  ) {
    // Sin animación (o al terminar) se devuelve exactamente la tarjeta original.
    double v(double Function(CardIntro) value) =>
        intro == null ? 1 : value(intro);
    final card = Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _open(section),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [accent.withValues(alpha: .18), YomaColors.surface],
            ),
          ),
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              introReveal(
                v((c) => c.thumb),
                introColorize(
                  v((c) => c.thumb),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(YomaRadii.lg),
                    child: Image.asset(
                      image,
                      width: 76,
                      height: 90,
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
                dx: -12,
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    introReveal(
                      v((c) => c.brand),
                      Text(
                        brand,
                        style: Theme.of(
                          context,
                        ).textTheme.labelLarge?.copyWith(color: accent),
                      ),
                      dx: -8,
                    ),
                    introReveal(
                      v((c) => c.title),
                      Text(
                        title,
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                      dx: -8,
                    ),
                    const SizedBox(height: 6),
                    introReveal(
                      v((c) => c.detail),
                      Text(
                        detail,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: YomaColors.textSecondary,
                        ),
                      ),
                      dy: 7,
                    ),
                  ],
                ),
              ),
              introReveal(
                v((c) => c.icon),
                Transform.rotate(
                  angle: -.31 * (1 - v((c) => c.icon)),
                  child: Icon(icon, color: accent, size: 30),
                ),
                scaleFrom: .4,
              ),
            ],
          ),
        ),
      ),
    );
    if (intro == null) return card;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        introReveal(intro.fill, card, dx: -20),
        Positioned.fill(
          child: CardBuildOverlay(
            phase: intro,
            accent: accent,
            code: code,
            annotation: annotation,
            radius: YomaRadii.lg,
          ),
        ),
      ],
    );
  }
}
