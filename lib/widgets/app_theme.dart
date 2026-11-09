import 'package:flutter/material.dart';

import '../design/yoma_theme.dart';
import 'app_metrics.dart';

export '../design/yoma_theme.dart'
    show accessibleAccent, contrastRatio, foregroundFor;

/// Nombre histórico del tema; ahora es el tema único de Yoma (Manga y Anime).
ThemeData buildYomashiTheme(Color primary, AppMetrics metrics) =>
    buildYomaTheme(primary, metrics);
