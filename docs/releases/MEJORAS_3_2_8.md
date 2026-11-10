# Yoma 3.2.8

Solo cambia textos de YomaTV; no cambia ningún comportamiento.

## Textos más claros

- **Idiomas con nombre.** SUB, LAT y DUB se muestran como «Subtitulado», «Latino» y «Doblado» en la ficha, el reproductor, Descargas y los ajustes.
- **Estados de descarga traducidos en la ficha.** La lista de episodios mostraba el estado interno en inglés (`queued`, `downloading`…); ahora dice «En cola», «Descargando», etc., igual que Descargas.
- **El reproductor ya no muestra el identificador técnico del anime**, solo el idioma.
- **Botón de descarga de la ficha:** «Descargar 3» en lugar de solo «3».
- **«Ver en la web»** sustituye a «Abrir respaldo web» y «Abrir en la web»; el acceso a la web se llama «YomaTV en la web».
- **Avisos de MyAnimeList:** «Tu progreso está guardado en el teléfono. No se pudo enviar a MyAnimeList: …».
- **Pendientes de MyAnimeList:** «Por enviar: hasta el episodio 3» y «Por deshacer en MyAnimeList: volver al episodio 3».
- **Conflictos:** «Dejar MAL como está» y «Enviar mi progreso».
- «MyAnimeList» y «Mi lista de MyAnimeList» en lugar de «MyAnimeList de Anime» y «Mi lista de anime MAL».
- Descargas: «Reproducir sin conexión», «Cancelar descarga» y «Las descargas necesitan Android 8 o posterior.».
- «Caché del catálogo borrada.» al limpiar la caché.

## Servidor

- La página de autorización dice «Yoma» en lugar de «YomaShi». Se publica con `python tools/deploy_anime_backend.py --publish --connect`.
