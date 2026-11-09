import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/download_queue_provider.dart';

import 'app_metrics.dart';

/// Índices de la navegación inferior YomaShi 2.0.
abstract final class YomashiNavIndex {
  static const int home = 0;
  static const int hitomi = 1;
  static const int offline = 2;
  static const int downloads = 3;
  static const int profile = 4;
}

/// Bottom navigation: Inicio · +18 · Biblioteca · Descargas · Perfil.
class YomashiBottomNavBar extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;

  const YomashiBottomNavBar({
    super.key,
    required this.currentIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final metrics = AppMetrics.of(context);
    final jobs =
        context.watch<DownloadQueueProvider?>()?.jobs ?? <DownloadJob>[];
    final count = jobs
        .where(
          (j) => {
            DownloadJobStatus.downloading,
            DownloadJobStatus.queued,
            DownloadJobStatus.paused,
            DownloadJobStatus.failed,
          }.contains(j.status),
        )
        .length;

    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(top: BorderSide(color: scheme.onSurface.withAlpha(22))),
      ),
      child: SafeArea(
        top: false,
        child: NavigationBar(
          height: metrics.navHeight,
          backgroundColor: Colors.transparent,
          elevation: 0,
          shadowColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          selectedIndex: currentIndex,
          onDestinationSelected: onTap,
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
          destinations: [
            const NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home_rounded),
              label: 'Inicio',
            ),
            const NavigationDestination(
              icon: Icon(Icons.eighteen_up_rating_outlined),
              selectedIcon: Icon(Icons.eighteen_up_rating_rounded),
              label: '+18',
            ),
            const NavigationDestination(
              icon: Icon(Icons.download_done_outlined),
              selectedIcon: Icon(Icons.download_done_rounded),
              label: 'Biblioteca',
            ),
            NavigationDestination(
              icon: Badge.count(
                count: count,
                isLabelVisible: count > 0,
                child: const Icon(Icons.download_outlined),
              ),
              selectedIcon: Badge.count(
                count: count,
                isLabelVisible: count > 0,
                child: const Icon(Icons.download_rounded),
              ),
              label: 'Descargas',
            ),
            const NavigationDestination(
              icon: Icon(Icons.person_outline_rounded),
              selectedIcon: Icon(Icons.person_rounded),
              label: 'Perfil',
            ),
          ],
        ),
      ),
    );
  }
}
