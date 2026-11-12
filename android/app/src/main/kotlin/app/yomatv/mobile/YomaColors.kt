package app.yomatv.mobile

/**
 * Colores de Yoma para las pantallas nativas de YomaTV (descargas de la cuenta
 * web, selector de capítulos y reproductor). Son los mismos valores que
 * lib/design/yoma_tokens.dart; test/unit/yoma_kotlin_colors_test.dart
 * comprueba que no se separen.
 */
object YomaColors {
    const val BACKGROUND = 0xFF101014.toInt()
    const val SURFACE = 0xFF211F27.toInt()
    const val SURFACE_HIGH = 0xFF2B2831.toInt()
    const val SURFACE_LOW = 0xFF18171D.toInt()
    const val ACCENT = 0xFFF0848D.toInt()
    const val ON_ACCENT = 0xFF101014.toInt()
    const val TEXT_PRIMARY = 0xFFFFFFFF.toInt()
    const val TEXT_SECONDARY = 0xFFA9A6B1.toInt()
    const val TEXT_MUTED = 0xFF7D7A85.toInt()
    const val BORDER = 0xFF39353F.toInt()
    const val BORDER_SUBTLE = 0xFF2E2B34.toInt()
    const val SUCCESS = 0xFF5FD3A0.toInt()
    const val ERROR = 0xFFF3A0A6.toInt()
    const val ANIME_TINT = 0xFFF080B7.toInt()

    /** Fondo del capítulo actual: el acento al 10 % sobre [SURFACE]. */
    const val ACCENT_SOFT = 0xFF362931.toInt()
}

/** Letra de los títulos de Yoma: sans del sistema en peso 800 (ver yoma_theme.dart). */
object YomaType {
    val title: android.graphics.Typeface
        get() = if (android.os.Build.VERSION.SDK_INT >= 28) {
            android.graphics.Typeface.create(android.graphics.Typeface.SANS_SERIF, 800, false)
        } else {
            android.graphics.Typeface.create("sans-serif", android.graphics.Typeface.BOLD)
        }

    /** Espaciado de los títulos, en em (Flutter usa unos -0,5 px a 26 px). */
    const val TITLE_SPACING = -0.02f
}
