# Yoma: guía para Claude

Las reglas de trabajo (idioma, forma de actuar, depuración, comunicación y entrega de APK) están en [AGENTS.md](AGENTS.md). Aquí está lo que hace falta saber del proyecto.

## Qué es

App Android en Flutter con dos experiencias en una instalación, más sus webs:

- **YomaShi (Manga):** lector con varias fuentes, biblioteca, descargas y lectura sin conexión.
- **YomaTV (Anime):** catálogo, fichas, reproductor y descargas nativos. Toma el catálogo de tv.yoma.site.
- **MyAnimeList:** una sola conexión para las dos. Los tokens de MAL viven en el servidor; el teléfono guarda una credencial opaca.
- **Webs** (InfinityFree, PHP 8.4): yoma.site, shi.yoma.site, tv.yoma.site y api.yoma.site.
- **Repositorio:** https://github.com/EduardoGPT4/Yoma (rama `main`).

## Estructura

| Ruta | Contenido |
|---|---|
| `lib/features/anime/` | YomaTV. `data/anime_controller.dart` es el controlador, partido con `part` en `anime_controller_mal.dart` (MAL) y `anime_controller_watching.dart` (biblioteca ↔ MAL, descarga automática y borrado de vistos). Las pestañas están en `tabs/` como `part of native_anime_screen.dart`. |
| `lib/screens/`, `lib/providers/`, `lib/services/` | YomaShi. `services/manga_sync.dart` sincroniza el manga entre dispositivos. |
| `lib/data/` | Base drift (`LibraryStore`). Los datos sueltos van en `app_records` por espacio de nombres: `getRecord`, `putRecord`, `replaceRecords`. |
| `lib/design/` | Tokens y componentes Yoma. La web copia los tokens con `tools/generate_web_tokens.py`. |
| `android/app/src/main/kotlin/` | Nativo: cola de descargas de anime (`app/yomatv/mobile/`) y puente `app.yoma/anime_local` (`LocalAnimePlatform.kt`). |
| `server/` | Fuente del puente MAL y de la sincronización (`private/yoma-sync.php`). Se copia a `web/api.yoma.site/private/` y a la versión activa de tv. Si cambias `server/`, actualiza también las copias. |
| `web/<dominio>/` | Lo que se sube a `htdocs` de cada dominio. Ver [web/README.md](web/README.md). |
| `tools/` | Publicación de APK y web, mantenimiento del catálogo y verificación Android. |
| `docs/releases/MEJORAS_X_Y_Z.md` | Notas de cada versión, que se usan también en la Release de GitHub. |

## Comandos

```shell
flutter pub get
dart format lib test integration_test test_driver   # la CI falla si queda algo sin formatear
flutter analyze
flutter test
python3 test/backend/test_yoma_sync.py               # y el resto de test/backend/*.py que lista la CI
```

- **Fuentes de Linux:** la CI corre en Linux sin Segoe UI. Para reproducir sus desbordes o textos fuera de pantalla en Windows, usa `WINDIR=C:/no-existe flutter test test/widgets`.
- **Capturas de las pruebas de diseño:** quedan en `build/test_screenshots/design/`.
- **CI** (`.github/workflows/flutter.yml`): Flutter 3.47.5 y PHP 8.4. Tiene dos trabajos, `checks` y `android-integration` (emulador). Las anotaciones de los fallos se leen sin iniciar sesión en `https://api.github.com/repos/EduardoGPT4/Yoma/check-runs/<id>/annotations`.
- **Límite de la API anónima de GitHub:** 60 consultas por hora. No sondees en bucle; la página pública `github.com/EduardoGPT4/Yoma/actions` (en el navegador integrado) no tiene límite. `gh` no está instalado.

## APK personal y publicación

1. **Versión:** sube `version:` en `pubspec.yaml` (`X.Y.Z+N`; versionCode = 2000 + N) y escribe `docs/releases/MEJORAS_X_Y_Z.md`.
2. **Compila:**
   ```shell
   flutter build apk --release --target-platform android-arm64,android-x64 --split-per-abi --dart-define=YOMASHI_PERSONAL_RELEASE=true
   ```
   La build x86_64 sirve para el emulador; la arm64, para el teléfono y la Release.
3. **Comprueba** con `aapt2 dump badging` (versión) y `apksigner verify --print-certs`. La firma debe ser `a8dc9aa621867f6229a9a2b8640f8343ec0de1302d9e97e885d3e78567806dc4`.
4. **Copia** el APK a `dist/Yoma-X.Y.Z-arm64.apk`. `dist/` no va en Git.
5. **Publica** después de que la CI pase:
   ```shell
   python -I tools/publish_apk.py --apk dist/Yoma-X.Y.Z-arm64.apk --notes-file docs/releases/MEJORAS_X_Y_Z.md --target <commit>
   ```
   Entrega al usuario el enlace `releases/download/vX.Y.Z/...`.
6. **Teléfono del usuario** (Xiaomi, serie `5HEAV46PBUMZBUCA`), solo si está conectado:
   - antes de instalar, compara la firma del APK instalado (`pm path` + `adb pull`) con la del nuevo;
   - instala con `adb install -r`, que conserva los datos;
   - comprueba que `firstInstallTime` no cambió.

## Restricciones que no se negocian

- **Nunca `flutter drive` ni `flutter run` contra el teléfono personal.** Una vez desinstaló `app.yomashi.reader` y borró los datos.
  - Las pruebas instrumentadas solo van en el emulador `SeasonAV1_QA`, con `tools/verify_android.ps1`, que compila el APK QA (`app.yomashi.reader.qa`) y verifica su paquete antes de instalarlo.
  - Copia `/sdcard/Yoma/YomaShi/Backups` antes de tocar la app del teléfono.
- **Secretos fuera de Git:** `lib/config/app_secrets.dart` y `lib/models/tmo_manga.dart` están en `.git/info/exclude`. Añade archivos uno por uno, nunca `git add -A`.
- **Credenciales:**
  - no leas, imprimas ni empaquetes `config.local.php` ni `access.local.php`;
  - no manejes contraseñas de FTP o MySQL ni tokens;
  - el usuario edita el servidor y los secretos de GitHub (`YOMA_MAINTENANCE_TOKEN`).
- **MAL real:** no escribas en una cuenta real de MyAnimeList para probar sin permiso explícito. Las pruebas usan MAL simulado.
- **Exclusiones de contenido** (`lib/services/content_exclusions.dart`): no cambies el bloque marcado «No cambies por nada del mundo esto». La protección de menores (`loli`, `shota`) se queda.
- **Regla de visto de YomaTV:** un episodio cuenta como visto al 80 % de la posición. El usuario decidió mantenerla; no propongas cambiarla.

## Webs (InfinityFree)

- **Alojamiento hostil:** no llega la cabecera `Authorization` (usa `X-YomaShi-Token` o `X-Yoma-Maintenance`) y falta el certificado intermedio GTS. En Linux hay que cargar `android/app/src/main/res/raw/gts_*.pem`. Todo cliente debe resolver el reto `__test`; ver `tools/run_catalog_maintenance.py`. Prueba siempre contra el servidor real, no solo con `php -S`.
- **tv.yoma.site por versiones:** `private/current.json` indica la versión activa en `releases/`.
  - Si cambias un archivo de la versión, recalcula su huella en `releases/<versión>/private/ready.json`; si no, falla `test/unit/yoma_web_source_test.dart`.
  - No borres `releases/yoma-bridge-*` ni `releases/yoma-native-mal-*`: siguen en uso.
- **Desplegar:** `python -I tools/web_release.py estado|paquete|publicado <sitio>`.
  - El usuario sube el zip de `dist/sitios/actualizacion/`.
  - Después, `publicado` comprueba el sitio y anota el commit en `web/desplegado.json`; haz commit de ese archivo.
- **Mantenimiento del catálogo:** lo lanza la tarea de GitHub `catalog-maintenance.yml`. GitHub la retrasa y a veces solo corre 3 o 4 veces al día.

## Entorno Windows: trampas conocidas

- **Finales de línea:** LF. El repositorio tiene `core.autocrlf=false`, `core.eol=lf` y `.gitattributes`. Escribe archivos con `newline='\n'`.
- **Bash, PowerShell y archivos:**
  - los heredocs de Python dentro de Bash rompen las comillas y barras de PHP, JS o Dart; para cambios con escapes usa la herramienta Edit o un script `.py` en el directorio temporal;
  - las capturas binarias (`adb exec-out screencap -p > s.png`) se hacen desde Bash: PowerShell corrompe el PNG;
  - `adb` está en `$LOCALAPPDATA/Android/Sdk/platform-tools/adb.exe`, no en el PATH.
- **Extensiones de Dart:** una extensión no puede declarar campos. Los campos van en la clase y sus miembros estáticos se nombran con el tipo.
