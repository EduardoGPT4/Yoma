# Arquitectura de YomaShi

## Capas

| Capa | Responsabilidad |
| --- | --- |
| models | Manga, capítulo, resultados de catálogo, bloques de capítulos, identidad y trabajos de descarga. |
| services/manga_source_adapter.dart | Contrato común y capacidades de cada fuente. |
| services/online_catalog_service.dart | Registro de adaptadores, identificación por dominio, deduplicación de peticiones, detalles reutilizables y unión de bloques. |
| services/*_service.dart | Peticiones y parsing de cada origen. zonatmo.org y zonatmo.to mantienen conectores independientes. |
| services/source_http_client.dart | Conexión, cabeceras y cuerpos con plazos, cancelación por operación y errores HTTP tipados. |
| services/download_engine.dart | Planificador, pausa, prioridad, trabajadores, reintentos y persistencia de la cola. |
| services/image_repository.dart | Flujo de imágenes, validación, archivos temporales, caché y reutilización de archivos descargados. |
| data | SQLite, migraciones, operaciones incrementales y manifiestos de archivos. |
| providers | Estado observable y comandos usados por las pantallas. |
| screens y widgets | Catálogo, detalle, biblioteca, lector, descargas, perfil y almacenamiento. |
| utils | Importación, backups, filtros, escaneo, orden natural y preferencias pequeñas. |

Los modelos online ya no dependen de TMO. tmo_manga.dart y el alias TmoCatalogPage mantienen compatibilidad con consumidores anteriores.

## Fuentes

El registro captura el adaptador al comenzar una operación. La selección global de fuente se utiliza como valor predeterminado de la interfaz. La resolución reconoce dominios y enlaces heredados; rechaza coincidencias ambiguas que podrían abrir otro contenido.

MangaDex utiliza la API y conserva número, volumen e idioma. La preferencia de idioma queda capturada durante cada página de capítulos. Los duplicados se unen por volumen/número, conservando capítulos especiales sin número por su ID. Puede utilizar imágenes data-saver o calidad original.

InManga combina ficha HTML, capítulos y controles del lector. Una ficha HTTP fallida o no reconocida se muestra como error.

TMO resuelve enlaces antiguos por coincidencia exacta y exige que una muestra permita inferir de forma consistente las páginas. Cada imagen descargada se verifica posteriormente.

ZonaTMO.to utiliza su API propia, ordena imágenes por page_number y no impone el antiguo límite de cuarenta páginas.

Los bloques de capítulos declaran hasMore y nextCursor. La ficha muestra que la lista es parcial y permite cargar más; el lector solicita el siguiente bloque al alcanzar el final. Continuar una lectura guardada busca el capítulo en los bloques posteriores. Descargar todo resuelve antes el plan completo.

Las [exclusiones de contenido](EXCLUSIONES.md) se configuran en `services/content_exclusions.dart`. El catálogo y el buscador reutilizan la misma lista; la caché de IDs excluidos también reside en ese componente, con carga limitada y manejo de errores comprobado con índices simulados.

## Descargas e integridad

Cada trabajo conserva su raíz de destino, selección de capítulos y capítulos confirmados. La selección vacía no significa descargar todo. Pausa y preempción cancelan operaciones activas y devuelven el trabajador al planificador.

Los trabajadores consumen una lista de páginas pendientes y comienzan la siguiente al terminar una transferencia. El número de trabajadores se captura por capítulo y se limita a ocho. El limitador global aplica contrapresión al flujo en bloques pequeños, sin descartar deuda de tiempo.

Una página se escribe en .part y pasa al nombre definitivo después de comprobar longitud y formato. Se rechazan HTML, JSON, imágenes vacías y listas sin páginas. El capítulo solo queda completo tras verificar todas sus páginas. Un reinicio vuelve a comprobar el plan; el cursor antiguo no decide qué archivos se omiten.

Los errores de red, timeout, 408, 429 y 5xx pueden reintentarse hasta cinco veces, con espera exponencial, variación y Retry-After. Los errores de parsing, almacenamiento y HTTP permanentes requieren intervención. La pausa manual no se reanuda por conectividad.

La persistencia de la cola está serializada. El progreso de la interfaz se agrupa a 200 ms y la escritura periódica a un segundo; los cambios de estado se guardan inmediatamente. Entre motores Android se envían actualizaciones pequeñas de progreso sin repetir los metadatos de toda la obra.

## Android

MainActivity ofrece canales para volumen, almacenamiento y comandos de descarga. DownloadHostService posee un FlutterEngine independiente y ejecuta downloadMain, conservado como entrypoint en compilaciones AOT.

La interfaz observa instantáneas del servicio; no crea un segundo planificador Android. El servicio mantiene la notificación de trabajo, ofrece pausa y termina al quedar inactivo. onTimeout pausa y guarda el estado antes de finalizar. No se inicia desde BOOT_COMPLETED. El servicio se recupera desde la cola persistida cuando vuelve a iniciarse.

La navegación por volumen solo se habilita mientras el lector la utiliza; fuera del lector se delega al sistema.

## Archivos y migración

    <raíz>/Manga/manga-<identidad>/
      manga.yomashi.json
      cover.image
      chapter-<identidad>/
        chapter.yomashi.json
        00001.image
        00002.image

La identidad procede de la referencia canónica, con dominio de origen y IDs cuando están disponibles. Los cambios de título no cambian la carpeta. Los manifiestos conservan título, origen, orden, número, volumen, idioma y páginas esperadas. Una identidad incompatible en una carpeta existente produce error.

La compatibilidad antigua conserva nombres y rutas para no romper progreso ni favoritos. La actualización de metadatos no inventa correspondencias con capítulos online. La copia entre destinos usa staging, verifica imágenes y tamaños y publica la carpeta al final; conserva el origen.

## Lector y memoria

El lector mantiene tres listas de páginas recientes y precarga una imagen adyacente. Las imágenes decodificadas se limitan al viewport y una altura máxima; el usuario puede pedir calidad original para ampliar. Ante presión de memoria se reduce la precarga y se libera la caché decodificada.

Las conversiones página/pliego se centralizan en ReaderPaging. Puede mostrarse una portada sola, con orden RTL o LTR. Ancho y alto se calculan con dimensiones de la imagen y viewport. El modo continuo usa slivers alrededor de la página de reanudación.

Los errores de capítulo e imagen ofrecen reintento. La navegación conserva la página al cambiar de modo. Las páginas precargadas que no son visibles no incrementan las estadísticas ni marcan capítulos como leídos.

## Persistencia y caché

SQLite versión 2 conserva progreso, favoritos y leídos mediante operaciones por registro. app_records almacena cola, archivo, categorías, estadísticas, enlaces, preferencias por manga, catálogo e índice de imágenes. La migración desde SharedPreferences conserva la compatibilidad. Se habilitan WAL y espera por bloqueo para los motores Android.

SharedPreferences conserva ajustes pequeños. Los backups incluyen datos de lectura, categorías, vínculos de origen y preferencias portables; las imágenes y rutas de carpetas del dispositivo no se trasladan automáticamente.

La caché de catálogo distingue fuente, idioma y sección, con edad y TTL de diez minutos. Las consultas de red se distinguen también por página, tamaño y búsqueda. Los detalles reutilizables tienen TTL de cinco minutos y un límite de doce entradas. Las imágenes de catálogo, lector y notificaciones comparten repositorio; la caché temporal tiene una cuota de 256 MiB. Las miniaturas locales usan dos trabajadores, memoización y cuota de 64 MiB.

La biblioteca emite resultados por lotes y actualiza carpetas concretas tras cambios o descargas. Las listas de Offline y Descargas usan slivers. Las pestañas inactivas no permanecen suscritas mediante IndexedStack.

## Importación, backup y diagnóstico

CBZ/ZIP se procesa mediante streams en un isolate, con orden natural, GIF, progreso, cancelación y límites de tamaño/entradas. El resultado se publica desde staging y no sobrescribe una obra existente.

La restauración valida versión, secciones, tipos y rangos antes de escribir; genera una copia previa, permite combinar/reemplazar y utiliza transacción SQLite con recuperación de ajustes pequeños ante fallo. El selector del sistema permite guardar el backup.

El registro de diagnóstico está acotado a cien eventos y omite cuerpos, cabeceras y URLs completas. Puede exportarse desde Perfil.

## Comprobaciones

La suite cubre las regresiones de integridad, pausa, prioridad, reinicio, raíz fija, copia, HTTP y compresión; contratos locales de las fuentes; bloques de series largas; backup transaccional e importación; lector con errores/webtoon; pliegos y puente nativo.

El workflow ejecuta formato, análisis, tests y compilación Android. La firma release utiliza exclusivamente credenciales externas; el APK debug firmado permite uso personal. [PRUEBAS_TELEFONO.md](../testing/PRUEBAS_TELEFONO.md) recoge la validación real en un POCO X6 Pro con Android 16. Otros fabricantes e iOS requieren sus entornos correspondientes.
