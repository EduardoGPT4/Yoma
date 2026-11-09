# YomaShi 2.3.2 — MyAnimeList para manga

## Uso

- Perfil → MyAnimeList · Manga → Conectar cuenta. La autorización se abre en el navegador; comprueba el código y vuelve a YomaShi al terminar.
- Busca por nombre, ID numérico o enlace `https://myanimelist.net/manga/ID/Titulo`.
- Selecciona un resultado para editar capítulos leídos y estado: leyendo, completado, en pausa, abandonado o por leer.
- Desde la ficha de una obra o el menú del lector puedes confirmar su vínculo con un resultado MAL y activar el envío automático al terminar capítulos.
- Los envíos automáticos conservan el mayor progreso existente. Se conservan los estados completado, en pausa y abandonado. Una obra se completa automáticamente solo cuando MAL confirma que terminó y se alcanza su total conocido.
- Los especiales fraccionarios y los capítulos sin número confirmado se omiten. En ediciones con numeraciones distintas, usa la actualización manual.
- La lectura local se guarda aunque la red falle. Los trabajos pendientes usan reintentos limitados y pueden reenviarse manualmente desde la pantalla MAL. No se envían trabajos de otra cuenta ni de un vínculo reemplazado.
- Desmarcar un capítulo local no reduce el contador remoto; puedes corregirlo manualmente en MAL.
- Las copias v4 incluyen vínculos por cuenta. La restauración sigue aceptando las versiones 1, 2 y 3. Las credenciales no se exportan.
- Desde 2.3.2, el perfil utiliza el nombre de la cuenta MAL conectada como nombre visible y `@usuario`. Se actualiza al autorizar, cambiar o desconectar la cuenta, y se conserva sin conexión mediante la sesión cifrada existente. El nombre local previo se recupera al desconectar y sigue siendo el que se guarda en las copias portables.

## Servidor y despliegue

Esta extensión utiliza la aplicación OAuth de tipo web ya configurada en el alojamiento de YomaTV y su callback `https://hk-br035.gt.tc/seasonav1/mal-callback.php`.

Android solo recibe una credencial de dispositivo. Se cifra con AES-GCM y una clave de Android Keystore; la sustitución condicional impide que respuestas de sesiones antiguas borren una conexión nueva. El servidor conserva cifrados los tokens MAL y protege el secreto de cliente en su configuración privada existente. OAuth usa PKCE y estado ligado a la sesión del navegador, con caducidad y uso único.

Instalar en el código del sitio existente:

```sh
python tools/install_mal_backend.py --web-root RUTA_A_YOMATVWEB
python test/backend/test_myanimelist.py
```

El instalador es idempotente. Añade las rutas de manga al adaptador MAL, extiende las listas de rutas públicas del publicador e incorpora los endpoints y la tabla privada `sa1_yomashi_devices`. El callback distingue los estados de YomaShi mediante el prefijo `ys_` y conserva el flujo de anime del sitio.

Publicar después con el procedimiento existente del sitio: copia de seguridad cifrada y verificada, release inmutable, validación de salud y cambio atómico de versión. No subir configuraciones privadas ni claves de firma al repositorio.

El despliegue inicial por FTPS se detuvo por un certificado vencido. La publicación se realizó después mediante el administrador oficial de InfinityFree por HTTPS, con copia de seguridad cifrada verificada y paquete de archivos comprobado antes de activar la nueva versión. Los auxiliares temporales de publicación se eliminan al terminar.

La versión 2.3.1 adapta las peticiones al alojamiento real: envía la credencial de dispositivo también en `X-YomaShi-Token`, porque el servidor elimina `Authorization`. El backend rechaza cabeceras que contengan credenciales diferentes. El cliente envía JSON UTF-8 con longitud explícita y cierra cada conexión HTTP para evitar respuestas malformadas del proxy.

El botón de autorización requiere además permitir el destino de la redirección en `form-action`. La página de conexión conserva la política del sitio y añade únicamente `https://myanimelist.net` a esa directiva. Esto corrige el bloqueo silencioso de Chromium al seguir el POST hacia MAL y se aplica en el servidor, sin reinstalar el APK.

## Verificación

Las pruebas de Flutter cubren búsquedas por nombre/ID/URL, estados, validación, cola sin conexión, reintentos, alias de capítulos locales y remotos, cambio de cuenta, respuestas antiguas, envíos concurrentes, capítulos especiales y backups sin credenciales. Las pruebas HTTP ejecutan los endpoints PHP con un proveedor MAL local: sesión, CSRF, PKCE, callback, cifrado, tokens de renovación rotativos, actualizaciones PATCH y límites de progreso. No modifican ninguna cuenta MAL real.

La prueba de conexión real puede ejecutarse de forma voluntaria con `flutter test test/live/myanimelist_live_test.dart --dart-define=YOMASHI_LIVE_MAL=true`. Requiere PHP local para reproducir la operación AES del puente Android. Crea y revoca su propia conexión pendiente; no autoriza ninguna cuenta MAL ni modifica listas. Las pruebas habituales omiten esta petición externa.

La regresión del botón se prueba también en un perfil nuevo de Chrome: con Node.js, Playwright y Chrome disponibles, ejecutar `test/backend/test_myanimelist.py` con `YOMASHI_BROWSER_TESTS=1`. `PLAYWRIGHT_MODULE` permite indicar la ruta de Playwright si no está instalado en el proyecto. La prueba hace clic en el formulario y comprueba que Chromium solicita la navegación a MAL; una respuesta HTTP 303 por sí sola no detecta este fallo de CSP.

La autorización de una cuenta personal se completa desde el navegador al conectar MyAnimeList en el APK. Las pruebas de actualización de capítulos y estado utilizan un proveedor local controlado; no alteran una cuenta real.

Validación del 27 de octubre de 2026: 120 pruebas locales aprobadas, análisis estático sin incidencias y prueba voluntaria contra el servidor real aprobada (conexión pendiente, estado y revocación). Se verificó además el formulario de vinculación, CSRF, PKCE y la redirección a la aplicación MAL registrada. El release web activo es `yomashi-authorize-20261027-1`; sus 131 archivos se comprobaron antes de la activación. El APK ARM64 2.3.1 usa código de versión 2005 y conserva el certificado de la instalación personal anterior.

La regresión adicional de Chromium reprodujo el bloqueo con la política anterior y aprobó con la corrección, tanto en la prueba local como en el sitio publicado: clic real, POST 303, solicitud al destino MAL y ausencia de errores CSP. Se revocaron las conexiones de prueba y se retiraron los auxiliares temporales del despliegue.

Validación de 2.3.2: 131 pruebas de Flutter aprobadas y análisis sin incidencias. Incluye perfil cacheado, modo sin conexión, inicio y cierre de sesión, revocación, cambio de cuenta, lecturas tardías y descarte de actualizaciones después de cerrar el perfil. La interfaz se probó a 320 píxeles con texto ampliado. El APK ARM64 utiliza código 2006 y el certificado personal anterior.

Referencias oficiales: [OAuth de MyAnimeList](https://myanimelist.net/apiconfig/references/authorization), [API v2](https://myanimelist.net/apiconfig/references/api/v2).
