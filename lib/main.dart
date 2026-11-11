import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'providers/categories_provider.dart';
import 'providers/chapter_read_provider.dart';
import 'providers/download_queue_provider.dart';
import 'providers/favorites_provider.dart';
import 'providers/library_provider.dart';
import 'providers/reader_settings_provider.dart';
import 'providers/profile_provider.dart';
import 'providers/source_provider.dart';
import 'providers/density_provider.dart';
import 'providers/theme_accent_provider.dart';
import 'data/library_store.dart';
import 'models/automation_settings.dart';
import 'services/maintenance_service.dart';
import 'services/rotating_backup_service.dart';
import 'services/diagnostics.dart';
import 'services/yoma_storage_migration.dart';
import 'services/mal_reading_sync.dart';
import 'services/myanimelist_service.dart';
import 'home/yoma_shell.dart';
import 'design/yoma_tokens.dart';
import 'services/download_notification_service.dart';
import 'services/background_downloads.dart';
import 'models/ui_density.dart';
import 'widgets/app_metrics.dart';
import 'widgets/app_theme.dart';
import 'widgets/onboarding_flow.dart';
import 'widgets/startup_storage.dart';
import 'widgets/storage_migration_screen.dart';

@pragma('vm:entry-point')
Future<void> downloadMain() => runDownloadHost();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await LibraryStore.initialize();
  } catch (error, stackTrace) {
    debugPrint('LibraryStore.initialize failed: $error\n$stackTrace');
    runApp(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'No se pudo abrir la biblioteca. Tus archivos se conservan.',
                  ),
                  const SizedBox(height: 12),
                  Text(error.toString()),
                  FilledButton(
                    onPressed: main,
                    child: const Text('Reintentar'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    return;
  }
  // Las notificaciones no deben bloquear el arranque de la UI.
  try {
    await DownloadNotificationService.init();
  } catch (error, stackTrace) {
    debugPrint('DownloadNotificationService.init failed: $error\n$stackTrace');
  }
  // Antes de cargar la biblioteca: la carpeta YomaShi pasa a Yoma/YomaShi.
  await YomaStorageMigration.run(
    onMoving: () async {
      runApp(const StorageMigrationApp());
      await WidgetsBinding.instance.endOfFrame;
    },
  );
  runApp(const MangaReaderApp());
  unawaited(_prepareMaintenance());
}

Future<void> _prepareMaintenance() async {
  try {
    final settings = await AutomationSettings.load();
    await MaintenancePlatform.schedule(settings);
    if (settings.backups) {
      await RotatingBackupService.run(retain: settings.backupRetention);
    }
  } catch (e) {
    await Diagnostics.record('automatic_backup', e);
  }
}

class MangaReaderApp extends StatelessWidget {
  const MangaReaderApp({super.key});

  /// Clave del Navigator de [MaterialApp]. Necesaria para diálogos globales
  /// (onboarding) que no pueden usar el context de un ancestro de MaterialApp.
  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeAccentProvider()..load()),
        ChangeNotifierProvider(create: (_) => DensityProvider()..load()),
        ChangeNotifierProvider(create: (_) => SourceProvider()..load()),
        ChangeNotifierProvider(create: (_) => ProfileProvider()..load()),
        ChangeNotifierProvider(create: (_) => LibraryProvider()..load()),
        ChangeNotifierProvider(create: (_) => DownloadQueueProvider()..load()),
        ChangeNotifierProvider(create: (_) => ReaderSettingsProvider()..load()),
        ChangeNotifierProvider(create: (_) => FavoritesProvider()..load()),
        ChangeNotifierProvider(create: (_) => CategoriesProvider()..load()),
        ChangeNotifierProvider(create: (_) => ChapterReadProvider()..load()),
      ],
      child: Consumer2<ThemeAccentProvider, DensityProvider>(
        builder: (context, accent, density, _) {
          final theme = buildYomashiTheme(
            accent.primary,
            density.density == UiDensity.comfortable
                ? AppMetrics.comfortable
                : AppMetrics.compact,
          );
          return _AppLifecycleHost(
            theme: theme,
            colorScheme: theme.colorScheme,
          );
        },
      ),
    );
  }
}

class _AppLifecycleHost extends StatefulWidget {
  final ThemeData theme;
  final ColorScheme colorScheme;

  const _AppLifecycleHost({required this.theme, required this.colorScheme});

  @override
  State<_AppLifecycleHost> createState() => _AppLifecycleHostState();
}

class _AppLifecycleHostState extends State<_AppLifecycleHost>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    MyAnimeListService.shared.client.sessionChanges.addListener(
      _malSessionChanged,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduleMalReading();
      // Debe usarse el context del Navigator de MaterialApp, no el de este
      // State (que es ancestro de MaterialApp y no tiene Navigator).
      final navContext = MangaReaderApp.navigatorKey.currentContext;
      if (navContext == null) {
        return;
      }
      unawaited(_startFirstLaunch(navContext));
    });
  }

  @override
  void dispose() {
    MyAnimeListService.shared.client.sessionChanges.removeListener(
      _malSessionChanged,
    );
    _stopWaitingForLibrary();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Una cuenta nueva no tiene copia de su lista: se descarga sola.
  void _malSessionChanged() => _scheduleMalReading();

  /// Escucha a la espera de la carga; guarda a quién escucha porque en
  /// `dispose` ya no se puede consultar el contexto.
  ({VoidCallback check, Listenable library, Listenable reads})?
  _malReadingWaiter;

  void _stopWaitingForLibrary() {
    final waiter = _malReadingWaiter;
    if (waiter == null) return;
    _malReadingWaiter = null;
    waiter.library.removeListener(waiter.check);
    waiter.reads.removeListener(waiter.check);
  }

  /// Ejecuta [_syncMalReading] cuando la biblioteca y los capítulos leídos
  /// ya se cargaron. Espera a sus avisos, sin temporizadores.
  void _scheduleMalReading() {
    if (!mounted || _malReadingWaiter != null) return;
    final library = context.read<LibraryProvider>();
    final reads = context.read<ChapterReadProvider>();
    var sawLoading = library.isLoading;
    bool ready() =>
        reads.isLoaded &&
        !library.isLoading &&
        (sawLoading ||
            library.mangas.isNotEmpty ||
            library.progressMap.isNotEmpty);
    if (ready()) {
      unawaited(_syncMalReading());
      return;
    }
    void check() {
      if (library.isLoading) sawLoading = true;
      if (!ready()) return;
      _stopWaitingForLibrary();
      unawaited(_syncMalReading());
    }

    _malReadingWaiter = (check: check, library: library, reads: reads);
    library.addListener(check);
    reads.addListener(check);
  }

  /// «Reading» de MyAnimeList → capítulos leídos de YomaShi.
  Future<void> _syncMalReading({bool force = false}) async {
    if (!mounted) return;
    final library = context.read<LibraryProvider>();
    final favorites = context.read<FavoritesProvider>();
    final reads = context.read<ChapterReadProvider>();
    try {
      await MalReadingSync.shared.run(
        MalReadingSync.candidates(
          library: library.mangas,
          favorites: favorites.entries,
          progress: library.progressMap.values,
        ),
        reads,
        force: force,
        // Al abrir o volver a Yoma, lo leído en la web de MAL aparece en una
        // hora como mucho.
        age: const Duration(hours: 1),
      );
    } catch (error) {
      await Diagnostics.record('myanimelist', error);
    }
  }

  Future<void> _startFirstLaunch(BuildContext navContext) async {
    await StartupStorage.runFirstLaunch(navContext);
    if (!navContext.mounted) {
      return;
    }
    await OnboardingFlow.showIfNeeded(navContext);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final downloader = context.read<DownloadQueueProvider>();
    switch (state) {
      case AppLifecycleState.resumed:
        unawaited(context.read<ProfileProvider>().refreshMyAnimeList());
        unawaited(MyAnimeListService.shared.flush().catchError((_) {}));
        _scheduleMalReading();
        unawaited(StartupStorage.ensureFolderAndDefaults(context));
        unawaited(downloader.checkForRetryableJobs());
        unawaited(_prepareMaintenance());
        break;
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Yoma',
      navigatorKey: MangaReaderApp.navigatorKey,
      debugShowCheckedModeBanner: false,
      theme: widget.theme,
      builder: (context, child) {
        return Stack(
          children: [
            const _AppBackdrop(),
            child ?? const SizedBox.shrink(),
            Consumer<ReaderSettingsProvider>(
              builder: (context, settings, child) {
                final opacity = settings.dimOpacity;
                if (opacity <= 0.0) {
                  return const SizedBox.shrink();
                }
                return IgnorePointer(
                  child: AnimatedOpacity(
                    opacity: opacity,
                    duration: const Duration(milliseconds: 180),
                    child: Container(color: widget.colorScheme.scrim),
                  ),
                );
              },
            ),
          ],
        );
      },
      home: const YomaShell(),
    );
  }
}

class _AppBackdrop extends StatelessWidget {
  const _AppBackdrop();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [YomaColors.surfaceLow, YomaColors.background],
          ),
        ),
      ),
    );
  }
}
