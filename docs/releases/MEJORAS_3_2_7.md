# Yoma 3.2.7

Cierra los pendientes que dejó la auditoría de YomaTV y MyAnimeList de la 3.2.6.

## Deshacer en MyAnimeList al desmarcar un episodio

Hasta ahora, desmarcar un episodio que YomaTV ya había enviado no cambiaba nada en MAL. Ahora se deshace:

- MAL baja al episodio visto más alto que queda en el teléfono.
- Nunca baja de lo que MAL tenía antes de que Yoma enviara nada: lo visto en otra app o en la web no se toca.
- Solo se aplica si MAL sigue exactamente donde Yoma lo dejó. Si cambió desde entonces, no se baja nada y se avisa.
- Un anime que quedó «Completado» por ese episodio vuelve a «Viendo».
- Funciona sin conexión: el deshacer queda en la cola y se envía al volver. Volver a marcar el episodio lo cancela.

**Requiere actualizar el servidor** (`python tools/deploy_anime_backend.py --publish`). Con el servidor anterior la app no envía nada y avisa de que MAL conserva el episodio.

Las vinculaciones creadas con versiones anteriores no pueden deshacer lo que ya enviaron, porque no guardaban el número que MAL tenía por su cuenta.

## Vinculación por nombre más segura

- Un anime de YomaTV ya no se empareja con una entrada de MAL del mismo título si es otra obra: cuando YomaTV publica más episodios de los que la obra tiene en MAL (con un margen de 2) o cuando los años de estreno difieren en más de uno.
- Si dos entradas de tu lista apuntan al mismo anime de YomaTV, no se vincula ninguna.
- Las coincidencias ya guardadas se vuelven a comprobar con estas reglas.
- El año de estreno llega con la actualización del servidor; sin ella solo se compara el número de episodios.

## Listas largas

Antes, la primera carga hacía una búsqueda en YomaTV por cada anime de «Viendo» y «Por ver». Ahora se consulta una vez el índice público del catálogo: los títulos que no existen en YomaTV no se buscan, y los que existen aparecen enseguida mientras se pide su ficha (portada, episodios y año). Hasta que esa ficha confirma que es la misma obra, se ven pero no se vinculan.

## Episodios decimales

Un especial como el «12.5» ahora cuenta en MAL como haber visto hasta el 12. Uno «0.5» no cuenta ninguno.

## Descargas

- Volver a pedir un episodio dice lo que pasó de verdad: añadido, puesto de nuevo en la cola (había fallado, estaba en pausa o faltaba su archivo), ya en la cola o ya descargado. Antes siempre decía «añadido» aunque no hiciera nada.
- Un episodio con la descarga fallida o en pausa vuelve a la cola conservando lo descargado.
- Añadir un episodio ya no reanuda una cola que pausaste; el mensaje lo indica.

## Servidor

- `yoma-anime-mal.php`: deshacer explícito (`decrease`) y año de estreno en las listas.
- `tools/deploy_anime_backend.py --publish --connect` sube además la página de autorización corregida en la 3.2.6. Esa opción no se ha probado contra el alojamiento.
