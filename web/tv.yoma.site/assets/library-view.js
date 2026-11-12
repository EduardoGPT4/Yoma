'use strict';
function library(favorites = false) {
  const rows = state.anime.filter(
    (a) =>
      (favorites ? a.favorite : a.status !== 'none') &&
      (libraryFilter === 'all' || a.status === libraryFilter) &&
      a.title.toLocaleLowerCase().includes(search.toLocaleLowerCase())
  );
  const intro = title(
    favorites ? 'LOS QUE NO TE QUIERES PERDER' : 'TU COLECCIÓN PERSONAL',
    favorites ? 'Tus favoritos.' : 'Una biblioteca muy tuya.',
    favorites
      ? 'Marca una estrella y ten tus próximas historias siempre a mano.'
      : 'Guarda animes, marca capítulos vistos y continúa donde te quedaste.',
    button('view_discover', 'Explorar animes', 'plus', '', 'ghost')
  );
  if (!state.user)
    return (
      intro +
      empty(
        'Tu temporada merece un lugar',
        'Inicia sesión o crea una cuenta para guardar favoritos y continuar tu biblioteca desde cualquier dispositivo.',
        button('account', 'Crear mi biblioteca', 'heart', '', 'primary')
      )
    );
  return (
    intro +
    `<div class="filter-bar"><select class="select-input compact" id="library-filter" aria-label="Estado de la biblioteca"><option value="all">Todos los estados</option>${Object.entries(
      FOLLOW
    )
      .map(
        ([k, v]) =>
          `<option value="${k}" ${libraryFilter === k ? 'selected' : ''}>${v}</option>`
      )
      .join(
        ''
      )}</select>${searchBox()}</div>${rows.length ? cards(rows, true) : empty(favorites ? 'Todavía no tienes favoritos' : 'Tu primera historia te espera', favorites ? 'Pulsa la estrella de cualquier anime para añadirlo aquí.' : 'Explora el horario y pulsa Seguir para comenzar tu colección.', button('view_schedule', 'Descubrir un anime', 'compass', '', 'primary'))}`
  );
}
