# Sincronización de Yoma

Estado: Yoma 3.2.24 (YomaTV desde 3.2.20, YomaShi desde 3.2.24). Cumple la opción 2 de `fase-3.md`.

## Qué se comparte

Entre los teléfonos y la web de **una misma cuenta de MyAnimeList**:

| Dato | App (YomaTV) | Web (tv.yoma.site) | Sentido |
|---|---|---|---|
| Guardado, favorito y estado de cada anime | `anime_library` | `sa1_follow` | App ↔ servidor ↔ web |
| Episodio visto | `anime_progress.watched` | `sa1_watched` | App ↔ servidor ↔ web |
| Posición dentro del episodio (historial) | `anime_progress.positionMs` | `sa1_playback` | Entre teléfonos ↔; de la web a los teléfonos → |

**YomaShi (versión 2, Yoma 3.2.24):** entre teléfonos, solo manga online. La web no tiene manga y no aplica estos tipos.

| Dato | App (YomaShi) | Tipo | Clave |
|---|---|---|---|
| Biblioteca (favoritos); quitarlo viaja como borrado | `FavoriteRows` + `manga_sync_log` | `manga` | huella de la URL |
| Dónde vas: capítulo y página | `ReadingProgressRows` (su fecha) | `manga_progress` | huella de la URL |
| Capítulo leído; desmarcarlo viaja como borrado | `ReadChapterRows` + `manga_sync_log` | `manga_read` | huella de la URL del capítulo |

- La huella son los 40 primeros caracteres hexadecimales del SHA-256 de la URL. El contenido lleva la URL.
- Los mangas sin conexión no viajan: se identifican por rutas de archivos de cada teléfono.
- Lo leído porque MAL ya lo tenía tampoco viaja: cada teléfono lo recibe de MAL.
- La app pregunta antes a `sync_capabilities`. Con un servidor sin estos tipos no sube nada y vuelve a probar a los 30 minutos (`lib/services/manga_sync.dart`).

**Fuera por ahora:**

- **Colecciones, notas y puntuación:** quedan para más adelante.
- **Posición de la app en la web:** la web no la recibe, porque su tabla de reproducción tiene control de sesión propio.

## Cómo funciona

- **Identidad.** Es la cuenta de MAL, sin cuentas nuevas:
  - el teléfono se acredita con el `device_token` de su conexión con MAL (`sa1_yomashi_devices.mal_user_id`);
  - la web, con `sa1_mal_connections`.
- **Servidor** (`server/private/yoma-sync.php`). Tabla `sa1_yoma_sync`: un elemento por fila (tipo + clave), con su contenido, la fecha del cambio y una revisión creciente por cuenta. Acciones del puente:
  - `sync_capabilities`;
  - `sync_pull` (lo cambiado desde una revisión);
  - `sync_push` (hasta 200 cambios).
- **Reglas del servidor:**
  - Gana el cambio más reciente de cada elemento.
  - Una fecha del futuro se limita a «ahora + 10 min», para que un reloj adelantado no bloquee cambios.
  - Solo se guardan los campos conocidos.
  - Las cuentas no se mezclan.
  - Nunca se llama a MAL ni se renuevan sus tokens.
- **App** (`lib/features/anime/data/anime_sync.dart`):
  - Sube lo que cambió desde la última vez y baja lo nuevo; lo aplica si es más reciente que lo del teléfono.
  - No sube lo que vino de MAL.
  - Si un episodio se desmarcó en otro sitio, MAL no vuelve a marcarlo aquí.
  - **Cuándo:** al abrir YomaTV, al volver a la app, al recuperar la red, al cambiar de cuenta, 20 s después de cada cambio y en el mantenimiento en segundo plano.
  - **Estado visible:** «Más › Sincronizar con tu cuenta».
  - Con un servidor sin la función, no hace nada.
- **Web** (`server/private/yoma-sync-web.php`, copiado en la versión de tv.yoma.site):
  - Al cargar la web (`state` y `home`), como mucho cada 30 s, compara la biblioteca web con la vez anterior y sube lo cambiado; después aplica lo nuevo de la cuenta.
  - La primera vez, la biblioteca web entra como antigua para no pisar lo más reciente de la app.
  - No toca los anime ocultos ni los que no están en el catálogo web.
  - Un fallo se registra y la web carga igual.

## Despliegue (orden recomendado)

1. **Web.** Sube a `tv.yoma.site/htdocs` el paquete `dist/sitios/actualizacion/tv.yoma.site-sincronizacion.zip`, con estos 4 archivos de `releases/yoma-design-20261111-1/private/`:
   - `app.php`;
   - `yoma-sync.php`;
   - `yoma-sync-web.php`;
   - `ready.json`.
2. **Servicios en api.yoma.site** (desde Yoma 3.2.21; pasos en `fase-3.md`, sección 3). El paquete `dist/sitios/api.yoma.site.zip` ya lleva la sincronización.
3. **Opcional: puente en tv.yoma.site**, para las versiones de la app anteriores a la 3.2.21 y como respaldo. Ejecuta en el equipo, con tus credenciales de FTP (se piden en la consola y no se guardan):
   ```
   python -I tools/deploy_anime_backend.py --remote-dir /tv.yoma.site/htdocs --publish
   ```
   Publica una extensión nueva con `yoma-sync.php` y cambia la entrada `yomashi-api.php` a ella, guardando copia de la anterior.
4. **App.** Instala Yoma 3.2.21 o posterior. Al abrir YomaTV, «Más › Sincronizar con tu cuenta» debe mostrar «Al día».

Las tablas se crean solas la primera vez.

## Verificado y pendiente

**Verificado** con PHP 8.5 real y SQLite:

- `test/backend/test_yoma_sync.py`: 7 pruebas.
- `test/backend/test_yoma_sync_web.py`: 7 pruebas, con las tablas reales de la web.
- `test/services/anime_sync_test.dart`: 6 pruebas.
- Comprobaciones estáticas: las copias de la web son las de `server/` y el enganche está protegido.

**No verificado:**

- **MySQL de InfinityFree.** El SQL es estándar y las tablas se crean antes de abrir transacciones (en MySQL, `CREATE TABLE` confirma la transacción en curso), pero no se pudo probar contra MySQL.
- **La web completa en local.** Necesita la configuración privada del servidor; se probó el reconciliador con sus tablas reales.

**Primera prueba real recomendada:** marca un favorito en la app, espera unos 20 s y recarga tv.yoma.site con la misma cuenta de MAL.
