# Yoma

Aplicación Android en Flutter que reúne dos experiencias con una sola instalación:

- **YomaShi (Manga):** lector con varias fuentes, biblioteca, descargas, lectura sin conexión, traducción de imágenes en el dispositivo y personalización.
- **YomaTV (Anime):** catálogo, fichas, reproductor y descargas nativos; usa la web YomaTV como fuente del catálogo y conserva un respaldo web para servidores no compatibles.
- **MyAnimeList:** una sola conexión para Manga y Anime. Los tokens de MAL se guardan en el servidor; el teléfono solo guarda una credencial opaca cifrada.

## Desarrollo

```shell
flutter pub get
flutter analyze
flutter test
python3 test/backend/test_myanimelist.py
python3 test/backend/test_anime.py
python3 test/backend/test_yoma_session.py
```

- El paquete de pruebas en Android es `app.yomashi.reader.qa`; el de producción, `app.yomashi.reader`.
- Las capturas que generan las pruebas se guardan en `build/test_screenshots/`.
- La carpeta `server/` contiene el puente MAL; los cambios ahí deben desplegarse aparte en el alojamiento.

## Documentación

- [Compatibilidad, almacenamiento y puente MAL](docs/yoma/COMPATIBILIDAD.md)
- [Verificación de anime nativo](docs/yoma/ANIME-NATIVO.md)
- [Diagnóstico del puente MAL](docs/yoma/DIAGNOSTICO-PUENTE-MAL.md)
- [Vista del selector](docs/yoma/selector.png)

Imágenes de marca: `assets/branding/1-Anime.png`, `2-Manga.png` y `3-AniManga.png`.
