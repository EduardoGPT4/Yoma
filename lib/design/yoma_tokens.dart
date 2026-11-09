import 'package:flutter/material.dart';

/// Yoma Design System: valores base compartidos por YomaShi (Manga) y
/// YomaTV (Anime). Ningún otro archivo debería declarar colores de la
/// interfaz; los componentes leen el tema o estas constantes.
///
/// Contraste comprobado (WCAG, texto normal ≥ 4.5):
/// - textPrimary sobre background 19.0, sobre surface 16.3
/// - textSecondary sobre background 7.9, sobre surface 6.8, sobre surfaceHigh 6.1
/// - accent sobre background 7.6, sobre surface 6.5, sobre surfaceHigh 5.8
/// - onAccent (#101014) sobre accent 7.6 (el blanco solo daría 2.5)
abstract final class YomaColors {
  /// Fondo principal de todas las pantallas.
  static const background = Color(0xFF101014);

  /// Tarjetas, hojas inferiores, diálogos y barras de navegación.
  static const surface = Color(0xFF211F27);

  /// Superficie secundaria: chips, campos, placeholders y estados elevados.
  static const surfaceHigh = Color(0xFF2B2831);

  /// Un paso por debajo de [surface]; separa la navegación global de la interna.
  static const surfaceLow = Color(0xFF18171D);

  /// Acento coral-rosado de Yoma. El usuario puede elegir otro en Perfil.
  static const accent = Color(0xFFF0848D);

  /// Texto e iconos sobre el acento (más legible que el blanco: 7.6 frente a 2.5).
  static const onAccent = Color(0xFF101014);

  static const textPrimary = Color(0xFFFFFFFF);
  static const textSecondary = Color(0xFFA9A6B1);

  /// Deshabilitado o decorativo (3.9 sobre surface); nunca para información útil.
  static const textMuted = Color(0xFF7D7A85);

  static const border = Color(0xFF39353F);
  static const borderSubtle = Color(0xFF2E2B34);

  /// Velo para texto sobre portadas, banners y video.
  static const scrim = Color(0xFF000000);

  // Estados semánticos (se usan con moderación).
  static const success = Color(0xFF5FD3A0);
  static const warning = Color(0xFFF2B45A);
  static const error = Color(0xFFF3A0A6);
  static const errorContainer = Color(0xFF3A2226);
  static const favorite = Color(0xFFFF7A93);
  static const rating = Color(0xFFFFCB77);

  /// Identidades de módulo en el selector principal (solo ahí).
  static const mangaTint = Color(0xFFAF83FF);
  static const animeTint = Color(0xFFF080B7);

  /// Acentos anteriores al sistema Yoma que se migran una vez al coral.
  static const legacyAccents = <int>[0xFF7C3AED, 0xFFDC2626];
}

/// Escala de espaciado (múltiplos de 4).
abstract final class YomaSpacing {
  static const double xxs = 2;
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 24;
  static const double xxxl = 32;
}

/// Radios de esquina compartidos.
abstract final class YomaRadii {
  /// Etiquetas sobre portadas y miniaturas pequeñas.
  static const double xs = 6;

  /// Miniaturas en listas, logotipos de encabezado.
  static const double sm = 8;

  /// Botones, campos, chips y tarjetas de contenido.
  static const double md = 12;

  /// Tarjetas destacadas, diálogos, estados vacíos.
  static const double lg = 16;

  /// Hojas inferiores.
  static const double xl = 24;
  static const double pill = 999;

  static BorderRadius get mdAll => BorderRadius.circular(md);
  static BorderRadius get lgAll => BorderRadius.circular(lg);
}

/// Tamaños de iconos y piezas fijas.
abstract final class YomaSizes {
  static const double iconSm = 18;
  static const double icon = 22;
  static const double iconLg = 28;

  /// Logotipo del módulo en el encabezado (YomaShi y YomaTV).
  static const double headerLogo = 32;

  /// Barra global Yoma / Ir a Manga / Ir a Anime.
  static const double sectionBarHeight = 44;
}

/// Duraciones y curvas: discretas y respetan «reducir movimiento».
abstract final class YomaMotion {
  static const fast = Duration(milliseconds: 150);
  static const medium = Duration(milliseconds: 220);
  static const curve = Curves.easeOutCubic;

  static Duration of(BuildContext context, Duration value) =>
      MediaQuery.maybeDisableAnimationsOf(context) ?? false
      ? Duration.zero
      : value;
}
