# Anime nativo y puente MAL — Yoma 2.9.0

## Resultado de las comprobaciones

- Flutter: 255 pruebas aprobadas, 3 opcionales omitidas, sin fallos (`anime-tests.json`). Análisis estático limpio.
- Motor JVM original: 18 pruebas aprobadas, sin errores. Incluyen reanudación/rangos, validadores, cancelación, MP4 truncado o falso, integridad y validación de hosts.
- Android API 35 en el emulador: 17 casos completados, 15 aprobados y 2 omitidos por ser pruebas optativas contra proveedores reales. Sin fallos (`android-verified.txt`).
- Puente MAL local: 13 comprobaciones aprobadas con HTTP y SQLite aislados (`test/backend/test_yoma_session.py`). No se utilizaron cuentas personales.
- Servidor real: puente desplegado; una solicitud anónima devuelve 401 y la salud de YomaTV permanece correcta. La versión activa sigue siendo `yomatv-episodes-20261108-1`.
- APK debug QA: Yoma 2.9.0, código 17, paquete `app.yomashi.reader.qa`, firma verificada con el mismo certificado debug anterior. SHA-256: `62C44356C53F408EF8D4A4AE8DA1299AD79F80436A7DE89791FC5F8588342AB2`.

## Qué se probó en Android

- Mensajes de origen ajeno y de iframes rechazados; mensaje válido de la página principal aceptado.
- Desconectar la identidad conserva archivos, registros y datos del manga.
- Separación de propietarios y deduplicación; presentación y consulta de 100 capítulos.
- Recuperación de un archivo final válido sin descargarlo otra vez.
- Reproducción offline, búsqueda de posición y marcado de visto al alcanzar el umbral original.
- Sesión web, cookies y CSRF en las solicitudes nativas; captura de identidad al enviar progreso.
- Lectura de rangos HTTP, rechazo de hosts no admitidos y reproducción de un video sintético por streaming.
- Panel de descargas que conserva las vistas y el desplazamiento durante los cambios de progreso.
- Progreso online separado de las descargas y recuperación de la biblioteca al actualizar su esquema.

Las dos omisiones de Android son `liveProviderDownloadPauseResumeAndDecode` y `liveMp4UploadPlaysAcrossTheReportedStallPosition`. Requieren los flags de pruebas en vivo del proyecto original. No se eliminaron ni se desactivaron pruebas para obtener estos resultados.

## Diagnóstico de los fallos intermedios

La primera ejecución Android detectó cuatro fallos:

1. `nativeApiUsesSessionCookieCsrfAndCapturedIdentity` y `streamSourceValidatesRangesAndProviderHosts`: los fixtures HTTP de 127.0.0.1 quedaban bloqueados porque faltaba portar la configuración de red de debug de YomaTV. Se restauró esa configuración exclusivamente en debug y solo para loopback, manteniendo HTTPS para el resto.
2. `onlinePlayerDecodesSeeksAndUsesTheSameEightyPercentRule`: mismo bloqueo de red; Logcat mostraba un error de fuente de ExoPlayer. Se resolvió al restaurar la configuración anterior.
3. `originAndMainFrameAreRequiredForNativeMessages`: el fixture `loadDataWithBaseURL` dejaba `WebView.url` en `about:blank`. El adaptador rechazaba correctamente esa URL. Se corrigió el fixture para interceptar una navegación real a su URL HTTPS sintética; la validación de producción no se debilitó.

Antes, la prueba JVM del motor no compilaba dentro del módulo Android porque `com.sun.net.httpserver` pertenece al JDK, no al SDK Android. Se mantuvo el motor en su módulo JVM original y se ejecutaron allí las mismas pruebas. También se alinearon las dependencias Android de debug con las que incorpora Flutter integration_test.

## Reproducción y límites

`tools/run_native_tests.ps1` compila e instala únicamente `app.yoma.integration.qa` y su instrumentación en `emulator-5554`, verifica los identificadores antes de instalar y falla si el informe no confirma éxito. Se preservó la instalación QA anterior del emulador. No se instaló nada en el teléfono conectado ni se editaron los proyectos originales.

El puente necesita que el ID MAL esté vinculado previamente a una única cuenta de YomaTV. No se realizó un OAuth personal ni una descarga completa de un episodio comercial. Las pruebas de reproducción utilizan videos sintéticos; la disponibilidad externa sigue dependiendo de los proveedores. Las descargas nativas requieren Android 8 o posterior.

La instalación y el uso se describen en COMPATIBILIDAD.md. No hubo publicación en GitHub.

## Comprobación visual adicional

Se abrió el selector Flutter y el catálogo real de YomaTV en el emulador y se comprobó que el botón de descargas de Flutter abre app.yomatv.mobile.MainActivity dentro de la misma instalación. Capturas: android-smoke.png y android-downloads.png. El emulador tenía configurado un proxy antiguo 127.0.0.1:8899; se desactivó temporalmente para la comprobación y se restauró después. Ese problema era del entorno, no del servidor ni del APK. El primer arranque debug del emulador tardó aproximadamente 29 segundos; esto no mide el rendimiento de una compilación release en teléfono.

