# Fase 2: arquitectura

Estado al 12 de noviembre de 2026 (Yoma 3.2.18).

## 1. Duplicación entre Flutter, Kotlin y la web

**Retirado.** Es el código Kotlin de la antigua YomaTV que trabajaba con la cuenta web. Desde la 3.2.17 ya no se abría desde ningún sitio y Flutter cubre todas sus funciones:

| Retirado (`app.yomatv.mobile`) | Lo cubre en Flutter |
|---|---|
| `MainActivity`: pestañas Inicio, Temporada, Descargas y Más | `NativeAnimeScreen` y la web integrada |
| `PlayerActivity`: reproductor con imagen en imagen | `AnimePlayerScreen`, con imagen en imagen desde la 3.2.17 |
| `DownloadsPanel`, `DownloadPresentation`, `CoverArt` | Pestaña Descargas de YomaTV |
| `EpisodePicker` | Selección de episodios en la ficha |
| `NavigationStyle`, `AccountAvatar`, `YomaColors.kt` | Tema y componentes de Flutter |
| `OnlinePlayback` y `StreamDataSource` (streaming de la cuenta web) | Reproductor de Flutter con fuentes locales |
| `WebApi` (envío de lo visto a la cuenta web) | Lo visto va a MAL con la sesión de la app |
| Cola de la cuenta web en `Queue` (`start`, `sync`, `pause`) | Cola local (`startLocal`) |

**Se conserva:**

- `Store`, la cola local y `DownloadWorker`;
- el motor `anime-engine`;
- la migración desde la cola web (`WebDownloadsMigration`);
- el puente de la web integrada (`NativeAnimeBridge`).

**Compatibilidad con trabajos programados por versiones anteriores.** WorkManager los guarda por nombre de clase:

- `SyncWorker` queda como un trabajo vacío (`RetiredWork.kt`);
- `DownloadWorker` no hace nada si el trabajo no es de la cola local.

**Prueba:** `DeviceTest.oldWebQueueWorkDoesNothing`.

**Dependencias.** `media3` deja de ser dependencia directa de la app; el reproductor de Flutter (`video_player`) trae la suya. Guava se declara en la misma versión que ya llegaba con `media3`, porque WorkManager la necesita.

**Pruebas nativas:**

- Se retiraron las del reproductor y del panel antiguos.
- `DeviceTest` prueba ahora la cola local: base de datos, recuperación de un archivo final, trabajos antiguos y descarga en vivo.
- `YomaAnimeBridgeTest` usa la actividad principal.

## 2. Archivos grandes

| Archivo | Antes | Después |
|---|---|---|
| `lib/features/anime/native_anime_screen.dart` | 1743 líneas | 364 + una parte por pestaña en `tabs/`: Inicio, Explorar, Biblioteca, Descargas y Más |
| `lib/screens/online_manga_detail_screen.dart` | 1397 | 922 + `online_manga_detail_widgets.dart` |
| `lib/screens/online_browser_screen.dart` | 1469 | 1290 + `online_browser_widgets.dart` |

**Método.** Son archivos `part`: el código se movió tal cual, sin cambios de comportamiento. Se comprobó que las líneas de código son las mismas antes y después.

**Sin dividir.** `lib/screens/reader_screen.dart` (2104 líneas) es una sola clase de estado. Dividirla exige separar su lógica (paginación, traducción, marcadores, MAL), es decir, reescribir el lector, que funciona. Requiere un trabajo propio con pruebas del lector antes de tocarlo.

## 3. Tokens de diseño

**Fuente única.** `lib/design/yoma_tokens.dart`.

- **Bloque generado.** `tools/generate_web_tokens.py` escribe en las hojas de `web/` un bloque `--yoma-*` con los mismos nombres que en Flutter:
  - `background` pasa a `--yoma-background`;
  - `surfaceHigh` pasa a `--yoma-surface-high`;
  - los radios pasan a `--yoma-radius-*`.
- **Nombres propios de cada sitio.**
  - En yoma.site y shi.yoma.site, `--bg`, `--surface`, `--text-2`… apuntan a ese bloque.
  - En tv.yoma.site, `--surface`, `--surface2`, `--muted`… apuntan a él, conservando sus nombres. Así un mismo nombre ya no significa colores distintos según el sitio.
- **Kotlin.** No queda ninguna paleta propia: las pantallas Kotlin con colores se retiraron.

**Prueba:** `test/unit/yoma_web_tokens_test.dart`. Falla si el bloque no coincide con `yoma_tokens.dart` o si un nombre de sitio vuelve a llevar un color suelto.

**Comprobación visual.** Las capturas de yoma.site y shi.yoma.site son idénticas píxel a píxel antes y después.

**Excepción.** El tema claro de la web (solo web; la app es oscura) sigue con sus valores propios.

## 4. MyAnimeList

**Lo que está bien.** YomaShi y YomaTV comparten el mismo cliente (`MyAnimeListClient`), la misma sesión y el mismo puente del servidor. Cada sección tiene su cola de pendientes con protecciones propias:

- **manga:** un lease contra envíos dobles;
- **anime:** el número esperado de episodios, que resuelve conflictos sin bajar nunca el progreso.

**Problema corregido.** Lo visto en YomaTV sin conexión solo se enviaba con YomaTV abierto. Lo leído en YomaShi, en cambio, se enviaba al volver a la app y en el mantenimiento en segundo plano. Ahora YomaTV también:

- envía sus pendientes al volver a la app aunque no sea la sección abierta;
- se envía en el mantenimiento en segundo plano. Un fallo ahí se registra y no detiene el resto.

Sin pendientes no se hace ninguna petición.

**No se unificó:**

- las dos colas de pendientes (`mal_pending` y `anime_mal_pending`);
- la sincronización desde MAL («Reading» → YomaShi y «Watching» → YomaTV).

Funcionan, tienen pruebas propias y sus reglas difieren: capítulos frente a episodios, y deshacer solo en anime. Unificarlas sería reescribir sin un fallo concreto que lo justifique.

## Pendiente

- Dividir `reader_screen.dart` con pruebas del lector previas.
- Subir el código de tv.yoma.site al repositorio, sin `private/config.local.php`, para generar también sus tokens desde aquí (Fase 3).
- Las 11 pruebas de exclusión siguen fallando hasta que se revisen las reglas (`docs/arquitectura/fase-1.md`).
