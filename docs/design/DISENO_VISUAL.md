# YomaShi — Diseño visual

**Documento de referencia del sistema visual** de **YomaShi**  
Lector de manga moderno con soporte **Offline + Online** y scraping inteligente.  
Versión de app: **2.0** · Material Design 3 · Solo tema oscuro · Fuentes modulares

---

## Fuente de verdad en código

| Área                  | Archivo                                      |
|-----------------------|----------------------------------------------|
| Tema / ColorScheme    | `lib/main.dart` → `_buildTheme`              |
| Acento personalizable | `lib/providers/theme_accent_provider.dart`   |
| Navegación inferior   | `lib/widgets/bottom_nav_bar.dart`            |
| Fuentes / Sources     | `lib/providers/source_provider.dart`         |
| Componentes           | `lib/widgets/*`                              |
| Pantallas             | `lib/screens/*`                              |

---

## 1. Principios de Diseño

1. **Dark-first, casi negro** — Fondos `#090909`–`#151515` para que las portadas y el acento destaquen.
2. **Acento único y vivo** — Un solo color primario (violeta por defecto) que tiñe botones, toggles, progreso y badges. El usuario puede cambiarlo.
3. **Fuentes modulares y transparentes** — El usuario siempre sabe **qué página se está scrapeando**. Pantalla dedicada "Fuentes".
4. **Tarjetas suaves con borde sutil** — Superficies con borde `onSurface` α18–28 + sombra negra suave.
5. **Tipografía densa y bold** — Títulos en `w800` con tracking negativo ligero.
6. **Radios generosos** — Píldoras (999), botones ~18, tarjetas 14–22.
7. **Mínima cromática semántica** — Solo unos pocos colores fijos (favorito, éxito, pausa, error).
8. **Navegación clara** — Bottom Navigation con **Inicio • Offline • Descargas**. Fuentes se abre desde el chip discreto de Inicio (`Fuente: nombre`).

---

## 2. Paleta de Colores

### 2.1 Neutros (fijos)

| Token                        | Hex       | Uso principal                          |
|-----------------------------|-----------|----------------------------------------|
| `background`                | `#090909` | Scaffold principal                     |
| Backdrop top                | `#111111` | Gradiente superior                     |
| Backdrop bottom             | `#090909` | Gradiente inferior                     |
| `surface`                   | `#151515` | Cards, bottom sheets, inputs           |
| `surfaceVariant`            | `#202020` | Chips, placeholders de cover           |
| `surfaceSoft`               | `#2A2A2A` | Contenedores de acento                 |
| `outline`                   | `#343434` | Bordes de chips e inputs               |
| `onSurface`                 | `#FFFFFF` | Texto principal                        |
| `onSurfaceVariant`          | `#D0D0D0` | Texto secundario                       |
| `scrim`                     | `#000000` | Overlay de atenuación de brillo        |

**Bordes en componentes:** siempre `onSurface.withAlpha(18–28)`.

### 2.2 Acento (personalizable por el usuario)

| Color   | Hex       | Nombre          |
|---------|-----------|-----------------|
| ●       | `#7C3AED` | **Violeta** (default) |
| ●       | `#2563EB` | Azul            |
| ●       | `#059669` | Esmeralda       |
| ●       | `#DC2626` | Rojo            |
| ●       | `#EA580C` | Naranja         |
| ●       | `#DB2777` | Rosa            |

Persistencia: `PreferencesService` → `theme_accent_v1`

### 2.3 Colores Semánticos (fijos)

| Estado              | Color texto     | Fondo                  | Uso                          |
|---------------------|-----------------|------------------------|------------------------------|
| Favorito            | `#FF6B8A`       | —                      | Corazón en MangaCard         |
| Descargando         | `primary`       | `primary` α36          | Badge + borde job activo     |
| Pausada             | `#F59E0B`       | `#33F59E0B`            | Badge en cola                |
| Completada          | `#34D399`       | `#3334D399`            | Badge e historial            |
| Error               | `error`         | `error` α36            | Estados de fallo             |

---

## 3. Tipografía

Sistema Material 3 (sin fuentes custom).

| Estilo                    | Peso   | Tamaño     | Uso                              |
|---------------------------|--------|------------|----------------------------------|
| Título AppBar             | w800   | 22         | Títulos de pantalla              |
| SectionHeader             | w800   | 20         | Encabezados de sección           |
| Título de manga (card)    | w800   | bodySmall  | Título bajo portada              |
| Cuerpo                    | w600   | bodyMedium | Descripciones, empty states      |
| Labels / Badges           | w700   | labelSmall | Chips, progreso, badges          |
| Botones                   | w700   | —          | Elevated / Filled                |

**Regla:** Títulos de UI siempre en **w800** + tracking negativo suave.

---

## 4. Navegación Inferior (Bottom Navigation)

**Nueva estructura recomendada (v2.0)**

| Tab          | Icono                  | Pantalla                  | Descripción                              |
|--------------|------------------------|---------------------------|------------------------------------------|
| **Inicio**   | `home_rounded`         | HomeScreen                | Catálogo online + chip `Fuente: nombre`  |
| **Offline**  | `download_done_rounded`| OfflineLibraryScreen      | Solo contenido descargado                |
| **Descargas**| `download_rounded`     | DownloadQueueScreen       | Cola activa + historial                  |

- **Fuentes:** no va en la barra inferior. Chip casi discreto arriba a la derecha en Inicio (`Fuente: MangaDex`) abre `SourcesScreen`.
- El tab **Offline** muestra únicamente la biblioteca local (sin conexión).
- Al cambiar de tab se mantiene el source seleccionado.

---

## 5. Pantalla de Fuentes (SourcesScreen) — Nueva

**Objetivo:** Que el usuario siempre sepa **qué página se va a scrappear**.

### Estructura visual

```
┌─────────────────────────────────────┐
│  Fuentes                            │  ← AppBar w800
├─────────────────────────────────────┤
│                                     │
│  [ MangaDex ]          ● Activo     │  Card con check
│  API oficial • Español              │
│                                     │
│  [ Inmanga ]                        │
│  Scraping • Español                 │
│                                     │
│  [ TuMangaOnline / Lectortmo ]      │
│  Scraping • Español                 │
│                                     │
│  [ ManhwaWeb ]                      │
│  Scraping • Español                 │
│                                     │
│  + Añadir fuente personalizada      │  Botón outlined
└─────────────────────────────────────┘
```

**Características visuales:**
- Cards con `surface` + borde `onSurface` α22
- Badge **"Activo"** en primary α36 cuando está seleccionada
- Toggle switch o radio button para activar/desactivar fuente
- Icono de fuente (MangaDex = logo, scraping = web icon)
- Sección "Fuentes activas" arriba con chips
- Al seleccionar una fuente se actualiza globalmente el `SourceProvider`

---

## 6. Componentes Principales

### 6.1 ModeToggle (Offline / Online)
- Shell: `surface` radius 16 + borde α22
- Seleccionado: fondo `primary`, texto `onPrimary`, sombra primary α80
- No seleccionado: transparente, texto `onSurface` α170
- Animación: 200ms `easeOutCubic`

### 6.2 MangaCard
- Ratio cover **2:3**
- Grid de **3 columnas** en home
- Radio 14
- Favorito: círculo negro α130 + corazón `#FF6B8A`
- Badge superior derecho (estado, capítulos nuevos)
- Long-press → menú contextual (categoría / actualizar fuente)

### 6.3 Status Badges (Descargas)
| Estado       | Texto          | Color                  |
|--------------|----------------|------------------------|
| queued       | En cola        | `onSurface` α200       |
| downloading  | Descargando    | `primary`              |
| paused       | Pausada        | `#F59E0B`              |
| completed    | Completada     | `#34D399`              |
| failed       | Error          | `error`                |

### 6.4 Progress Bar
- Clip radius **999**
- Track: `onSurface` α20
- Fill: `primary`
- Progreso por **capítulos** (no por páginas)

---

## 7. Flujo de Scraping

1. Usuario abre **tab Fuentes**
2. Selecciona la página deseada (MangaDex recomendado o scraping)
3. Vuelve a **Inicio** → el `SourceProvider` ya está actualizado
4. Busca y explora con la fuente activa
5. Descarga capítulos → se guardan en la biblioteca **Offline**

---

## 8. Checklist de Nueva UI

- [x] Fondo `background` o `surface` correcto
- [x] Usar `primary` del usuario para CTAs y progreso
- [x] Radio acorde a la tabla de radios
- [x] Padding horizontal 20 en pantallas tipo home
- [x] `SectionHeader` con icono redondeado
- [x] Empty state con icono + mensaje claro
- [x] Bordes α18–28 + sombra suave en cards
- [x] Textos secundarios con alpha (nunca gris hardcodeado)
- [x] Estados semánticos correctos (descarga / pausa / error)
- [x] En Fuentes: mostrar claramente la fuente **activa**
- [x] Bottom nav: Inicio · Fuentes · Offline · Descargas
- [x] `SourceProvider` + persistencia de fuente activa
- [x] Lectortmo, InManga, ManhwaWeb y MangaDex implementados
- [x] MangaDex cableado (API oficial: catálogo, detalle, capítulos, páginas, descarga)

---

## 9. Referencia Rápida de Archivos

```
lib/main.dart
lib/providers/
  ├── source_provider.dart          ← NUEVO
  ├── theme_accent_provider.dart
  └── download_queue_provider.dart

lib/widgets/
  ├── bottom_nav_bar.dart           ← NUEVO
  ├── mode_toggle.dart
  ├── manga_card.dart
  ├── section_header.dart
  └── sources_list_card.dart        ← NUEVO

lib/screens/
  ├── home_screen.dart
  ├── sources_screen.dart           ← NUEVO
  ├── offline_library_screen.dart   ← NUEVO
  ├── download_queue_screen.dart
  └── reader_screen.dart
```

---

**YomaShi 2.0** — Diseño limpio, oscuro y centrado en el usuario.  
El usuario siempre sabe **qué página está scrapeando**.

---

*Documento actualizado para alinearse con el sistema de fuentes modulares y navegación inferior con apartado Offline.*