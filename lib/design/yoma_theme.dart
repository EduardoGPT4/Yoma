import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../widgets/app_metrics.dart';
import 'yoma_tokens.dart';

/// Lightens an accent only as much as needed for readable small labels.
Color accessibleAccent(Color accent, Color background) {
  final opaque = accent.withAlpha(255);
  for (var step = 0; step <= 100; step++) {
    final candidate = Color.lerp(opaque, Colors.white, step / 100)!;
    final selectedBackground = Color.alphaBlend(
      candidate.withAlpha(36),
      background,
    );
    if (contrastRatio(candidate, background) >= 4.5 &&
        contrastRatio(candidate, selectedBackground) >= 4.5) {
      return candidate;
    }
  }
  return Colors.white;
}

double contrastRatio(Color a, Color b) {
  final x = a.computeLuminance();
  final y = b.computeLuminance();
  return ((x > y ? x : y) + 0.05) / ((x < y ? x : y) + 0.05);
}

/// Texto legible sobre [background]; usa el tono oscuro de Yoma en vez de negro.
Color foregroundFor(Color background) =>
    contrastRatio(Colors.white, background) >=
        contrastRatio(YomaColors.onAccent, background)
    ? Colors.white
    : YomaColors.onAccent;

/// Escala tipográfica compartida. Cada rol tiene un único estilo:
///
/// | Rol                         | Estilo          |
/// |-----------------------------|-----------------|
/// | Título principal / banner   | headlineMedium  |
/// | Título de pantalla          | titleLarge      |
/// | Encabezado de sección       | titleMedium     |
/// | Nombre de manga o anime     | titleSmall      |
/// | Subtítulo                   | bodyMedium      |
/// | Metadatos, texto secundario | bodySmall       |
/// | Botones                     | labelLarge      |
/// | Chips y etiquetas           | labelMedium     |
/// | Estados y badges            | labelSmall      |
///
/// Todos los tamaños se escalan con el ajuste de fuente de Android.
TextTheme yomaTextTheme() {
  final base = Typography.material2021(platform: TargetPlatform.android).white;
  TextStyle? style(
    TextStyle? source,
    double size,
    FontWeight weight, {
    double spacing = 0,
    double? height,
    Color color = YomaColors.textPrimary,
  }) => source?.copyWith(
    fontSize: size,
    fontWeight: weight,
    letterSpacing: spacing,
    height: height,
    color: color,
  );
  return base.copyWith(
    displayLarge: style(base.displayLarge, 52, FontWeight.w800, spacing: -1),
    displayMedium: style(base.displayMedium, 42, FontWeight.w800, spacing: -1),
    displaySmall: style(base.displaySmall, 34, FontWeight.w800, spacing: -.6),
    headlineLarge: style(base.headlineLarge, 30, FontWeight.w800, spacing: -.6),
    headlineMedium: style(
      base.headlineMedium,
      26,
      FontWeight.w800,
      spacing: -.5,
      height: 1.15,
    ),
    headlineSmall: style(base.headlineSmall, 22, FontWeight.w800, spacing: -.4),
    titleLarge: style(base.titleLarge, 20, FontWeight.w800, spacing: -.3),
    titleMedium: style(base.titleMedium, 16, FontWeight.w700, spacing: -.2),
    titleSmall: style(
      base.titleSmall,
      14,
      FontWeight.w700,
      spacing: -.1,
      height: 1.2,
    ),
    bodyLarge: style(base.bodyLarge, 16, FontWeight.w400, height: 1.45),
    bodyMedium: style(base.bodyMedium, 14, FontWeight.w500, height: 1.4),
    bodySmall: style(
      base.bodySmall,
      12.5,
      FontWeight.w500,
      height: 1.35,
      color: YomaColors.textSecondary,
    ),
    labelLarge: style(base.labelLarge, 14, FontWeight.w700, spacing: .1),
    labelMedium: style(base.labelMedium, 12, FontWeight.w700, spacing: .2),
    labelSmall: style(base.labelSmall, 11, FontWeight.w700, spacing: .3),
  );
}

/// Tema único de Yoma para Manga y Anime. [accent] es el color elegido por el
/// usuario (coral por defecto); los neutros son siempre los de Yoma.
ThemeData buildYomaTheme(Color accent, AppMetrics metrics) {
  accent = accent.withAlpha(255);
  final readableAccent = accessibleAccent(accent, YomaColors.surfaceHigh);
  final filledForeground = foregroundFor(accent);
  final text = yomaTextTheme();
  final buttonShape = RoundedRectangleBorder(borderRadius: YomaRadii.mdAll);
  const buttonPadding = EdgeInsets.symmetric(horizontal: 18, vertical: 14);
  final selectionTint = readableAccent.withAlpha(40);

  final colorScheme =
      ColorScheme.fromSeed(
        seedColor: accent,
        brightness: Brightness.dark,
      ).copyWith(
        surface: YomaColors.surface,
        onSurface: YomaColors.textPrimary,
        onSurfaceVariant: YomaColors.textSecondary,
        surfaceContainerLowest: YomaColors.background,
        surfaceContainerLow: YomaColors.surfaceLow,
        surfaceContainer: YomaColors.surface,
        surfaceContainerHigh: YomaColors.surfaceHigh,
        surfaceContainerHighest: YomaColors.surfaceHigh,
        surfaceTint: Colors.transparent,
        primary: readableAccent,
        onPrimary: foregroundFor(readableAccent),
        primaryContainer: Color.alphaBlend(
          readableAccent.withAlpha(46),
          YomaColors.surfaceHigh,
        ),
        onPrimaryContainer: YomaColors.textPrimary,
        secondary: YomaColors.textSecondary,
        onSecondary: YomaColors.background,
        secondaryContainer: YomaColors.surfaceHigh,
        onSecondaryContainer: YomaColors.textPrimary,
        tertiary: YomaColors.textSecondary,
        onTertiary: YomaColors.background,
        tertiaryContainer: YomaColors.surfaceHigh,
        onTertiaryContainer: YomaColors.textPrimary,
        error: YomaColors.error,
        onError: YomaColors.background,
        errorContainer: YomaColors.errorContainer,
        onErrorContainer: YomaColors.textPrimary,
        outline: YomaColors.border,
        outlineVariant: YomaColors.borderSubtle,
        shadow: YomaColors.scrim,
        scrim: YomaColors.scrim,
        inverseSurface: YomaColors.textPrimary,
        onInverseSurface: YomaColors.background,
        inversePrimary: accent,
      );

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: colorScheme,
    textTheme: text,
    scaffoldBackgroundColor: YomaColors.background,
    canvasColor: YomaColors.surface,
    visualDensity: VisualDensity.standard,
    materialTapTargetSize: MaterialTapTargetSize.padded,
    splashFactory: InkSparkle.splashFactory,
    iconTheme: const IconThemeData(
      size: YomaSizes.icon,
      color: YomaColors.textPrimary,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: YomaColors.background,
      foregroundColor: YomaColors.textPrimary,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleSpacing: YomaSpacing.lg,
      toolbarHeight: metrics.isCompact ? 52 : 56,
      iconTheme: const IconThemeData(size: YomaSizes.icon),
      actionsIconTheme: const IconThemeData(size: YomaSizes.icon),
      titleTextStyle: text.titleLarge,
      systemOverlayStyle: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
        systemNavigationBarColor: YomaColors.surfaceLow,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: accent,
      foregroundColor: filledForeground,
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: YomaRadii.lgAll),
    ),
    cardTheme: CardThemeData(
      color: YomaColors.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: YomaRadii.lgAll,
        side: const BorderSide(color: YomaColors.borderSubtle),
      ),
      margin: EdgeInsets.zero,
    ),
    chipTheme: ChipThemeData(
      backgroundColor: YomaColors.surfaceHigh,
      selectedColor: selectionTint,
      checkmarkColor: readableAccent,
      disabledColor: YomaColors.surface,
      padding: EdgeInsets.symmetric(horizontal: metrics.isCompact ? 6 : 8),
      labelPadding: const EdgeInsets.symmetric(horizontal: 4),
      labelStyle: text.labelLarge?.copyWith(
        fontSize: metrics.isCompact ? 12.5 : 13,
      ),
      secondaryLabelStyle: text.labelLarge?.copyWith(
        fontSize: metrics.isCompact ? 12.5 : 13,
        color: YomaColors.textPrimary,
      ),
      side: WidgetStateBorderSide.resolveWith(
        (states) => BorderSide(
          color: states.contains(WidgetState.selected)
              ? readableAccent.withAlpha(120)
              : YomaColors.border,
        ),
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(YomaRadii.sm),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: accent,
        foregroundColor: filledForeground,
        padding: buttonPadding,
        shape: buttonShape,
        textStyle: text.labelLarge,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: accent,
        foregroundColor: filledForeground,
        disabledBackgroundColor: YomaColors.surfaceHigh,
        disabledForegroundColor: YomaColors.textMuted,
        padding: buttonPadding,
        shape: buttonShape,
        textStyle: text.labelLarge,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: readableAccent,
        padding: buttonPadding,
        side: const BorderSide(color: YomaColors.border),
        shape: buttonShape,
        textStyle: text.labelLarge,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: readableAccent,
        shape: buttonShape,
        textStyle: text.labelLarge,
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(iconSize: YomaSizes.icon),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(
        selectedBackgroundColor: selectionTint,
        selectedForegroundColor: YomaColors.textPrimary,
        side: const BorderSide(color: YomaColors.border),
        shape: buttonShape,
        textStyle: text.labelLarge,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: YomaColors.surfaceHigh,
      hintStyle: text.bodyMedium?.copyWith(color: YomaColors.textSecondary),
      labelStyle: text.bodyMedium?.copyWith(color: YomaColors.textSecondary),
      floatingLabelStyle: WidgetStateTextStyle.resolveWith(
        (states) => text.bodyMedium!.copyWith(
          color: states.contains(WidgetState.error)
              ? YomaColors.error
              : states.contains(WidgetState.focused)
              ? readableAccent
              : YomaColors.textSecondary,
        ),
      ),
      prefixIconColor: YomaColors.textSecondary,
      suffixIconColor: YomaColors.textSecondary,
      border: OutlineInputBorder(
        borderRadius: YomaRadii.mdAll,
        borderSide: const BorderSide(color: YomaColors.borderSubtle),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: YomaRadii.mdAll,
        borderSide: const BorderSide(color: YomaColors.borderSubtle),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: YomaRadii.mdAll,
        borderSide: BorderSide(color: readableAccent, width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: YomaColors.surfaceHigh,
      contentTextStyle: text.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
      actionTextColor: readableAccent,
      shape: RoundedRectangleBorder(borderRadius: YomaRadii.mdAll),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: YomaColors.surface,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: text.titleLarge,
      contentTextStyle: text.bodyMedium,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(YomaRadii.xl),
      ),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: YomaColors.surface,
      modalBackgroundColor: YomaColors.surface,
      surfaceTintColor: Colors.transparent,
      dragHandleColor: YomaColors.border,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(YomaRadii.xl)),
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: YomaColors.surfaceHigh,
      surfaceTintColor: Colors.transparent,
      elevation: 6,
      textStyle: text.bodyMedium,
      shape: RoundedRectangleBorder(
        borderRadius: YomaRadii.mdAll,
        side: const BorderSide(color: YomaColors.border),
      ),
    ),
    menuTheme: MenuThemeData(
      style: MenuStyle(
        backgroundColor: const WidgetStatePropertyAll(YomaColors.surfaceHigh),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: YomaRadii.mdAll),
        ),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      height: metrics.navHeight,
      indicatorColor: selectionTint,
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return TextStyle(
          fontSize: metrics.navLabelSize,
          fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
          letterSpacing: -0.1,
          height: 1.1,
          color: selected ? YomaColors.textPrimary : YomaColors.textSecondary,
        );
      }),
      iconTheme: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return IconThemeData(
          size: metrics.navIconSize,
          color: selected ? readableAccent : YomaColors.textSecondary,
        );
      }),
    ),
    drawerTheme: const DrawerThemeData(
      backgroundColor: YomaColors.surface,
      surfaceTintColor: Colors.transparent,
    ),
    listTileTheme: const ListTileThemeData(iconColor: YomaColors.textSecondary),
    bannerTheme: MaterialBannerThemeData(
      backgroundColor: YomaColors.surfaceHigh,
      contentTextStyle: text.bodyMedium,
      dividerColor: YomaColors.borderSubtle,
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: YomaColors.surfaceHigh,
        borderRadius: BorderRadius.circular(YomaRadii.sm),
        border: Border.all(color: YomaColors.border),
      ),
      textStyle: text.bodySmall?.copyWith(color: YomaColors.textPrimary),
    ),
    badgeTheme: BadgeThemeData(
      backgroundColor: accent,
      textColor: filledForeground,
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: readableAccent,
      linearTrackColor: YomaColors.textPrimary.withAlpha(24),
      circularTrackColor: Colors.transparent,
    ),
    dividerTheme: const DividerThemeData(
      color: YomaColors.borderSubtle,
      space: 1,
    ),
  );
}
