# YomaShi 2.2.0+3 — mejoras y verificación

## Funciones implementadas

| Mejora | Comportamiento y ubicación |
| --- | --- |
| APK personal ARM64 | Compilación release con indicador personal explícito y el mismo certificado de la instalación anterior. No requiere Play Store. |
| Capítulo en otra fuente | Menú del lector y botones de error. Busca títulos equivalentes, compara número, volumen e idioma cuando existen y pide elegir la edición. Abre su primera página; no mezcla páginas de traducciones distintas. |
| Reparación | Perfil → Almacenamiento → obra → Revisar y reparar. Verifica manifiestos y estructura de imágenes, conserva páginas válidas y recupera las ausentes o truncadas. Solo considera capítulos cuya descarga ya se inició. |
| Novedades de favoritos | Perfil → Automatización y copias. La primera comprobación establece la base; las siguientes detectan novedades. Descarga opcional con Wi-Fi, carga y batería mínima configurables. Los fallos de una fuente no interrumpen las demás. |
| Prioridad del lector | Durante la lectura se limitan a dos los trabajadores de páginas de la cola. La precarga considera latencia y presión de memoria. La señal del lector expira si la pantalla desaparece; no inicia por sí sola un servicio de descargas. |
| Copias rotativas | Una diaria, con retención configurable de 2 a 30. Creación manual, historial, exportación y restauración combinada. Incluyen progreso, favoritos, leídos, categorías, ajustes, enlaces y marcadores; no imágenes. |
| Próximos capítulos | De 0 a 10 capítulos siguientes, con presupuesto configurable de 32 a 8192 MiB para páginas automáticas. Se contabilizan también descargas parciales y espacio reservado por la cola. Nunca elimina mangas para hacer espacio. |
| Herramientas del lector | Marcadores por página, lista para regresar al capítulo, recorte opcional de márgenes blancos y orientación por manga. Los ajustes de una obra no pasan a otra. El recorte conserva originales, procesa una imagen a la vez y limita su caché derivada. |
| Validación reproducible | Pruebas unitarias, integración nativa Android, medición de fotogramas y memoria en modo profile, script PowerShell y trabajo CI de emulador. |

## Correcciones surgidas al verificar

- La reparación mantiene el destino original y no queda bloqueada por trabajos anteriores detenidos o fallidos.
- Las novedades pendientes pueden descargarse cuando vuelven a cumplirse las condiciones; no se pierden tras una primera comprobación sin Wi-Fi.
- Los capítulos parcialmente descargados entran en la cuota automática.
- Una ficha paginada conserva en el manifiesto los capítulos conocidos de otras páginas.
- Los cambios de recorte invalidan dimensiones y precarga; se liberan las referencias a imágenes recibidas por los listeners.
- Se evitan callbacks de toques pendientes durante la destrucción del lector.
- Las transacciones de lectura/escritura reservan la escritura antes de consultar, para evitar SQLITE_BUSY_SNAPSHOT entre UI y servicio Android. Una prueba con dos conexiones WAL conserva 40 incrementos concurrentes.
- WorkManager y el servicio comparten un solo motor de cola. El trabajador puede iniciar un motor sin Activity y lo cierra al terminar.

## Pruebas

- Análisis Flutter sin incidencias y 96 pruebas automatizadas aprobadas.
- Las pruebas nuevas comprueban condiciones de red/batería, correspondencia y paginación entre fuentes, próximos N capítulos, cuota, marcadores concurrentes, copias válidas e inválidas, rotación, recorte, aislamiento de ajustes, reparación de una sola página y prioridad del lector.
- El escenario Android usa únicamente `app.yomashi.reader.qa` y un servidor local con imágenes conocidas. Comprueba pausa persistida en SQLite, reanudación, ocho páginas completas, reparación de una página sin tocar las otras, lectura, marcadores, recorte, orientación, copias y WorkManager.
- Escenario completo aprobado en el POCO X6 Pro 5G, Android 16, modo profile: ocho páginas verificadas, una sola petición adicional para reparar la página eliminada y WorkManager finalizado con SUCCEEDED después de cerrar el servicio de descargas.
- Navegación: 193 fotogramas, construcción media 1.154 ms, rasterización media 3.308 ms; ningún fotograma excedió el presupuesto de construcción o rasterización informado por Flutter.
- Apertura del lector de la muestra local: 555 ms. Memoria PSS del proceso completo (UI más motor del servicio): 254.0 → 260.5 MiB durante las doce transiciones. Es una muestra, no una prueba de ausencia de fugas a largo plazo.
- Informe crudo: `build/integration_reports/poco-profile.json`. Registro: `build/reports/logs/integration-profile.log`. No hubo errores SQLite en la ejecución aprobada.

## Datos y aislamiento

El primer despliegue de integración usó por error el identificador personal: una variable de entorno Gradle no llegó al proceso lanzado por Flutter. El guard de Dart detuvo la prueba antes de modificar datos, pero Flutter retiró la aplicación. Al reinstalar se recuperaron y comprobaron 8 progresos, 2 favoritos, 94 capítulos leídos, los dos trabajos anteriores en sus estados originales y el progreso anterior en página 10. Se guardaron una copia JSON y una captura de datos en el PC; los mangas públicos permanecieron en sus carpetas.

El aislamiento ahora deriva del mismo `--dart-define=YOMASHI_QA=true` utilizado por Dart. Antes de instalar, `tools/verify_android.ps1` comprueba el identificador real del APK con aapt y pasa ese binario a Flutter Drive. Además, el test exige en ejecución el identificador QA antes de escribir. Las compilaciones se ejecutan secuencialmente para no mezclar los registradores de plugins generados.

Las copias automáticas usan `/storage/emulated/0/YomaShi/Backups` si existe permiso de almacenamiento. Sin permiso, usan una carpeta privada y la pantalla avisa que debe exportarse para sobrevivir a una desinstalación. El permiso se restablece por el flujo normal de Android.

Flutter 3.47.5 genera una referencia al plugin de integración incluso cuando Gradle lo excluye de release. `android/app/build.gradle.kts` prepara una copia del registrador sin ese bloque exclusivamente para la compilación Java de release. Conserva el generado original para debug/profile y no modifica el SDK. Revisar y retirar esta compatibilidad cuando se resuelva [flutter/flutter#186800](https://github.com/flutter/flutter/issues/186800).

La verificación del APK release comprueba además que `io.flutter.plugins.GeneratedPluginRegistrant` exista realmente en el DEX. Esto evita entregar un APK que compile sin registrar sus plugins nativos. La misma comprobación se añadió a CI.

## Reproducción

```powershell
flutter pub get
dart format --output=none --set-exit-if-changed lib test integration_test test_driver
flutter analyze
flutter test
pwsh -File tools/verify_android.ps1 -Device IDENTIFICADOR -Mode profile
flutter build apk --release --target-platform android-arm64 --split-per-abi --dart-define=YOMASHI_PERSONAL_RELEASE=true
```

No ejecutar compilaciones Flutter simultáneas en este directorio. No ejecutar `flutter test integration_test` sobre la instalación personal. El script de validación solo admite el identificador QA y falla antes de instalar si no coincide.

## APK final instalado

- Archivo: `build/app/outputs/flutter-apk/YomaShi-2.2.0-arm64-personal.apk`.
- Release ARM64, sin modo depuración; versión visible 2.2.0, código Android 2003 (desplazamiento por ABI de Flutter sobre +3).
- Tamaño: 24,470,112 bytes (23.34 MiB).
- SHA-256: `1e1387859c32838de9b7817656e40786d13156203138c36aea86f63c9f26ce70`. Se comprobó el mismo hash en el APK instalado.
- Firma compatible con la instalación previa. Actualización final con `adb install -r`, sin desinstalar.
- Arranque Android COLD: TotalTime 990 ms. Después se comprobó el proceso vivo y la pantalla inicial con el progreso original en página 10.
- Registrador de plugins nativos presente en el DEX; el cierre de la primera compilación release quedó corregido antes de esta entrega.
- Informe de la comprobación final: `build/verification/final-summary.json`.

## Límites

Android decide cuándo ejecutar las tareas periódicas; la frecuencia de 12 horas no es una alarma exacta. HyperOS y las restricciones de batería pueden posponerlas. Un cierre forzado desde Ajustes requiere volver a abrir la app. Los sitios pueden cambiar, bloquear solicitudes o publicar imágenes inexistentes.

La reparación necesita identidad de origen y carpetas de descarga verificables; las carpetas antiguas sin ella se conservan como biblioteca local. Verifica cabeceras, tamaño, terminación y correspondencia con manifiestos; no es un análisis exhaustivo de todos los píxeles ni certifica toda la fuente.

Las mediciones profile son una muestra corta con imágenes locales controladas. El teléfono está conectado por USB y cargando, por lo que no sirven para estimar autonomía. No se ha probado iOS, agotamiento real del almacenamiento ni una sesión de varias horas. La configuración CI se entrega sin afirmar una ejecución remota en GitHub.
