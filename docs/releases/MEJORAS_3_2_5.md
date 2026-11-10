# Yoma 3.2.5

## Conflictos de MyAnimeList resueltos automáticamente

Para aceptar un episodio, el servidor comprueba que MAL siga con el número de episodios que la app esperaba. Si cambió (desde la web, otra app, o porque la copia de tu lista tenía horas), antes el episodio quedaba apartado como «conflicto» hasta revisarlo a mano. Ahora YomaTV consulta el número actual de MAL y:

- si MAL va por detrás, corrige el número esperado y reenvía el episodio al momento;
- si MAL ya tiene ese episodio o más, respeta su número y elimina el pendiente (nunca baja la cuenta de MAL);
- solo deja para revisión los casos dudosos, como un episodio mayor que el total del anime en MAL (vinculación equivocada) o un segundo rechazo.
