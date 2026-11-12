# Yoma 3.2.15

## YomaShi: un solo vínculo de MyAnimeList por obra

El manga offline y su ficha online usaban el mismo código para MyAnimeList, pero guardaban el vínculo con claves distintas: la carpeta del teléfono en un caso y la URL online en el otro. Por eso una obra vinculada desde la biblioteca offline aparecía sin vincular al abrirla online.

Ahora las dos copias comparten el vínculo:

- **Mangas descargados desde una fuente online:** se reconocen por la URL de origen guardada al descargar. Los vínculos nuevos se guardan con esa URL, y los antiguos, guardados con la carpeta, también se encuentran desde la ficha online.
- **Carpetas sin URL de origen:** se unen con la ficha online del mismo nombre, solo si hay una única obra vinculada con ese nombre. Una carpeta descargada de otra fuente no se une por nombre.
- **Quitar vínculo:** al quitarlo en una copia se quita en las dos, y ninguna se vuelve a vincular sola.

## Estado en MAL automático

La ficha online ya no tiene el botón «Consultar estado en MAL»: el estado se consulta solo al abrirla, mientras se muestra «Consultando MyAnimeList…». Si se consultó hace menos de dos minutos no se repite.
