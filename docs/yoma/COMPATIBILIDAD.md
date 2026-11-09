# Yoma 2.9.0: puente MAL y anime nativo

## Integración

Yoma conserva el lector, las fuentes, SQLite, páginas vistas, biblioteca y cola de manga. El WebView de Flutter permanece montado al cambiar de sección y ahora se conecta al motor Android original de YomaTV mediante `NativeAnimeBridge`.

En la ficha y el reproductor aparecen las acciones nativas de descargar. El icono de descargas en la barra de YomaTV abre el panel Android: selección de capítulos, cola persistente, pausa/reintento, opción solo Wi-Fi, agrupación por serie, progreso, verificación de archivos y reproducción offline. Se porta el reproductor Media3 original y su seguimiento de posición/vistos. Volver al catálogo actualiza su progreso con el evento original de YomaTV.

El motor de transferencia conserva su módulo JVM y sus pruebas originales. Solo cambian los puntos de integración y nombres que deben evitar colisiones con manga.

## Separación de datos

- Preferencias anime: `yoma_anime_private`.
- SQLite anime: `yoma_anime.db`, con registros y progreso separados por propietario web.
- Videos: directorio externo privado de la app `Movies/Yoma/YomaTV/EpisodiosDescargados/<owner>/...`; fallback privado persistente si no está disponible.
- Cola WorkManager: `yoma-anime-downloads` y `yoma-anime-sync-<owner>`.
- Canales de notificación y archivo de bloqueo propios para anime.

Salir de MAL cancela los trabajos de la cuenta anterior, reinicia la identidad nativa y espera a que termine la eliminación de cookies. Los archivos y el progreso por propietario se conservan. Biblioteca, páginas y descargas de manga no se migran ni se borran. Al volver a autenticar la cuenta web correspondiente se puede retomar su biblioteca de anime.

## Puente MAL publicado

Endpoint: https://hk-br035.gt.tc/seasonav1/yoma-session.php.

El endpoint recibe la credencial opaca del dispositivo por una cabecera HTTPS, comprueba hash y caducidad y vincula una única cuenta web que tenga el mismo ID MAL. Regenera la sesión y CSRF. No envía tokens OAuth a Flutter o JavaScript ni los pone en URLs o archivos de descargas.

Se publicó como extensión inmutable verificada por FTPS. La publicación activa de YomaTV no se reemplazó y su salud se comprobó después. Recibos: mal-bridge-deploy.json y mal-bridge-live.json. tools/deploy_yoma_bridge.py permite comprobar el estado y rechaza sobrescribir un endpoint distinto.

Requisito actual: la identidad MAL debe estar vinculada una vez a una cuenta de la web YomaTV. Si falta la vinculación o el ID aparece en varias cuentas, se rechaza con 409 y se ofrece abrir la cuenta web. No se crean cuentas ni se elige silenciosamente entre varias. La administración central de MAL está en el inicio de Yoma; cambiar la conexión directamente en la web no reemplaza automáticamente las credenciales del lector.

## Límite de confianza

Se usa `WebViewCompat.addWebMessageListener` con origen HTTPS exacto, comprobación de frame principal y ruta de YomaTV. No se utiliza `addJavascriptInterface`. No se admiten rutas, URLs o intents arbitrarios desde mensajes web. El adaptador recibe metadatos de planes autorizados; la cola obtiene el video mediante el resolver existente y verifica el resultado antes de marcarlo completo.

El adaptador accede al WebView del plugin mediante su identificador público y su instance manager Android. webview_flutter y webview_flutter_android están fijados en 4.14.1: cualquier actualización debe ejecutar la regresión Android del adaptador.

## Compatibilidad y pruebas

Las descargas nativas requieren Android 8/API 26 o posterior. El lector y la web siguen disponibles desde API 24; los métodos nativos informan si el dispositivo no es compatible. Los botones del catálogo requieren Android System WebView compatible con WEB_MESSAGE_LISTENER.

Se conservan los proveedores y límites de YomaTV original. El motor nativo descarga/reproduce desde los servidores admitidos por ese resolver, incluido MP4Upload; otros reproductores pueden continuar en la web. No se afirma disponibilidad actual de todos los proveedores externos.

La matriz exacta de comprobaciones se registra en ANIME-NATIVO.md. El emulador usa un paquete de integración independiente, app.yoma.integration.qa; no se sobrescribió su instalación QA previa ni se instaló nada en el teléfono conectado.

El APK entregado sigue siendo una compilación debug personal de prueba con app.yomashi.reader.qa; la versión de producción conserva su identificador. No se publicó en GitHub. Los datos privados no sobreviven normalmente a una desinstalación y no se importan automáticamente desde las APK antiguas.
