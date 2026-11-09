# Rendimiento y optimización — Yoma 3.0.1

Mediciones realizadas el 9 de noviembre de 2026 en Android 35, emulador x86_64, 2048 MB de RAM y SwiftShader (GPU por software). Se utilizó el APK Release para arranque/memoria y un APK Profile con el catálogo público real para los tiempos Flutter. Ninguna medición de rendimiento utiliza el modo Debug.

| Medición | Referencia 3.0.0 | Final 3.0.1 |
|---|---:|---:|
| Inicio de Activity, tres muestras (ms) | [3113, 3077, 3050] | [2442, 2465, 2646] |
| Mediana de `am start -W` (ms) | 3077 | 2465 |
| PSS después de entrar en Anime y desplazarlo (MiB) | 109.66 | 104.71 |

Se observaron aproximadamente un 20 % menos en la mediana de inicio y un 4,5 % menos de PSS en estas muestras. Son tres ejecuciones por versión, sin aislamiento completo de caché del sistema y red: sirven como comparación orientativa, no demuestran por sí solas causalidad ni garantizan el mismo cambio en otros teléfonos. El tiempo de Activity no es una medición separada del catálogo ya descargado/interactivo.

## Cuadros Flutter en Profile

Se midieron 597 cuadros durante desplazamientos repetidos del catálogo, con datos y portadas reales:

- Construcción media: 1.83 ms; percentil 99: 11.338 ms.
- 5 cuadros excedieron el presupuesto de construcción del dispositivo de prueba.
- Rasterizado medio: 36.12 ms; percentil 99: 79.245 ms; peor muestra: 800.204 ms.
- El rasterizado superó el presupuesto en 591 cuadros. **No se alcanzan 60 FPS estables en este emulador con renderizado por software.** La construcción Dart es rápida; estos resultados de rasterizado no permiten atribuir una causa precisa a un widget ni extrapolar el rendimiento gráfico de un teléfono con GPU real.

Los contadores `gfxinfo` de Android devolvieron cero cuadros para la superficie Flutter. No se interpretaron como cero saltos ni se usaron para calcular FPS. Para cuadros se utilizó `IntegrationTestWidgetsFlutterBinding.watchPerformance`, cuyos datos completos están en `build/integration_reports/anime-performance.json`.

## Optimizaciones implementadas y comprobadas

1. Las solicitudes públicas idénticas que coinciden en el tiempo comparten una sola petición; el arranque de Anime deja de duplicar la misma página entre inicio y catálogo. La prueba HTTP de loopback comprueba una sola petición de catálogo para dos llamadas simultáneas.
2. El sondeo de descargas se programa únicamente con trabajos activos, sección visible y cola sin pausar. La cola vacía deja de consultar SQLite/canal Android cada dos segundos.
3. Los avances ordinarios del vídeo conservan persistencia sin notificar a las cinco pestañas en cada guardado. Un episodio nuevo o un cambio de visto sigue notificando la interfaz.
4. La sincronización MAL simultánea comparte una operación, y su confirmación actualiza la base remota de los avances nuevos sin borrar pendientes recientes.
5. Se mantienen listas y rejillas diferidas, portadas redimensionadas y caché persistente de imágenes separada del vídeo. Las fichas guardadas se muestran inmediatamente y se actualizan en segundo plano.
6. El reproductor pausa al abandonar Anime y libera sus recursos al cerrar su ruta; su temporizador se cancela al destruir la pantalla. No descarga capítulos automáticamente.

## Reproducción de las mediciones

- `tools/measure_anime_performance.py`: arranque y PSS en el emulador QA. Antes de medir se verifican pantallas reales; la primera ejecución bloqueada en permisos se descartó.
- `integration_test/anime_performance_test.dart`: navegación/scroll del catálogo real en Profile.
- Los scripts de Android utilizan exclusivamente el emulador QA. Las capturas de memoria y cuadros están en `docs/yoma/performance-*-mem.txt` y `performance-*-gfx.txt`.

Queda pendiente medir rasterizado, temperatura, batería y uso prolongado en un teléfono físico representativo. No se redujeron funciones de Manga ni se eliminaron validaciones para mejorar estas cifras.

## Actualización: teléfono físico

Se completaron pruebas en Xiaomi 2311DRK48G con Mali-G615 MC6 y Android 16: 831 cuadros, construcción media 1,51 ms, rasterizado medio 2,943 ms y mediana de inicio Release 1072 ms. Consulta PRUEBAS-TELEFONO-FISICO.md para las condiciones, referencia a 120 Hz y resultados completos. La batería y el uso prolongado siguen fuera de este ensayo.
