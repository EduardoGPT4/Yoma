import 'package:flutter/material.dart';

import 'yoma_tokens.dart';

/// Componentes visuales compartidos por Manga y Anime. Solo contienen
/// presentación: ninguna lógica de fuentes, descargas o reproducción.

/// Estado vacío, de carga o de error con el mismo aspecto en ambos módulos.
class YomaStateMessage extends StatelessWidget {
  final IconData icon;
  final String message;
  final String? title;
  final bool isError;
  final String? actionLabel;
  final IconData? actionIcon;
  final VoidCallback? onAction;

  /// Con marco de tarjeta (listas) o sin él (pantallas completas).
  final bool framed;

  const YomaStateMessage({
    super.key,
    required this.icon,
    required this.message,
    this.title,
    this.isError = false,
    this.actionLabel,
    this.actionIcon,
    this.onAction,
    this.framed = true,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final tone = isError ? scheme.error : scheme.primary;
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            color: tone.withAlpha(30),
            shape: BoxShape.circle,
          ),
          child: SizedBox.square(
            dimension: 52,
            child: Icon(icon, color: tone, size: 26),
          ),
        ),
        if (title != null) ...[
          const SizedBox(height: YomaSpacing.md),
          Text(
            title!,
            style: theme.textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
        ],
        const SizedBox(height: YomaSpacing.sm),
        Text(
          message,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: isError ? scheme.error : scheme.onSurfaceVariant,
          ),
          textAlign: TextAlign.center,
        ),
        if (actionLabel != null && onAction != null) ...[
          const SizedBox(height: YomaSpacing.lg),
          actionIcon == null
              ? FilledButton(onPressed: onAction, child: Text(actionLabel!))
              : FilledButton.icon(
                  onPressed: onAction,
                  icon: Icon(actionIcon),
                  label: Text(actionLabel!),
                ),
        ],
      ],
    );
    if (!framed) {
      return Padding(
        padding: const EdgeInsets.all(YomaSpacing.xl),
        child: content,
      );
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: YomaSpacing.lg,
        vertical: YomaSpacing.xxl,
      ),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: YomaRadii.lgAll,
        border: Border.all(
          color: isError ? scheme.error.withAlpha(70) : YomaColors.borderSubtle,
        ),
      ),
      child: content,
    );
  }
}

/// Relleno para portadas que aún cargan o no están disponibles. Conserva el
/// espacio de la imagen para que la cuadrícula no salte.
class YomaImageFallback extends StatelessWidget {
  final IconData icon;
  final double iconSize;

  const YomaImageFallback({
    super.key,
    this.icon = Icons.image_not_supported_outlined,
    this.iconSize = 28,
  });

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: YomaColors.surfaceHigh,
    child: Center(
      child: Icon(icon, size: iconSize, color: YomaColors.textMuted),
    ),
  );
}

/// Bloque de esqueleto para estados de carga.
class YomaSkeleton extends StatelessWidget {
  final double? width;
  final double? height;
  final double radius;

  const YomaSkeleton({
    super.key,
    this.width,
    this.height,
    this.radius = YomaRadii.md,
  });

  @override
  Widget build(BuildContext context) => Container(
    width: width,
    height: height,
    decoration: BoxDecoration(
      color: YomaColors.surfaceHigh,
      borderRadius: BorderRadius.circular(radius),
    ),
  );
}

/// Etiqueta sobre portadas y banners (formato, «Nuevo», capítulos…).
class YomaCoverTag extends StatelessWidget {
  final String label;
  final IconData? icon;

  /// Con acento para novedades; neutra (velo oscuro) para datos.
  final bool emphasis;
  final int maxLines;

  const YomaCoverTag({
    super.key,
    required this.label,
    this.icon,
    this.emphasis = false,
    this.maxLines = 1,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final background = emphasis
        ? theme.colorScheme.primary
        : YomaColors.scrim.withAlpha(178);
    final foreground = emphasis
        ? theme.colorScheme.onPrimary
        : YomaColors.textPrimary;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(YomaRadii.xs),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 12, color: foreground),
              const SizedBox(width: 3),
            ],
            Flexible(
              child: Text(
                label,
                maxLines: maxLines,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: foreground,
                  height: 1.2,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Barra de progreso fina y redondeada (lectura, episodios, descargas).
class YomaProgressBar extends StatelessWidget {
  final double? value;
  final double height;

  /// Sobre una imagen el fondo es un velo oscuro en lugar del gris del tema.
  final bool overImage;

  const YomaProgressBar({
    super.key,
    required this.value,
    this.height = 3,
    this.overImage = false,
  });

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(YomaRadii.pill),
    child: LinearProgressIndicator(
      value: value?.clamp(0.0, 1.0),
      minHeight: height,
      backgroundColor: overImage
          ? YomaColors.scrim.withAlpha(110)
          : YomaColors.textPrimary.withAlpha(24),
      color: Theme.of(context).colorScheme.primary,
    ),
  );
}

/// Encabezado de pantalla de un módulo: logotipo + nombre (texto o imagen).
/// Mismo tamaño de logotipo, radio y separación en YomaShi y YomaTV.
class YomaModuleTitle extends StatelessWidget {
  final String logoAsset;
  final Widget label;

  const YomaModuleTitle({
    super.key,
    required this.logoAsset,
    required this.label,
  });

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(YomaRadii.sm),
        child: Image.asset(
          logoAsset,
          width: YomaSizes.headerLogo,
          height: YomaSizes.headerLogo,
          fit: BoxFit.cover,
        ),
      ),
      const SizedBox(width: YomaSpacing.sm + 2),
      label,
    ],
  );
}

/// Contenedor común de las barras de navegación de cada módulo: mismo fondo,
/// altura (del tema), borde superior y área segura.
class YomaNavigationBar extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final List<Widget> destinations;

  const YomaNavigationBar({
    super.key,
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.destinations,
  });

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: const BoxDecoration(
      color: YomaColors.surface,
      border: Border(top: BorderSide(color: YomaColors.borderSubtle)),
    ),
    child: SafeArea(
      top: false,
      child: NavigationBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        shadowColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        animationDuration: YomaMotion.of(context, YomaMotion.medium),
        selectedIndex: selectedIndex,
        onDestinationSelected: onDestinationSelected,
        destinations: destinations,
      ),
    ),
  );
}

/// Visibilidad compartida de la barra del módulo y la barra global de Yoma.
/// [YomaScrollBars] la cambia según el desplazamiento vertical del contenido.
class YomaBarsScope extends InheritedNotifier<ValueNotifier<bool>> {
  const YomaBarsScope({
    super.key,
    required ValueNotifier<bool> visible,
    required super.child,
  }) : super(notifier: visible);

  /// `true` si no hay ámbito (pantallas sueltas y pruebas).
  static bool visibleOf(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<YomaBarsScope>()
          ?.notifier
          ?.value ??
      true;
}

/// Oculta las barras al desplazarse hacia abajo y las muestra al subir o al
/// volver al principio. Solo atiende listas verticales de la página visible:
/// carruseles, hojas inferiores y diálogos no las mueven.
class YomaScrollBars extends StatelessWidget {
  final ValueNotifier<bool> visible;
  final Widget child;

  /// Desplazamiento mínimo antes de reaccionar, para ignorar temblores.
  static const double threshold = 12;

  const YomaScrollBars({super.key, required this.visible, required this.child});

  bool _handle(ScrollNotification notification) {
    final metrics = notification.metrics;
    if (metrics.axis != Axis.vertical) return false;
    final context = notification.context;
    final route = context == null ? null : ModalRoute.of(context);
    if (route is! PageRoute || !route.isCurrent) return false;
    if (metrics.pixels <= metrics.minScrollExtent + threshold) {
      visible.value = true;
    } else if (notification is ScrollUpdateNotification &&
        notification.dragDetails != null) {
      final delta = notification.scrollDelta ?? 0;
      if (delta > threshold / 2) visible.value = false;
      if (delta < -threshold / 2) visible.value = true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) =>
      NotificationListener<ScrollNotification>(
        onNotification: _handle,
        child: child,
      );
}

/// Pliega una barra inferior deslizándola hacia abajo con una animación
/// suave; con «reducir movimiento» el cambio es inmediato.
class YomaHideOnScroll extends StatelessWidget {
  final Widget child;
  const YomaHideOnScroll({super.key, required this.child});

  static const duration = Duration(milliseconds: 260);

  @override
  Widget build(BuildContext context) {
    final visible = YomaBarsScope.visibleOf(context);
    final time = YomaMotion.of(context, duration);
    return ClipRect(
      child: AnimatedAlign(
        alignment: Alignment.topCenter,
        heightFactor: visible ? 1 : 0,
        duration: time,
        curve: Curves.easeOutCubic,
        child: AnimatedOpacity(
          opacity: visible ? 1 : 0,
          duration: time,
          curve: Curves.easeOut,
          child: IgnorePointer(ignoring: !visible, child: child),
        ),
      ),
    );
  }
}
