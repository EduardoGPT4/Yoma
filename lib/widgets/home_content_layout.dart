import 'package:flutter/material.dart';

import 'app_metrics.dart';

class HomeContentLayout {
  static const String appVersion = '2.8.3';

  static EdgeInsets paddingOf(BuildContext context) =>
      AppMetrics.of(context).pagePadding;

  static double sectionOf(BuildContext context) =>
      AppMetrics.of(context).sectionSpacing;

  /// Valores compactos por si un sitio no tiene contexto todavía.
  static const EdgeInsets contentPadding = EdgeInsets.fromLTRB(12, 8, 12, 16);
  static const double sectionSpacing = 12;
}
