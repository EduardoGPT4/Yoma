> Informe histórico de 3.0.0. Para el cierre actualizado, consulta INFORME-FINAL-3.0.1.md. MAL Anime ya está implementado y desplegado; vídeo y descarga completa ya se comprobaron en Android.

# Yoma 3.0.0 — Migración Anime a Flutter

Trabajo realizado exclusivamente en el proyecto Yoma. No se modificaron Expedition-6, Expedition-9 ni la web en producción. No se publicó en GitHub.

## Funciones migradas

La entrada Anime del selector abre ahora pantallas Flutter: inicio con portada destacada, novedades, continuar viendo, catálogo paginado, búsqueda, filtros de categoría/temporada/año/género, fichas con sinopsis y géneros, temporadas relacionadas y selección de episodios. Los datos proceden del JSON público real auditado; no hay un catálogo de demostración dentro de la aplicación.

Biblioteca, favoritos, estado, puntuación, notas, historial, episodios vistos, posición en milisegundos, idioma, velocidad, reproducción automática, búsqueda y filtros se guardan localmente. La biblioteca y las fichas previamente consultadas funcionan con metadatos persistentes sin conexión. Las fichas almacenadas se muestran inmediatamente y se intentan actualizar en segundo plano. La caché de metadatos se limpia independientemente de la biblioteca, el progreso y las descargas.

El reproductor Flutter usa video_player con los MP4 que admite el resolutor existente de MP4Upload: controles de pausa, avance/retroceso, barra de tiempo, reanudación, velocidad, pantalla completa, orientación, episodios anterior/siguiente, selección de servidor/idioma y marcado de vistos. Pausa al salir de Anime o al pasar la app a segundo plano. Guarda el progreso cada cinco segundos y en transiciones. Las escrituras se serializan con una instantánea del episodio para que un cambio de episodio no atribuya progreso al siguiente. Abrir el reproductor no inicia una descarga.

Las descargas locales reutilizan el motor Kotlin/WorkManager de Yoma con cola y base de datos separadas de las antiguas cuentas web. Incluyen progreso, pausa, cancelación, reintentos, restricción Wi-Fi, detección de duplicados, recuperación de transferencias, comprobación de archivo MP4 y SHA-256 y reproducción desde archivo local. La carpeta `local` evita colisiones con descargas antiguas de usuarios numéricos. En versiones anteriores a Android 8 la cola local no se ofrece como compatible.

## Navegación y protección de Manga

Se conserva el selector, los botones globales Yoma/Manga/Anime, el Navigator de Manga y un Navigator interno de Anime. Cambiar de sección mantiene montadas las pantallas y pausa el vídeo. Búsqueda/filtros/tab y preferencias persisten entre aperturas; la pila de fichas y el desplazamiento se conservan durante la sesión, no se promete restaurar toda la pila tras terminar el proceso.

No se cambiaron las fuentes, el lector, las descargas, la biblioteca ni el servicio OAuth de Manga. Se corrigió en la copia Yoma un desbordamiento real de la cabecera de Manga en una pantalla de 320 px con escala de texto 1.6: ahora su marca se ajusta al espacio disponible.

## Archivos y componentes

Nuevos componentes en `lib/features/anime/`:

- `models/anime_models.dart`: títulos, páginas, temporadas, episodios, servidores y descargas.
- `data/yomatv_source.dart`: API pública y sesión anónima del alojamiento, sin identidad web obligatoria.
- `data/anime_local_store.dart`: registros SQLite por espacios de nombres, sin cambiar el esquema Manga.
- `data/anime_controller.dart`: catálogo, búsqueda, estado local, caché, navegación y cola.
- `data/local_anime_downloads.dart`: canal Android local independiente del puente web anterior.
- `data/anime_mal_client.dart`: reutilización del cliente MAL compartido y negociación explícita de capacidades pendientes.
- `native_anime_screen.dart`: inicio, explorar, biblioteca, descargas y ajustes.
- `screens/anime_detail_screen.dart`, `anime_player_screen.dart`, `anime_mal_screen.dart`.
- `widgets/anime_cover.dart`, `anime_widgets.dart`: portadas con repositorio persistente separado y tarjetas.

Modificados: `lib/home/yoma_shell.dart`, `lib/features/anime/anime_screen.dart`, `lib/screens/home_screen.dart`, `pubspec.yaml` y `pubspec.lock` (video_player y versión 3.0.0+20).

Android: nuevo `android/app/src/main/kotlin/app/yomashi/reader/LocalAnimePlatform.kt`; registro en MainActivity y adaptación localizada de `app/yomatv/mobile/Store.kt` y `Queue.kt` para el almacenamiento local independiente. El motor de transferencia y su validación se conservan.

Pruebas: `test/unit/native_anime_test.dart` y actualización de `test/widgets/yoma_shell_test.dart`. Evidencias y auditoría: `docs/yoma/AUDITORIA-FLUTTER-ANIME.md`, `source-audit/`, `CONTRATO-MAL-ANIME.md` y registros `native-*.txt`. Herramienta de auditoría: `tools/audit_anime_source.py`; los scripts puntuales de implementación no son migraciones necesarias para ejecutar la app y no deben repetirse.

## WebView conservado

La opción de respaldo abre el YomaTV completo original. Conserva cuentas web, reproductores exclusivamente web, radio y herramientas sin equivalente nativo comprobado. No es el catálogo principal ni una pantalla de cuenta simplificada. El respaldo no intenta transferir tokens MAL a JavaScript. Las sesiones y descargas anteriores permanecen separadas; no se migran automáticamente a la cola local nueva.

## Límites reales y trabajo pendiente

La API pública responde para catálogo y fichas sin cuenta. El endpoint web `player` responde 401 a usuarios anónimos, por lo que no se utiliza como una API pública de streams. La resolución nativa reutiliza exclusivamente los proveedores compatibles ya contemplados por el motor. Si no hay servidor compatible o cambia su HTML, se muestra el error y se ofrece el respaldo web. No se añadieron controles de calidad ni subtítulos inexistentes en los datos. Los banners usan portadas reales como composición visual; no se inventan banners ni miniaturas de episodios.

MyAnimeList Anime **no está terminado de extremo a extremo**: el backend local inspeccionado solo admite operaciones de manga. La identidad opcional compartida se reconoce sin segundo OAuth y existe cliente preparado para lista, asociación explícita por ID MAL y cola de episodios, pero falta implementar y desplegar el contrato descrito en `CONTRATO-MAL-ANIME.md`. No se modificó ni desplegó el servidor. La app muestra esta limitación; la biblioteca, el progreso y las descargas locales no requieren MAL. La revocación sigue siendo la compartida existente. No se debe considerar cumplido el criterio de sincronización Anime/Manga con MAL hasta probar esa extensión con una cuenta autorizada.

No se ha realizado en este cambio una prueba instrumental en un dispositivo Android de reproducción real, descarga completa, reapertura offline o rendimiento Profile. La compilación y las pruebas del motor no sustituyen esas comprobaciones. Deben verificarse además el botón Atrás, rotación/pantalla completa, cambio Manga/Anime durante vídeo, interrupción de descarga y restablecimiento del proceso en el dispositivo objetivo antes de retirar el respaldo.

## Verificación

- Flutter analyze: sin incidencias.
- Suite Flutter: 260 pruebas correctas, tres omitidas por activación opcional (pruebas externas/capturas); ninguna desactivada para ocultar fallos.
- Motor JVM: 18 pruebas, cero errores, cero fallos. Transferencia, rangos, integridad y validación del proveedor comprobadas por la suite existente.
- APK Android Debug: compilado correctamente.
- APK Android Release: compilado con identificador QA para prueba independiente. Firma de depuración de pruebas; no se presenta como actualización personal de producción.
- Auditoría HTTP: catálogo real (4488 entradas en la captura), fichas y episodios públicos; reproductor privado 401. Las respuestas auditadas son evidencia de esa fecha, no garantía de disponibilidad futura.

Fallos investigados: el selector esperaba el mensaje del WebView anterior (prueba desactualizada, sustituida por comprobación de navegación nativa); el test de la cabecera MAL detectó un desbordamiento real, corregido en Yoma; el nuevo test HTTP necesitó un cliente de loopback real porque Flutter intercepta las conexiones en pruebas de widgets. Se mantuvieron todas las comprobaciones de Manga y la suite completa pasó después.

APK: dist/Yoma-3.0.0-anime-nativo-prueba.apk. Paquete app.yomashi.reader.qa, versión 3.0.0 (20), Android mínimo 24, target 36, 162272911 bytes. SHA-256: 5C61D4C6907CAF1D74BE5D68F9057C65668399547F4E3A0D6F26B82DB1772267. Firma verificada: Android Debug, certificado SHA-256 a8dc9aa621867f6229a9a2b8640f8343ec0de1302d9e97e885d3e78567806dc4. Puede actualizar la instalación QA firmada con ese certificado; no reemplaza la aplicación personal con otro paquete/firma.
