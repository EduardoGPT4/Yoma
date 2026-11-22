# Yoma 3.2.33

## YomaShi: lector más fluido

- **Pasar páginas sin tirones:** en 3.2.32, la biblioteca que queda debajo del lector volvía a limpiar todos los títulos cada vez que cambiabas de página. Con bibliotecas grandes eso frenaba el lector. Ahora cada título se limpia una sola vez.
- **Menos trabajo por página:** pasar de página ya no reconstruye el inicio, la biblioteca y la ficha que quedan debajo.
  - El progreso se sigue guardando en cada página, así que no se pierde si la app se cierra.
  - Dentro del mismo capítulo, esas pantallas se actualizan una vez al dejar de pasar páginas; al cambiar de capítulo, enseguida.
- **Modo webtoon:** cada página avisa una sola vez que terminó de cargar, en lugar de hacerlo en cada desplazamiento.
- **Sin arranques del servicio de descargas al leer:** al abrir cada capítulo, el lector despertaba el servicio de descargas para preparar los siguientes capítulos, aunque la descarga anticipada estuviera desactivada. Cada arranque levanta un segundo motor de la app y podía dar un tirón. Ahora solo lo despierta si la descarga anticipada está activa y se cumplen sus condiciones (wifi, batería).
