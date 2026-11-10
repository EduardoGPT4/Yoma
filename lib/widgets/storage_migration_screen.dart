import 'package:flutter/material.dart';

import '../design/yoma_theme.dart';
import '../design/yoma_tokens.dart';
import '../utils/yomashi_public_storage.dart';
import 'app_metrics.dart';

/// Se muestra mientras la carpeta YomaShi pasa a Yoma/YomaShi. Android
/// actualiza su índice archivo por archivo y, con miles de páginas, puede
/// tardar; sin esta pantalla Yoma quedaba en negro y parecía colgada.
class StorageMigrationApp extends StatelessWidget {
  const StorageMigrationApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: buildYomaTheme(YomaColors.accent, AppMetrics.compact),
    home: const StorageMigrationScreen(),
  );
}

class StorageMigrationScreen extends StatelessWidget {
  const StorageMigrationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(YomaSpacing.xxl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(YomaRadii.xl),
                  child: Image.asset(
                    'assets/branding/3-AniManga.png',
                    width: 88,
                    height: 88,
                  ),
                ),
                const SizedBox(height: YomaSpacing.xxl),
                Text(
                  'Organizando tus archivos',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineMedium,
                ),
                const SizedBox(height: YomaSpacing.md),
                Text(
                  'Tus mangas y copias de seguridad pasan a la carpeta '
                  '${YomashiPublicStorage.relativePath}. Solo ocurre una vez y '
                  'puede tardar un minuto si tienes muchas descargas.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: YomaColors.textSecondary,
                  ),
                ),
                const SizedBox(height: YomaSpacing.xxl),
                const SizedBox(width: 220, child: LinearProgressIndicator()),
                const SizedBox(height: YomaSpacing.lg),
                Text(
                  'No cierres Yoma. Si se interrumpe, seguirá al volver a abrirla.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
