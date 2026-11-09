# Auditoría previa — migración Anime a Flutter

Solo se trabaja en Yoma. Las copias de código nativo presentes en este proyecto son la base; no se utilizan los proyectos antiguos como dependencia. No se cambia ni despliega la web.

## Flujo actual

AnimeScreen inicializa webview_flutter hacia https://hk-br035.gt.tc/seasonav1/. NativeAnimeBridge añade un canal restringido al origen y frame principal, inyecta presentación y abre los componentes Android de descargas/Media3. El servidor web gestiona cuentas, biblioteca, vistos y progreso mediante actions.php con sesión y CSRF. La cola Android guarda videos y SQLite de anime por propietario web; el usuario depende de esa sesión para obtener planes y sincronizar. YomaShi usa proveedores Flutter, LibraryStore/Drift e ImageRepository. MAL central usa una credencial opaca cifrada en Android y tokens cifrados en yomashi-api.php; la implementación presente solo expone operaciones de manga.

## Contratos públicos comprobados sin cuenta

| Recurso | Respuesta comprobada | Uso nativo |
| --- | --- | --- |
| GET actions.php?action=state | 200, ok/data; sesión anónima y CSRF | Transporte público, nunca login web |
| GET actions.php?action=catalog | 200, catalog/items, page, pages, total, años, temporadas, géneros y categorías | Catálogo paginado, búsqueda y filtros |
| GET catalog-public.php | 200, version/updated_at/items | Índice público y caché |
| GET actions.php?action=home | 200, home | Portada y emisión pública |
| GET actions.php?action=detail&slug=... | 200, detail/anime, episodes, seasons, relations, warning | Fichas, temporadas relacionadas y episodios |
| POST actions.php action=player | 401 con sesión anónima y CSRF correcto | No se usa como dependencia de la APK |

El catálogo devolvió 4488 títulos durante la comprobación. Los episodios incluyen id, slug, number y URL pública de origen. Las temporadas relacionadas se entregan como slug/title/label/category; no se fabrican números de temporada ni episodios desconocidos. Los datos públicos no ofrecen banners independientes, miniaturas de episodio, calidades ni subtítulos garantizados. Las portadas pueden servir de fondo visual, sin inventar esos metadatos.

Los scripts reales descargados para auditoría están en source-audit/. Son referencias de lectura, no código ejecutado por el cliente Flutter.

## Reproducción y descargas reutilizables

El resolver Android existente lee la página de episodio devuelta por la fuente, interpreta sus datos literales sin ejecutar scripts y admite MP4Upload. El motor Transfer ya comprueba hosts, rangos, validadores, cancelación y MP4; DownloadWorker añade verificación de duración, frame y hash antes de renombrar. Se reutiliza para una cola local separada, sin propietario web. Flutter video_player ofrece la superficie y controles del reproductor nuevo. Los servidores exclusivamente web y las funciones complementarias quedan accesibles en el respaldo anterior.

La biblioteca local nueva usa namespaces anime_* del almacén persistente existente, conservando el esquema de manga y sus registros. La cola local Android utiliza su propio fichero de base de datos y preferencias. Visitar un reproductor no encola descargas.

## Contrato MAL que falta

El servidor del cliente móvil existente no tiene operaciones de anime con la credencial de dispositivo. La API web de anime requiere usuario web, que la APK ya no debe exigir. Hace falta una extensión de yomashi-api.php para capacidades, lista, ficha y actualización de anime, usando la misma credencial opaca y renovación ya existente. Se preparará bajo server/ y se comprobará localmente, pero no se considerará disponible en producción hasta desplegarla. La interfaz debe comunicar esa limitación sin bloquear datos locales ni presentar una lista ficticia.

## Fuera de la sustitución inmediata

Se conserva el WebView completo como respaldo explícito para radio/YouTube, cola de PC, cuenta y otras herramientas web; no se elimina antes de verificar equivalentes. No se cambian la web original, credenciales, fuentes, lector, descargas ni traducción de manga. Los formatos/proveedores no compatibles se informan y conservan alternativa web; no se evaden DRM ni controles de acceso.

Documentación del reproductor elegido: https://pub.dev/packages/video_player (paquete oficial Flutter, versión consultada 2.14.1, Android API 24+).
