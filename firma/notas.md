APK personal ARM64 de Yoma 3.0.3 (código de versión 2023), compilado desde el commit 84bd04c y firmado con el mismo certificado de la instalación anterior, así que se instala encima sin perder datos.

## Cambios
- Las páginas de manga vistas se guardan en el almacenamiento de la app, no en la caché temporal; la caché antigua se traslada sola.
- Al cambiar a Anime con un capítulo abierto, el lector suelta las teclas de volumen y la orientación, y guarda el progreso.
- La barra Yoma / Ir a Anime solo aparece en la pantalla principal de cada sección.
- Atrás en Manga vuelve primero a Inicio.
- Un conflicto de MyAnimeList en un anime ya no bloquea la sincronización de los demás.
- Sin conexión se puede olvidar la cuenta de MyAnimeList solo en el teléfono.
- Sin red, el reproductor usa cualquier descarga lista del episodio.
- La caché de búsquedas de anime guarda las 40 más recientes, y la ficha abierta se actualiza al refrescar.
- Corregidos el desborde de los chips Catálogo / Temporadas y un fallo al cerrar el lector.

Detalle completo: `docs/releases/MEJORAS_3_0_3.md`.

## Pendiente
- La renovación de la sesión de MyAnimeList necesita subir `server/private/yomashi-mal.php` al alojamiento.
- Probado en emulador Android 15; no en un teléfono físico.

La suma SHA-256 está en `SHA256SUMS.txt`.
