# Diagnóstico y propuesta mínima: Yoma → YomaTV / MAL

Estado: investigación en modo lectura del servidor y propuesta. No se han modificado ni desplegado cambios de autenticación en esta fase. Las modificaciones de imágenes solicitadas después se realizan de forma independiente.

## Identificación de la pantalla

Los mensajes «Conecta MAL desde Yoma.» y «Abrir cuenta de YomaTV» se emiten juntos en `server/yoma-session.php`, dentro de su respuesta de error. Es una página técnica del puente. No es el catálogo ni la sección de cuenta de YomaTV. El enlace apunta a `./#account`, que sí abre la sección real de cuenta de la web completa.

Se comprobó por FTPS que el código publicado del puente coincide con el local. La publicación activa sigue siendo `yomatv-episodes-20261108-1`.

## Causa confirmada del mensaje concreto

La frase «Conecta MAL desde Yoma.» se devuelve cuando falta `X-YomaShi-Token` o no tiene el formato esperado. Una credencial con formato válido que no pertenece a un dispositivo registrado produce otro mensaje: «La conexión MAL caducó.».

Prueba controlada en el servidor, sin credenciales personales:

- Petición nueva: HTTP 200 con el desafío JavaScript de cookies del alojamiento y una navegación posterior por JavaScript.
- Después del desafío, mismo navegador y cookie, con una credencial ficticia de formato válido: HTTP 401 y mensaje de dispositivo caducado. La petición sí llega a la búsqueda del dispositivo.
- Misma petición sin cabecera: HTTP 401 y exactamente los dos textos descritos por el usuario.

El código Flutter abre la URL del puente con una cabecera adicional. El alojamiento puede contestar primero con JavaScript que establece su cookie y vuelve a navegar a la URL. Esa nueva navegación no reconstruye la cabecera que añadió Flutter. La respuesta técnica termina ocupando el WebView.

Además, `_hasSynced` se marca como verdadero cuando `loadRequest` termina de iniciar la carga, sin esperar la confirmación de una sesión web válida. El botón de compartir vuelve a salir inmediatamente si la credencial no ha cambiado. La recarga genérica actúa sobre la URL técnica actual. Esto impide una recuperación fiable.

## Los dos sistemas actuales

YomaShi/Yoma usan OAuth MAL mediante `yomashi-connect.php`, PKCE y el callback compartido. El servidor guarda los tokens cifrados en `sa1_yomashi_devices`; Android guarda una credencial opaca del dispositivo en su almacén cifrado. Conectar aquí no establece por sí mismo una sesión de usuario YomaTV.

YomaTV autentica correo/contraseña y establece `SEASONAV1_WEB`, con `user_id`, `auth_version` y CSRF. Su conexión MAL se guarda por usuario web en `sa1_mal_connections`. También existe `sa1_mal_identity`, que conserva el ID numérico verificado por OAuth y se actualiza al cambiar la identidad MAL.

El puente ya intenta reconocer la misma identidad mediante ID MAL numérico, no por nombre. Sin embargo, solo acepta una fila única en `sa1_mal_connections` con `needs_auth=0`. Eso exige una conexión MAL web actualmente activa y desaprovecha una asociación previamente verificada si esa conexión necesita renovarse. No se consultaron filas personales; no está confirmado que ese sea el estado de la cuenta concreta del usuario.

## Contraste y funciones

La página técnica no carga hojas de estilo, no define colores y su CSP bloquea recursos de estilo por defecto. Sobre el fondo oscuro del WebView, el texto predeterminado puede quedar negro y poco legible. No corresponde a una sustitución del catálogo por una interfaz nueva, sino a una respuesta técnica visible por el fallo de sesión.

La web completa sigue en la URL raíz y conserva las rutas de catálogo, temporada, biblioteca, reproductor y cuenta. Los componentes nativos de descargas y Media3 siguen en el APK. El contenedor Yoma conserva su IndexedStack, Navigator de manga y botones para Yoma / Manga / Anime. El problema bloquea el acceso normal; no hay evidencia de que esas funciones hayan sido eliminadas. Esta revisión no vuelve a probar una descarga real ni un OAuth personal.

## Cierre de sesión: defecto confirmado

El puente guarda el hash del dispositivo como `$_SESSION['yoma_device']`, pero la función `validate_session()` publicada solo comprueba `auth_version`. No valida ese vínculo con el dispositivo.

Al desconectar desde Yoma se elimina `sa1_yomashi_devices` y se limpian cookies y trabajos locales, pero una sesión PHP ya emitida no queda invalidada en el servidor por esa eliminación. Hace falta comprobar el vínculo también en el backend; borrar cookies no equivale a revocar la sesión remota.

## Modificación mínima propuesta

1. Conservar la web y sus navegadores. Abrir siempre la raíz y sus rutas completas; no dejar respuestas del puente como pantalla principal. Mostrar fallos de conexión como avisos legibles y mantener disponible el acceso manual a `#account`.
2. Hacer el intercambio autenticado con el cliente HTTP nativo que ya gestiona el desafío del alojamiento, en lugar de depender de una cabecera adjunta a una navegación WebView. El servidor crea/regenera la sesión web y devuelve su cookie para instalarla mediante el código nativo del WebView. Mantener `Secure`, `HttpOnly`, `SameSite`, ruta y dominio exactos. Ningún token MAL ni credencial de dispositivo pasa al JavaScript. Un ticket corto de un solo uso ligado al WebView sería otra opción, pero añade almacenamiento y no es la primera elección para este proyecto.
3. Resolver el usuario web por una única asociación de ID MAL numérico verificada en el servidor, reutilizando `sa1_mal_identity` y las comprobaciones actuales. Sin asociación, o si es ambigua, mantener el inicio manual. Tras autenticar manualmente, la asociación se establece solo mediante una verificación MAL válida; nunca por nombres coincidentes ni fusiones de bibliotecas.
4. Reutilizar los adaptadores de acceso MAL para que ambos módulos consulten una fuente autorizada de tokens y su renovación. Iniciar una sesión web y compartir la autorización MAL son operaciones distintas: no basta con poner `user_id`. No copiar el mismo refresh token a dos almacenes que lo renueven independientemente, ni reemplazar contraseñas o datos de la cuenta web.
5. Ampliar `validate_session()` únicamente para sesiones vinculadas a Yoma: comprobar que el dispositivo siga existiendo, no haya caducado y siga asociado a esa misma cuenta/ID MAL. Al eliminarlo desde Yoma, las sesiones relacionadas quedan inválidas en su siguiente solicitud. Conservar las comprobaciones actuales de versión de autenticación y no cerrar indiscriminadamente otras sesiones manuales.
6. Marcar la sincronización como conseguida solo tras la confirmación del servidor y permitir reintentos explícitos. Evitar la doble navegación inicial y conservar los botones y el estado de cada sección. Aplicar colores de error coherentes con el tema y retirar la página técnica sin estilo del flujo normal.

## Verificación necesaria después de implementar

Primer acceso con cookies del alojamiento vacías; conexión y reconexión; cuenta vinculada, sin asociación y ambigua; renovación concurrente de credenciales; cookies de sesión protegidas; revocación remota tras salir de Yoma; acceso manual conservado; regresiones de catálogo, temporadas, biblioteca, reproductor, descargas y navegación entre secciones. No exponer secretos en registros ni inspeccionar credenciales del teléfono para realizar estas pruebas.
