# Yoma 3.0.1 (21) — Cierre de implementación y validación

Se trabajó en Yoma. No se modificaron los proyectos originales de Manga o Anime. No se publicó código ni APK en GitHub. El despliegue adicional de MAL Anime fue autorizado expresamente por el usuario durante esta tarea.

## Resultado

El catálogo, búsqueda, fichas, temporadas, episodios, biblioteca, favoritos, historial, ajustes, reproducción compatible y descargas son nativos. El WebView completo permanece como respaldo para funciones o servidores exclusivos de la web. No es la pantalla principal de Anime.

El reproductor ya está registrado correctamente en Android. Se detectó que el registrador generado antiguo omitía video_player tras un fallo del entorno de enlaces simbólicos: compilar no bastaba para descubrirlo. MainActivity registra el plugin si todavía no está registrado; si Flutter lo registra normalmente, el guard evita duplicarlo. La corrección fue validada con decodificación real, vídeo online y archivo offline.

## MyAnimeList compartido, implementado y desplegado

La extensión usa la misma sesión cifrada/credencial opaca del dispositivo y la misma renovación OAuth de Manga. No se creó otro OAuth, no se entregan tokens MAL a JavaScript y no se requiere usuario de YomaTV Web para las funciones locales.

Se añadieron capacidades de anime, consulta de lista paginada, detalle por ID y actualización de episodios al despachador existente. El adaptador reutiliza las rutas reales del mal-http.php activo, que se inspeccionaron por FTPS. La lógica de Manga y las cuentas web se conservaron.

La app permite vincular explícitamente por ID numérico MAL, desde la lista o introduciendo el ID. Conserva el progreso local anterior a la conexión, guarda pendientes por propietario y versión, reanuda sincronización al volver a Anime o cambiar la sesión y mantiene el historial al desconectar. Las respuestas tardías no pueden sustituir un vínculo nuevo ni borrar un avance más reciente. Se puede resolver un pendiente conservando MAL o enviando explícitamente el avance local tras volver a comprobar el remoto; no se reduce automáticamente el progreso de MAL.

El backend compara el progreso remoto observado con la base esperada, conserva estados remotos como pausa/abandono y rechaza conflictos. Se trata de comprobación optimista: la API externa no proporciona aquí una transacción conjunta con otros clientes de MAL, por lo que no se promete una operación atómica entre la consulta y una modificación externa simultánea.

Despliegue verificado: extensión `yoma-native-mal-daa327d67e790ffd`. La versión activa de la web sigue siendo `yomatv-episodes-20261108-1`. Se guardó y verificó el punto de entrada anterior antes del reemplazo y se verificaron los bytes de los archivos subidos. No se sustituyeron configuración, cuentas, base de datos ni interfaz de la web. Evidencias y ubicación de respaldo: `docs/yoma/deployment/receipt.json`.

Tras el despliegue: sesión pública y catálogo HTTP 200; catálogo real con 4488 entradas en esa comprobación; nueva acción Anime devuelve HTTP 401 ante dispositivo inexistente; progreso negativo devuelve HTTP 422. Las pruebas autenticadas usan un servidor MAL local aislado y comprueban renovación/revocación, propietarios, conflictos y actualizaciones. No se inició sesión como el usuario ni se modificó su lista MAL real durante la validación.

## Pruebas ejecutadas

| Comprobación | Resultado |
|---|---|
| Flutter analyze | Sin incidencias |
| Suite Flutter completa | 268 correctas; 3 opcionales omitidas |
| Pruebas enfocadas de fuente/almacenamiento/MAL | 13 correctas, incluida deduplicación HTTP y resolución de conflictos |
| Backend HTTP PHP | OK, 13 casos del conjunto ampliado, 1 omisión opcional; incluye regresiones de Manga |
| Motor de transferencia JVM | 18 pruebas sin fallos; motor conservado |
| Instrumentación Android | Runner OK (19 tests); 2 supuestos externos omitidos según su registro |
| Flutter Android offline | MP4 decodificado, avance, pausa y posición persistente; cero encolados automáticos |
| Flutter Android online, fuente pública real | Resolución y reproducción compatibles sin cuenta web: correcto |
| Descarga completa real Android | Worker, integridad y reproducción del archivo local: correcto; repetición 2:46 |
| Profile con catálogo real | Navegación y desplazamientos correctos; 597 cuadros medidos |
| APK Release final | Compilado, versión/paquete/firma verificados |

La primera prueba de descarga completa fue interrumpida porque el emulador entero dejó de responder incluso a `adb shell echo`; no se consideró un resultado válido. Se conservó el registro, se reinició exclusivamente el AVD QA y se repitió. La repetición transfirió el episodio real de 211332232 bytes, verificó el MP4/SHA-256 y abrió el archivo local con el reproductor Android. No se sustituyó el capítulo por un archivo de muestra para esa comprobación. El archivo de muestra se usa únicamente en la prueba independiente de controles/persistencia offline y está excluido del punto de entrada de producción.

## Optimización y rendimiento

Se deduplican solicitudes públicas simultáneas; la cola vacía deja de consultar Android cada dos segundos; los avances periódicos de vídeo ya no reconstruyen las cinco pestañas; la sincronización simultánea de MAL comparte una operación y preserva pendientes posteriores. Continúan las rejillas diferidas, imágenes redimensionadas y caché separada de vídeos.

En el mismo emulador, la mediana de inicio de Activity pasó de 3077 a 2465 ms y PSS de 112292 a 107225 KiB. Son tres muestras por versión, orientativas y afectadas por cachés y red. Profile midió construcción media de 1,83 ms y rasterizado medio de 36,12 ms. **No hubo 60 FPS estables con la GPU por software del emulador.** Las cifras y límites completos están en `RENDIMIENTO-3.0.1.md`; queda pendiente medir rasterizado, batería y uso prolongado en un teléfono físico con GPU real.

## Archivos de implementación cambiados en este cierre

- `server/private/yoma-anime-mal.php` nuevo y `server/private/yomashi-mal.php`: operaciones Anime sobre la autenticación común.
- `android/app/src/main/kotlin/app/yomashi/reader/MainActivity.kt`: registro seguro del plugin de vídeo.
- `lib/features/anime/data/anime_mal_client.dart`: lista/detalle, asociaciones, cola, concurrencia y conflictos.
- `lib/features/anime/data/anime_controller.dart`: sincronización, notificaciones y sondeo de descargas activos.
- `lib/features/anime/data/yomatv_source.dart`: deduplicación de solicitudes.
- `lib/features/anime/screens/anime_mal_screen.dart`: ID, pendientes y resolución explícita.
- `lib/home/yoma_shell.dart`: texto de conexión común a ambas listas.
- `pubspec.yaml`: versión 3.0.1+21; la dependencia video_player de la migración se conserva.
- `.gitignore`: excluye el AVD de pruebas local.

Nuevas comprobaciones: `test/services/anime_mal_test.dart`, `integration_test/anime_device_test.dart`, `anime_live_test.dart`, `anime_download_live_test.dart`, `anime_performance_test.dart`, `android/app/src/androidTest/kotlin/app/yomatv/mobile/LocalAnimeStoreTest.kt` y ampliación de `test/unit/native_anime_test.dart`. Las muestras de vídeo están solo en los recursos/código de prueba.

Herramientas autosuficientes en Yoma: `tools/deploy_anime_backend.py`, `check_anime_deployment.py` y `measure_anime_performance.py`. La herramienta de despliegue solicita credenciales con entrada oculta; no guarda la contraseña. Las copias y manifiestos no incluyen configuración privada del alojamiento.

## Respaldo y límites conservados

La web completa sigue disponible para servidores sin resolución nativa, radio y otras funciones originales. MP4Upload es el proveedor nativo comprobado; no se inventa compatibilidad de calidad, subtítulos o DRM que la fuente no entregue. La disponibilidad de proveedores externos puede variar y genera un error específico con alternativa web. Las descargas nativas se ofrecen desde Android 8; la app conserva su mínimo Android 7 para las funciones compatibles.

La pila y desplazamiento se conservan durante cambios de sección en la sesión; posición de reproducción, biblioteca, historial y preferencias persisten entre aperturas. No se promete restaurar toda la pila de pantallas tras finalizar el proceso Android. Las pruebas no sustituyen una prueba prolongada en el teléfono personal.

## Entrega

APK: `dist/Yoma-3.0.1-anime-nativo-prueba.apk`. Paquete QA `app.yomashi.reader.qa`, versión 3.0.1 (21), mínimo SDK 24, target 36. Firma verificada Android Debug existente para instalaciones QA; no se presenta como actualización del paquete personal de producción. Certificado SHA-256: `a8dc9aa621867f6229a9a2b8640f8343ec0de1302d9e97e885d3e78567806dc4`.

Tamaño: 162502287 bytes. SHA-256 APK: `a6a4d76ed86a14524bf1bf689f433930367fe43baa6d0c4a2e0404b2377db931`. El backend ya está desplegado; `dist/Yoma-MAL-Anime-backend.zip` conserva sus dos archivos privados como paquete fuente, no es un reemplazo completo de la web.

Revisión visual final: iconos de navegación con contraste corregido y archivos de imágenes reasignados según el encargo: 1 Anime (marrón), 2 Manga (morado) y 3 AniManga (monocromo). Se regeneró el launcher Android desde AniManga. Capturas del Release real: selector-final.png y catalogo-final.png. Las mediciones de rendimiento preceden este ajuste cosmético de colores/branding.

El ajuste final de contraste está en lib/features/anime/native_anime_screen.dart. También cambiaron assets/branding/2-Manga.png, assets/branding/3-AniManga.png, assets/brand/yoma_icon.png y los recursos mipmap del launcher Android.

Actualización posterior: se validó el teléfono físico con catálogo, vídeo online/offline y rendimiento. Resultados y protección de datos: PRUEBAS-TELEFONO-FISICO.md. Las dos aplicaciones previamente instaladas permanecieron sin cambios.
