# Yoma 3.2.19

## YomaTV: horario de emisión

Nuevo botón **Horario de emisión** (icono de calendario) en la barra de YomaTV:

- Los anime de la temporada, día por día, con **Hoy** seleccionado y cuántos se emiten cada día.
- El último episodio de cada uno y su próxima emisión estimada cuando cae en esta semana.
- No necesita cuenta. Se guarda en el teléfono: se ve sin conexión y se actualiza cada 6 horas o con el botón de actualizar.

## Fase 3: web y app

- **Conexión con MyAnimeList.** Tiene su propia configuración de servicios compartidos y ya no depende de la dirección de YomaTV. Sigue en el mismo sitio; así se podrá mover más adelante a `api.yoma.site` sin tocar YomaTV.
- **Código de tv.yoma.site.** Está en el repositorio (`web/tv.yoma.site`), sin credenciales ni datos del servidor, con pruebas que lo comprueban.
- **Documentación.** `docs/arquitectura/fase-3.md` recoge:
  - la evaluación de cómo compartir biblioteca, favoritos e historial entre web y app;
  - qué funciones de la web conviene traer;
  - los pasos para mover los servicios compartidos;
  - la estructura propuesta para yoma.site, tv.yoma.site, shi.yoma.site y api.yoma.site.
