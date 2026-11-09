# Pruebas en teléfono físico — Yoma 3.0.1

Fecha: 9 de noviembre de 2026. Xiaomi 2311DRK48G (duchamp), Android 16 / SDK 36, GPU Mali-G615 MC6. Flutter utilizó Impeller/Vulkan según el registro del proceso de prueba.

## Protección de las instalaciones existentes

El teléfono ya tenía app.yomashi.reader (2.8.3, código 2016) y app.yomashi.reader.qa (2.9.0, código 17). No se actualizaron ni se desinstalaron. Se utilizó exclusivamente app.yoma.integration.qa, que no estaba instalado al empezar y se retiró al terminar. Sus datos de prueba eran independientes de las bibliotecas y sesiones personales.

Las versiones y fechas de instalación/actualización de las dos aplicaciones existentes coinciden antes y después. Evidencias: phone-existing-*-before.txt, phone-existing-*-after.txt y physical/cleanup.json.

El dispositivo rechazó conceder notificaciones mediante ADB. Se respetó la restricción y la app solicitó el permiso con el diálogo normal de Android; no se cambiaron ajustes globales de seguridad ni se concedió acceso a todos los archivos. El driver se conectó a la VM de la app ya instalada manualmente, sin delegar la instalación/desinstalación a Flutter.

## Rendimiento gráfico en Profile

Se desplazó repetidamente el catálogo público real, se regresó al selector y se volvió a Anime comprobando su conservación de estado. Se registraron 831 cuadros.

| Fase | Media | Percentil 99 | Peor muestra |
|---|---:|---:|---:|
| Construcción | 1.51 ms | 8.217 ms | 14.77 ms |
| Rasterizado | 2.943 ms | 8.241 ms | 11.175 ms |

No hubo fases por encima del presupuesto de aproximadamente 16,7 ms que utiliza el resumen de la prueba. El teléfono tiene configurado un pico de refresco de 120 Hz: con la referencia más estricta de 8,33 ms, hubo 8 fases de construcción y 7 de rasterizado por encima, entre 831 cuadros. No se afirma que todos los cuadros mantengan 120 FPS ni que estos tiempos midan por sí solos toda la composición del sistema.

El límite gráfico observado en el emulador con GPU por software no aparece en esta muestra física. No se detectó un fallo de rendimiento que justificase cambiar de nuevo la lógica de producción. Se conservan las optimizaciones anteriores de peticiones compartidas, sondeo de descargas y notificaciones de progreso.

## Arranque del Release normal

Se instaló en el paquete temporal una compilación Release de lib/main.dart, sin código de integración como punto de entrada. Se detuvo únicamente ese proceso antes de cada uno de los cinco arranques; no se vació la caché del sistema ni se borraron datos entre muestras.

- TotalTime de Activity, ms: [1599, 1072, 975, 899, 1118].
- Mediana: 1072 ms. Media: 1132.6 ms.
- PSS del selector, Release: 219868 KiB (214.7 MiB).

El tiempo de Activity no equivale a esperar a descargar todo el catálogo. La memoria Profile después de los escenarios de catálogo/vídeo fue 316466 KiB; corresponde a otro modo y otra carga y no se compara directamente con el selector Release o con el emulador.

## Funciones comprobadas en este teléfono

Las tres pruebas físicas terminaron correctamente en unos 42 segundos: catálogo y navegación con medición Profile; decodificación de MP4 offline con avance, pausa y posición persistente sin encolado automático; y resolución/reproducción online de MP4Upload desde la fuente pública sin cuenta web. El proveedor devolvió un vídeo de 1491084 ms y el catálogo contenía 4488 entradas durante la comprobación.

La prueba offline de controles utiliza el MP4 de prueba explícito en el almacenamiento privado de la instalación temporal. La prueba online utiliza contenido real de la fuente. La descarga real completa de 211 MB ya se verificó anteriormente en el emulador; no se repitió esa transferencia completa en este teléfono. Tampoco se inició sesión con la cuenta MAL personal ni se modificó su lista.

## Límites y evidencias

El teléfono estaba cargando; la temperatura de batería registrada al finalizar fue 38,4 °C. No se pueden extraer conclusiones de autonomía ni de calentamiento atribuible a la app a partir de este ensayo corto y con carga externa. Quedan fuera una prueba prolongada, llamadas/interrupciones y todas las combinaciones de proveedores y configuraciones personales.

Datos crudos: build/integration_reports/phone-profile.json, physical/phone-profile-logcat.txt, physical/phone-profile-driver.txt, physical/phone-release.json y physical/phone-release-launches.txt. Herramientas: tools/run_physical_profile.py y tools/measure_physical_release.py. Las pruebas modificadas siguen funcionando con la QA del emulador o con el paquete de integración aislado según su flag de compilación.

El APK entregado dist/Yoma-3.0.1-anime-nativo-prueba.apk permanece sin cambios. Las compilaciones temporales de esta comprobación utilizan otro identificador y no sustituyen ese artefacto ni las aplicaciones del teléfono.
