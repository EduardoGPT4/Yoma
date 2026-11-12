# Yoma 3.2.13

## YomaTV pasa a tv.yoma.site

El dominio anterior (`hk-br035.gt.tc`) ya no tiene la web: tras la verificación del hosting responde con una redirección a la página de error 404 de InfinityFree. La app no sigue redirecciones a propósito, así que YomaTV mostraba «HTTP 302» y no cargaba.

Ahora la app usa `tv.yoma.site`, donde YomaTV vive en la raíz:

- el catálogo, las fichas y los episodios;
- la conexión con MyAnimeList (`tv.yoma.site/yomashi-api.php` y `yomashi-connect.php`);
- la web de YomaTV dentro de la app.

El dominio anterior ya no se acepta como origen de confianza.

Las sesiones de MyAnimeList siguen funcionando, porque la base de datos es la misma. Para conectar una cuenta nueva, la dirección de retorno de la aplicación de MyAnimeList tiene que ser `https://tv.yoma.site/mal-callback.php`.

## La web de Yoma

El código de las páginas está ahora en el proyecto, en `web/`:

- `yoma.site`: página principal.
- `shi.yoma.site`: presentación de YomaShi.
- `tv.yoma.site/yoma.css`: hoja que da a YomaTV el diseño de la app.

Las tres usan los mismos colores, la misma letra y la misma barra de sección que la app.
