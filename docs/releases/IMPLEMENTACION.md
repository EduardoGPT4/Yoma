# Implementación del informe

Fecha: 20 de octubre de 2026. Proyecto: Expedition-9.

Se implementaron las correcciones y mejoras del informe en las cuatro fuentes solicitadas, manteniendo la biblioteca local y el conector adicional existente. La copia anterior a los cambios se conserva fuera del proyecto, en el directorio de trabajo de la auditoría.

## Bugs

| Punto | Implementación |
| --- | --- |
| B01 | DownloadEngine confirma únicamente archivos verificados. Pausa y prioridad cancelan transferencias sin avanzar por páginas ausentes. |
| B02 | ContentIdentity, carpetas por ID y manifiestos de manga/capítulo. Verificación de colisiones. Migración compatible de metadatos antiguos sin alterar sus rutas ni inventar su origen. |
| B03 | Archivos .part, publicación por renombrado, comprobación de tipo/longitud/formato y verificación final del capítulo. Las listas vacías no se completan. |
| B04 | Selecciones explícitas y conjunto de capítulos confirmados; los contadores se reconstruyen al reanudar, sin depender del cursor antiguo. |
| B05 | Estados de error de capítulo e imagen con reintento accesible, cancelación y protección contra respuestas de capítulos anteriores. |
| B06 | El ciclo completo del trabajo captura errores de almacenamiento y libera el planificador para la siguiente descarga. |
| B07 | Pausa manual persistente que devuelve el trabajador y no se revierte por reconexión ni por el final de un lote. |
| B08 | SourceHttpClient limita conexión, cabeceras, inactividad y duración del cuerpo; cancela peticiones y limita tamaños de respuesta. |
| B09 | Eventos de capítulos confirmados actualizan la carpeta correspondiente en Offline sin exigir watchers. |
| B10 | Raíz fija por trabajo; conservación de bibliotecas anteriores y copia explícita, pausada y verificada hacia otro destino. |
| B11 | InManga propaga el fallo de ficha y rechaza HTML no reconocido; no presenta una descarga genérica exitosa. |
| B12 | Resolución exacta y única de enlaces heredados de TMO; desaparecen los fallbacks al primer manga/capítulo. |
| B13 | Errores tipados, Retry-After, espera exponencial con variación y máximo de cinco reintentos automáticos. |
| B14 | Inicialización SQLite reintentable. El arranque muestra recuperación si falla; el servicio informa del fallo y la cola lo expone. |
| B15 | Generaciones por operación, reinicio de paginación, captura de fuente y cancelación de búsquedas sustituidas. |
| B16 | MangaDex deduplica por volumen/número y prioriza idioma; los especiales sin número conservan su ID. |
| B17 | Estados normalizados, clasificación MangaDex por idioma original y filtros acordes a las capacidades publicadas. |
| B18 | Mapeo centralizado página/pliego, portada separada, orden RTL, zonas de navegación y remapeo al cambiar modo. |
| B19 | Canal Android setEnabled para volumen; al salir del lector se devuelve el control al sistema, incluso durante el inicio asíncrono del canal. |
| B20 | Orden natural en CBZ/ZIP y soporte GIF coherente con el escáner. |
| B21 | Bloques de capítulos bajo demanda con hasMore/nextCursor, aviso de lista parcial y continuación desde el lector. Eliminados los cortes de 2.000 registros y cuarenta páginas. |
| B22 | Backup v2 validado antes de escribir, transacción SQLite, recuperación de ajustes y copia previa; categorías restauradas en la interfaz. |
| B23 | Proveedores y mensajeros capturados antes de esperas; comprobaciones mounted y tratamiento de fallos en operaciones de interfaz. |
| B24 | Estadísticas y leídos derivados de páginas visibles y cargadas; las imágenes precargadas fuera de pantalla no cuentan. |
| B25 | Detenciones archivadas y lista explícita de capítulos confirmados, incluidas selecciones discontinuas. |
| B26 | Número correcto de páginas MangaDex mediante división entera hacia arriba. |

## Rendimiento

| Punto | Implementación |
| --- | --- |
| R01 | UPSERT por progreso/favorito/leído; datos estructurados crecientes en SQLite. Cola e historial guardados en orden y progreso persistido por intervalos. Estadísticas agrupadas. |
| R02 | Transferencia de imágenes por stream, escritura por bloques y contrapresión del limitador global. No se acumula el capítulo completo en RAM. |
| R03 | Decodificación acotada, precarga de una imagen adyacente, tres listas de capítulos, reacción a presión de memoria, modo de ahorro MangaDex y calidad original solicitada por el usuario. |
| R04 | Trabajadores que toman otra página al terminar, concurrencia acotada y configuración estable durante el capítulo; peticiones del mismo origen con límite de conexiones. |
| R05 | Repositorio común para lector, catálogo y notificaciones; deduplicación de imágenes, índice de archivos offline y cuota de caché. |
| R06 | Caché con fuente/idioma/sección y edad; claves de peticiones con consulta, página y opciones. Detalles reutilizables y una petición compartida para las listas equivalentes de MangaDex. |
| R07 | Futures de miniaturas memorizados, generación desde archivo en isolate, dos trabajadores, límites de entrada y caché con cuota. |
| R08 | Emisión del escaneo por lotes, actualizaciones dirigidas por carpeta y eventos, listas perezosas de Offline/Descargas y desmontaje de pestañas inactivas. |
| R09 | ZIP desde archivo por stream en isolate, staging, límites, progreso, cancelación y limpieza coordinada con la salida del trabajador. |

## Funciones y experiencia

| Punto | Implementación |
| --- | --- |
| F01 | DownloadHostService de Android con motor independiente, notificación y pausa, persistencia y tratamiento de timeout del sistema. |
| F02 | Selección persistida de fuentes de búsqueda, estado por fuente, resultados progresivos, paginación y reintento individual. |
| F03 | Webtoon continuo, cálculo de ajuste con dimensiones/viewport, preferencias por obra, portada y pliegos. Conservación de la página al cambiar modo o rotar. |
| F04 | Solo faltantes, no leídos, siguientes N y rango; control de duplicados, estados por capítulo, bytes, velocidad, ETA aproximada y espacio libre. |
| F05 | Etiquetas según el significado real del feed, edad de caché, estados de búsqueda y recuperación por fuente. |
| F06 | Pantalla Almacenamiento con tamaños, espacio libre Android, limpieza de caché/parciales y borrado por capítulo. Se pausan las descargas afectadas antes de borrar. |
| F07 | Guardado de backup mediante selector del sistema, vista previa, combinar/reemplazar, copia previa, enlaces y ajustes portables, incluidos ajustes por manga. |

## Arquitectura y mantenimiento

| Punto | Implementación |
| --- | --- |
| A01 | Modelos online neutrales, adaptadores y capacidades; registro e inyección de dependencias del motor. Se conservan aliases de compatibilidad. |
| A02 | Separación DownloadEngine / DownloadJob / DownloadStorage / Provider y propiedad única de la cola en Android. El estado del planificador gobierna las transiciones. |
| A03 | SQLite versión 2, migración desde preferencias, datos estructurados, identidades estables, enlaces de origen y manifiestos compatibles con las carpetas existentes. |
| A04 | AppFailure tipado, diagnóstico acotado exportable, cancelaciones, liberación de streams, timers, watchers y listeners. |
| A05 | Pruebas de regresión y contratos de fuentes con servidor local; workflow de formato, análisis, tests y compilación. |
| A06 | Configuración de firma release por archivo privado o entorno. Se impide reutilizar la firma debug y se ignoran keystores/credenciales. |
| A07 | README y ESTRUCTURA actualizados con arquitectura, flujos, configuración, compatibilidad y límites comprobados. |

## Verificación

Resultados: **78 pruebas aprobadas**, incluidos los tests originales y regresiones añadidas; análisis Flutter sin incidencias y APK de desarrollo Android compilado. El formato de Dart también se comprueba en CI. La comprobación posterior en un POCO X6 Pro con Android 16 y sus correcciones se documentan en [PRUEBAS_TELEFONO.md](../testing/PRUEBAS_TELEFONO.md).

La suite incluye prioridad durante transferencia, pausa, reanudación de selección discontinua, capítulos vacíos, fallo de carpeta, raíz fija, identidades, respuesta HTML, imagen incompleta, HTTP permanente/transitorio, compresión gzip y copia de archivos. Incluye contratos de las cuatro fuentes, feed MangaDex de 2.100 capítulos, zonatmo.to de 41 páginas, listas parciales y resolución del capítulo guardado.

También verifica cuota y deduplicación de caché, índices de capítulos parciales, rollback de SQLite, inicialización reintentable, restauración/combinar backups, orden de importación y conservación del destino existente, errores recuperables del lector, ancla webtoon, pliegos con portada y deserialización del puente Android.

## Alcance de la validación

- Las pruebas automatizadas de fuentes usan fixtures y un servidor local. También se comprobaron los cuatro sitios reales en el teléfono: las muestras y el caso de una imagen antigua con 404 están descritos en el informe de pruebas.
- Se verificaron pausa, reanudación, lectura local, rotación y avance con pantalla apagada en un POCO X6 Pro con Android 16. No se extrapola ese resultado a todos los fabricantes ni a ejecuciones de duración ilimitada.
- Android limita foreground dataSync; el servicio respeta el timeout y conserva el plan. No promete ejecución ilimitada ni arranque tras forzar la detención de la app. Referencia: [documentación oficial](https://developer.android.com/develop/background-work/services/fgs/timeout).
- El APK de desarrollo está firmado y sirve para la instalación y el uso personal. Una compilación release con firma propia requiere las credenciales del propietario; no son necesarias para usar el APK entregado.
- El segundo plano nativo se implementó para Android, tal como planteaba el informe. No se ha añadido ni validado un servicio equivalente en iOS.
- Las carpetas heredadas cuyo origen no puede demostrarse permanecen locales y conservan sus archivos. La actualización de manifiestos no certifica como completos archivos antiguos que pudieron descargarse parcialmente.
