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
    WidgetsBinding.instance.addPostFrameCallback((_) {
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
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
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
