# Yoma 3.1.0

## Diseño unificado (Yoma Design System)

- YomaShi y YomaTV comparten paleta oscura con acento coral, tipografía, botones, tarjetas, chips, diálogos, menús y barras de navegación.
- Cada módulo conserva su estructura: YomaShi sigue compacto y configurable; YomaTV mantiene banner, pósteres grandes y degradados.
- El violeta anterior por defecto y el rojo saturado pasan una sola vez al coral. Los demás acentos elegidos se respetan.
- Las etiquetas técnicas del catálogo de manga se agrupan en una línea discreta.
- Referencia: `docs/design/YOMA_DESIGN_SYSTEM.md`.

## Barras que se ocultan al desplazar

- En las pantallas principales de YomaShi y YomaTV, la barra del módulo y la barra Yoma / Ir a… se pliegan juntas con una animación suave al desplazar hacia abajo y vuelven al subir o al llegar arriba.
- Carruseles horizontales, hojas inferiores y diálogos no las mueven. Al cambiar de módulo o volver de una ficha, reaparecen.
- Con «Quitar animaciones» de Android el cambio es inmediato.

## MyAnimeList en YomaTV

- Con una cuenta MAL conectada, el Inicio de YomaTV muestra «Viendo en MyAnimeList» y «Por ver en MyAnimeList» con los animes de esas listas que existen en YomaTV con el mismo nombre (sin distinguir mayúsculas, espacios ni comillas tipográficas).
- Las listas y las coincidencias se guardan en el teléfono: aparecen al instante y solo se consulta MAL si la copia tiene más de 12 horas o al deslizar hacia abajo para actualizar. «Limpiar caché del catálogo» no las borra.
- Al empezar a ver un anime desde esas secciones se vincula automáticamente con su entrada de MAL y los episodios vistos se sincronizan. Una vinculación existente nunca se reemplaza.

## Correcciones

- Lector, reproductor y fichas respetan otra vez el área segura inferior de Android: los controles ya no quedan bajo la barra de gestos.
