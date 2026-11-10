import 'dart:io';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../design/yoma_tokens.dart';
import '../utils/permissions.dart';
import '../utils/preferences.dart';
import '../utils/yomashi_public_storage.dart';

/// Estado real de los permisos que Yoma necesita (no una marca guardada:
/// Android restaura las preferencias desde la copia de Google al reinstalar,
/// pero nunca el acceso a todos los archivos).
class AppPermissionState {
  final bool storage;
  final bool notifications;
  final bool notificationsBlocked;
  const AppPermissionState({
    required this.storage,
    required this.notifications,
    this.notificationsBlocked = false,
  });
  bool get complete => storage && notifications;
}

/// Acceso al sistema; se sustituye en las pruebas.
class AppPermissionBackend {
  const AppPermissionBackend();

  Future<AppPermissionState> read() async => AppPermissionState(
    storage: await StoragePermissionService.isManageAllFilesGranted(),
    notifications: await StoragePermissionService.notificationsGranted(),
    notificationsBlocked:
        Platform.isAndroid && await Permission.notification.isPermanentlyDenied,
  );

  /// En Android 11+ abre la pantalla de Ajustes «Acceso a todos los archivos».
  Future<void> requestStorage() =>
      StoragePermissionService.requestManageAllFiles();

  Future<void> requestNotifications() =>
      StoragePermissionService.requestNotifications();

  Future<void> openSettings() => openAppSettings();
}

class PermissionsGate {
  PermissionsGate._();

  /// El almacenamiento es imprescindible para descargar: se pide en cada
  /// arranque mientras falte. Las notificaciones se piden una sola vez.
  static bool shouldShow(AppPermissionState state, {required bool asked}) =>
      !state.storage || (!state.notifications && !asked);

  static Future<void> showIfNeeded(
    BuildContext context, {
    AppPermissionBackend backend = const AppPermissionBackend(),
  }) async {
    // Las compilaciones QA de las pruebas de dispositivo no pueden conceder
    // permisos especiales; la pantalla las bloquearía.
    if (!Platform.isAndroid || const bool.fromEnvironment('YOMASHI_QA')) {
      return;
    }
    final state = await backend.read();
    final asked = await PreferencesService.getNotificationsAsked();
    if (!context.mounted || !shouldShow(state, asked: asked)) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => PermissionsScreen(backend: backend),
      ),
    );
  }
}

class PermissionsScreen extends StatefulWidget {
  final AppPermissionBackend backend;
  const PermissionsScreen({
    super.key,
    this.backend = const AppPermissionBackend(),
  });

  @override
  State<PermissionsScreen> createState() => _PermissionsScreenState();
}

class _PermissionsScreenState extends State<PermissionsScreen>
    with WidgetsBindingObserver {
  AppPermissionState? _state;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Al volver de Ajustes se vuelve a leer el estado real.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    final state = await widget.backend.read();
    if (mounted) setState(() => _state = state);
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } finally {
      await _refresh();
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _storage() => _run(widget.backend.requestStorage);

  Future<void> _notifications() => _run(() async {
    await PreferencesService.setNotificationsAsked(true);
    if (_state?.notificationsBlocked == true) {
      await widget.backend.openSettings();
    } else {
      await widget.backend.requestNotifications();
    }
  });

  Future<void> _all() => _run(() async {
    if (_state?.storage != true) await widget.backend.requestStorage();
    final state = await widget.backend.read();
    if (!state.notifications && !state.notificationsBlocked) {
      await PreferencesService.setNotificationsAsked(true);
      await widget.backend.requestNotifications();
    }
  });

  Future<void> _close() async {
    // Cerrar sin conceder las notificaciones cuenta como respuesta.
    await PreferencesService.setNotificationsAsked(true);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = _state;
    final path =
        YomashiPublicStorage.appFolderPath ??
        '/storage/emulated/0/${YomashiPublicStorage.relativePath}';
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close();
      },
      child: Scaffold(
        body: SafeArea(
          child: state == null
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  padding: const EdgeInsets.fromLTRB(
                    YomaSpacing.xxl,
                    YomaSpacing.xxxl,
                    YomaSpacing.xxl,
                    YomaSpacing.xxl,
                  ),
                  children: [
                    Center(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(YomaRadii.xl),
                        child: Image.asset(
                          'assets/branding/3-AniManga.png',
                          width: 80,
                          height: 80,
                        ),
                      ),
                    ),
                    const SizedBox(height: YomaSpacing.xl),
                    Text(
                      'Permisos de Yoma',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineMedium,
                    ),
                    const SizedBox(height: YomaSpacing.sm),
                    Text(
                      'Concede estos permisos para descargar mangas y seguir '
                      'el progreso de tus descargas. Puedes cambiarlos cuando '
                      'quieras en los ajustes de Android.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: YomaColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: YomaSpacing.xxl),
                    _PermissionCard(
                      icon: Icons.folder_open_rounded,
                      title: 'Acceso a todos los archivos',
                      badge: 'Necesario',
                      body:
                          'Guarda tus descargas y copias de seguridad en $path. '
                          'Esa carpeta se conserva aunque reinstales Yoma.',
                      granted: state.storage,
                      action: 'Permitir',
                      onAction: _busy ? null : _storage,
                    ),
                    const SizedBox(height: YomaSpacing.md),
                    _PermissionCard(
                      icon: Icons.notifications_active_outlined,
                      title: 'Notificaciones',
                      badge: 'Recomendado',
                      body:
                          'Muestra el progreso de las descargas y avisa cuando '
                          'terminan o necesitan atención.',
                      granted: state.notifications,
                      action: state.notificationsBlocked
                          ? 'Abrir ajustes'
                          : 'Permitir',
                      onAction: _busy ? null : _notifications,
                    ),
                    const SizedBox(height: YomaSpacing.xxl),
                    if (!state.storage)
                      Padding(
                        padding: const EdgeInsets.only(bottom: YomaSpacing.md),
                        child: Text(
                          'Sin acceso a los archivos no se pueden descargar '
                          'capítulos. Te lo volveremos a pedir al abrir Yoma.',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                    if (state.complete)
                      FilledButton.icon(
                        onPressed: _close,
                        icon: const Icon(Icons.check_rounded),
                        label: const Text('Continuar'),
                      )
                    else ...[
                      FilledButton.icon(
                        onPressed: _busy ? null : _all,
                        icon: const Icon(Icons.verified_user_outlined),
                        label: const Text('Permitir todo'),
                      ),
                      const SizedBox(height: YomaSpacing.sm),
                      TextButton(
                        onPressed: _busy ? null : _close,
                        child: const Text('Ahora no'),
                      ),
                    ],
                  ],
                ),
        ),
      ),
    );
  }
}

class _PermissionCard extends StatelessWidget {
  final IconData icon;
  final String title, badge, body, action;
  final bool granted;
  final VoidCallback? onAction;

  const _PermissionCard({
    required this.icon,
    required this.title,
    required this.badge,
    required this.body,
    required this.granted,
    required this.action,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tone = granted ? YomaColors.success : theme.colorScheme.primary;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(YomaSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: tone.withAlpha(30),
                    shape: BoxShape.circle,
                  ),
                  child: SizedBox.square(
                    dimension: 44,
                    child: Icon(icon, color: tone),
                  ),
                ),
                const SizedBox(width: YomaSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: theme.textTheme.titleMedium),
                      const SizedBox(height: 2),
                      Text(
                        badge,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: YomaColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: YomaSpacing.md),
            Text(
              body,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: YomaColors.textSecondary,
              ),
            ),
            const SizedBox(height: YomaSpacing.md),
            Align(
              alignment: Alignment.centerRight,
              child: granted
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.check_circle_rounded,
                          size: YomaSizes.iconSm,
                          color: YomaColors.success,
                        ),
                        const SizedBox(width: YomaSpacing.xs),
                        Text(
                          'Concedido',
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: YomaColors.success,
                          ),
                        ),
                      ],
                    )
                  : FilledButton.tonal(
                      onPressed: onAction,
                      child: Text(action),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
