# Diagnóstico de pruebas de Yoma

Se comparó la suite en Expedition-9 original (solo ejecución de pruebas, sin editar código) con la copia Yoma. La ejecución reproducible inicial mostró 11 fallos en el original y esos mismos 11 más un fallo del test de navegación en Yoma. Los resultados completos están en baseline-tests.json y tests.json. final-tests.json corresponde a una ejecución intermedia anterior a restaurar los filtros; verified-tests.json es la comprobación posterior a las correcciones.

## Error real: faltaban reglas en ContentExclusions

`lib/services/content_exclusions.dart` contenía solo `electroencefalografista` y `esternocleidomastoideo`. Las pruebas exigían además `loli`, `shota`, `guro`, `ryona` y `snuff`. Se confirmó la discrepancia leyendo la configuración y siguiendo sus consumidores: metadatos, sugerencias, búsquedas y los índices de IDs excluidos. No era una caída de red: las pruebas utilizan datos e índices simulados.

Se restauraron esas cinco entradas SOLO en Yoma, manteniendo las otras dos. No se cambió ni desactivó ninguna prueba de filtros. La clave de caché existente depende de las reglas: cambia automáticamente y evita reutilizar catálogos guardados bajo reglas incompletas. No se borran biblioteca, historial ni páginas offline.

| Archivo de prueba | Prueba exacta | Causa comprobada |
| --- | --- | --- |
| test/services/content_exclusion_test.dart | exclusion filter recognizes blocked tags after normalization | `matches` devolvía false porque faltaban las reglas normalizadas esperadas. |
| test/services/content_exclusion_test.dart | exclusion filter rejects blocked metadata among unrelated tags | La etiqueta del fixture no estaba en la configuración y la galería no se rechazaba. |
| test/services/content_exclusion_test.dart | additional restrictions apply to metadata and suggestions | Faltaban las tres reglas adicionales; afectaba tanto metadatos como sugerencias. |
| test/services/hitomi_service_test.dart | el catálogo omite galerías bloqueadas y conserva el orden | No se consultaban los índices de las reglas ausentes y quedaban IDs prohibidos en el catálogo simulado. |
| test/services/hitomi_service_test.dart | additional exclusions reject direct details and pages | Las fichas y páginas con esas etiquetas no eran rechazadas por `galleryIsBlocked`. |
| test/services/hitomi_service_test.dart | failed exclusion indexes report an error and can be retried | El fixture falla al cargar el índice guro; como no se solicitaba ese índice, no aparecía el error esperado. La lógica de reintento no era la causa. |
| test/services/hitomi_service_test.dart | restricted searches and suggestions stop before requesting indexes | La consulta restringida no se reconocía y llegaba al adaptador en lugar de detenerse antes. |
| test/unit/content_exclusions_test.dart | one configuration contains the existing and additional restrictions | La configuración carecía de cinco elementos requeridos. |
| test/unit/content_exclusions_test.dart | recognizes case, separators, compound tags and query namespaces | El normalizador funcionaba; faltaban los patrones con los que comparar. |
| test/unit/content_exclusions_test.dart | the same rules supply general and namespaced exclusion indexes | `indexTokens` producía solo seis tokens en lugar de incluir las variantes de las reglas ausentes. |
| test/widgets/hitomi_tag_suggestions_test.dart | un término bloqueado no se ofrece ni se busca | El panel permitía consultar términos que la configuración ya no reconocía como restringidos. |

## Problema de prueba: nueva ruta inicial

`test/widgets/catalog_ui_ux_test.dart` → `switching tabs preserves the search controller and its query` buscaba inmediatamente el primer TextField tras montar MangaReaderApp. En Yoma, la primera pantalla es el selector, que no contiene ese campo. La primera adaptación seleccionaba Manga pero todavía necesitaba esperar a que el Navigator interno montara su ruta inicial; el error era `Bad state: No element`, no pérdida de un controlador.

Se ajustó únicamente esta prueba en Yoma para entrar a Manga y esperar su ruta. Se conservaron las comprobaciones de identidad del controlador y del texto y se añadieron cambios Yoma → Anime → Manga. Con esa secuencia se conserva la misma instancia del controlador y `one piece`. No se alteró el lector para satisfacer la prueba.

## Verificaciones y alcance

- Las 29 pruebas dirigidas de siete archivos pasan: configuración y exclusiones, servicio, caché, panel de búsqueda, catálogo/navegación y selector/perfil. Registro: targeted-tests.txt.
- El nuevo test del selector comprueba también que el nombre MAL aparece al conectar y desaparece al desconectar.
- Las pruebas en vivo están separadas y requieren sus variables de activación. Las verificaciones con fixtures no prueban disponibilidad actual de proveedores externos.
- El archivo original Expedition-9/lib/services/content_exclusions.dart conserva SHA-256 6142EE3AEBE1653E3C07EB5B507DD51D94CF7AF227DF399E2A8B09008C93CA23 antes y después de la corrección. No se editó código de Expedition-9.

## Resultado final

Suite completa: 255 pruebas aprobadas, 3 omitidas y 0 fallos (verified-tests.json). flutter analyze --no-pub: sin incidencias. PHP: sintaxis válida. APK QA compilado y verificado con aapt/apksigner, Android 7.0/API 24 o posterior, etiqueta Yoma, paquete app.yomashi.reader.qa, firma debug. Archivo dist/Yoma-prueba.apk. SHA-256: A9E9A4524E9BFCCA0844E532335B5454C080F85967B915846E339884B4BB8C13.

No se han probado dispositivos reales ni la integración del nuevo endpoint en el servidor. Las pruebas omitidas son optativas y no se desactivaron para esta entrega.

