# Yoma 3.2.1

## Entrada animada del selector

Al abrir Yoma, la pantalla de selección parece programarse en tiempo real (unos 3 segundos):

- Una terminal escribe `> yoma.init()` y va marcando cada paso de la construcción.
- El contorno del logo se traza mientras se escribe `<Yoma.Logo />` y la imagen pasa de gris a color.
- «Yoma» se escribe letra a letra con cursor.
- Cada tarjeta se marca, dibuja su borde y escribe su código (`<YomaShi type="manga" />`, `<YomaTV type="anime" />`); después el código se disuelve, cruza una línea de compilación y aparecen imagen, textos e icono con un destello.
- La tarjeta de MyAnimeList se despliega y las anotaciones desaparecen, dejando el selector de siempre.

Se reproduce una sola vez al abrir la app, los botones funcionan desde el primer momento (al tocarlos la animación termina) y con «Quitar animaciones» de Android se muestra el selector directamente.
