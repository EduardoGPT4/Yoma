# Yoma 3.0.3 — Correcciones de la auditoría técnica

Correcciones derivadas de la auditoría del 9 de noviembre de 2026. Los identificadores (Y-xx) son los del informe de auditoría.

## Cambios

| ID | Cambio | Archivos principales |
| --- | --- | --- |
| Y-01 | Las páginas de manga vistas se guardan en `files/Yoma/YomaShi/PaginasVistas` en lugar de la caché temporal. La caché antigua se migra una vez sin volver a descargar. Se mantiene el límite de 256 MiB; en Almacenamiento aparecen como "Páginas vistas". | `lib/services/image_repository.dart` |
| Y-02 | Al salir de Manga con un capítulo abierto, el lector suelta las teclas de volumen, la orientación y el modo de pantalla, guarda el progreso y deja de precargar. Al volver los recupera. | `lib/home/yoma_shell.dart`, `lib/screens/reader_screen.dart` |
| Y-04 | Un conflicto de MAL Anime (409/422) se aparta 15 minutos y no bloquea la sincronización de los demás animes. Resolverlo lo envía al momento. | `lib/features/anime/data/anime_mal_client.dart` |
| Y-05 | La sesión MAL del dispositivo se renueva con el uso (90 días deslizantes, como máximo una escritura al día). Sin conexión se puede olvidar la cuenta solo en el teléfono. | `server/private/yomashi-mal.php`, `lib/services/myanimelist_client.dart`, `lib/screens/myanimelist_screen.dart` |
| Y-06 | AGENTS.md ya no ordena publicar en GitHub sin autorización. | `AGENTS.md` |
| Y-09 | La barra "Yoma / Ir a Anime" solo aparece en la pantalla principal de cada sección, no sobre el lector ni el reproductor. | `lib/home/yoma_shell.dart`, `lib/features/anime/native_anime_screen.dart` |
| Y-10 | Sin red, el reproductor usa una descarga lista del episodio aunque sea de otro idioma. | `lib/features/anime/screens/anime_player_screen.dart` |
| Y-11 | La caché de búsquedas de anime conserva las 40 más recientes. Las fichas no se recortan porque sirven sin conexión. | `lib/features/anime/data/anime_local_store.dart`, `lib/data/library_store.dart` |
| Y-16 | La prueba del selector escribe su captura en `build/test_screenshots/`; la del puente de sesión encuentra PHP en Linux, y el CI ejecuta las tres suites del backend. | `test/`, `.github/workflows/flutter.yml` |
| Y-17 | Se eliminan `lib/config/app_secrets.dart` y `lib/models/tmo_manga.dart`, sin uso. | — |
| Y-19 | README actualizado. | `README.md` |
| Y-20 | Atrás en Manga vuelve primero a Inicio y después al selector. | `lib/screens/main_shell.dart` |
| Y-23 | La ficha de anime abierta se actualiza cuando llegan datos nuevos. | `lib/features/anime/screens/anime_detail_screen.dart` |

## Despliegue pendiente

El cambio de `server/private/yomashi-mal.php` (Y-05) debe subirse al alojamiento para que la sesión deje de caducar a los 90 días. Hasta entonces la app funciona igual que antes.

## Pendiente de decisión (no incluido)

- Y-03: que la web exponga los servidores de cada episodio en vez de leerlos de AnimeAV1.
- Y-07 y Y-08: unificar las colas de anime y decidir una carpeta común para las descargas.
- Y-12: notificador separado para descargas de anime (requiere medir antes).
- Y-13: keystore de release propio (requiere reinstalar una vez).
- Y-24: actualización de Gradle y AGP.

## Otros ajustes

- La fila de chips "Catálogo / Temporadas" de YomaTV baja de línea con letra grande en vez de desbordarse (también hacía fallar la prueba del selector en Linux).
- Formato de `lib/services/content_exclusions.dart` e `integration_test/sample_video_fixture.dart` según `dart format`: solo sangría y saltos de línea, sin cambiar su contenido.
