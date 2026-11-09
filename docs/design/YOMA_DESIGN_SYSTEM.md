# Yoma Design System

Lenguaje visual común de **YomaShi** (Manga) y **YomaTV** (Anime). Sustituye a la
paleta propia de cada módulo; `DISENO_VISUAL.md` queda como historia de YomaShi 2.x.

## Fuente de verdad

| Qué | Archivo |
|---|---|
| Colores, espaciado, radios, tamaños, movimiento | `lib/design/yoma_tokens.dart` |
| Tema único (`buildYomaTheme`) y escala tipográfica | `lib/design/yoma_theme.dart` |
| Componentes compartidos | `lib/design/yoma_components.dart` |
| Encabezado de sección | `lib/widgets/section_header.dart` |
| Nombre histórico del tema (`buildYomashiTheme`) | `lib/widgets/app_theme.dart` |

Fuera de `yoma_tokens.dart` no se declaran colores de interfaz. Las excepciones
son las opciones del selector de acento (son datos que elige el usuario) y el
renderizador de traducciones, que pinta sobre las páginas del manga.

## Auditoría previa (3.0.3)

| Aspecto | YomaShi | YomaTV |
|---|---|---|
| Tema | `buildYomashiTheme`, neutros grises `#090909`–`#2A2A2A` | `ThemeData.dark` propio que reemplazaba el tema de la app |
| Acento | Elegido por el usuario (violeta por defecto, rojo saturado como opción) | Fijo `#FF6A55`, secundario menta `#AEE6C9`, indicador marrón `#52332F` |
| Barra global | Botones de texto heredando el acento de Manga (violeta también en Anime) | Igual |
| Navegación | `NavigationBar` sobre `surface` con borde, altura según densidad | `NavigationBar` M3 por defecto (80 px, fondo `#17141F`) |
| Búsqueda | Campo relleno con borde redondeado | Campo con subrayado |
| Tarjetas | Radios mezclados 9/10/14 | Pósteres de radio 18 |
| Márgenes | 12 a la izquierda y 20 a la derecha en el catálogo | 20 |
| Estados vacíos | `_MessageCard` local | `AnimeMessage` con otro icono y color |

## Paleta

| Token | Valor | Uso |
|---|---|---|
| `background` | `#101014` | Fondo de todas las pantallas |
| `surface` | `#211F27` | Tarjetas, hojas, diálogos, barras |
| `surfaceHigh` | `#2B2831` | Chips, campos, menús, placeholders |
| `surfaceLow` | `#18171D` | Barra global Yoma / Ir a… |
| `accent` | `#F0848D` | Acento por defecto (configurable) |
| `onAccent` | `#101014` | Texto sobre el acento |
| `textPrimary` | `#FFFFFF` | Texto principal |
| `textSecondary` | `#A9A6B1` | Metadatos y texto secundario |
| `border` / `borderSubtle` | `#39353F` / `#2E2B34` | Bordes |

La propuesta inicial se mantuvo; solo se añadieron `surfaceLow`, `borderSubtle`
y los estados semánticos. Contraste WCAG medido: texto secundario 6,1–7,9; acento
5,8–7,6 sobre las superficies; texto oscuro sobre el acento 7,6 (el blanco daría
2,5, por eso los botones llenos usan `onAccent`).

**Migración del acento:** la primera vez que se abre esta versión, el violeta
anterior por defecto y el rojo `#DC2626` pasan al coral. Cualquier otro color
elegido se conserva, y en Perfil → Color de acento el rojo pasa a ser «Coral Yoma».

## Tipografía

| Rol | Estilo | Tamaño / peso |
|---|---|---|
| Título principal, banner | `headlineMedium` | 26 / w800 |
| Título de pantalla, AppBar | `titleLarge` | 20 / w800 |
| Encabezado de sección | `titleMedium` + w800 | 16 |
| Nombre de manga o anime | `titleSmall` | 14 / w700 (tarjetas compactas de Manga: 12–13 según densidad) |
| Subtítulo | `bodyMedium` | 14 / w500 |
| Metadatos | `bodySmall` | 12,5 / w500, `textSecondary` |
| Botones | `labelLarge` | 14 / w700 |
| Chips y etiquetas | `labelMedium` | 12 / w700 |
| Estados y badges | `labelSmall` | 11 / w700 |

Todo escala con el tamaño de fuente de Android.

## Forma y espaciado

- Espaciado en múltiplos de 4 (`YomaSpacing`). El margen lateral es el de la
  densidad elegida (12 compacta, 16 cómoda) en ambos módulos.
- Radios: 6 etiquetas · 8 miniaturas y logotipos · 12 botones, campos y
  portadas · 16 tarjetas destacadas · 24 hojas y diálogos.
- Sin sombras en tarjetas: borde `borderSubtle` sobre `surface`.

## Componentes compartidos

| Componente | Uso |
|---|---|
| `YomaNavigationBar` | Barra inferior de YomaShi y YomaTV: mismo fondo, borde, altura y área segura |
| `YomaModuleTitle` | Logotipo 32 px (radio 8) + nombre en el AppBar de cada módulo |
| `SectionHeader` | Icono de acento + título + contador, en ambos módulos |
| `YomaStateMessage` | Vacío, error o aviso con acción (`_MessageCard`, `AnimeMessage`) |
| `YomaCoverTag` | Etiqueta sobre portadas (formato, «Nuevo», fuente) |
| `YomaProgressBar` | Progreso de lectura y de episodios |
| `YomaImageFallback` / `YomaSkeleton` | Portada no disponible y carga |

## Identidad de cada módulo

- **YomaShi** conserva su densidad: cuadrícula de 3 columnas, selector de
  fuentes, búsqueda global, filtros, +18, perfil y ajustes del lector. Las
  etiquetas técnicas del catálogo («Catálogo de X» y «Catálogo guardado…») se
  unieron en una sola línea discreta; el selector de alcance muestra solo el
  valor («Todas las fuentes») porque el campo ya dice «Buscar en…».
- **YomaTV** conserva el banner, los pósteres grandes y los degradados; el
  degradado funde con el fondo de Yoma.

## Navegación

La barra del módulo (`surface`) y la barra global (`surfaceLow`, 44 px) quedan
apiladas y separadas por una línea fina. «Yoma» va en texto secundario y
«Ir a Manga / Ir a Anime» en texto principal; ninguno usa el acento, porque no
son pestañas seleccionadas. Rutas, `IndexedStack` y conservación del estado no
cambiaron.

## Pruebas

`test/widgets/yoma_design_system_test.dart` comprueba el contraste, la migración
del acento, que Manga y Anime usan la misma altura de navegación, el mismo
acento y la misma barra global, y que no hay desbordes a 412 × 915 ni a
360 × 740 con texto al 130 %. Guarda capturas en `build/test_screenshots/design/`.

### Área segura en rutas internas

Antes, `YomaShell` siempre entregaba un `bottomNavigationBar` (vacío en lector,
reproductor y fichas), y el `Scaffold` quitaba el margen inferior del área
segura: los controles del lector quedaban bajo la barra de Android. Ahora la
barra global solo existe en la pantalla principal de cada módulo
(`yoma_shell_test` lo comprueba con un margen inferior simulado de 48 px).
