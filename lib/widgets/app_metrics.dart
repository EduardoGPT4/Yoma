import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/ui_density.dart';
import '../providers/density_provider.dart';

/// Tamaños de interfaz según Compacta / Cómoda.
class AppMetrics {
  final UiDensity density;
  final double horizontalPadding;
  final double sectionSpacing;
  final double gridSpacing;
  final int gridColumns;
  final double gridAspectRatio;
  final double titleSize;
  final double continueHeight;
  final double continueCover;
  final double continueWidth;
  final double chapterRowHeight;
  final double navHeight;
  final double navIconSize;
  final double navLabelSize;
  final double searchVerticalPadding;

  const AppMetrics({
    required this.density,
    required this.horizontalPadding,
    required this.sectionSpacing,
    required this.gridSpacing,
    required this.gridColumns,
    required this.gridAspectRatio,
    required this.titleSize,
    required this.continueHeight,
    required this.continueCover,
    required this.continueWidth,
    required this.chapterRowHeight,
    required this.navHeight,
    required this.navIconSize,
    required this.navLabelSize,
    required this.searchVerticalPadding,
  });

  bool get isCompact => density == UiDensity.compact;

  EdgeInsets get pagePadding =>
      EdgeInsets.fromLTRB(horizontalPadding, 8, horizontalPadding, 16);

  static const compact = AppMetrics(
    density: UiDensity.compact,
    horizontalPadding: 12,
    sectionSpacing: 12,
    gridSpacing: 8,
    gridColumns: 3,
    gridAspectRatio: 0.58,
    titleSize: 12,
    continueHeight: 76,
    continueCover: 56,
    continueWidth: 232,
    chapterRowHeight: 52,
    navHeight: 56,
    navIconSize: 20,
    navLabelSize: 11,
    searchVerticalPadding: 8,
  );

  static const comfortable = AppMetrics(
    density: UiDensity.comfortable,
    horizontalPadding: 16,
    sectionSpacing: 16,
    gridSpacing: 10,
    gridColumns: 3,
    gridAspectRatio: 0.54,
    titleSize: 13,
    continueHeight: 96,
    continueCover: 68,
    continueWidth: 260,
    chapterRowHeight: 56,
    navHeight: 62,
    navIconSize: 22,
    navLabelSize: 12,
    searchVerticalPadding: 10,
  );

  static AppMetrics of(BuildContext context) {
    final density = context.watch<DensityProvider>().density;
    return density == UiDensity.comfortable ? comfortable : compact;
  }
}
