# Yoma 3.2.11

## Vínculo con MyAnimeList desde la ficha

- La ficha de un anime muestra con qué entrada de MyAnimeList está vinculado y cuántos episodios tiene vistos allí. Desde ahí se puede quitar el vínculo o, si no tiene, ir a vincularlo.
- Un vínculo que quites no se vuelve a crear solo, ni en YomaTV ni en YomaShi. Vincularlo a mano lo deshace.

## Lo traído de MyAnimeList se distingue

- YomaTV muestra «Visto en MAL» en los episodios que vinieron de MyAnimeList.
- YomaShi muestra «Leído en MAL» en los capítulos que vinieron de MyAnimeList.

## Listas de MyAnimeList más al día

Al abrir Yoma o volver a ella, las listas «Viendo» y «Reading» se actualizan si tienen más de una hora. Antes esperaban hasta 12 horas.

## Siguiente episodio

- Al terminar un episodio aparece «Episodio N en 5 s», con «Cancelar» y «Ver ahora». También funciona en pantalla completa.
- Se puede desactivar en Más → «Pasar al siguiente episodio al terminar».
- Un episodio guardado en sus últimos segundos se vuelve a ver desde el principio, en vez de terminar y saltar al siguiente nada más abrirlo.

## Aviso de episodios nuevos

La comprobación en segundo plano que ya avisaba de capítulos nuevos de tus favoritos ahora también revisa los animes de «Viendo» en MyAnimeList, incluidos los vinculados a mano. Si tienen episodios nuevos en YomaTV, avisa con una notificación.

- La primera vez solo anota cuántos episodios hay.
- Lo que ya viste en la ficha no se avisa.
- Usa los mismos ajustes de actualizaciones automáticas (Wi-Fi, batería) que los favoritos.

## Copias de seguridad

- **Ahora incluyen YomaTV:** progreso, biblioteca, ajustes y vínculos con MyAnimeList. También guardan las marcas de lo que desmarcaste o vino de MAL. Los envíos pendientes a MAL no se copian, porque restaurados en otro teléfono podrían repetirse. Las copias antiguas se siguen pudiendo restaurar.
- **Ya no se duplican:** la app y la comprobación en segundo plano podían hacer la copia del día a la vez. Ahora se reservan con un archivo de bloqueo compartido.

## Correcciones

- Dos vinculaciones automáticas a la vez (al abrir YomaTV y al ver un episodio) podían dejar un episodio sin enviar a MyAnimeList. Ahora la vinculación automática nunca sustituye un vínculo existente.
- Las fichas de YomaTV y YomaShi actualizaban la pantalla de una forma que Flutter rechaza en modo depuración.
- `tools/run_native_tests.ps1` ya funciona en Windows PowerShell 5.1.
