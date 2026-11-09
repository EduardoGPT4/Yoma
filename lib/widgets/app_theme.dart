import 'package:flutter/material.dart';

import 'app_metrics.dart';

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

Color foregroundFor(Color background) =>
    contrastRatio(Colors.white, background) >=
        contrastRatio(Colors.black, background)
    ? Colors.white
    : Colors.black;

ThemeData buildYomashiTheme(Color primary, AppMetrics metrics) {
  const background = Color(0xFF090909);
  const surface = Color(0xFF151515);
  const surfaceVariant = Color(0xFF202020);
  const surfaceSoft = Color(0xFF2A2A2A);
  const secondary = Color(0xFFC7C7C7);
  const tertiary = Color(0xFF9A9A9A);
  const outline = Color(0xFF343434);
  const inverseSurface = Color(0xFFF1F1F1);

  primary = primary.withAlpha(255);
  final readableAccent = accessibleAccent(primary, surfaceSoft);
  final filledForeground = foregroundFor(primary);

  final colorScheme =
      ColorScheme.fromSeed(
        seedColor: primary,
        brightness: Brightness.dark,
      ).copyWith(
        surface: surface,
        onSurface: Colors.white,
        surfaceContainerHighest: surfaceVariant,
        onSurfaceVariant: const Color(0xFFD0D0D0),
        primary: readableAccent,
        onPrimary: foregroundFor(readableAccent),
        primaryContainer: surfaceSoft,
        onPrimaryContainer: Colors.white,
        secondary: secondary,
        onSecondary: Colors.black,
        secondaryContainer: surfaceSoft,
        onSecondaryContainer: Colors.white,
        tertiary: tertiary,
        onTertiary: Colors.black,
        tertiaryContainer: surfaceSoft,
        onTertiaryContainer: Colors.white,
        error: const Color(0xFFD4A3A3),
        onError: Colors.black,
        errorContainer: const Color(0xFF2A1F1F),
        onErrorContainer: Colors.white,
        outline: outline,
        outlineVariant: const Color(0xFF2B2B2B),
        shadow: Colors.black,
        scrim: Colors.black,
        inverseSurface: inverseSurface,
        onInverseSurface: Colors.black,
        inversePrimary: const Color(0xFF777777),
        surfaceTint: Colors.transparent,
        surfaceContainer: surface,
        surfaceContainerLow: surface,
        surfaceContainerHigh: surfaceVariant,
        surfaceContainerLowest: background,
      );

  return ThemeData(
    useMaterial3: true,
    scaffoldBackgroundColor: background,
    canvasColor: surface,
    colorScheme: colorScheme,
    visualDensity: VisualDensity.standard,
    materialTapTargetSize: MaterialTapTargetSize.padded,
    splashFactory: InkSparkle.splashFactory,
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      foregroundColor: colorScheme.onSurface,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      toolbarHeight: metrics.isCompact ? 48 : 56,
      titleTextStyle: TextStyle(
        fontSize: metrics.isCompact ? 18 : 20,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.3,
        color: Colors.white,
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: colorScheme.secondary,
      foregroundColor: colorScheme.onSecondary,
      elevation: 1,
    ),
    cardTheme: CardThemeData(
      color: surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      margin: EdgeInsets.zero,
    ),
    chipTheme: ChipThemeData(
      backgroundColor: surfaceVariant,
      padding: EdgeInsets.symmetric(horizontal: metrics.isCompact ? 6 : 8),
      labelPadding: const EdgeInsets.symmetric(horizontal: 4),
      labelStyle: TextStyle(
        color: Colors.white,
        fontWeight: FontWeight.w700,
        fontSize: metrics.isCompact ? 12 : 13,
      ),
      side: BorderSide(color: outline),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: primary,
        foregroundColor: filledForeground,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: const TextStyle(fontWeight: FontWeight.w700),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: primary,
        foregroundColor: filledForeground,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: const TextStyle(fontWeight: FontWeight.w700),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: colorScheme.primary,
        textStyle: const TextStyle(fontWeight: FontWeight.w700),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: surface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: outline),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: outline),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: colorScheme.primary),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: colorScheme.primary,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        side: BorderSide(color: outline),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: const TextStyle(fontWeight: FontWeight.w700),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: surfaceSoft,
      contentTextStyle: const TextStyle(
        color: Colors.white,
        fontWeight: FontWeight.w600,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Colors.transparent,
      elevation: 0,
      height: metrics.navHeight,
      indicatorColor: colorScheme.primary.withAlpha(40),
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return TextStyle(
          fontSize: metrics.navLabelSize,
          fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
          letterSpacing: -0.1,
          height: 1.1,
        );
      }),
      iconTheme: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return IconThemeData(
          size: metrics.navIconSize,
          color: selected
              ? colorScheme.primary
              : colorScheme.onSurface.withAlpha(170),
        );
      }),
    ),
    drawerTheme: const DrawerThemeData(
      backgroundColor: surface,
      surfaceTintColor: Colors.transparent,
    ),
    popupMenuTheme: const PopupMenuThemeData(
      color: surfaceVariant,
      surfaceTintColor: Colors.transparent,
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: colorScheme.primary,
      linearTrackColor: colorScheme.onSurface.withAlpha(24),
    ),
    dividerTheme: DividerThemeData(
      color: colorScheme.onSurface.withAlpha(18),
      space: 1,
    ),
  );
}
